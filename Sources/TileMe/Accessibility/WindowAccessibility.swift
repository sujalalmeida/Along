import ApplicationServices
import Foundation

/// Expected failures at the boundary with another process. Callers decide whether
/// to keep a window for a later retry or forget a window that no longer exists.
enum WindowAccessError: Error, Equatable {
    case accessibility(operation: String, code: AXError)
    case invalidValue(attribute: String)
    case invalidFrame
    case constrained

    var windowClosed: Bool {
        if case .accessibility(_, .invalidUIElement) = self { return true }
        return false
    }
}

/// All methods run on RowWindowEngine's serial worker, including in tests.
protocol WindowAccessibility: Sendable {
    var isTrusted: Bool { get }
    func application(pid: pid_t) -> AXUIElement
    func windows(of app: AXUIElement) throws -> [AXUIElement]
    func focusedWindow(of app: AXUIElement) throws -> AXUIElement?
    func frame(of window: AXUIElement) throws -> CGRect
    func isMovable(_ window: AXUIElement) throws -> Bool
    func title(of window: AXUIElement) throws -> String
    func place(_ window: AXUIElement, at frame: CGRect, from current: CGRect?) throws
    func move(_ window: AXUIElement, to point: CGPoint) throws
    func focus(_ window: AXUIElement, pid: pid_t) throws
}

struct SystemWindowAccessibility: WindowAccessibility {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func application(pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        return app
    }

    private func check(_ result: AXError, operation: String) throws {
        guard result == .success else {
            throw WindowAccessError.accessibility(operation: operation, code: result)
        }
    }

    private func read(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef {
        var value: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(element, attribute as CFString, &value), operation: attribute)
        guard let value else { throw WindowAccessError.invalidValue(attribute: attribute) }
        return value
    }

    func windows(of app: AXUIElement) throws -> [AXUIElement] {
        guard let windows = try read(app, kAXWindowsAttribute) as? [AXUIElement] else {
            throw WindowAccessError.invalidValue(attribute: kAXWindowsAttribute)
        }
        for window in windows { AXUIElementSetMessagingTimeout(window, 0.15) }
        return windows
    }

    func focusedWindow(of app: AXUIElement) throws -> AXUIElement? {
        do {
            let value = try read(app, kAXFocusedWindowAttribute)
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                throw WindowAccessError.invalidValue(attribute: kAXFocusedWindowAttribute)
            }
            // Core Foundation's type ID check is required before this bridge cast.
            return (value as! AXUIElement)
        } catch WindowAccessError.accessibility(_, .noValue) {
            return nil
        }
    }

    func frame(of window: AXUIElement) throws -> CGRect {
        let position = try read(window, kAXPositionAttribute)
        let size = try read(window, kAXSizeAttribute)
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw WindowAccessError.invalidFrame
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
            AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
        else {
            throw WindowAccessError.invalidFrame
        }
        let result = CGRect(origin: point, size: dimensions)
        guard result.isUsableWindowFrame else { throw WindowAccessError.invalidFrame }
        return result
    }

    func isMovable(_ window: AXUIElement) throws -> Bool {
        guard try read(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole else { return false }
        guard let minimized = try read(window, kAXMinimizedAttribute) as? Bool else {
            throw WindowAccessError.invalidValue(attribute: kAXMinimizedAttribute)
        }
        if minimized { return false }
        do {
            guard let fullScreen = try read(window, "AXFullScreen") as? Bool else {
                throw WindowAccessError.invalidValue(attribute: "AXFullScreen")
            }
            if fullScreen { return false }
        } catch WindowAccessError.accessibility(_, .attributeUnsupported) {
            // Some ordinary windows do not implement the optional full-screen attribute.
        }
        for attribute in [kAXPositionAttribute, kAXSizeAttribute] {
            var settable = DarwinBoolean(false)
            try check(AXUIElementIsAttributeSettable(window, attribute as CFString, &settable), operation: attribute)
            if !settable.boolValue { return false }
        }
        return true
    }

    func title(of window: AXUIElement) throws -> String {
        try read(window, kAXTitleAttribute) as? String ?? "Window"
    }

    func place(_ window: AXUIElement, at frame: CGRect, from current: CGRect?) throws {
        guard frame.isUsableWindowFrame else { throw WindowAccessError.invalidFrame }
        if let current, current.isClose(to: frame) { return }
        let sameSize = current.map { abs($0.width - frame.width) < 1 && abs($0.height - frame.height) < 1 } ?? false
        if !sameSize {
            var size = frame.size
            guard let value = AXValueCreate(.cgSize, &size) else { throw WindowAccessError.invalidFrame }
            try check(AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value), operation: "resize")
        }
        try move(window, to: frame.origin)
    }

    func move(_ window: AXUIElement, to point: CGPoint) throws {
        guard point.x.isFinite, point.y.isFinite else { throw WindowAccessError.invalidFrame }
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { throw WindowAccessError.invalidFrame }
        try check(AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value), operation: "move")
    }

    func focus(_ window: AXUIElement, pid: pid_t) throws {
        try check(AXUIElementPerformAction(window, kAXRaiseAction as CFString), operation: "raise")
        let app = application(pid: pid)
        try check(
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue), operation: "activate")
        try check(AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window), operation: "focus")
    }
}

extension CGRect {
    var isUsableWindowFrame: Bool {
        origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite && size.width > 0
            && size.height > 0
    }

    func isClose(to other: CGRect) -> Bool {
        abs(minX - other.minX) < 3 && abs(minY - other.minY) < 3 && abs(width - other.width) < 3
            && abs(height - other.height) < 3
    }
}
