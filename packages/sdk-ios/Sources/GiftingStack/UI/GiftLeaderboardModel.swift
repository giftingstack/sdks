#if canImport(SwiftUI) && canImport(ImageIO)
import Combine
import Foundation
import SwiftUI

/// The SwiftUI state holder of a leaderboard: a `LeaderboardController` (spec 16.3) that
/// publishes its state, looks up display names and polls when asked to.
///
/// ```swift
/// @StateObject var board = GiftLeaderboardModel(client: client, board: .senders)
/// ...
/// ScrollView { GiftLeaderboard(model: board) }
/// ```
@MainActor
public final class GiftLeaderboardModel: ObservableObject {
    @Published public private(set) var state: LeaderboardState
    /// Display names looked up so far.
    @Published public private(set) var names: [String: GiftUserInfo] = [:]
    /// Ids asked for and not answered yet: their rows wait (a short while).
    @Published public private(set) var asking: Set<String> = []

    /// The pure controller underneath. `board`, `limit`, `includeMe` apply to the next request.
    public let controller: LeaderboardController
    /// Names (and pictures) for the ids. Fallback: the id.
    public var resolveUsers: GiftResolveUsers?
    /// Poll every so many ms while the board is on screen. 0 (default): no polling (it fetches
    /// on a tab change and on `refresh()`). Read by `start()`.
    public var refreshIntervalMs: Int
    public var onError: ((GiftingError) -> Void)? {
        didSet {
            controller.onError = onError
        }
    }

    private var started = false
    private var pollTask: Task<Void, Never>?
    private var unsubscribe: (() -> Void)?

    /// - Parameters:
    ///   - periods: tabs in this order. Empty (default): day, week, month, all. One item: no tabs.
    ///   - initialPeriod: default `.week` (the first tab when week is not offered).
    ///   - metric: default `.units` for senders, `.gifts` for receivers.
    ///   - limit: rows, 1 to 100. Default 10.
    public init(
        client: any GiftLeaderboardAPI,
        board: LeaderboardBoard = .senders,
        periods: [LeaderboardPeriod] = [],
        initialPeriod: LeaderboardPeriod = .week,
        metric: LeaderboardMetric? = nil,
        limit: Int = defaultLeaderboardLimit,
        resolveUsers: GiftResolveUsers? = nil,
        refreshIntervalMs: Int = 0,
        onError: ((GiftingError) -> Void)? = nil
    ) {
        let controller = LeaderboardController(
            client: client,
            board: board,
            periods: periods,
            initialPeriod: initialPeriod,
            metric: metric,
            limit: limit,
            onError: onError
        )
        self.controller = controller
        self.state = controller.state
        self.resolveUsers = resolveUsers
        self.refreshIntervalMs = refreshIntervalMs
        self.onError = onError
        unsubscribe = controller.subscribe { [weak self] next in
            self?.onState(next)
        }
    }

    /// The display name of an id (the id itself until it is known).
    public func name(of id: String) -> String {
        names[id]?.name ?? id
    }

    /// The board is on screen: the first load (once), and polling when `refreshIntervalMs > 0`.
    public func start() {
        if !started {
            started = true
            controller.start()
        }
        startPolling()
    }

    /// The board left the screen: polling stops (the cache stays).
    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Fetch the current tab again now ("Try again", pull to refresh).
    public func refresh() {
        controller.refresh()
    }

    public func setPeriod(_ period: LeaderboardPeriod) {
        controller.setPeriod(period)
    }

    public func setMetric(_ metric: LeaderboardMetric) {
        controller.setMetric(metric)
    }

    /// The screen is gone for good: late answers change nothing.
    public func dispose() {
        stop()
        controller.dispose()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = nil
        let ms = leaderboardPollMs(refreshIntervalMs)
        guard ms > 0 else {
            return
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                if Task.isCancelled {
                    return
                }
                self?.controller.refresh()
            }
        }
    }

    private func onState(_ next: LeaderboardState) {
        state = next
        guard let resolve = resolveUsers, let data = next.data else {
            return
        }
        // The rows, and the viewer (whose own row may be pinned under them).
        var wanted = data.data.map { $0.user }
        if let me = data.me {
            wanted.append(me.user)
        }
        var fresh: [String] = []
        for id in wanted where names[id] == nil && !asking.contains(id) && !fresh.contains(id) {
            fresh.append(id)
        }
        if fresh.isEmpty {
            return
        }
        asking.formUnion(fresh)
        let ids = fresh
        Task { [weak self] in
            let found = await resolveUsersWithin(ids, waitMs: 2_000, resolve: resolve, onError: self?.onError)
            guard let self = self else {
                return
            }
            if let found = found {
                var merged = self.names
                for (id, info) in found {
                    merged[id] = info
                }
                self.names = merged
            }
            // Whatever came back (or did not), these rows may draw now.
            self.asking.subtract(ids)
        }
    }
}
#endif
