import AppKit
import ApplicationServices
import Combine
import TileMeCore

@MainActor
final class RowController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var message = "Start a scrolling row on the current display"
    @Published private(set) var shortcutWarning = ""
    private let engine = RowWindowEngine()
    private let border = FocusBorderWindow()
    private let hotkeys = HotkeyManager()
    private var timer: Task<Void, Never>?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var panelTargetPID: pid_t?
    func rememberTargetApplication() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            panelTargetPID = app.processIdentifier
        }
    }
    private var targetPID: pid_t? {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return pid == ProcessInfo.processInfo.processIdentifier ? panelTargetPID : pid
    }
    private var pending = NavigationBuffer()
    private var pendingResize = false
    private var pendingSync = false
    private var cachedSnapshot: RowSnapshot?
    private var lastScan = Date.distantPast
    private var viewport = CGRect.zero
    private var scrollAmount: CGFloat = 0
    private var lastSwipe = Date.distantPast

    func startMonitoring() {
        hotkeys.onAction = { [weak self] id in
            guard let self else { return }
            switch id {
            case 1: send(.step(-1))
            case 2: send(.step(1))
            case 3: send(.resize)
            case 4: toggle()
            default: break
            }
        }
        hotkeys.start()
        shortcutWarning = hotkeys.conflicts.joined(separator: "; ")
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.enabled,
                      event.modifierFlags.intersection([.control, .option]) == [.control, .option],
                      abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
                      event.momentumPhase.isEmpty else { return }
                if event.phase == .began { self.scrollAmount = 0 }
                self.scrollAmount += event.scrollingDeltaX
                if abs(self.scrollAmount) >= 35 && Date().timeIntervalSince(self.lastSwipe) > 0.25 {
                    self.send(.step(self.scrollAmount < 0 ? 1 : -1))
                    self.scrollAmount = 0; self.lastSwipe = Date()
                }
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.stop(reason: "Space changed — row stopped and positions restored. Start a row in this Space.") }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.stop(reason: "Display configuration changed — start the row again.") }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.send(.focus) }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.send(.sync) }
            })
        }
    }
    private func snapshot() -> RowSnapshot {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
        let eligible = Set(apps.filter { $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != ownPID }.map(\.processIdentifier))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let visible = windows.compactMap { entry -> VisibleWindow? in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32, eligible.contains(pid),
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return VisibleWindow(pid: pid, frame: rect)
        }
        return RowSnapshot(visible: visible, frontmostPID: targetPID,
                           eligiblePIDs: eligible, runningPIDs: Set(apps.map(\.processIdentifier)),
                           reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    func toggle() {
        if enabled { Task { await stop() }; return }
        guard !busy else { return }
        guard AXIsProcessTrusted() else { message = "Grant Accessibility access in Setup before starting the row."; return }
        guard let primary = NSScreen.screens.first else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? primary
        viewport = ScreenGeometry.flip(screen.visibleFrame.insetBy(dx: 12, dy: 12), primaryMaxY: primary.frame.maxY)
        enabled = true
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard let self, enabled else { return }
                send(Date().timeIntervalSince(lastScan) >= 2 ? .sync : .focus)
            }
        }
        send(.sync)
    }
    func send(_ command: RowWindowEngine.Command) {
        guard enabled else { return }
        if busy {
            switch command {
            case .step(let direction): pending.add(direction)
            case .resize: pendingResize = true
            case .sync: pendingSync = true
            default: break
            }
            return
        }
        if !AXIsProcessTrusted() {
            Task { await stop(reason: "Accessibility access was removed. Grant it again in Setup.") }
            return
        }
        busy = true
        let state: RowSnapshot
        if case .sync = command {
            state = snapshot(); cachedSnapshot = state; lastScan = Date()
        } else if let cachedSnapshot {
            state = RowSnapshot(visible: cachedSnapshot.visible,
                                frontmostPID: targetPID,
                                eligiblePIDs: cachedSnapshot.eligiblePIDs, runningPIDs: cachedSnapshot.runningPIDs,
                                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        } else { state = snapshot() }
        if case .step = command { border.hide() }
        Task {
            let result = await engine.run(command, snapshot: state, viewport: viewport)
            if enabled {
                if message != result.message { message = result.message }
                if let rect = result.focusedFrame, let primary = NSScreen.screens.first,
                   result.focusedPID == NSWorkspace.shared.frontmostApplication?.processIdentifier {
                    border.show(frame: ScreenGeometry.flip(rect, primaryMaxY: primary.frame.maxY))
                } else { border.hide() }
                busy = false
                let steps = pending.take()
                if steps != 0 { send(.step(steps)) }
                else if pendingResize { pendingResize = false; send(.resize) }
                else if pendingSync || (result.needsScan && Date().timeIntervalSince(lastScan) > 0.4) {
                    pendingSync = false; send(.sync)
                }
            }
        }
    }
    func stop(reason: String? = nil) async {
        guard enabled else { return }
        enabled = false
        timer?.cancel(); timer = nil
        pending = NavigationBuffer(); pendingResize = false; pendingSync = false
        cachedSnapshot = nil
        border.hide()
        // The engine serializes restoration behind any in-flight layout operation.
        busy = true
        let result = await engine.run(.stop, snapshot: snapshot(), viewport: viewport)
        message = reason ?? result.message
        busy = false
    }
    func shutdown() async {
        timer?.cancel(); timer = nil
        hotkeys.stop()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        await stop()
    }
}
