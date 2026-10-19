/// Coalesces repeated navigation while a window operation is in flight.
public struct NavigationBuffer: Sendable {
    public private(set) var steps = 0
    public init() {}
    public mutating func add(_ direction: Int) { steps = max(-20, min(20, steps + max(-20, min(20, direction)))) }
    public mutating func take() -> Int {
        let result = steps
        steps = 0
        return result
    }
}
