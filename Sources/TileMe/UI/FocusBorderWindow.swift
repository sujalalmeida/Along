import AppKit

@MainActor
final class FocusBorderWindow {
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.ignoresCycle, .stationary]
        panel.contentView = BorderView()
        return panel
    }()
    func show(frame: CGRect) {
        let target = frame.insetBy(dx: -2, dy: -2)
        if panel.frame != target { panel.setFrame(target, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    func hide() { panel.orderOut(nil) }
}

private final class BorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemOrange.withAlphaComponent(0.85).setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 10, yRadius: 10)
        path.lineWidth = 2; path.stroke()
    }
}
