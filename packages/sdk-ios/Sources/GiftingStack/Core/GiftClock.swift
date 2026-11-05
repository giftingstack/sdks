import Foundation

/// The clock and the timers of the component controllers (`GiftWallLoader`, `AwayController`,
/// `LeaderboardController`). Injected so the fixtures can drive them with a fake clock; apps use
/// the default `SystemGiftClock`.
@MainActor
public protocol GiftClock: AnyObject {
    /// Milliseconds on a clock that only moves forward.
    var nowMs: Int { get }
    /// Runs `fire` once, `ms` milliseconds from now, on the main actor. Returns a handle for `cancel`.
    func schedule(afterMs ms: Int, _ fire: @escaping () -> Void) -> Int
    /// Stops a timer that has not fired yet. Unknown or fired handles are ignored.
    func cancel(_ handle: Int)
}

/// Limits of the real clock.
enum GiftClockLimits {
    /// The longest timer `SystemGiftClock` accepts, in milliseconds.
    static let maxTimerMs = 1_000_000_000_000
}

/// The real clock: the system uptime (monotonic) and `Task.sleep` timers on the main actor.
@MainActor
public final class SystemGiftClock: GiftClock {
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var nextHandle = 0

    public init() {}

    public var nowMs: Int {
        Int(ProcessInfo.processInfo.systemUptime * 1000)
    }

    public func schedule(afterMs ms: Int, _ fire: @escaping () -> Void) -> Int {
        nextHandle += 1
        let handle = nextHandle
        // A server-supplied wait (`retry_after`) can be enormous: clamp before multiplying, so the product
        // cannot overflow and trap (1e12 ms is about 31 years, 1e18 ns still fits a UInt64).
        let nanos = UInt64(min(max(0, ms), GiftClockLimits.maxTimerMs)) * 1_000_000
        tasks[handle] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled {
                return
            }
            self?.tasks[handle] = nil
            fire()
        }
        return handle
    }

    public func cancel(_ handle: Int) {
        tasks[handle]?.cancel()
        tasks[handle] = nil
    }
}
