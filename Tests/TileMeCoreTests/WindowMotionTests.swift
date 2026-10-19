import CoreGraphics
import Testing

@testable import TileMeCore

struct WindowMotionTests {
    @Test func movementStartsAtCurrentPositionAndVelocity() {
        let sample = WindowMotion.sample(from: 40, to: 900, velocity: 120, elapsed: 0)
        #expect(sample.position == 40)
        #expect(sample.velocity == 120)
    }
    @Test func settlesWithoutOvershootFromRest() {
        var previous = 0.0
        for tick in 0...36 {
            let sample = WindowMotion.sample(from: 0, to: 1200, elapsed: Double(tick) / 120)
            #expect(sample.position >= previous)
            #expect(sample.position <= 1200)
            previous = sample.position
        }
        #expect(abs(previous - 1200) < 0.5)
    }
    @Test func changingTargetPreservesPositionAndVelocity() {
        let midway = WindowMotion.sample(from: 0, to: 900, elapsed: 0.07)
        let retargeted = WindowMotion.sample(from: midway.position, to: -300, velocity: midway.velocity, elapsed: 0)
        #expect(retargeted.position == midway.position)
        #expect(abs(retargeted.velocity - midway.velocity) < 0.00001)
        let settled = WindowMotion.sample(from: midway.position, to: -300, velocity: midway.velocity, elapsed: 1)
        #expect(abs(settled.position + 300) < 0.001)
    }
    @Test func stationaryWindowsStayStationary() {
        let sample = WindowMotion.sample(from: 300, to: 300, elapsed: 0.1)
        #expect(sample.position == 300)
        #expect(sample.velocity == 0)
    }
    @Test func trackpadDeltaMovesRowWithoutSnappingToFocusedWindow() {
        var row = ScrollingRow()
        row.insert(id: 1, width: 600)
        row.insert(id: 2, width: 600)
        let viewport = CGRect(x: 12, y: 30, width: 1000, height: 700)
        row.focus(id: 1)
        _ = row.layout(in: viewport)
        row.scroll(by: 37.5, in: viewport)
        let frames = row.layout(in: viewport, revealFocus: false)
        #expect(row.offset == 37.5)
        #expect(frames[1]!.minX == 12 - 37.5)
        #expect(frames[2]!.width == 600)
    }
    @Test func scrollingClampsAtBothEnds() {
        var row = ScrollingRow()
        row.insert(id: 1, width: 600)
        row.insert(id: 2, width: 600)
        let viewport = CGRect(x: 0, y: 0, width: 1000, height: 700)
        row.scroll(by: 10000, in: viewport)
        #expect(row.offset == 212)
        row.scroll(by: -10000, in: viewport)
        #expect(row.offset == 0)
        row.scroll(by: .nan, in: viewport)
        #expect(row.offset == 0)
    }
    @Test func scrollSelectsNearestColumnForSettling() {
        var row = ScrollingRow()
        for id in 1...4 { row.insert(id: id, width: 500) }
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 700)
        row.scroll(by: 700, in: viewport)
        #expect(row.focusedID == 3)
        #expect(row.columns.allSatisfy { $0.width == 500 })
        #expect(row.layout(in: viewport)[3]!.maxX <= viewport.maxX)
    }
}
