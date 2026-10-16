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
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                self?.send(.sync)
            }
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
        return RowSnapshot(visible: visible, frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                           eligiblePIDs: eligible)
    }
    func toggle() {
        guard !busy else { return }
        if enabled { Task { await stop() }; return }
        guard AXIsProcessTrusted() else { message = "Grant Accessibility access in Setup before starting the row."; return }
        guard let primary = NSScreen.screens.first else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? primary
        viewport = ScreenGeometry.flip(screen.visibleFrame.insetBy(dx: 12, dy: 12), primaryMaxY: primary.frame.maxY)
        enabled = true
        send(.sync)
    }
    func send(_ command: RowWindowEngine.Command) {
        guard enabled, !busy else { return }
        if !AXIsProcessTrusted() {
            Task { await stop(reason: "Accessibility access was removed. Grant it again in Setup.") }
            return
        }
        busy = true
        let state = snapshot()
        Task {
            let result = await engine.run(command, snapshot: state, viewport: viewport)
            if enabled {
                message = result.message
                if let rect = result.focusedFrame, let primary = NSScreen.screens.first,
                   result.focusedPID == NSWorkspace.shared.frontmostApplication?.processIdentifier {
                    border.show(frame: ScreenGeometry.flip(rect, primaryMaxY: primary.frame.maxY))
                } else { border.hide() }
                busy = false
            }
        }
    }
    func stop(reason: String? = nil) async {
        guard enabled else { return }
        enabled = false
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
