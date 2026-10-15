import Testing
import CoreGraphics
@testable import TileMeCore

struct ScreenGeometryTests {
    private let visible = CGRect(x: 0, y: 24, width: 1200, height: 876)
    private let current = CGRect(x: 80, y: 100, width: 400, height: 300)

    private func target(_ action: SnapAction, inner: CGFloat = 0, outer: CGFloat = 0) -> CGRect {
        ScreenGeometry.target(for: action, visibleFrame: visible, currentFrame: current, innerGap: inner, outerGap: outer)!
    }

    @Test func testHalvesCoverVisibleFrameWithoutOverlap() {
        let left = target(.leftHalf), right = target(.rightHalf)
        #expect(left == CGRect(x: 0, y: 24, width: 600, height: 876))
        #expect(left.maxX == right.minX)
        #expect(left.union(right) == visible)
        #expect(target(.bottomHalf).maxY == target(.topHalf).minY)
        #expect(target(.bottomHalf).union(target(.topHalf)) == visible)
    }

    @Test func testQuartersUseTopAndBottomCorrectly() {
        #expect(target(.topLeft) == CGRect(x: 0, y: 462, width: 600, height: 438))
        #expect(target(.topRight) == CGRect(x: 600, y: 462, width: 600, height: 438))
        #expect(target(.bottomLeft) == CGRect(x: 0, y: 24, width: 600, height: 438))
        #expect(target(.bottomRight) == CGRect(x: 600, y: 24, width: 600, height: 438))
    }

    @Test func testGapsAreSharedOnceBetweenNeighbors() {
        let left = target(.leftHalf, inner: 12, outer: 20)
        let right = target(.rightHalf, inner: 12, outer: 20)
        #expect(left.minX == 20)
        #expect(right.maxX == 1180)
        #expect(right.minX - left.maxX == 12)
        #expect(left.minY == 44)
        #expect(left.maxY == 880)
        #expect(target(.topLeft, inner: 12, outer: 20).minY - target(.bottomLeft, inner: 12, outer: 20).maxY == 12)
    }

    @Test func testThirdsAndTwoThirdsShareBoundaries() {
        #expect(target(.leftThird).width == 400)
        #expect(target(.centerThird).minX == 400)
        #expect(target(.rightThird).minX == 800)
        #expect(target(.leftTwoThirds).maxX == target(.rightThird).minX)
        #expect(target(.rightTwoThirds).minX == target(.leftThird).maxX)
        #expect(abs((target(.rightThird, inner: 8).minX - target(.leftTwoThirds, inner: 8).maxX) - (8)) <= 0.001)
    }

    @Test func testCenterPreservesSizeAndMaximizeRespectsInsets() {
        #expect(target(.center) == CGRect(x: 400, y: 312, width: 400, height: 300))
        #expect(target(.maximize, inner: 12, outer: 10) == visible.insetBy(dx: 10, dy: 10))
        let oversized = CGRect(x: 0, y: 0, width: 3000, height: 3000)
        #expect(ScreenGeometry.target(for: .center, visibleFrame: visible, currentFrame: oversized, outerGap: 0) == visible)
        #expect(ScreenGeometry.target(for: .restore, visibleFrame: visible, currentFrame: current) == nil)
    }

    @Test func testCoordinateConversionRoundTripForDisplaysAboveAndLeft() {
        for rect in [current, CGRect(x: -1400, y: 1050, width: 800, height: 500), CGRect(x: 20, y: -900, width: 600, height: 400)] {
            let ax = ScreenGeometry.flip(rect, primaryMaxY: 900)
            #expect(ax.minY == 900 - rect.maxY)
            #expect(ScreenGeometry.flip(ax, primaryMaxY: 900) == rect)
        }
    }

    @Test func testDisplaySelectionUsesLargestOverlapThenNearest() {
        let screens = [ScreenDescriptor(frame: CGRect(x: 0, y: 0, width: 1200, height: 900), visibleFrame: visible),
                       ScreenDescriptor(frame: CGRect(x: -1200, y: 0, width: 1200, height: 900), visibleFrame: visible)]
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: -700, y: 100, width: 900, height: 500), screens: screens) == 1)
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: 1800, y: 100, width: 300, height: 300), screens: screens) == 0)
        #expect(ScreenGeometry.screenIndex(for: current, screens: []) == nil)
    }

    @Test func testExtremeGapsNeverProduceNegativeFrames() {
        for action in SnapAction.allCases where action != .restore {
            for gap: CGFloat in [-10, 0, 8, 10000, .infinity, .nan] {
                let frame = ScreenGeometry.target(for: action, visibleFrame: CGRect(x: -50, y: 20, width: 80, height: 60),
                                                  currentFrame: current, innerGap: gap, outerGap: gap)!
                #expect(frame.width > 0)
                #expect(frame.height > 0)
                #expect(frame.minX.isFinite && frame.minY.isFinite)
            }
        }
    }
}
