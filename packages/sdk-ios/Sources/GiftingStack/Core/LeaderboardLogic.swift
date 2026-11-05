import Foundation

// Leaderboard logic (spec section 16): tabs, a per-tab cache that answers at once and
// revalidates in the background, the pinned "your rank" row and rank labels. Ported from
// `packages/sdk-js/src/core/leaderboard.ts`. No drawing; the clock is injected.

/// A cached tab older than this is shown and fetched again in the background.
public let leaderboardStaleMs = 30_000
public let defaultLeaderboardLimit = 10

/// Medal colours for ranks 1 to 3 (spec 16.2): new tokens used only by the leaderboard, not part
/// of `GiftTheme`. The rank number on them uses the theme's `noticeBigText`; the contract is
/// >= 4.5:1 (fixture `leaderboard.json#rankColors`).
public struct GiftRankColors: Sendable, Equatable, Hashable {
    public var rank1: String
    public var rank2: String
    public var rank3: String

    public init(rank1: String = "#e8a93a", rank2: String = "#b8bcc8", rank3: String = "#c07a45") {
        self.rank1 = rank1
        self.rank2 = rank2
        self.rank3 = rank3
    }

    /// `RANK_COLORS` of the reference.
    public static let standard = GiftRankColors()

    /// The medal colour of a rank, or nil from rank 4 on.
    public func color(for rank: Int) -> String? {
        switch rank {
        case 1: return rank1
        case 2: return rank2
        case 3: return rank3
        default: return nil
        }
    }
}

/// `1234567` -> `"1,234,567"`: whole numbers with a separator every three digits.
public func groupThousands(_ n: Int, separator: String = ",") -> String {
    let digits = String(n.magnitude)
    var out = ""
    for (index, ch) in digits.enumerated() {
        if index > 0 && (digits.count - index) % 3 == 0 {
            out += separator
        }
        out.append(ch)
    }
    return n < 0 ? "-" + out : out
}

/// `"#1"`, `"#417"`, `"#1,000"`; nil (beyond the top 1,000) -> `overflow` (default `"1,000+"`).
public func leaderboardRankLabel(_ rank: Int?, overflow: String = "1,000+") -> String {
    guard let rank = rank else {
        return overflow
    }
    return "#" + groupThousands(rank)
}

/// The viewer's own row, pinned under the list, or nil (spec 16.2). Pinned when the viewer has a
/// `me` block, is not hidden, has a score above 0 on the metric, and is not visible in the rows:
/// `rank` is nil (beyond the top 1,000) or greater than `limit`, or a tie at the cut put them
/// outside the returned rows.
public func pinnedMe(_ board: Leaderboard?, limit: Int) -> LeaderboardMe? {
    guard let board = board, let me = board.me, !me.hidden else {
        return nil
    }
    let score = board.metric == "gifts" ? me.gifts : me.units
    if score <= 0 {
        return nil
    }
    guard let rank = me.rank, rank <= limit else {
        return me
    }
    return board.data.contains(where: { $0.user == me.user }) ? nil : me
}

public enum LeaderboardStatus: String, Sendable, Hashable {
    /// Nothing to show yet (skeleton rows).
    case loading
    /// `data` is shown.
    case ready
    /// `data` has no rows.
    case empty
    /// The first load of this tab failed (message + "Try again").
    case error
}

public struct LeaderboardState: Sendable, Equatable {
    public var periods: [LeaderboardPeriod]
    public var period: LeaderboardPeriod
    public var metric: LeaderboardMetric
    public var status: LeaderboardStatus
    /// The answer shown for the current tab (possibly stale), else nil.
    public var data: Leaderboard?
    /// A request for the current tab is in flight while `data` stays visible.
    public var refreshing: Bool
    /// The last failure for the current tab, cleared by its next success.
    public var error: GiftingError?
    /// The viewer's row to pin under the list (`pinnedMe`).
    public var pinned: LeaderboardMe?
}

/// One tab: a period and a metric.
private struct LeaderboardTab: Hashable, Sendable {
    let period: LeaderboardPeriod
    let metric: LeaderboardMetric
}

/// Tabs and a per-tab cache for one leaderboard (spec 16.3). A cached tab shows at once and, if
/// 30 s old or more, revalidates in the background while its rows stay visible; a failed
/// revalidation keeps the rows. No polling inside: call `refresh()` on your own timer.
///
/// `client`, `board`, `limit`, `includeMe`, `staleMs` and `onError` are read at each use.
@MainActor
public final class LeaderboardController {
    public var client: any GiftLeaderboardAPI
    public var board: LeaderboardBoard
    /// Rows, 1 to 100.
    public var limit: Int
    /// Ask for the viewer's own `me` block.
    public var includeMe: Bool
    public var staleMs: Int
    public var onError: ((GiftingError) -> Void)?

    public private(set) var state: LeaderboardState {
        didSet {
            for entry in observers {
                entry.callback(state)
            }
        }
    }

    private let clock: any GiftClock
    private var observers: [(token: Int, callback: (LeaderboardState) -> Void)] = []
    private var nextObserverToken = 0
    private var cache: [LeaderboardTab: (value: Leaderboard, at: Int)] = [:]
    private var errors: [LeaderboardTab: GiftingError] = [:]
    private var inFlight: Set<LeaderboardTab> = []
    private var alive = true

    /// - Parameters:
    ///   - periods: the tabs, in this order. Empty (default): day, week, month, all.
    ///   - initialPeriod: default `.week`, or the first of `periods` when week is not one of them.
    ///   - metric: default `.gifts` for receivers, `.units` for senders (decision F.11).
    public init(
        client: any GiftLeaderboardAPI,
        board: LeaderboardBoard = .senders,
        periods: [LeaderboardPeriod] = [],
        initialPeriod: LeaderboardPeriod = .week,
        metric: LeaderboardMetric? = nil,
        limit: Int = defaultLeaderboardLimit,
        includeMe: Bool = true,
        staleMs: Int = leaderboardStaleMs,
        clock: (any GiftClock)? = nil,
        onError: ((GiftingError) -> Void)? = nil
    ) {
        let tabs = periods.isEmpty ? LeaderboardPeriod.allCases : periods
        let first = tabs.contains(initialPeriod) ? initialPeriod : tabs[0]
        let defaultMetric: LeaderboardMetric = board == .receivers ? .gifts : .units
        self.client = client
        self.board = board
        self.limit = limit
        self.includeMe = includeMe
        self.staleMs = staleMs
        self.clock = clock ?? SystemGiftClock()
        self.onError = onError
        self.state = LeaderboardState(
            periods: tabs,
            period: first,
            metric: metric ?? defaultMetric,
            status: .loading,
            data: nil,
            refreshing: false,
            error: nil,
            pinned: nil
        )
    }

    /// Calls `observer` after every state change. Returns a function that stops it.
    @discardableResult
    public func subscribe(_ observer: @escaping (LeaderboardState) -> Void) -> () -> Void {
        let token = nextObserverToken
        nextObserverToken += 1
        observers.append((token: token, callback: observer))
        return { [weak self] in
            self?.observers.removeAll { $0.token == token }
        }
    }

    private var currentTab: LeaderboardTab {
        LeaderboardTab(period: state.period, metric: state.metric)
    }

    /// Recompute the visible state of the current tab from the cache and the requests.
    private func render() {
        let tab = currentTab
        let data = cache[tab]?.value
        let error = errors[tab]
        let busy = inFlight.contains(tab)
        var next = state
        next.data = data
        next.error = error
        next.refreshing = data != nil && busy
        if let data = data {
            next.status = data.data.isEmpty ? .empty : .ready
        } else {
            next.status = (error != nil && !busy) ? .error : .loading
        }
        next.pinned = pinnedMe(data, limit: limit)
        state = next
    }

    /// Show the current tab: cached answer at once, a request if none or if it is stale.
    private func show(force: Bool) {
        let tab = currentTab
        var stale = true
        if let hit = cache[tab] {
            stale = clock.nowMs - hit.at >= staleMs
        }
        if (force || stale) && !inFlight.contains(tab) {
            fetch(tab)
        }
        render()
    }

    private func fetch(_ tab: LeaderboardTab) {
        inFlight.insert(tab)
        let client = self.client
        let board = self.board
        let query = LeaderboardQuery(
            period: tab.period,
            metric: tab.metric,
            limit: limit,
            includeMe: includeMe ? nil : false
        )
        Task { [weak self] in
            var value: Leaderboard?
            var failure: GiftingError?
            do {
                value = try await client.getLeaderboard(board, query: query)
            } catch {
                failure = asGiftingError(error)
            }
            self?.settle(tab, value: value, failure: failure)
        }
    }

    private func settle(_ tab: LeaderboardTab, value: Leaderboard?, failure: GiftingError?) {
        if let value = value {
            cache[tab] = (value: value, at: clock.nowMs)
            errors[tab] = nil
        } else if let failure = failure {
            errors[tab] = failure
            if alive {
                onError?(failure)
            }
        }
        inFlight.remove(tab)
        if alive {
            render()
        }
    }

    /// The screen opened: load the first tab.
    public func start() {
        show(force: false)
    }

    public func setPeriod(_ period: LeaderboardPeriod) {
        if period == state.period {
            return
        }
        state.period = period
        show(force: false)
    }

    public func setMetric(_ metric: LeaderboardMetric) {
        if metric == state.metric {
            return
        }
        state.metric = metric
        show(force: false)
    }

    /// Fetch the current tab again now (pull to refresh, "Try again", a poll).
    public func refresh() {
        show(force: true)
    }

    /// The screen is gone: answers that arrive later change nothing.
    public func dispose() {
        alive = false
    }
}
