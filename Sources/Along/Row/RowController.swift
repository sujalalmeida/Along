import AlongCore
import AppKit
import ApplicationServices
import Combine

@MainActor
final class RowController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var message = "Start a scrolling row on the current display"
    @Published private(set) var shortcutWarning = ""
    @Published private(set) var pendingRestorations = 0
    private var generation: UInt64 = 0
    private var monitoring = false
    private var stopTask: Task<Void, Never>?
    private let engine = RowWindowEngine()
    private let hotkeys = HotkeyManager()
    private var timer: Task<Void, Never>?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var panelTargetPID: pid_t?
    func rememberTargetApplication() {
        if let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            panelTargetPID = app.processIdentifier
        }
    }
    private var targetPID: pid_t? {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return pid == ProcessInfo.processInfo.processIdentifier ? panelTargetPID : pid
    }
    private var pending = NavigationBuffer()
    private var pendingScroll: CGFloat = 0
    private var pendingSettle = false
    private var scrollTask: Task<Void, Never>?
    private var displayRefreshRate = 60
    private var pendingResize = false
    private var pendingSync = false
    private var cachedSnapshot: RowSnapshot?
    private var lastScan = Date.distantPast
    private var viewport = CGRect.zero

    func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        hotkeys.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .previousWindow: send(.step(-1))
            case .nextWindow: send(.step(1))
            case .cycleWidth: send(.resize)
            case .toggleRow: toggle()
            }
        }
        hotkeys.start()
        shortcutWarning = hotkeys.conflicts.joined(separator: "; ")
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.enabled,
                    event.modifierFlags.intersection([.control, .option]) == [.control, .option],
                    abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                else { return }
                let delta = -event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 12)
                self.send(.scroll(delta))
                self.scrollTask?.cancel()
                self.scrollTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
                    guard let self else { return }
                    self.send(.settle)
                    self.scrollTask = nil
                }
            }
        }
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.stop(reason: "Space changed — start a row in this Space.") }
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.stop(reason: "Display configuration changed — start the row again.") }
            })
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.send(.focus) }
            })
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ] {
            observers.append(
                NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor in self?.send(.sync) }
                })
        }
    }
    private func snapshot() -> RowSnapshot {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
        let eligible = Set(
            apps.filter { $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != ownPID }.map(
                \.processIdentifier))
        let windows =
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let visible = windows.compactMap { entry -> VisibleWindow? in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32, eligible.contains(pid),
                entry[kCGWindowLayer as String] as? Int == 0,
                let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return VisibleWindow(pid: pid, frame: rect)
        }
        return RowSnapshot(
            visible: visible, frontmostPID: targetPID,
            eligiblePIDs: eligible, runningPIDs: Set(apps.map(\.processIdentifier)),
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            refreshRate: displayRefreshRate)
    }
    func toggle() {
        if enabled {
            Task { await stop() }
            return
        }
        guard !busy else { return }
        guard AXIsProcessTrusted() else {
            message = "Grant Accessibility access in Setup before starting the row."
            return
        }
        guard let primary = NSScreen.screens.first else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? primary
        displayRefreshRate = min(120, max(30, screen.maximumFramesPerSecond))
        viewport = ScreenGeometry.flip(screen.visibleFrame.insetBy(dx: 12, dy: 12), primaryMaxY: primary.frame.maxY)
        generation &+= 1
        enabled = true
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard let self, enabled else { return }
                guard scrollTask == nil else { continue }
                send(Date().timeIntervalSince(lastScan) >= 2 ? .sync : .focus)
            }
        }
        send(.sync)
    }
    func send(_ command: RowWindowEngine.Command) {
        guard enabled else { return }
        if case .scroll = command { pendingSettle = false }
        if busy {
            switch command {
            case .step(let direction):
                pending.add(direction)
                engine.interruptMotion()
            case .scroll(let delta):
                pendingScroll = min(10000, max(-10000, pendingScroll + delta))
                engine.interruptMotion()
            case .settle: pendingSettle = true
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
            state = snapshot()
            cachedSnapshot = state
            lastScan = Date()
        } else if let cachedSnapshot {
            state = RowSnapshot(
                visible: cachedSnapshot.visible,
                frontmostPID: targetPID,
                eligiblePIDs: cachedSnapshot.eligiblePIDs, runningPIDs: cachedSnapshot.runningPIDs,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                refreshRate: displayRefreshRate)
        } else {
            state = snapshot()
        }
        let requestGeneration = generation
        Task {
            let result = await engine.run(command, snapshot: state, viewport: viewport)
            if enabled && generation == requestGeneration {
                if message != result.message { message = result.message }
                busy = false
                if result.scanInterrupted { pendingSync = true }
                let steps = pending.take()
                if steps != 0 {
                    send(.step(steps))
                } else if abs(pendingScroll) > 0.01 {
                    let delta = pendingScroll
                    pendingScroll = 0
                    send(.scroll(delta))
                } else if pendingSettle {
                    pendingSettle = false
                    send(.settle)
                } else if pendingResize {
                    pendingResize = false
                    send(.resize)
                } else if scrollTask == nil
                    && (pendingSync || (result.needsScan && Date().timeIntervalSince(lastScan) > 0.4))
                {
                    pendingSync = false
                    send(.sync)
                }
            }
        }
    }
    func stop(reason: String? = nil) async {
        // A quit request must join an existing stop rather than outrun restoration.
        if let stopTask {
            await stopTask.value
            return
        }
        guard enabled || (pendingRestorations > 0 && !busy) else { return }
        generation &+= 1
        enabled = false
        timer?.cancel()
        timer = nil
        pending = NavigationBuffer()
        pendingResize = false
        pendingSync = false
        cachedSnapshot = nil
        scrollTask?.cancel()
        scrollTask = nil
        pendingScroll = 0
        pendingSettle = false
        engine.interruptMotion()
        // The engine serializes restoration behind any in-flight layout operation.
        busy = true
        let state = snapshot()
        let task = Task {
            let result = await engine.run(.stop, snapshot: state, viewport: viewport)
            pendingRestorations = result.pendingRestorations
            message = result.pendingRestorations > 0 ? result.message : reason ?? result.message
            busy = false
            stopTask = nil
        }
        stopTask = task
        await task.value
    }
    func shutdown() async {
        timer?.cancel()
        timer = nil
        hotkeys.stop()
        monitoring = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        await stop()
    }
}
