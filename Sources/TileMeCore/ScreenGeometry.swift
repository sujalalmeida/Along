import Foundation
import CoreGraphics

public struct ScreenDescriptor: Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect
    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public enum ScreenGeometry {
    /// AX uses a top-left origin anchored to the primary display; AppKit uses bottom-left.
    /// Use the primary screen's maxY, never the union of all displays.
    public static func flip(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryMaxY - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func screenIndex(for window: CGRect, screens: [ScreenDescriptor]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let areas = screens.map { screen -> CGFloat in
            let overlap = window.intersection(screen.frame)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        if let largest = areas.max(), largest > 0 { return areas.firstIndex(of: largest) }
        // An off-screen window can still be recovered on the nearest display.
        return screens.indices.min { a, b in
            func distance(_ rect: CGRect) -> CGFloat {
                let dx = max(rect.minX - window.midX, 0, window.midX - rect.maxX)
                let dy = max(rect.minY - window.midY, 0, window.midY - rect.maxY)
                return dx * dx + dy * dy
            }
            return distance(screens[a].frame) < distance(screens[b].frame)
        }
    }

    public static func target(for action: SnapAction, visibleFrame: CGRect, currentFrame: CGRect,
                              innerGap: CGFloat = 8, outerGap: CGFloat = 8) -> CGRect? {
        guard action != .restore, visibleFrame.width > 0, visibleFrame.height > 0 else { return nil }
        let outer = min(max(outerGap.isFinite ? outerGap : 0, 0), max(0, (min(visibleFrame.width, visibleFrame.height) - 1) / 2))
        let area = visibleFrame.insetBy(dx: outer, dy: outer)
        if action == .center {
            let width = min(max(currentFrame.width, 1), area.width)
            let height = min(max(currentFrame.height, 1), area.height)
            return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
        }
        // Fractions below use AppKit's bottom-left origin.
        let region: CGRect
        switch action {
        case .leftHalf: region = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: region = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: region = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .bottomHalf: region = CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .topLeft: region = CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .topRight: region = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .bottomLeft: region = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .bottomRight: region = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .leftThird: region = CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)
        case .centerThird: region = CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .rightThird: region = CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .leftTwoThirds: region = CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1)
        case .rightTwoThirds: region = CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)
        case .maximize: return area
        case .center, .restore: return nil
        }
        let gap = min(max(innerGap.isFinite ? innerGap : 0, 0), max(0, min(area.width / 3, area.height / 2) - 1))
        let left = region.minX > 0 ? gap / 2 : 0
        let right = region.maxX < 1 - 0.000001 ? gap / 2 : 0
        let bottom = region.minY > 0 ? gap / 2 : 0
        let top = region.maxY < 1 - 0.000001 ? gap / 2 : 0
        return CGRect(x: area.minX + area.width * region.minX + left,
                      y: area.minY + area.height * region.minY + bottom,
                      width: area.width * region.width - left - right,
                      height: area.height * region.height - bottom - top)
    }
}
