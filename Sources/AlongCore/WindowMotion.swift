import Foundation

/// Critically damped movement with velocity continuity when input changes the target.
public enum WindowMotion {
    public static let duration: Double = 0.3
    public static func sample(
        from start: Double, to target: Double, velocity: Double = 0,
        elapsed: Double
    ) -> (position: Double, velocity: Double) {
        let t = max(0, elapsed)
        let omega = 36.0
        let displacement = start - target
        let coefficient = velocity + omega * displacement
        let decay = exp(-omega * t)
        return (
            target + (displacement + coefficient * t) * decay,
            (velocity - omega * coefficient * t) * decay
        )
    }
}
