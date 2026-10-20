import CoreGraphics

public enum ScreenGeometry {
    /// AX uses a top-left origin anchored to the primary display; AppKit uses bottom-left.
    /// Use the primary screen's maxY, never the union of all displays.
    public static func flip(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryMaxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
