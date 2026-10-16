import Testing
@testable import TileMeCore

struct NavigationBufferTests {
    @Test func rapidInputIsCoalescedAndConsumedOnce() {
        var buffer = NavigationBuffer()
        buffer.add(1); buffer.add(1); buffer.add(1)
        #expect(buffer.take() == 3)
        #expect(buffer.take() == 0)
    }
    @Test func reversalCancelsPendingMovement() {
        var buffer = NavigationBuffer()
        buffer.add(1); buffer.add(-1)
        #expect(buffer.take() == 0)
    }
    @Test func keyRepeatHasBoundedBacklog() {
        var buffer = NavigationBuffer()
        for _ in 0..<1000 { buffer.add(1) }
        #expect(buffer.take() == 20)
        buffer.add(Int.min)
        #expect(buffer.take() == -20)
    }
}
