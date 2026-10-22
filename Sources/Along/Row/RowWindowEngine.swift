import AlongCore
import ApplicationServices
import Foundation
import OSLog

struct VisibleWindow: Sendable {
    let pid: pid_t
    let frame: CGRect
}
struct RowSnapshot: Sendable {
    let visible: [VisibleWindow]
    let frontmostPID: pid_t?
    let eligiblePIDs: Set<pid_t>
    var runningPIDs: Set<pid_t> = []
    var reduceMotion = false
    var refreshRate = 60
}
struct RowResult: Sendable {
    let message: String
    var needsScan = false
    var pendingRestorations = 0
}

/// AX objects and the row are confined to one worker. No AX calls block the UI.
final class RowWindowEngine: @unchecked Sendable {
    enum Command: Sendable {
        case sync, focus
        case step(Int)
        case scroll(CGFloat)
        case settle, resize, stop
    }
    private struct Record {
        let id: Int
        let pid: pid_t
        let window: AXUIElement
        var lastApplied: CGRect?
        var title: String
    }
    private let accessibility: any WindowAccessibility
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "WindowAccess")

    init(accessibility: any WindowAccessibility = SystemWindowAccessibility()) {
        self.accessibility = accessibility
    }

    private let motion = MotionInterruption()
    private var velocities: [Int: CGVector] = [:]
    func interruptMotion() { motion.interrupt() }
    private let queue = DispatchQueue(label: "\(AppIdentity.bundleIdentifier).row", qos: .userInitiated)
    private var records: [Record] = []
    private var row = ScrollingRow()
    private var originals: [(pid: pid_t, window: AXUIElement, frame: CGRect)] = []
    private var nextID = 1
    private var viewport = CGRect.zero
    private var needsRelayout = false
    private var placementConstrained = false
    private var unavailable = Set<Int>()
    private var lastFocused: Int?

    func run(_ command: Command, snapshot: RowSnapshot, viewport: CGRect) async -> RowResult {
        let revision = motion.current()
        return await withCheckedContinuation { continuation in
            queue.async {
                let result = autoreleasepool {
                    self.execute(command, snapshot: snapshot, viewport: viewport, revision: revision)
                }
                continuation.resume(returning: result)
            }
        }
    }
    /// Preserve failed originals until an explicit retry succeeds. Closed windows
    /// can be discarded; a timeout, minimized window, or permission loss cannot.
    private func restore(snapshot: RowSnapshot) -> RowResult {
        originals.removeAll { !snapshot.runningPIDs.contains($0.pid) }
        originals = originals.filter { record in
            do {
                return try !accessibility.restoreFrame(record.window, to: record.frame)
            } catch let error as WindowAccessError where error.windowClosed {
                return false
            } catch {
                report(error)
                return true
            }
        }
        records.removeAll()
        row = ScrollingRow()
        lastFocused = nil
        needsRelayout = false
        placementConstrained = false
        unavailable.removeAll()
        velocities.removeAll()
        let count = originals.count
        let windows = count == 1 ? "window" : "windows"
        return RowResult(
            message: count == 0
                ? "Row stopped. Original positions restored."
                : "Row stopped. \(count) \(windows) still need restoring. Unminimize them or check Accessibility, then retry.",
            pendingRestorations: count
        )
    }

    private func report(_ error: Error) {
        // Never log window titles, application contents, or user data.
        logger.debug("Window operation failed: \(String(describing: error), privacy: .public)")
    }

    private func synchronize(snapshot: RowSnapshot, viewport: CGRect) -> (dirty: Bool, failed: Bool) {
        var dirty = false
        var transientFailure = false
        unavailable.removeAll(keepingCapacity: true)
        originals.removeAll { !snapshot.runningPIDs.contains($0.pid) }
        let pids = Set(snapshot.visible.map(\.pid) + records.map(\.pid) + originals.map(\.pid))
        var alive = Set<Int>()
        var focusedID: Int?
        for pid in pids.sorted() where snapshot.eligiblePIDs.contains(pid) {
            let app = accessibility.application(pid: pid)
            let windows: [AXUIElement]
            do { windows = try accessibility.windows(of: app) } catch {
                report(error)
                // A transient AX timeout must not discard original frames.
                let deferred = records.filter { $0.pid == pid }.map(\.id)
                alive.formUnion(deferred)
                unavailable.formUnion(deferred)
                transientFailure = true
                continue
            }
            // AXWindows can omit a live window temporarily. Only an invalid AX
            // reference or a terminated process proves its original is obsolete.
            originals.removeAll { original in
                guard original.pid == pid, !windows.contains(where: { CFEqual($0, original.window) }) else {
                    return false
                }
                do {
                    _ = try accessibility.frame(of: original.window)
                    return false
                } catch let error as WindowAccessError {
                    return error.windowClosed
                } catch {
                    return false
                }
            }
            var focused: AXUIElement?
            if pid == snapshot.frontmostPID {
                do { focused = try accessibility.focusedWindow(of: app) } catch {
                    report(error)
                    transientFailure = true
                }
            }
            for window in windows {
                let known = records.firstIndex { CFEqual($0.window, window) }
                let rect: CGRect
                do {
                    rect = try accessibility.frame(of: window)
                    guard try accessibility.isMovable(window) else { continue }
                } catch let error as WindowAccessError where error.windowClosed {
                    continue
                } catch {
                    report(error)
                    if let known {
                        alive.insert(records[known].id)
                        unavailable.insert(records[known].id)
                    }
                    transientFailure = true
                    continue
                }
                let id: Int
                if let known {
                    id = records[known].id
                    if let applied = records[known].lastApplied, abs(applied.width - rect.width) > 3 {
                        row.resize(id: id, width: rect.width)
                        dirty = true
                    }
                    records[known].lastApplied = rect
                } else {
                    guard snapshot.visible.contains(where: { $0.pid == pid && $0.frame.isClose(to: rect) }),
                        rect.intersection(viewport).width > 0, rect.intersection(viewport).height > 0
                    else { continue }
                    id = nextID
                    nextID += 1
                    // A missing title affects presentation only; geometry must still succeed.
                    let title = (try? accessibility.title(of: window)) ?? "Window"
                    if !originals.contains(where: { CFEqual($0.window, window) }) {
                        originals.append((pid, window, rect))
                    }
                    records.append(Record(id: id, pid: pid, window: window, title: title))
                    row.insert(id: id, width: min(rect.width, viewport.width))
                    dirty = true
                }
                alive.insert(id)
                if let focused, CFEqual(focused, window) { focusedID = id }
            }
        }
        for record in records where !alive.contains(record.id) {
            row.remove(id: record.id)
            dirty = true
        }
        records.removeAll { !alive.contains($0.id) }
        if let focusedID, focusedID != lastFocused {
            row.focus(id: focusedID)
            dirty = true
        }
        lastFocused = focusedID
        return (dirty, transientFailure)
    }

    private struct MotionTarget {
        let id: Int
        let window: AXUIElement
        let start: CGRect
        let target: CGRect
        let velocity: CGVector
    }

    private func animate(targets: [Int: CGRect], viewport: CGRect, refreshRate: Int, revision: UInt64)
        -> (interrupted: Bool, failed: Bool)
    {
        var interrupted = false
        var failed = false
        let moving = records.compactMap { record -> MotionTarget? in
            guard !unavailable.contains(record.id), let target = targets[record.id],
                let start = record.lastApplied ?? (try? accessibility.frame(of: record.window)),
                abs(start.minX - target.minX) > 0.5 || abs(start.minY - target.minY) > 0.5,
                start.intersects(viewport) || target.intersects(viewport)
            else { return nil }
            return MotionTarget(
                id: record.id, window: record.window, start: start, target: target,
                velocity: velocities[record.id] ?? .zero)
        }
        if !moving.isEmpty {
            let startTime = ProcessInfo.processInfo.systemUptime
            let fps = Double(min(120, max(30, refreshRate)))
            while true {
                if motion.current() != revision {
                    interrupted = true
                    break
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - startTime
                if elapsed >= WindowMotion.duration { break }
                for item in moving {
                    let (id, window, start, target, velocity) = (
                        item.id, item.window, item.start, item.target, item.velocity
                    )
                    if motion.current() != revision {
                        interrupted = true
                        break
                    }
                    let x = WindowMotion.sample(
                        from: start.minX, to: target.minX, velocity: velocity.dx, elapsed: elapsed)
                    let y = WindowMotion.sample(
                        from: start.minY, to: target.minY, velocity: velocity.dy, elapsed: elapsed)
                    do {
                        let point = CGPoint(x: x.position, y: y.position)
                        if let index = records.firstIndex(where: { $0.id == id }),
                            let current = records[index].lastApplied,
                            abs(current.minX - point.x) < 0.5 && abs(current.minY - point.y) < 0.5
                        {
                            continue
                        }
                        try accessibility.move(window, to: point)
                        if let index = records.firstIndex(where: { $0.id == id }) {
                            records[index].lastApplied = CGRect(origin: point, size: start.size)
                        }
                        velocities[id] = CGVector(dx: x.velocity, dy: y.velocity)
                    } catch {
                        // Stop this animation rather than hammering an unresponsive app
                        // at display refresh rate. The final placement reports the issue.
                        report(error)
                        if let index = records.firstIndex(where: { $0.id == id }) { records[index].lastApplied = nil }
                        velocities.removeValue(forKey: id)
                        failed = true
                        break
                    }
                }
                if interrupted || failed { break }
                // Schedule against the animation clock, skipping missed frames.
                let now = ProcessInfo.processInfo.systemUptime - startTime
                let next = (floor(now * fps) + 1) / fps
                Thread.sleep(forTimeInterval: max(0, next - now))
            }
        }
        return (interrupted, failed)
    }

    private func apply(targets: [Int: CGRect], resizeWindows: Bool) -> Int {
        var constrained = 0
        for index in records.indices {
            guard !unavailable.contains(records[index].id), let target = targets[records[index].id] else { continue }
            let window = records[index].window
            do {
                if resizeWindows {
                    let current = try records[index].lastApplied ?? accessibility.frame(of: window)
                    if current.isClose(to: target) { continue }
                    try accessibility.place(window, at: target, from: current)
                    let actual = try accessibility.frame(of: window)
                    if !actual.isClose(to: target) { constrained += 1 }
                    if abs(actual.width - target.width) > 3 {
                        row.resize(id: records[index].id, width: actual.width)
                        needsRelayout = true
                    }
                    records[index].lastApplied = actual
                } else {
                    // Navigation only changes position. Avoid repeated AX reads and
                    // size writes; the next full scan reconciles app constraints.
                    if let current = records[index].lastApplied,
                        current.origin == target.origin
                    {
                        continue
                    }
                    try accessibility.move(window, to: target.origin)
                    if let current = records[index].lastApplied {
                        records[index].lastApplied = CGRect(origin: target.origin, size: current.size)
                    }
                }
            } catch {
                report(error)
                constrained += 1
                records[index].lastApplied = nil
            }
        }
        return constrained
    }

    private func execute(_ command: Command, snapshot: RowSnapshot, viewport: CGRect, revision: UInt64) -> RowResult {
        if case .stop = command { return restore(snapshot: snapshot) }
        guard accessibility.isTrusted else { return RowResult(message: "Accessibility permission is required.") }
        guard viewport.isUsableWindowFrame else { return RowResult(message: "This display has no usable window area.") }
        var dirty = self.viewport != viewport || needsRelayout
        needsRelayout = false
        self.viewport = viewport
        var transientFailure = false

        if case .sync = command {
            let discovery = synchronize(snapshot: snapshot, viewport: viewport)
            dirty = dirty || discovery.dirty
            transientFailure = discovery.failed
        }
        var focusChanged = false
        if case .focus = command, let pid = snapshot.frontmostPID {
            let app = accessibility.application(pid: pid)
            let focused: AXUIElement?
            do { focused = try accessibility.focusedWindow(of: app) } catch {
                report(error)
                return RowResult(
                    message: "The active app is not responding. \(AppIdentity.name) will try again shortly.")
            }
            if let focused {
                guard let known = records.first(where: { CFEqual($0.window, focused) }) else {
                    return RowResult(message: "Updating windows…", needsScan: true)
                }
                if lastFocused != known.id {
                    row.focus(id: known.id)
                    lastFocused = known.id
                    dirty = true
                    focusChanged = true
                }
            }
        }
        var raise = false
        var directScroll = false
        var resizeWindows = false
        switch command {
        case .step(let direction):
            row.step(direction)
            dirty = true
            raise = true
        case .scroll(let delta):
            row.scroll(by: delta, in: viewport)
            dirty = true
            directScroll = true
        case .settle:
            dirty = true
            raise = true
        case .resize:
            resizeWindows = true
            if let id = row.focusedID, let column = row.columns.first(where: { $0.id == id }) {
                let widths = [viewport.width / 3, (viewport.width - 12) / 2, viewport.width * 2 / 3, viewport.width]
                row.resize(id: id, width: widths.first(where: { $0 > column.width + 15 }) ?? widths[0])
                dirty = true
            }
        case .sync: resizeWindows = true
        case .focus, .stop: break
        }
        let targets = row.layout(in: viewport, revealFocus: !directScroll)
        if case .sync = command {
            // A window skipped during an earlier failed scan may still be away
            // from its target even when the row's columns have not changed.
            dirty =
                dirty
                || records.contains { record in
                    guard !unavailable.contains(record.id), let target = targets[record.id] else { return false }
                    return record.lastApplied?.isClose(to: target) != true
                }
        }
        var constrained = 0
        if dirty {
            var interrupted = false
            if (raise || focusChanged) && !snapshot.reduceMotion {
                let animation = animate(
                    targets: targets, viewport: viewport, refreshRate: snapshot.refreshRate, revision: revision)
                interrupted = animation.interrupted
                transientFailure = transientFailure || animation.failed
            }
            if interrupted {
                // Keep actual in-flight positions. The pending command retargets from here
                // instead of snapping to an obsolete destination before starting again.
                return RowResult(message: "Moving through row…")
            }
            velocities.removeAll(keepingCapacity: true)
            constrained = apply(targets: targets, resizeWindows: resizeWindows)
        }
        if dirty { placementConstrained = constrained > 0 }
        guard let focus = records.first(where: { $0.id == row.focusedID }) else {
            return RowResult(message: "Row ready — open a normal window on this display.")
        }
        if raise && !unavailable.contains(focus.id) {
            do {
                try accessibility.focus(focus.window, pid: focus.pid)
                lastFocused = focus.id
            } catch {
                report(error)
                return RowResult(message: "The selected app could not take focus. Try selecting its window directly.")
            }
        }
        let index = (row.columns.firstIndex { $0.id == focus.id } ?? 0) + 1
        let suffix =
            placementConstrained
            ? " · Some positions constrained by macOS/app" : transientFailure ? " · An app is not responding" : ""
        return RowResult(message: "\(index) of \(row.columns.count) · \(focus.title)\(suffix)")
    }
}
