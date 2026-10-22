import ApplicationServices
import Foundation
import Testing

@testable import Along

/// Owned by one test; configuration and reads happen between awaited commands.
final class NavigationAccessibility: WindowAccessibility, @unchecked Sendable {
    let windows = (201...203).map { AXUIElementCreateApplication(pid_t($0)) }
    let app = AXUIElementCreateApplication(101)
    var frames = (0..<3).map { CGRect(x: $0 * 400, y: 80, width: 400, height: 450) }
    var focused = 0
    var frameReads = 0
    var placements = 0
    var moves = 0
    var onMove: (@Sendable () -> Void)?
    var isTrusted: Bool { true }
    func application(pid: pid_t) -> AXUIElement { app }
    func windows(of app: AXUIElement) throws -> [AXUIElement] { windows }
    func focusedWindow(of app: AXUIElement) throws -> AXUIElement? { windows[focused] }
    func index(_ window: AXUIElement) -> Int { windows.firstIndex { CFEqual($0, window) }! }
    func frame(of window: AXUIElement) throws -> CGRect {
        frameReads += 1
        return frames[index(window)]
    }
    func isMovable(_ window: AXUIElement) throws -> Bool { true }
    func title(of window: AXUIElement) throws -> String { "Window \(index(window))" }
    func place(_ window: AXUIElement, at frame: CGRect, from current: CGRect?) throws {
        placements += 1
        frames[index(window)] = frame
    }
    func move(_ window: AXUIElement, to point: CGPoint) throws {
        moves += 1
        frames[index(window)].origin = point
        onMove?()
    }
    func focus(_ window: AXUIElement, pid: pid_t) throws { focused = index(window) }
    var snapshot: RowSnapshot {
        RowSnapshot(
            visible: frames.map { VisibleWindow(pid: 101, frame: $0) }, frontmostPID: 101,
            eligiblePIDs: [101], runningPIDs: [101], reduceMotion: true)
    }
}

struct NavigationPerformanceTests {
    private let viewport = CGRect(x: 12, y: 32, width: 1000, height: 700)

    @Test func keyboardNavigationDoesNotReadOrResizeEveryWindow() async {
        let access = NavigationAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        let reads = access.frameReads
        let placements = access.placements
        _ = await engine.run(.step(2), snapshot: access.snapshot, viewport: viewport)
        #expect(access.focused == 2)
        #expect(access.frameReads == reads)
        #expect(access.placements == placements)
        #expect(access.frames[2].maxX == viewport.maxX)
    }

    @Test func selectingAnotherVisibleWindowNeedsNoGeometryWork() async {
        let access = NavigationAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        let reads = access.frameReads
        let moves = access.moves
        let placements = access.placements
        _ = await engine.run(.step(1), snapshot: access.snapshot, viewport: viewport)
        #expect(access.focused == 1)
        #expect(access.frameReads == reads)
        #expect(access.moves == moves)
        #expect(access.placements == placements)
    }

    @Test func animatedNavigationReachesTargetsWithoutGeometryReads() async {
        let access = NavigationAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        let reads = access.frameReads
        let placements = access.placements
        var snapshot = access.snapshot
        snapshot.reduceMotion = false
        _ = await engine.run(.step(2), snapshot: snapshot, viewport: viewport)
        #expect(access.focused == 2)
        #expect(access.frames[2].maxX == viewport.maxX)
        #expect(access.frameReads == reads)
        #expect(access.placements == placements)
        #expect(access.moves > 0)
    }

    @Test func interruptedAnimationRetargetsFromCachedSuccessfulWrites() async {
        let access = NavigationAccessibility()
        let engine = RowWindowEngine(accessibility: access)
        _ = await engine.run(.sync, snapshot: access.snapshot, viewport: viewport)
        let initial = access.frames
        let reads = access.frameReads
        var snapshot = access.snapshot
        snapshot.reduceMotion = false
        access.onMove = { engine.interruptMotion() }
        let result = await engine.run(.step(2), snapshot: snapshot, viewport: viewport)
        #expect(result.message == "Moving through row…")
        #expect(access.frameReads == reads)
        access.onMove = nil
        _ = await engine.run(.step(-2), snapshot: access.snapshot, viewport: viewport)
        #expect(access.frames == initial)
        #expect(access.frameReads == reads)
    }
}
