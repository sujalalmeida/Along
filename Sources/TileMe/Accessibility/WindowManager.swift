import ApplicationServices
import Foundation
import TileMeCore

/// All AX references and restore history stay on this dedicated serial queue.
/// The unchecked conformance is limited to this queue-confined bridge.
final class WindowManager: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.tileme.accessibility", qos: .userInitiated)
    private var history: [(window: AXUIElement, frame: CGRect)] = []

    func perform(_ action: SnapAction, pid: pid_t, screens: [ScreenDescriptor], primaryMaxY: CGFloat,
                 innerGap: CGFloat, outerGap: CGFloat) async -> String {
        await withCheckedContinuation { continuation in
            queue.async {
                do {
                    let message = try self.apply(action, pid: pid, screens: screens, primaryMaxY: primaryMaxY,
                                                 innerGap: innerGap, outerGap: outerGap)
                    continuation.resume(returning: message)
                } catch {
                    continuation.resume(returning: error.localizedDescription)
                }
            }
        }
    }

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func attribute(_ window: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func frame(_ window: AXUIElement) throws -> CGRect {
        guard let position = attribute(window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(window, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw Failure(message: "This window does not expose its position and size.")
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else {
            throw Failure(message: "The application returned an invalid window frame.")
        }
        return CGRect(origin: point, size: dimensions)
    }

    private func writable(_ window: AXUIElement, _ name: String) -> Bool {
        var value = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window, name as CFString, &value) == .success && value.boolValue
    }

    private func write(_ window: AXUIElement, rect: CGRect, resize: Bool) throws {
        var size = rect.size
        var point = rect.origin
        if resize {
            guard let value = AXValueCreate(.cgSize, &size),
                  AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success else {
                throw Failure(message: "The application refused to resize this window. Restore is available if it moved.")
            }
        }
        guard let value = AXValueCreate(.cgPoint, &point),
              AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success else {
            throw Failure(message: "The application refused to move this window. Restore is available if it resized.")
        }
    }

    private func apply(_ action: SnapAction, pid: pid_t, screens: [ScreenDescriptor], primaryMaxY: CGFloat,
                       innerGap: CGFloat, outerGap: CGFloat) throws -> String {
        guard AXIsProcessTrusted() else { throw Failure(message: "Grant Accessibility access in TileMe Setup first.") }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let value = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw Failure(message: "No focused window found. Focus a normal app window and try again.")
        }
        let window = value as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.3)
        if (attribute(window, kAXMinimizedAttribute) as? Bool) == true ||
            (attribute(window, "AXFullScreen") as? Bool) == true {
            throw Failure(message: "Minimized and full-screen windows are skipped.")
        }
        guard (attribute(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole else {
            throw Failure(message: "Only standard application windows can be tiled.")
        }
        let original = try frame(window)
        let existing = history.firstIndex { CFEqual($0.window, window) }
        let target: CGRect
        if action == .restore {
            guard let existing else { throw Failure(message: "No saved frame for this window yet.") }
            target = history[existing].frame
        } else {
            let appKitFrame = ScreenGeometry.flip(original, primaryMaxY: primaryMaxY)
            guard let index = ScreenGeometry.screenIndex(for: appKitFrame, screens: screens),
                  let rect = ScreenGeometry.target(for: action, visibleFrame: screens[index].visibleFrame,
                                                   currentFrame: appKitFrame, innerGap: innerGap, outerGap: outerGap) else {
                throw Failure(message: "No usable display found.")
            }
            target = ScreenGeometry.flip(rect, primaryMaxY: primaryMaxY)
        }
        let resize = abs(original.width - target.width) > 1 || abs(original.height - target.height) > 1
        guard writable(window, kAXPositionAttribute), !resize || writable(window, kAXSizeAttribute) else {
            throw Failure(message: "This window does not support the requested move or resize.")
        }
        if action != .restore && existing == nil {
            if history.count >= 128 { history.removeFirst() }
            history.append((window, original))
        }
        try write(window, rect: target, resize: resize)
        // Some apps apply AX writes asynchronously. This short wait is on the dedicated worker, never the UI thread.
        Thread.sleep(forTimeInterval: 0.08)
        var actual = try frame(window)
        func matches(_ rect: CGRect) -> Bool {
            abs(rect.minX - target.minX) <= 2 && abs(rect.minY - target.minY) <= 2 &&
            abs(rect.width - target.width) <= 2 && abs(rect.height - target.height) <= 2
        }
        if !matches(actual) {
            // One bounded retry handles apps that adjust position during a resize.
            try write(window, rect: target, resize: resize)
            Thread.sleep(forTimeInterval: 0.08)
            actual = try frame(window)
        }
        guard matches(actual) else {
            return "Window adjusted, but the app imposed a size or position limit. Restore remains available."
        }
        if action == .restore, let existing { history.remove(at: existing) }
        return "\(action.title) applied."
    }
}
