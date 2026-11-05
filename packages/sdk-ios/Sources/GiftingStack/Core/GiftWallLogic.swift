import Foundation

// Gift wall logic (spec section 14): which chips a wall shows, how counts are written, and a
// loader that batches the walls of a feed into few requests. Ported from
// `packages/sdk-js/src/core/wall.ts`. No drawing; the clock and the timer are injected.

/// Chips a wall shows by default, the overflow chip included.
public let defaultWallMax = 6
/// Requests made within this many ms of the first one share one batch call.
public let wallBatchWindowMs = 50
/// The API answers at most this many walls per call; more make several calls.
public let wallBatchSize = 25
/// A wall's answer is reused for this long.
public let wallCacheTtlMs = 60_000

/// `.count`: most received first (ties keep the catalog order). `.catalog`: the server's order.
public enum WallOrder: String, Sendable, Hashable {
    case count
    case catalog
}

/// One chip of a wall.
public enum WallChip: Sendable, Equatable, Hashable {
    case gift(gift: GiftSummary, count: Int)
    /// `count` = the SUM of the hidden gifts' counts; `hidden` = how many gift kinds it stands for.
    case overflow(count: Int, hidden: Int)
}

/// The chips of a wall (spec 14.2). `items` comes in catalog order (as the API sends it). Counts
/// of 0 or less are dropped. With more gifts than `max`, the first `max - 1` are shown and one
/// overflow chip carries the sum of the rest. `max` below 1 counts as 1.
public func wallChips(_ items: [ReceivedGift], max maxChips: Int = defaultWallMax, order: WallOrder = .count) -> [WallChip] {
    let limit = Swift.max(1, maxChips)
    var kept = items.filter { $0.count > 0 }
    if order == .count {
        // Stable: equal counts keep the catalog order.
        let indexed = Array(kept.enumerated())
        let sorted = indexed.sorted { a, b in
            if a.element.count != b.element.count {
                return a.element.count > b.element.count
            }
            return a.offset < b.offset
        }
        kept = sorted.map { $0.element }
    }
    if kept.count <= limit {
        return kept.map { WallChip.gift(gift: $0.gift, count: $0.count) }
    }
    var chips: [WallChip] = []
    for item in kept[0..<(limit - 1)] {
        chips.append(.gift(gift: item.gift, count: item.count))
    }
    let hidden = kept[(limit - 1)...]
    var sum = 0
    for item in hidden {
        sum += item.count
    }
    chips.append(.overflow(count: sum, hidden: hidden.count))
    return chips
}

/// Suffixes of `formatCount`.
public struct CountLabels: Sendable, Equatable, Hashable {
    /// Default `"K"`.
    public var thousand: String
    /// Default `"M"`.
    public var million: String
    /// Default `"."`.
    public var decimal: String

    public init(thousand: String = "K", million: String = "M", decimal: String = ".") {
        self.thousand = thousand
        self.million = million
        self.decimal = decimal
    }
}

/// A short count that never overstates (spec 14.3): `999`, `1K`, `1.9K` (1,999), `12K`, `999K`,
/// `1M`, `1.2M`, `12M`. Always rounded DOWN; a `.0` is left out. Integer arithmetic only, no
/// locale grouping. Below 1,000 (negative included) written as is.
public func formatCount(_ n: Int, labels: CountLabels = CountLabels()) -> String {
    let v = n
    func tenths(_ unit: Int, _ suffix: String) -> String {
        let t = v / (unit / 10)
        let whole = t / 10
        let dec = t % 10
        return dec == 0 ? "\(whole)\(suffix)" : "\(whole)\(labels.decimal)\(dec)\(suffix)"
    }
    if v < 1_000 {
        return String(v)
    }
    if v < 10_000 {
        return tenths(1_000, labels.thousand)
    }
    if v < 1_000_000 {
        return String(v / 1_000) + labels.thousand
    }
    if v < 10_000_000 {
        return tenths(1_000_000, labels.million)
    }
    return String(v / 1_000_000) + labels.million
}

// MARK: - Loader (spec 14.4)

/// The batch call of a `GiftWallLoader`: send `items`, then call `done` exactly once, on the main
/// actor, with the walls in request order or the failure. `GiftWallLoader(client:)` makes one
/// from `queryGiftWalls`.
public typealias GiftWallQuery = (_ items: [GiftWallQueryItem], _ done: @escaping (Result<[GiftWallResult], Error>) -> Void) -> Void

/// A wall queued or in flight: everyone who asked for it waits for the same answer.
private final class WallWaiter {
    let item: GiftWallQueryItem
    var continuations: [CheckedContinuation<[ReceivedGift], Error>] = []
    var generation: Int

    init(item: GiftWallQueryItem, generation: Int) {
        self.item = item
        self.generation = generation
    }
}

/// Shares wall requests across every `GiftWall` on a screen. `load` calls made within
/// `windowMs` (50) of the first queued one go out together when that window closes, in batches of
/// at most 25 walls, in the order first asked. A wall that is queued or in flight is not asked
/// again (same answer). An answer is cached per `(user, reference)` for `ttlMs` (60,000) from the
/// moment it arrived; a failure is not cached. Create one per app (or screen) and share it.
@MainActor
public final class GiftWallLoader {
    private let query: GiftWallQuery
    private let clock: any GiftClock
    private let windowMs: Int
    private let batchSize: Int
    private let ttlMs: Int

    private var cache: [String: (gifts: [ReceivedGift], at: Int)] = [:]
    /// Queued (window open) or in flight, by key.
    private var waiting: [String: WallWaiter] = [:]
    /// Keys queued in the open window, in the order first asked.
    private var queue: [String] = []
    private var windowOpen = false
    private var generations: [String: Int] = [:]

    public init(
        query: @escaping GiftWallQuery,
        clock: (any GiftClock)? = nil,
        windowMs: Int = wallBatchWindowMs,
        batchSize: Int = wallBatchSize,
        ttlMs: Int = wallCacheTtlMs
    ) {
        self.query = query
        self.clock = clock ?? SystemGiftClock()
        self.windowMs = windowMs
        self.batchSize = batchSize
        self.ttlMs = ttlMs
    }

    /// A loader whose batch call is `client.queryGiftWalls`.
    public convenience init(client: any GiftWallAPI, clock: (any GiftClock)? = nil) {
        self.init(
            query: { items, done in
                Task { @MainActor in
                    do {
                        let walls = try await client.queryGiftWalls(items)
                        done(.success(walls))
                    } catch {
                        done(.failure(error))
                    }
                }
            },
            clock: clock
        )
    }

    private static func key(_ user: String, _ reference: String?) -> String {
        user + "\u{0}" + (reference ?? "")
    }

    /// The cached wall if it is still fresh, else nil. Lets a wall draw at once.
    public func peek(_ user: String, reference: String? = nil) -> [ReceivedGift]? {
        guard let hit = cache[GiftWallLoader.key(user, reference)] else {
            return nil
        }
        return clock.nowMs - hit.at < ttlMs ? hit.gifts : nil
    }

    /// The wall's counters: a fresh cached answer at once, else the shared answer of the next
    /// batch. Throws the batch's error.
    public func load(_ user: String, reference: String? = nil) async throws -> [ReceivedGift] {
        if let fresh = peek(user, reference: reference) {
            return fresh
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ReceivedGift], Error>) in
            self.enqueue(user, reference: reference, continuation: continuation)
        }
    }

    private func enqueue(_ user: String, reference: String?, continuation: CheckedContinuation<[ReceivedGift], Error>) {
        let key = GiftWallLoader.key(user, reference)
        if let known = waiting[key] {
            known.continuations.append(continuation)
            return
        }
        let waiter = WallWaiter(
            item: GiftWallQueryItem(receiver: user, reference: reference),
            generation: generations[key] ?? 0
        )
        waiter.continuations.append(continuation)
        waiting[key] = waiter
        queue.append(key)
        if !windowOpen {
            windowOpen = true
            _ = clock.schedule(afterMs: windowMs) { [weak self] in
                self?.flush()
            }
        }
    }

    /// Forget a wall (for example after the person sent a gift to it): the next `load` asks the
    /// server again, even if an older request is still in flight (its answer is then not cached).
    public func invalidate(_ user: String, reference: String? = nil) {
        let key = GiftWallLoader.key(user, reference)
        cache[key] = nil
        let generation = (generations[key] ?? 0) + 1
        generations[key] = generation
        guard let waiter = waiting[key] else {
            return
        }
        // A queued wall has not been asked yet: it goes out with its window and its answer counts.
        // One in flight is let go: its answer reaches its callers but is not cached.
        if queue.contains(key) {
            waiter.generation = generation
        } else {
            waiting[key] = nil
        }
    }

    /// Forget every cached wall (requests already queued or in flight are kept).
    public func clear() {
        cache = [:]
    }

    private func flush() {
        windowOpen = false
        let keys = queue
        queue = []
        let size = Swift.max(1, batchSize)
        var start = 0
        while start < keys.count {
            let end = Swift.min(start + size, keys.count)
            let chunk = Array(keys[start..<end])
            var waiters: [WallWaiter] = []
            for key in chunk {
                if let waiter = waiting[key] {
                    waiters.append(waiter)
                }
            }
            send(chunk, waiters)
            start = end
        }
    }

    private func send(_ keys: [String], _ waiters: [WallWaiter]) {
        let items = waiters.map { $0.item }
        query(items) { result in
            self.finish(keys, waiters, result)
        }
    }

    private func finish(_ keys: [String], _ waiters: [WallWaiter], _ result: Result<[GiftWallResult], Error>) {
        switch result {
        case .success(let walls):
            let at = clock.nowMs
            for (index, waiter) in waiters.enumerated() {
                let key = keys[index]
                let gifts = index < walls.count ? walls[index].gifts : []
                if waiting[key] === waiter {
                    waiting[key] = nil
                }
                if (generations[key] ?? 0) == waiter.generation {
                    cache[key] = (gifts: gifts, at: at)
                }
                let continuations = waiter.continuations
                waiter.continuations = []
                for continuation in continuations {
                    continuation.resume(returning: gifts)
                }
            }
        case .failure(let error):
            for (index, waiter) in waiters.enumerated() {
                let key = keys[index]
                if waiting[key] === waiter {
                    waiting[key] = nil
                }
                let continuations = waiter.continuations
                waiter.continuations = []
                for continuation in continuations {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
