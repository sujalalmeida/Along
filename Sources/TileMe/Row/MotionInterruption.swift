import Foundation

/// Input can interrupt AX animation without waiting for its serial worker.
final class MotionInterruption: @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64 = 0
    func current() -> UInt64 { lock.lock(); defer { lock.unlock() }; return revision }
    func interrupt() { lock.lock(); defer { lock.unlock() }; revision &+= 1 }
}
