import ApplicationServices
import Foundation
import TileMeCore

struct VisibleWindow: Sendable { let pid: pid_t; let frame: CGRect }
struct RowSnapshot: Sendable {
    let visible: [VisibleWindow]
    let frontmostPID: pid_t?
    let eligiblePIDs: Set<pid_t>
    var runningPIDs: Set<pid_t> = []
    var reduceMotion = false
}
struct RowResult: Sendable {
    let message: String
    var focusedPID: pid_t? = nil
    var focusedFrame: CGRect? = nil
    var needsScan = false
}

/// AX objects and the row are confined to one worker. No AX calls block the UI.
final class RowWindowEngine: @unchecked Sendable {
    enum Command: Sendable { case sync, focus, step(Int), resize, stop }
    private struct Record {
        let id: Int
        let pid: pid_t
        let window: AXUIElement
        let original: CGRect
        var lastApplied: CGRect?
        var title: String
    }
    private let queue = DispatchQueue(label: "io.tileme.row", qos: .userInitiated)
    private var records: [Record] = []
    private var row = ScrollingRow()
    private var originals: [(pid: pid_t, window: AXUIElement, frame: CGRect)] = []
    private var nextID = 1
    private var viewport = CGRect.zero
    private var needsRelayout = false
    private var placementConstrained = false
    private var lastFocused: Int?

    func run(_ command: Command, snapshot: RowSnapshot, viewport: CGRect) async -> RowResult {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = autoreleasepool { self.execute(command, snapshot: snapshot, viewport: viewport) }
                continuation.resume(returning: result)
            }
        }
    }
    private func read(_ window: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, key as CFString, &value) == .success else { return nil }
        return value
    }
    private func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = read(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = read(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
              point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }
    private func movable(_ window: AXUIElement) -> Bool {
        guard read(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              read(window, kAXMinimizedAttribute) as? Bool != true,
              read(window, "AXFullScreen") as? Bool != true else { return false }
        var position = DarwinBoolean(false); var size = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &position) == .success && position.boolValue &&
               AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &size) == .success && size.boolValue
    }
    @discardableResult private func place(_ window: AXUIElement, _ rect: CGRect, from current: CGRect? = nil) -> Bool {
        if let current, close(current, rect) { return true }
        var size = rect.size; var point = rect.origin
        guard let s = AXValueCreate(.cgSize, &size), let p = AXValueCreate(.cgPoint, &point) else { return false }
        let resize: AXError = current.map { abs($0.width - rect.width) < 1 && abs($0.height - rect.height) < 1 } == true
            ? .success : AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
        let move = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        return resize == .success && move == .success
    }
    private func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3 && abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
    }
    private func execute(_ command: Command, snapshot: RowSnapshot, viewport: CGRect) -> RowResult {
        if case .stop = command {
            var failures = 0
            for record in originals where frame(record.window) != nil && movable(record.window) {
                if !place(record.window, record.frame) { failures += 1 }
            }
            records.removeAll(); originals.removeAll(); row = ScrollingRow(); lastFocused = nil
            needsRelayout = false; placementConstrained = false
            return RowResult(message: failures == 0 ? "Row stopped. Original positions restored." : "Row stopped; \(failures) windows refused restoration.")
        }
        guard AXIsProcessTrusted() else { return RowResult(message: "Accessibility permission is required.") }
        var dirty = self.viewport != viewport || needsRelayout
        needsRelayout = false
        self.viewport = viewport
        var transientFailure = false
        if case .sync = command {
            originals.removeAll { !snapshot.runningPIDs.contains($0.pid) }
            let pids = Set(snapshot.visible.map(\.pid) + records.map(\.pid) + originals.map(\.pid))
            var alive = Set<Int>()
            var focusedID: Int?
            for pid in pids.sorted() where snapshot.eligiblePIDs.contains(pid) {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.15)
                guard let windows = read(app, kAXWindowsAttribute) as? [AXUIElement] else {
                    // A transient AX timeout must not discard original frames.
                    alive.formUnion(records.filter { $0.pid == pid }.map(\.id))
                    transientFailure = true
                    continue
                }
                // Only prune after a successful enumeration; a timeout is not a closed window.
                originals.removeAll { original in
                    original.pid == pid && !windows.contains { CFEqual($0, original.window) }
                }
                let focused = pid == snapshot.frontmostPID ? read(app, kAXFocusedWindowAttribute) : nil
                for window in windows {
                    AXUIElementSetMessagingTimeout(window, 0.15)
                    let known = records.firstIndex { CFEqual($0.window, window) }
                    guard let rect = frame(window) else {
                        if let known { alive.insert(records[known].id) }
                        continue
                    }
                    guard movable(window) else {
                        // Leave minimized/full-screen windows alone and remove them from the active row.
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
                        guard snapshot.visible.contains(where: { $0.pid == pid && close($0.frame, rect) }),
                              rect.intersection(viewport).width > 0, rect.intersection(viewport).height > 0 else { continue }
                        id = nextID; nextID += 1
                        let title = read(window, kAXTitleAttribute) as? String ?? "Window"
                        let original = originals.first(where: { CFEqual($0.window, window) })?.frame ?? rect
                        if !originals.contains(where: { CFEqual($0.window, window) }) { originals.append((pid, window, rect)) }
                        records.append(Record(id: id, pid: pid, window: window, original: original, title: title))
                        row.insert(id: id, width: min(rect.width, viewport.width))
                        dirty = true
                    }
                    alive.insert(id)
                    if let focused, CFEqual(focused, window) { focusedID = id }
                }
            }
            for record in records where !alive.contains(record.id) { row.remove(id: record.id); dirty = true }
            records.removeAll { !alive.contains($0.id) }
            if let focusedID, focusedID != lastFocused {
                row.focus(id: focusedID); dirty = true
            }
            lastFocused = focusedID
        }
        var focusChanged = false
        if case .focus = command, let pid = snapshot.frontmostPID {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.1)
            if let focused = read(app, kAXFocusedWindowAttribute) {
                guard let known = records.first(where: { CFEqual($0.window, focused) }) else {
                    return RowResult(message: "Updating windows…", needsScan: true)
                }
                if lastFocused != known.id {
                    row.focus(id: known.id); lastFocused = known.id
                    dirty = true; focusChanged = true
                }
            }
        }
        var raise = false
        switch command {
        case .step(let direction): row.step(direction); dirty = true; raise = true
        case .resize:
            if let id = row.focusedID, let column = row.columns.first(where: { $0.id == id }) {
                let widths = [viewport.width / 3, (viewport.width - 12) / 2, viewport.width * 2 / 3, viewport.width]
                row.resize(id: id, width: widths.first(where: { $0 > column.width + 15 }) ?? widths[0])
                dirty = true
            }
        case .sync, .focus, .stop: break
        }
        let targets = row.layout(in: viewport)
        var constrained = 0
        if dirty {
            if (raise || focusChanged) && !snapshot.reduceMotion {
                let moving = records.compactMap { record -> (AXUIElement, CGRect, CGRect)? in
                    guard let start = record.lastApplied, let target = targets[record.id],
                          abs(start.minX - target.minX) > 1 || abs(start.minY - target.minY) > 1,
                          start.intersects(viewport) || target.intersects(viewport) else { return nil }
                    return (record.window, start, target)
                }
                if !moving.isEmpty {
                    let startTime = ProcessInfo.processInfo.systemUptime
                    let duration = 0.16
                    // Elapsed-time interpolation skips frames if an app responds slowly.
                    while true {
                        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
                        if elapsed >= duration { break }
                        let t = CGFloat(elapsed / duration)
                        let eased = t * t * (3 - 2 * t)
                        for (window, start, target) in moving {
                            var point = CGPoint(x: start.minX + (target.minX - start.minX) * eased,
                                                y: start.minY + (target.minY - start.minY) * eased)
                            if let value = AXValueCreate(.cgPoint, &point) {
                                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
                            }
                        }
                        let spent = ProcessInfo.processInfo.systemUptime - startTime - elapsed
                        if spent < 1.0 / 60 { Thread.sleep(forTimeInterval: 1.0 / 60 - spent) }
                    }
                }
            }
            // Place offscreen columns first so the selected window can be raised last.
            for index in records.indices {
                guard let target = targets[records[index].id] else { continue }
                if !place(records[index].window, target, from: records[index].lastApplied) { constrained += 1 }
                let actual = frame(records[index].window)
                if let actual, !close(actual, target) { constrained += 1 }
                if let actual, abs(actual.width - target.width) > 3 {
                    row.resize(id: records[index].id, width: actual.width)
                    needsRelayout = true
                }
                records[index].lastApplied = actual ?? target
            }
        }
        if dirty { placementConstrained = constrained > 0 }
        guard let focus = records.first(where: { $0.id == row.focusedID }) else {
            return RowResult(message: "Row ready — open a normal window on this display.")
        }
        if raise {
            AXUIElementPerformAction(focus.window, kAXRaiseAction as CFString)
            let app = AXUIElementCreateApplication(focus.pid)
            AXUIElementSetMessagingTimeout(app, 0.15)
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, focus.window)
            lastFocused = focus.id
        }
        let index = (row.columns.firstIndex { $0.id == focus.id } ?? 0) + 1
        let suffix = placementConstrained ? " · Some positions constrained by macOS/app" : transientFailure ? " · An app is not responding" : ""
        return RowResult(message: "\(index) of \(row.columns.count) · \(focus.title)\(suffix)",
                         focusedPID: focus.pid, focusedFrame: frame(focus.window))
    }
}
