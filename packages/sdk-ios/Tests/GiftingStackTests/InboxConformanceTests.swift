import Foundation
import XCTest
@testable import GiftingStack

/// conformance/inbox.json (spec 19): the `client` section (getInbox with and without a query),
/// inboxTimeLabel, inboxRows and inboxUnread.
final class InboxConformanceTests: XCTestCase {
    private static let topKeys: Set<String> = ["description", "client", "time", "rows", "unread"]

    func testFileHasOnlyKnownSections() throws {
        let f = try Fixtures.conformance("inbox.json")
        assertKnownKeys(f, InboxConformanceTests.topKeys, "[inbox.json]")
    }

    func testClientSection() async throws {
        let f = try Fixtures.conformance("inbox.json")
        for s in try Fixtures.list(f["client"], "inbox.json client") {
            try await runClientScenario(s, fixture: "inbox.json")
        }
    }

    func testTimeLabel() throws {
        let f = try Fixtures.conformance("inbox.json")
        for c in try Fixtures.list(f["time"], "inbox.json time") {
            let name = c["name"]?.stringValue ?? "?"
            let at = "[inbox.json time] \(name)"
            assertKnownKeys(c, ["name", "description", "createdAtMs", "nowMs", "label"], at)
            let created = try XCTUnwrap(c["createdAtMs"]?.intValue, at)
            let now = try XCTUnwrap(c["nowMs"]?.intValue, at)
            XCTAssertEqual(inboxTimeLabel(createdAtMs: created, nowMs: now), c["label"]?.stringValue, at)
        }
    }

    func testRows() throws {
        let f = try Fixtures.conformance("inbox.json")
        for c in try Fixtures.list(f["rows"], "inbox.json rows") {
            let name = c["name"]?.stringValue ?? "?"
            let at = "[inbox.json rows] \(name)"
            assertKnownKeys(c, ["name", "description", "nowMs", "names", "items", "expect"], at)
            let now = try XCTUnwrap(c["nowMs"]?.intValue, at)
            var names: [String: String] = [:]
            for (id, value) in c["names"]?.objectValue ?? [:] {
                names[id] = value.stringValue
            }
            let items = try (c["items"] ?? .array([])).decode([InboxItem].self)
            let rows = inboxRows(items, nowMs: now, names: names)
            let expected = c["expect"]?.arrayValue ?? []
            XCTAssertEqual(rows.count, expected.count, "\(at): row count")
            for (row, want) in zip(rows, expected) {
                assertKnownKeys(want, ["id", "senderName", "giftName", "quantity", "time", "iconUrl", "sender"], at)
                XCTAssertEqual(row.id, want["id"]?.stringValue, "\(at) id")
                XCTAssertEqual(row.senderName, want["senderName"]?.stringValue, "\(at) \(row.id) senderName")
                XCTAssertEqual(row.giftName, want["giftName"]?.stringValue, "\(at) \(row.id) giftName")
                XCTAssertEqual(row.quantity, want["quantity"]?.intValue, "\(at) \(row.id) quantity")
                XCTAssertEqual(row.time, want["time"]?.stringValue, "\(at) \(row.id) time")
                if let icon = want["iconUrl"] {
                    XCTAssertEqual(row.iconUrl, icon.stringValue, "\(at) \(row.id) iconUrl")
                }
                if let sender = want["sender"] {
                    XCTAssertEqual(row.sender, sender.stringValue, "\(at) \(row.id) sender")
                }
            }
        }
    }

    func testUnread() throws {
        let f = try Fixtures.conformance("inbox.json")
        for c in try Fixtures.list(f["unread"], "inbox.json unread") {
            let name = c["name"]?.stringValue ?? "?"
            let at = "[inbox.json unread] \(name)"
            assertKnownKeys(c, ["name", "description", "lastSeenMs", "items", "count"], at)
            // The fixture items only carry created_at, status and quantity.
            var items: [InboxItem] = []
            for (index, raw) in (c["items"]?.arrayValue ?? []).enumerated() {
                items.append(InboxItem(
                    id: "g\(index)",
                    createdAt: raw["created_at"]?.stringValue ?? "",
                    sender: nil,
                    gift: InboxGift(id: "rose", name: "Rose", price: 10),
                    quantity: raw["quantity"]?.intValue ?? 1,
                    units: 10,
                    status: raw["status"]?.stringValue ?? "completed"
                ))
            }
            let count = inboxUnread(items, lastSeenMs: c["lastSeenMs"]?.intValue)
            XCTAssertEqual(count, c["count"]?.intValue, at)
        }
    }
}
