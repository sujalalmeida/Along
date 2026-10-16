import Testing
import CoreGraphics
@testable import TileMeCore

struct ScrollingRowTests {
    let viewport = CGRect(x: 12, y: 36, width: 1000, height: 720)

    @Test func insertsAfterActiveWithoutResizingNeighbors() {
        var row = ScrollingRow()
        row.insert(id: 1, width: 450); row.insert(id: 2, width: 600)
        row.focus(id: 1); row.insert(id: 3, width: 300)
        #expect(row.columns.map(\.id) == [1, 3, 2])
        #expect(row.columns.map(\.width) == [450, 300, 600])
        #expect(row.focusedID == 3)
    }
    @Test func overflowSlidesViewportInsteadOfShrinking() {
        var row = ScrollingRow()
        for id in 1...4 { row.insert(id: id, width: 600) }
        let frames = row.layout(in: viewport)
        #expect(frames[4]!.maxX == viewport.maxX)
        #expect(frames[1]!.maxX < viewport.minX)
        #expect(frames.values.allSatisfy { $0.width == 600 && $0.height == 720 })
        #expect(frames[2]!.minX - frames[1]!.maxX == 12)
        row.focus(id: 1)
        let first = row.layout(in: viewport)
        #expect(first[1]!.minX == viewport.minX)
        #expect(row.offset == 0)
    }
    @Test func navigationStopsAtEndsAndKeepsVisibleNeighborsStill() {
        var row = ScrollingRow()
        row.insert(id: 1, width: 300); row.insert(id: 2, width: 300)
        let before = row.layout(in: viewport)
        #expect(row.step(1) == 2)
        #expect(row.step(-1) == 1)
        #expect(row.step(-1) == 1)
        #expect(row.layout(in: viewport) == before)
    }
    @Test func closeFocusedWindowSelectsNeighborAndClampsOffset() {
        var row = ScrollingRow()
        row.insert(id: 1, width: 600); row.insert(id: 2, width: 600)
        _ = row.layout(in: viewport)
        #expect(row.offset > 0)
        row.remove(id: 2)
        #expect(row.focusedID == 1)
        #expect(row.layout(in: viewport)[1]!.minX == viewport.minX)
        row.remove(id: 1)
        #expect(row.focusedID == nil)
        #expect(row.layout(in: viewport).isEmpty)
        #expect(row.step(1) == nil)
    }
    @Test func resizeOnlyChangesSelectedColumn() {
        var row = ScrollingRow()
        row.insert(id: 1, width: 400); row.insert(id: 2, width: 500)
        row.resize(id: 1, width: 700)
        #expect(row.columns.map(\.width) == [700, 500])
        row.resize(id: 1, width: .nan)
        #expect(row.columns[0].width == 700)
    }
    @Test func oversizedColumnAnchorsLeftAndDuplicateInsertIsIgnored() {
        var row = ScrollingRow()
        row.insert(id: 1, width: 1500); row.insert(id: 1, width: 100)
        #expect(row.columns.count == 1)
        #expect(row.layout(in: viewport)[1]!.minX == viewport.minX)
        #expect(row.columns[0].width == 1500)
    }
}
