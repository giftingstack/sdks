#if canImport(SwiftUI) && canImport(ImageIO)
import Combine
import Foundation
import SwiftUI

/// Where the inbox list stands (spec 19.3).
public enum GiftInboxStatus: Sendable, Equatable {
    /// Nothing asked yet, or the first page is on its way.
    case loading
    /// No gift to show (and no further page).
    case empty
    /// The first page failed.
    case error
    /// At least one page is shown.
    case ready
}

public struct GiftInboxState: Sendable, Equatable {
    public var status: GiftInboxStatus = .loading
    /// Every item loaded so far, newest first (reversed ones included; the view hides them).
    public var items: [InboxItem] = []
    public var hasMore = false
    public var nextCursor: String?
    /// The next page is on its way.
    public var loadingMore = false
}

/// The SwiftUI state holder of the gift inbox: loads the last 24 hours page by page, looks up
/// sender names, and keeps the list.
///
/// ```swift
/// @StateObject var inbox = GiftInboxModel(client: client, resolveUsers: lookUpNames)
/// ...
/// ScrollView { GiftInbox(model: inbox) }
/// ```
@MainActor
public final class GiftInboxModel: ObservableObject {
    @Published public private(set) var state = GiftInboxState()
    /// Display names looked up so far.
    @Published public private(set) var names: [String: GiftUserInfo] = [:]

    public let client: any GiftInboxAPI
    /// Names (and pictures) for the sender ids. Fallback: the id.
    public var resolveUsers: GiftResolveUsers?
    /// Rows per request, 1 to 100. Default 20.
    public var pageSize: Int
    /// Called with every item loaded so far after each successful load, so the app can compute
    /// its own badge with `inboxUnread`.
    public var onLoaded: (([InboxItem]) -> Void)?
    public var onError: ((GiftingError) -> Void)?

    private var started = false
    private var generation = 0
    private var disposed = false

    public init(
        client: any GiftInboxAPI,
        resolveUsers: GiftResolveUsers? = nil,
        pageSize: Int = 20,
        onLoaded: (([InboxItem]) -> Void)? = nil,
        onError: ((GiftingError) -> Void)? = nil
    ) {
        self.client = client
        self.resolveUsers = resolveUsers
        self.pageSize = min(100, max(1, pageSize))
        self.onLoaded = onLoaded
        self.onError = onError
    }

    /// The display name of a sender id (the id itself until it is known).
    public func name(of id: String) -> String {
        names[id]?.name ?? id
    }

    /// The rows to draw now (reversed gifts dropped), with names applied.
    public func rows(nowMs: Int, someone: String = "Someone") -> [InboxRow] {
        var map: [String: String] = [:]
        for (id, info) in names {
            map[id] = info.name
        }
        return inboxRows(state.items, nowMs: nowMs, names: map, someone: someone)
    }

    /// The list is on screen: the first load, once. Do not wait.
    public func load() {
        if started {
            return
        }
        started = true
        Task { [weak self] in
            await self?.loadFirstPage()
        }
    }

    /// Reload from the first page ("Try again", pull to refresh). Do not wait.
    public func refresh() {
        started = true
        Task { [weak self] in
            await self?.loadFirstPage()
        }
    }

    /// Append the next (older) page while `hasMore`. Do not wait.
    public func loadMore() {
        Task { [weak self] in
            await self?.loadNextPage()
        }
    }

    /// The screen is gone for good: late answers change nothing.
    public func dispose() {
        disposed = true
        generation += 1
    }

    // MARK: - Loading

    /// The first page replaces the list. While the very first load runs the list shows its
    /// loading state; a refresh keeps the old rows until the new page is there.
    func loadFirstPage() async {
        generation += 1
        let mine = generation
        let hadItems = !state.items.isEmpty
        if !hadItems {
            state.status = .loading
        }
        state.loadingMore = false
        do {
            let page = try await client.getInbox(InboxQuery(cursor: nil, limit: pageSize))
            guard mine == generation, !disposed else {
                return
            }
            await resolveNames(page.data)
            guard mine == generation, !disposed else {
                return
            }
            apply(page, replacing: true)
        } catch {
            guard mine == generation, !disposed else {
                return
            }
            let failure = asGiftingError(error)
            if !hadItems {
                state.status = .error
            }
            onError?(failure)
        }
    }

    func loadNextPage() async {
        guard !disposed, state.status == .ready, state.hasMore, !state.loadingMore, let cursor = state.nextCursor else {
            return
        }
        let mine = generation
        state.loadingMore = true
        do {
            let page = try await client.getInbox(InboxQuery(cursor: cursor, limit: pageSize))
            guard mine == generation, !disposed else {
                return
            }
            await resolveNames(page.data)
            guard mine == generation, !disposed else {
                return
            }
            apply(page, replacing: false)
        } catch {
            guard mine == generation, !disposed else {
                return
            }
            // The list stays as it is; "Show more" is still there to try again.
            state.loadingMore = false
            onError?(asGiftingError(error))
        }
    }

    private func apply(_ page: Inbox, replacing: Bool) {
        var next = state
        var all = replacing ? [] : next.items
        let known = Set(all.map { $0.id })
        for item in page.data where !known.contains(item.id) {
            all.append(item)
        }
        next.items = all
        next.hasMore = page.hasMore && page.nextCursor != nil
        next.nextCursor = page.nextCursor
        next.loadingMore = false
        let hasRows = all.contains(where: { $0.status != "reversed" })
        next.status = (hasRows || next.hasMore) ? .ready : .empty
        state = next
        onLoaded?(all)
    }

    /// Sender names first (briefly), so the rows do not show ids and then change.
    private func resolveNames(_ items: [InboxItem]) async {
        guard let resolve = resolveUsers else {
            return
        }
        var missing: [String] = []
        for item in items {
            if let id = item.sender, names[id] == nil, !missing.contains(id) {
                missing.append(id)
            }
        }
        if missing.isEmpty {
            return
        }
        let found = await resolveUsersWithin(missing, waitMs: 1_500, resolve: resolve, onError: onError)
        if let found = found {
            var merged = names
            for (id, info) in found {
                merged[id] = info
            }
            names = merged
        }
    }
}
#endif
