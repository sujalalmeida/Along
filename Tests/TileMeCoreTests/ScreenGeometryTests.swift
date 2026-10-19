import CoreGraphics
import Testing

@testable import TileMeCore

struct ScreenGeometryTests {
    @Test func coordinateConversionRoundTripsAcrossDisplays() {
        for rect in [
            CGRect(x: 80, y: 100, width: 400, height: 300),
            CGRect(x: -1400, y: 1050, width: 800, height: 500),
            CGRect(x: 20, y: -900, width: 600, height: 400),
        ] {
            let ax = ScreenGeometry.flip(rect, primaryMaxY: 900)
            #expect(ax.minY == 900 - rect.maxY)
            #expect(ScreenGeometry.flip(ax, primaryMaxY: 900) == rect)
        }
    }

    @Test func visibleFrameInsetsSurviveConversion() {
        let visible = CGRect(x: 0, y: 60, width: 1440, height: 815).insetBy(dx: 12, dy: 12)
        let ax = ScreenGeometry.flip(visible, primaryMaxY: 900)
        #expect(ax == CGRect(x: 12, y: 37, width: 1416, height: 791))
    }

    @Test func displayAbovePrimaryHasNegativeAccessibilityY() {
        let upperDisplay = CGRect(x: 100, y: 900, width: 1920, height: 1080)
        #expect(ScreenGeometry.flip(upperDisplay, primaryMaxY: 900).minY == -1080)
    }
}
