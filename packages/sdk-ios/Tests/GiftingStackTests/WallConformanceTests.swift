import Foundation
import XCTest
@testable import GiftingStack

/// conformance/wall.json (spec 14): wallChips, formatCount, the GiftWallLoader with a fake clock
/// and a scripted batch call, and the `client` section (getReceivedGifts with a reference,
/// queryGiftWalls).
@MainActor
final class WallConformanceTests: XCTestCase {
    private static let topKeys: Set<String> = ["description", "gifts", "chips", "formatCount", "loader", "client"]
    private static let stepKeys: Set<String> = ["load", "id", "advance", "respond", "fail", "invalidate", "expect"]
    private static let expectKeys: Set<String> = ["batches", "waiting", "resolved", "rejected"]

    func testFileHasOnlyKnownSections() throws {
        let f = try Fixtures.conformance("wall.json")
        assertKnownKeys(f, WallConformanceTests.topKeys, "[wall.json]")
    }

    // MARK: - chips

    func testChips() throws {
        let f = try Fixtures.conformance("wall.json")
        let gifts = try XCTUnwrap(f["gifts"]?.objectValue, "wall.json gifts")
        for c in try Fixtures.list(f["chips"], "wall.json chips") {
            let name = c["name"]?.stringValue ?? "?"
            let at = "[wall.json chips] \(name)"
            assertKnownKeys(c, ["name", "description", "items", "options", "expect"], at)
            assertKnownKeys(c["options"], ["max", "order"], "\(at) options")
            let items = try received(c["items"], gifts, at)
            var order = WallOrder.count
            if let raw = c["options"]?["order"]?.stringValue {
                order = try XCTUnwrap(WallOrder(rawValue: raw), "\(at): order \(raw)")
            }
            let maxChips = c["options"]?["max"]?.intValue ?? defaultWallMax
            let chips = wallChips(items, max: maxChips, order: order)
            let actual: [JSONValue] = chips.map { chip in
                switch chip {
                case .gift(let gift, let count):
                    return .object(["gift": .string(gift.id), "count": .number(Double(count))])
                case .overflow(let count, let hidden):
                    return .object(["overflow": .number(Double(count)), "hidden": .number(Double(hidden))])
                }
            }
            assertJSONEqual(.array(actual), c["expect"] ?? .null, at)
        }
    }

    // MARK: - formatCount

    func testFormatCount() throws {
        let f = try Fixtures.conformance("wall.json")
        for c in try Fixtures.list(f["formatCount"], "wall.json formatCount") {
            assertKnownKeys(c, ["n", "labels", "expect"], "[wall.json formatCount] \(c)")
            assertKnownKeys(c["labels"], ["thousand", "million", "decimal"], "[wall.json formatCount] \(c) labels")
            let n = try XCTUnwrap(c["n"]?.intValue, "\(c)")
            var labels = CountLabels()
            if let v = c["labels"]?["thousand"]?.stringValue {
                labels.thousand = v
            }
            if let v = c["labels"]?["million"]?.stringValue {
                labels.million = v
            }
            if let v = c["labels"]?["decimal"]?.stringValue {
                labels.decimal = v
            }
            XCTAssertEqual(formatCount(n, labels: labels), c["expect"]?.stringValue, "[wall.json formatCount] \(c)")
        }
    }

    // MARK: - loader

    func testLoader() async throws {
        let f = try Fixtures.conformance("wall.json")
        let gifts = try XCTUnwrap(f["gifts"]?.objectValue, "wall.json gifts")
        for s in try Fixtures.list(f["loader"], "wall.json loader") {
            try await runLoader(s, gifts)
        }
    }

    private func runLoader(_ s: JSONValue, _ gifts: [String: JSONValue]) async throws {
        let name = s["name"]?.stringValue ?? "?"
        assertKnownKeys(s, ["name", "description", "steps"], "[wall.json loader] \(name)")
        let clock = FakeGiftClock()
        let log = LoaderLog()
        let loader = GiftWallLoader(
            query: { items, done in
                log.batches.append(Batch(items: items, done: done))
            },
            clock: clock
        )
        var order: [String] = []

        for (index, step) in try Fixtures.list(s["steps"], "\(name) steps").enumerated() {
            let at = "[wall.json loader] \(name) step \(index + 1)"
            assertKnownKeys(step, WallConformanceTests.stepKeys, at)
            if let load = step["load"]?.arrayValue {
                let id = try XCTUnwrap(step["id"]?.stringValue, "\(at): id")
                let user = try XCTUnwrap(load.first?.stringValue, "\(at): user")
                let reference = load.count > 1 ? load[1].stringValue : nil
                order.append(id)
                Task {
                    do {
                        let list = try await loader.load(user, reference: reference)
                        log.settled[id] = .object(["ok": .bool(true), "value": compactGifts(list)])
                    } catch {
                        log.settled[id] = .object(["ok": .bool(false), "value": .string(asGiftingError(error).type)])
                    }
                }
            } else if let ms = step["advance"]?.intValue {
                clock.advance(ms)
            } else if let target = step["invalidate"]?.arrayValue {
                let user = try XCTUnwrap(target.first?.stringValue, "\(at): user")
                loader.invalidate(user, reference: target.count > 1 ? target[1].stringValue : nil)
            } else if let respond = step["respond"] {
                let n = try XCTUnwrap(respond["batch"]?.intValue, "\(at): batch")
                guard n >= 1 && n <= log.batches.count else {
                    XCTFail("\(at): batch \(n) was never sent (sent: \(log.batches.count))")
                    await clock.settle()
                    continue
                }
                let batch = log.batches[n - 1]
                let walls = respond["walls"]?.arrayValue ?? []
                var answer: [GiftWallResult] = []
                for (k, item) in batch.items.enumerated() {
                    let list = k < walls.count ? walls[k] : JSONValue.array([])
                    answer.append(GiftWallResult(receiver: item.receiver, reference: item.reference, gifts: try received(list, gifts, at)))
                }
                batch.done(.success(answer))
            } else if let fail = step["fail"] {
                let n = try XCTUnwrap(fail["batch"]?.intValue, "\(at): batch")
                guard n >= 1 && n <= log.batches.count else {
                    XCTFail("\(at): batch \(n) was never sent")
                    await clock.settle()
                    continue
                }
                log.batches[n - 1].done(.failure(try fixtureError(try XCTUnwrap(fail["error"], at), at)))
            } else if let x = step["expect"] {
                assertKnownKeys(x, WallConformanceTests.expectKeys, at)
                if let expected = x["batches"] {
                    var actual: [JSONValue] = []
                    for batch in log.batches {
                        actual.append(.array(try batch.items.map { try JSONValue.of($0) }))
                    }
                    assertJSONEqual(.array(actual), expected, "\(at) batches")
                }
                if let expected = x["waiting"] {
                    let open = order.filter { log.settled[$0] == nil }
                    assertJSONEqual(.array(open.map { .string($0) }), expected, "\(at) waiting")
                }
                for (id, value) in x["resolved"]?.objectValue ?? [:] {
                    let want: JSONValue = .object(["ok": .bool(true), "value": value])
                    assertJSONEqual(log.settled[id] ?? .null, want, "\(at) resolved \(id)")
                }
                for (id, value) in x["rejected"]?.objectValue ?? [:] {
                    let want: JSONValue = .object(["ok": .bool(false), "value": value])
                    assertJSONEqual(log.settled[id] ?? .null, want, "\(at) rejected \(id)")
                }
            } else {
                XCTFail("\(at): unknown step \(step)")
            }
            await clock.settle()
        }
    }

    // MARK: - client

    func testClientSection() async throws {
        let f = try Fixtures.conformance("wall.json")
        for s in try Fixtures.list(f["client"], "wall.json client") {
            try await runClientScenario(s, fixture: "wall.json")
        }
    }

    // MARK: - Helpers

    /// `[{ "gift": "<id>", "count": n }]` -> received gifts built from `gifts[id]`.
    private func received(_ list: JSONValue?, _ gifts: [String: JSONValue], _ at: String) throws -> [ReceivedGift] {
        var out: [ReceivedGift] = []
        for item in list?.arrayValue ?? [] {
            let id = try XCTUnwrap(item["gift"]?.stringValue, "\(at): gift id")
            let gift = try XCTUnwrap(gifts[id], "\(at): unknown gift \(id)").decode(GiftSummary.self)
            out.append(ReceivedGift(gift: gift, count: try XCTUnwrap(item["count"]?.intValue, "\(at): count")))
        }
        return out
    }

}

/// One batch call of the loader, answered by a step.
private final class Batch {
    let items: [GiftWallQueryItem]
    let done: (Result<[GiftWallResult], Error>) -> Void

    init(items: [GiftWallQueryItem], done: @escaping (Result<[GiftWallResult], Error>) -> Void) {
        self.items = items
        self.done = done
    }
}

/// What the scenario recorded: the batches sent and the settled loads (a class, so the load
/// tasks can write to it).
@MainActor
private final class LoaderLog {
    var batches: [Batch] = []
    var settled: [String: JSONValue] = [:]
}

/// Received gifts written back as `{ gift: id, count }`.
private func compactGifts(_ list: [ReceivedGift]) -> JSONValue {
    .array(list.map { .object(["gift": .string($0.gift.id), "count": .number(Double($0.count))]) })
}
