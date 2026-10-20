import CoreGraphics
import Testing

@testable import AlongCore

struct ScrollingRowValidationTests {
    private let viewport = CGRect(x: 0, y: 24, width: 1000, height: 700)

    @Test func extremeNavigationCannotOverflow() {
        var row = ScrollingRow()
        row.insert(id: 1, width: 600)
        row.insert(id: 2, width: 600)
        #expect(row.step(Int.max) == 2)
        #expect(row.step(Int.min) == 1)
    }

    @Test func invalidViewportDoesNotCorruptOffset() {
        var row = ScrollingRow()
        row.insert(id: 1, width: 600)
        row.insert(id: 2, width: 600)
        row.scroll(by: 100, in: viewport)
        let offset = row.offset
        row.scroll(by: 100, in: CGRect(x: CGFloat.nan, y: 0, width: 1000, height: 700))
        #expect(row.offset == offset)
        #expect(row.layout(in: .zero).isEmpty)
        #expect(row.offset == offset)
        #expect(row.layout(in: viewport).values.allSatisfy { $0.minX.isFinite && $0.width > 0 })
    }

    @Test func invalidGapHasSameBehaviorForScrollingAndLayout() {
        for gap: CGFloat in [.nan, .infinity, -12] {
            var row = ScrollingRow()
            row.insert(id: 1, width: 600)
            row.insert(id: 2, width: 600)
            row.scroll(by: 100, in: viewport, gap: gap)
            #expect(row.offset == 100)
            let frames = row.layout(in: viewport, gap: gap, revealFocus: false)
            #expect(frames[2]?.minX == 500)
        }
    }
}
