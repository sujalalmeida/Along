import Foundation
import Testing

@testable import Along

struct ScanInterruptionTests {
    private let viewport = CGRect(x: 12, y: 32, width: 1000, height: 700)

    @Test func shortcutInterruptsScanBeforeReadingEveryWindow() async {
        let access = NavigationAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        let reads = access.frameReads
        access.onFrameRead = { engine.interruptMotion() }
        let result = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        #expect(result.scanInterrupted)
        #expect(access.frameReads - reads == 1)
        access.onFrameRead = nil
        let navigation = await engine.run(.step(2), snapshot: access.snapshot, viewport: viewport)
        #expect(navigation.message.contains("3 of 3"))
        #expect(access.focused == 2)
    }

    @Test func stoppingDuringEnumerationKeepsEveryOriginalFrame() async {
        let access = NavigationAccessibility()
        let original = access.frames
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        let reads = access.frameReads
        access.onEnumeration = { engine.interruptMotion() }
        let interrupted = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        #expect(interrupted.scanInterrupted)
        #expect(access.frameReads == reads)
        access.onEnumeration = nil
        let stopped = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(stopped.pendingRestorations == 0)
        #expect(access.frames == original)
    }

    @Test func quitRestoresAllWindowsAfterAnimatedNavigation() async {
        let access = NavigationAccessibility()
        let original = access.frames
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        var snapshot = access.snapshot
        snapshot.reduceMotion = false
        _ = await engine.run(.step(2), snapshot: snapshot, viewport: viewport)
        _ = await engine.run(.step(-1), snapshot: access.snapshot, viewport: viewport)
        let stopped = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(stopped.pendingRestorations == 0)
        #expect(access.frames == original)
    }
}
