import Foundation

/// Counts the same gift sent again and again by the same person ("x2, x3, x4"). A pause of
/// `windowMs` or more since the previous hit starts a new run (spec 4.3). Every (sender, gift) pair
/// keeps its own run, so several people can combo at the same time.
public final class ComboTracker {
    /// Read at every hit, so the effect scheduler can follow a remote recipe set (spec 13.4).
    public var windowMs: Int
    /// Runs remembered at once (the oldest is dropped beyond this).
    public static let maxRuns = 64

    private struct Run {
        let sender: String
        let giftId: String
        let count: Int
        let at: Double
    }

    /// Oldest first.
    private var runs: [Run] = []

    public init(windowMs: Int = GiftingSpec.comboWindowMs) {
        self.windowMs = windowMs
    }

    /// Registers one more send and returns how many in a row this is, starting at 1. The two
    /// strings of a pair compare exactly.
    /// `now` is in milliseconds (default: a monotonic clock).
    @discardableResult
    public func hit(sender: String, giftId: String, now: Double = ComboTracker.monotonicNowMs()) -> Int {
        // A run that paused for the window or more is over.
        runs.removeAll { now - $0.at >= Double(windowMs) }
        var count = 1
        if let index = runs.firstIndex(where: { $0.sender == sender && $0.giftId == giftId }) {
            count = runs[index].count + 1
            runs.remove(at: index)
        }
        runs.append(Run(sender: sender, giftId: giftId, count: count, at: now))
        if runs.count > ComboTracker.maxRuns {
            runs.removeFirst()
        }
        return count
    }

    /// Forgets every run.
    public func reset() {
        runs = []
    }

    /// Milliseconds since boot. Monotonic, unlike the wall clock the reference uses.
    public static func monotonicNowMs() -> Double {
        ProcessInfo.processInfo.systemUptime * 1000
    }
}
