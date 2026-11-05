import Foundation
import XCTest
@testable import GiftingStack

#if canImport(SwiftUI) && canImport(ImageIO)

/// Answers `getInbox` from a script: pages by cursor (nil = the first page), or a failure while
/// `failing` is set. Records every query.
@MainActor
private final class FakeInboxClient: GiftInboxAPI {
    var pages: [String: Inbox] = [:]
    var failing = false
    private(set) var queries: [InboxQuery] = []

    func getInbox(_ query: InboxQuery) async throws -> Inbox {
        queries.append(query)
        if failing {
            throw GiftingError(status: 503, type: "unavailable", message: "Down")
        }
        guard let page = pages[query.cursor ?? ""] else {
            throw GiftingError(status: 400, type: "bad_request", message: "No such page")
        }
        return page
    }
}

@MainActor
final class GiftInboxModelTests: XCTestCase {
    private func item(_ id: String, sender: String?, at: String = "2026-11-02T09:00:00.000Z", status: String = "completed") -> InboxItem {
        InboxItem(
            id: id,
            createdAt: at,
            sender: sender,
            gift: InboxGift(id: "rose", name: "Rose", price: 10),
            quantity: 1,
            units: 10,
            status: status
        )
    }

    private func page(_ items: [InboxItem], next: String? = nil) -> Inbox {
        Inbox(
            user: "ava",
            since: "2026-11-01T10:00:00.000Z",
            until: "2026-11-02T10:00:00.000Z",
            data: items,
            hasMore: next != nil,
            nextCursor: next
        )
    }

    func testFirstPageThenShowMoreAppendsAndHidesReversed() async throws {
        let client = FakeInboxClient()
        client.pages[""] = page([item("g3", sender: "ayla"), item("g2", sender: "mert", status: "reversed")], next: "c1")
        client.pages["c1"] = page([item("g1", sender: nil)])
        var loaded: [[String]] = []
        let model = GiftInboxModel(client: client, pageSize: 2, onLoaded: { items in
            loaded.append(items.map { $0.id })
        })
        XCTAssertEqual(model.state.status, .loading)

        await model.loadFirstPage()
        XCTAssertEqual(model.state.status, .ready)
        XCTAssertTrue(model.state.hasMore)
        XCTAssertEqual(client.queries, [InboxQuery(cursor: nil, limit: 2)])
        XCTAssertEqual(model.rows(nowMs: 1_793_613_600_000).map { $0.id }, ["g3"])

        await model.loadNextPage()
        XCTAssertFalse(model.state.hasMore)
        XCTAssertEqual(client.queries.last, InboxQuery(cursor: "c1", limit: 2))
        XCTAssertEqual(model.rows(nowMs: 1_793_613_600_000).map { $0.id }, ["g3", "g1"])
        XCTAssertEqual(model.rows(nowMs: 1_793_613_600_000).last?.senderName, "Someone")
        XCTAssertEqual(loaded, [["g3", "g2"], ["g3", "g2", "g1"]])

        // No more pages: asking again changes nothing.
        await model.loadNextPage()
        XCTAssertEqual(client.queries.count, 2)
    }

    func testEmptyWhenNothingToShow() async throws {
        let client = FakeInboxClient()
        client.pages[""] = page([item("g1", sender: "ayla", status: "reversed")])
        let model = GiftInboxModel(client: client)
        await model.loadFirstPage()
        XCTAssertEqual(model.state.status, .empty)
    }

    func testErrorThenTryAgain() async throws {
        let client = FakeInboxClient()
        client.failing = true
        var errors: [String] = []
        let model = GiftInboxModel(client: client, onError: { errors.append($0.type) })
        await model.loadFirstPage()
        XCTAssertEqual(model.state.status, .error)
        XCTAssertEqual(errors, ["unavailable"])

        client.failing = false
        client.pages[""] = page([item("g1", sender: "ayla")])
        await model.loadFirstPage()
        XCTAssertEqual(model.state.status, .ready)
        XCTAssertEqual(model.state.items.map { $0.id }, ["g1"])
    }

    func testFailedShowMoreKeepsTheList() async throws {
        let client = FakeInboxClient()
        client.pages[""] = page([item("g2", sender: "ayla")], next: "c1")
        let model = GiftInboxModel(client: client)
        await model.loadFirstPage()
        client.failing = true
        await model.loadNextPage()
        XCTAssertEqual(model.state.status, .ready)
        XCTAssertTrue(model.state.hasMore)
        XCTAssertFalse(model.state.loadingMore)
        XCTAssertEqual(model.state.items.map { $0.id }, ["g2"])
    }

    func testRefreshReloadsFromTheFirstPage() async throws {
        let client = FakeInboxClient()
        client.pages[""] = page([item("g1", sender: "ayla")])
        let model = GiftInboxModel(client: client)
        await model.loadFirstPage()
        client.pages[""] = page([item("g2", sender: "ayla"), item("g1", sender: "ayla")])
        await model.loadFirstPage()
        XCTAssertEqual(model.state.items.map { $0.id }, ["g2", "g1"])
    }

    func testSenderNamesComeFromResolveUsers() async throws {
        let client = FakeInboxClient()
        client.pages[""] = page([item("g2", sender: "ayla"), item("g1", sender: "mert")])
        let model = GiftInboxModel(client: client, resolveUsers: { ids in
            var out: [String: GiftUserInfo] = [:]
            for id in ids where id == "ayla" {
                out[id] = GiftUserInfo(name: "Ayla K.")
            }
            return out
        })
        await model.loadFirstPage()
        let rows = model.rows(nowMs: 1_793_613_600_000)
        XCTAssertEqual(rows.map { $0.senderName }, ["Ayla K.", "mert"])
    }

    func testDisposeDropsLateAnswers() async throws {
        let client = FakeInboxClient()
        client.pages[""] = page([item("g1", sender: "ayla")])
        let model = GiftInboxModel(client: client)
        model.dispose()
        await model.loadFirstPage()
        XCTAssertEqual(model.state.status, .loading)
        XCTAssertTrue(model.state.items.isEmpty)
    }
}

#endif
