import ApplicationServices
import Foundation
import Testing

@testable import Along

/// Each test owns a separate fake. It is configured only before an awaited
/// engine command and inspected after that command's worker has completed.
private final class FakeAccessibility: WindowAccessibility, @unchecked Sendable {
    let window = AXUIElementCreateApplication(101)
    let original = CGRect(x: 100, y: 80, width: 600, height: 400)
    var current = CGRect(x: 100, y: 80, width: 600, height: 400)
    var isTrusted = true
    var listed = true
    var enumerationFails = false
    var eligibilityFails = false
    var movable = true
    var placementFails = false
    var ignoresPlacement = false
    var focusFails = false
    var closed = false
    var frameFails = false
    var writes = 0
    var requiresMoveBeforeResize = false
    var placementFailuresRemaining = 0

    func application(pid: pid_t) -> AXUIElement { window }
    func windows(of app: AXUIElement) throws -> [AXUIElement] {
        if enumerationFails { throw timeout }
        return listed ? [window] : []
    }
    func focusedWindow(of app: AXUIElement) throws -> AXUIElement? { listed ? window : nil }
    func frame(of window: AXUIElement) throws -> CGRect {
        if frameFails { throw timeout }
        if closed { throw WindowAccessError.accessibility(operation: "frame", code: .invalidUIElement) }
        return current
    }
    func isMovable(_ window: AXUIElement) throws -> Bool {
        if eligibilityFails { throw timeout }
        return movable
    }
    func title(of window: AXUIElement) throws -> String { "Test window" }
    func place(_ window: AXUIElement, at frame: CGRect, from current: CGRect?) throws {
        if let current, current.isClose(to: frame) { return }
        writes += 1
        if placementFails { throw timeout }
        if placementFailuresRemaining > 0 {
            placementFailuresRemaining -= 1
            throw timeout
        }
        if requiresMoveBeforeResize && self.current.origin != frame.origin && self.current.size != frame.size {
            self.current = CGRect(origin: frame.origin, size: CGSize(width: frame.width - 40, height: frame.height))
            return
        }
        if !ignoresPlacement { self.current = frame }
    }
    func move(_ window: AXUIElement, to point: CGPoint) throws { current.origin = point }
    func focus(_ window: AXUIElement, pid: pid_t) throws {
        if focusFails { throw timeout }
    }
    private var timeout: WindowAccessError { .accessibility(operation: "test", code: .cannotComplete) }
    var snapshot: RowSnapshot {
        RowSnapshot(
            visible: [VisibleWindow(pid: 101, frame: current)], frontmostPID: 101,
            eligiblePIDs: [101], runningPIDs: [101], reduceMotion: true)
    }
}

struct RowWindowEngineTests {
    private let viewport = CGRect(x: 12, y: 32, width: 1200, height: 800)

    @Test func failedRestoreCanBeRetriedWithoutLosingOriginalFrame() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        #expect(access.current != access.original)
        access.placementFails = true
        let failed = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(failed.pendingRestorations == 1)
        access.placementFails = false
        let restored = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(restored.pendingRestorations == 0)
        #expect(access.current == access.original)
    }

    @Test func restoreMovesBackBeforeResizingAnOffscreenWindow() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        access.requiresMoveBeforeResize = true
        let result = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(result.pendingRestorations == 0)
        #expect(access.current == access.original)
    }

    @Test func restorationRetriesATransientWriteWithoutAnotherQuit() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        access.placementFailuresRemaining = 1
        let result = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(result.pendingRestorations == 0)
        #expect(access.current == access.original)
    }

    @Test func temporarilyUnlistedWindowKeepsItsOriginalForQuit() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        access.listed = false
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        let result = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(result.pendingRestorations == 0)
        #expect(access.current == access.original)
    }

    @Test func silentlyConstrainedRestorationIsNotReportedAsSuccess() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        access.ignoresPlacement = true
        let result = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(result.pendingRestorations == 1)
    }

    @Test func minimizedWindowKeepsItsOriginalUntilRestored() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        access.movable = false
        let deferred = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(deferred.pendingRestorations == 1)
        access.movable = true
        _ = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(access.current == access.original)
    }

    @Test func failedFrameReadCannotSilentlyDiscardTheOriginal() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        access.frameFails = true
        let deferred = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(deferred.pendingRestorations == 1)
        access.frameFails = false
        _ = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(access.current == access.original)
    }

    @Test func terminatedAppDoesNotLeaveAnUnresolvableRestore() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        var snapshot = access.snapshot
        snapshot.runningPIDs = []
        let result = await engine.run(.stop, snapshot: snapshot, viewport: viewport)
        #expect(result.pendingRestorations == 0)
    }

    @Test func closedWindowDoesNotBlockRestoration() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        access.closed = true
        let result = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(result.pendingRestorations == 0)
    }

    @Test func transientEnumerationFailureKeepsRowAndOriginal() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        access.enumerationFails = true
        let result = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        #expect(result.message.contains("1 of 1"))
        access.enumerationFails = false
        _ = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(access.current == access.original)
    }

    @Test func failedEligibilityCheckPreservesRecordWithoutWritingToIt() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        access.eligibilityFails = true
        let writesBefore = access.writes
        let result = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport.insetBy(dx: 10, dy: 10))
        #expect(result.message.contains("1 of 1"))
        #expect(access.writes == writesBefore)
        _ = await engine.run(.step(1), snapshot: access.snapshot, viewport: viewport)
        #expect(access.writes == writesBefore)
        access.eligibilityFails = false
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        _ = await engine.run(.stop, snapshot: access.snapshot, viewport: viewport)
        #expect(access.current == access.original)
    }

    @Test func recoveredWindowReachesItsTargetWithoutAnotherNavigationCommand() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        // The user may be in an unmanaged app, so focus changes cannot trigger
        // a relayout for the recovered window.
        let snapshot = RowSnapshot(
            visible: access.snapshot.visible, frontmostPID: nil,
            eligiblePIDs: [101], runningPIDs: [101], reduceMotion: true)
        _ = await engine.run(.sync, snapshot: snapshot, viewport: viewport)
        let nextViewport = viewport.offsetBy(dx: 100, dy: 0)
        access.eligibilityFails = true
        _ = await engine.run(.sync, snapshot: snapshot, viewport: nextViewport)
        #expect(access.current.minX == viewport.minX)
        access.eligibilityFails = false
        _ = await engine.run(.sync, snapshot: snapshot, viewport: nextViewport)
        #expect(access.current.minX == nextViewport.minX)
    }

    @Test func failedScrollWriteIsRetriedWhenTargetIsUnchanged() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        access.placementFails = true
        _ = await engine.run(.scroll(0), snapshot: access.snapshot, viewport: viewport.offsetBy(dx: 100, dy: 0))
        access.placementFails = false
        _ = await engine.run(.scroll(0), snapshot: access.snapshot, viewport: viewport.offsetBy(dx: 100, dy: 0))
        #expect(access.current.minX == viewport.minX + 100)
    }

    @Test func missingPermissionAndInvalidViewportNeverMoveWindows() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        access.isTrusted = false
        let denied = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        #expect(denied.message.contains("permission"))
        access.isTrusted = true
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: .zero)
        #expect(access.writes == 0)
    }

    @Test func failedFocusDoesNotClaimTheAppWasSelected() async {
        let access = FakeAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        access.focusFails = true
        let result = await engine.run(.step(1), snapshot: access.snapshot, viewport: viewport)
        #expect(result.message.contains("could not take focus"))
    }
}
