import Foundation
import XCTest
@testable import GiftingStack

/// conformance/away.json (spec 15): planAwayReplay, awaySenderLabel, the AwayController with a
/// fake clock, a scripted client and a stub effect player, and the `client` section (getAway,
/// ackAway with its 204).
@MainActor
final class AwayConformanceTests: XCTestCase {
    private static let topKeys: Set<String> = ["description", "gifts", "plan", "senderLabel", "summaries", "controller", "client"]
    private static let planOptionKeys: Set<String> = ["maxEffects", "budgetMs", "thresholds", "quality", "reducedMotion", "labels"]
    private static let itemKeys: Set<String> = ["gift", "name", "price", "image", "icon", "atMs", "durationMs", "tier", "quantity", "sender"]
    private static let controllerOptionKeys: Set<String> = ["ackOn", "maxGroups", "maxEffects", "budgetMs", "effects", "reducedMotion"]
    private static let stepKeys: Set<String> = ["check", "foreground", "start", "dismiss", "ack", "dispose", "advance", "resolve", "reject", "expect"]
    private static let expectKeys: Set<String> = ["status", "summaryCursor", "planEndMs", "played", "calls", "pending", "shown", "done", "errors"]

    func testFileHasOnlyKnownSections() throws {
        let f = try Fixtures.conformance("away.json")
        assertKnownKeys(f, AwayConformanceTests.topKeys, "[away.json]")
    }

    // MARK: - plan

    func testPlan() throws {
        let f = try Fixtures.conformance("away.json")
        let gifts = try XCTUnwrap(f["gifts"]?.objectValue, "away.json gifts")
        for c in try Fixtures.list(f["plan"], "away.json plan") {
            let name = c["name"]?.stringValue ?? "?"
            let at = "[away.json plan] \(name)"
            assertKnownKeys(c, ["name", "description", "groups", "names", "options", "expect"], at)
            let o = c["options"]
            assertKnownKeys(o, AwayConformanceTests.planOptionKeys, "\(at) options")
            assertKnownKeys(o?["labels"], ["someone"], "\(at) labels")
            assertKnownKeys(o?["thresholds"], ["mediumFrom", "largeFrom"], "\(at) thresholds")
            var options = AwayReplayOptions()
            if let n = o?["maxEffects"]?.intValue {
                options.maxEffects = n
            }
            if let n = o?["budgetMs"]?.intValue {
                options.budgetMs = n
            }
            if let t = o?["thresholds"] {
                options.thresholds = TierThresholds(
                    mediumFrom: t["mediumFrom"]?.intValue ?? GiftingSpec.defaultMediumFrom,
                    largeFrom: t["largeFrom"]?.intValue ?? GiftingSpec.defaultLargeFrom
                )
            }
            if let raw = o?["quality"]?.stringValue {
                options.quality = try XCTUnwrap(EffectQuality(rawValue: raw), "\(at): quality \(raw)")
            }
            if let flag = o?["reducedMotion"]?.boolValue {
                options.reducedMotion = flag
            }
            if let someone = o?["labels"]?["someone"]?.stringValue {
                options.labels.someone = someone
            }
            var names: [String: String] = [:]
            for (id, value) in c["names"]?.objectValue ?? [:] {
                names[id] = value.stringValue ?? id
            }
            options.resolveName = { id in names[id] ?? id }

            let plan = planAwayReplay(try awayGroups(c["groups"], gifts, at), options: options)
            let expected = try XCTUnwrap(c["expect"], "\(at): expect")
            assertKnownKeys(expected, ["endMs", "items"], "\(at) expect")
            XCTAssertEqual(plan.endMs, expected["endMs"]?.intValue, "\(at) endMs")
            let items = expected["items"]?.arrayValue ?? []
            XCTAssertEqual(plan.items.count, items.count, "\(at) items")
            for (i, item) in plan.items.enumerated() where i < items.count {
                var actual: [String: JSONValue] = [:]
                actual["gift"] = .string(item.event.gift.id)
                actual["name"] = .string(item.event.gift.name)
                actual["price"] = .number(Double(item.event.gift.price))
                actual["image"] = optionalString(item.event.gift.image)
                actual["icon"] = optionalString(item.event.gift.icon)
                actual["atMs"] = .number(Double(item.atMs))
                actual["durationMs"] = .number(Double(item.durationMs))
                actual["tier"] = .string(item.tier.rawValue)
                actual["quantity"] = optionalNumber(item.event.quantity)
                actual["sender"] = optionalString(item.event.sender)
                assertKnownKeys(items[i], AwayConformanceTests.itemKeys, "\(at) item \(i + 1)")
                for (key, value) in items[i].objectValue ?? [:] {
                    assertJSONEqual(actual[key] ?? .null, value, "\(at) item \(i + 1).\(key)")
                }
            }
        }
    }

    // MARK: - senderLabel

    func testSenderLabel() throws {
        let f = try Fixtures.conformance("away.json")
        for c in try Fixtures.list(f["senderLabel"], "away.json senderLabel") {
            let at = "[away.json senderLabel] \(c)"
            assertKnownKeys(c, ["names", "senderCount", "labels", "expect"], at)
            assertKnownKeys(c["labels"], ["someone", "pair", "oneOther", "others"], "\(at) labels")
            let names = (c["names"]?.arrayValue ?? []).map { $0.stringValue ?? "" }
            let count = try XCTUnwrap(c["senderCount"]?.intValue, at)
            var labels = AwaySenderLabels()
            if let v = c["labels"]?["someone"]?.stringValue {
                labels.someone = v
            }
            if let v = c["labels"]?["pair"]?.stringValue {
                labels.pair = v
            }
            if let v = c["labels"]?["oneOther"]?.stringValue {
                labels.oneOther = v
            }
            if let v = c["labels"]?["others"]?.stringValue {
                labels.others = v
            }
            XCTAssertEqual(awaySenderLabel(names, senderCount: count, labels: labels), c["expect"]?.stringValue, at)
        }
    }

    // MARK: - controller

    func testController() async throws {
        let f = try Fixtures.conformance("away.json")
        let gifts = try XCTUnwrap(f["gifts"]?.objectValue, "away.json gifts")
        let summaries = try XCTUnwrap(f["summaries"]?.objectValue, "away.json summaries")
        for s in try Fixtures.list(f["controller"], "away.json controller") {
            try await runController(s, gifts: gifts, summaries: summaries)
        }
    }

    private func runController(_ s: JSONValue, gifts: [String: JSONValue], summaries: [String: JSONValue]) async throws {
        let name = s["name"]?.stringValue ?? "?"
        assertKnownKeys(s, ["name", "description", "options", "steps"], "[away.json controller] \(name)")
        let o = s["options"]
        assertKnownKeys(o, AwayConformanceTests.controllerOptionKeys, "[away.json controller] \(name) options")
        let clock = FakeGiftClock()
        let client = ScriptedComponentClient()
        let player = AwayStubPlayer(clock: clock)
        let log = AwayLog()

        var ackOn = AwayAckOn.shown
        if let raw = o?["ackOn"]?.stringValue {
            ackOn = try XCTUnwrap(AwayAckOn(rawValue: raw), "\(name): ackOn \(raw)")
        }
        let effects: (() -> (any EffectPlayer)?)?
        if o?["effects"]?.boolValue == false {
            effects = nil
        } else {
            effects = { player }
        }
        let reducedMotion: (() -> Bool)?
        if o?["reducedMotion"]?.boolValue == true {
            reducedMotion = { true }
        } else {
            reducedMotion = nil
        }
        let controller = AwayController(
            client: client,
            effects: effects,
            reducedMotion: reducedMotion,
            ackOn: ackOn,
            maxGroups: o?["maxGroups"]?.intValue,
            maxEffects: o?["maxEffects"]?.intValue ?? defaultAwayMaxEffects,
            budgetMs: o?["budgetMs"]?.intValue ?? defaultAwayBudgetMs,
            clock: clock,
            onShow: { _ in log.shown += 1 },
            onDone: { log.done += 1 },
            onError: { e in log.errors.append(e.type) }
        )

        for (index, step) in try Fixtures.list(s["steps"], "\(name) steps").enumerated() {
            let at = "[away.json controller] \(name) step \(index + 1)"
            assertKnownKeys(step, AwayConformanceTests.stepKeys, at)
            if step["check"]?.boolValue == true {
                Task { await controller.check() }
            } else if step["foreground"]?.boolValue == true {
                Task { await controller.foreground() }
            } else if step["start"]?.boolValue == true {
                controller.start()
            } else if step["dismiss"]?.boolValue == true {
                controller.dismiss()
            } else if step["ack"]?.boolValue == true {
                controller.ack()
            } else if step["dispose"]?.boolValue == true {
                controller.dispose()
            } else if let ms = step["advance"]?.intValue {
                clock.advance(ms)
            } else if let resolve = step["resolve"] {
                let method = try XCTUnwrap(resolve["method"]?.stringValue, at)
                if method == "getAway" {
                    let key = try XCTUnwrap(resolve["value"]?.stringValue, "\(at): summary key")
                    let raw = try XCTUnwrap(summaries[key], "\(at): unknown summary \(key)")
                    let summary = try expandAwayGifts(raw, gifts, at).decode(AwaySummary.self)
                    try client.resolveAway(summary, at: at)
                } else if method == "ackAway" {
                    try client.resolveAck(at: at)
                } else {
                    XCTFail("\(at): unknown method \(method)")
                }
            } else if let reject = step["reject"] {
                let method = try XCTUnwrap(reject["method"]?.stringValue, at)
                try client.reject(method, error: try fixtureError(try XCTUnwrap(reject["error"], at), at), at: at)
            } else if let x = step["expect"] {
                assertKnownKeys(x, AwayConformanceTests.expectKeys, at)
                let state = controller.state
                if let expected = x["status"] {
                    assertJSONEqual(.string(state.status.rawValue), expected, "\(at) status")
                }
                if let expected = x["summaryCursor"] {
                    let cursor = state.summary?.cursor
                    assertJSONEqual(cursor.map { JSONValue.string($0) } ?? .null, expected, "\(at) summaryCursor")
                }
                if let expected = x["planEndMs"] {
                    let end = state.plan?.endMs
                    assertJSONEqual(end.map { JSONValue.number(Double($0)) } ?? .null, expected, "\(at) planEndMs")
                }
                if let expected = x["played"] {
                    assertJSONEqual(.array(player.played), expected, "\(at) played")
                }
                if let expected = x["calls"] {
                    assertJSONEqual(.array(client.calls), expected, "\(at) calls")
                }
                if let expected = x["pending"] {
                    assertJSONEqual(.array(client.pending.map { .string($0.method) }), expected, "\(at) pending")
                }
                if let expected = x["shown"] {
                    assertJSONEqual(.number(Double(log.shown)), expected, "\(at) shown")
                }
                if let expected = x["done"] {
                    assertJSONEqual(.number(Double(log.done)), expected, "\(at) done")
                }
                if let expected = x["errors"] {
                    assertJSONEqual(.array(log.errors.map { .string($0) }), expected, "\(at) errors")
                }
            } else {
                XCTFail("\(at): unknown step \(step)")
            }
            await clock.settle()
        }
    }

    // MARK: - client

    /// The `client` section: getAway (with and without a query) and ackAway (204, retry, 400).
    func testClientSection() async throws {
        let f = try Fixtures.conformance("away.json")
        for s in try Fixtures.list(f["client"], "away.json client") {
            try await runClientScenario(s, fixture: "away.json")
        }
    }
}

/// A `plan`/`summaries` summary whose `groups[].gift` is an id (the fixture shorthand, never used
/// in a `client` body): the gift object from `gifts[id]`.
/// Objects without `groups` come back unchanged.
func expandAwayGifts(_ summary: JSONValue, _ gifts: [String: JSONValue], _ at: String) throws -> JSONValue {
    guard var object = summary.objectValue, let groups = object["groups"]?.arrayValue else {
        return summary
    }
    var out: [JSONValue] = []
    for group in groups {
        guard var g = group.objectValue else {
            out.append(group)
            continue
        }
        if let id = g["gift"]?.stringValue {
            g["gift"] = try XCTUnwrap(gifts[id], "\(at): unknown gift \(id)")
        }
        out.append(.object(g))
    }
    object["groups"] = .array(out)
    return .object(object)
}

/// Groups written with `"gift": "<id>"`, decoded as `AwayGroup`s.
func awayGroups(_ list: JSONValue?, _ gifts: [String: JSONValue], _ at: String) throws -> [AwayGroup] {
    let wrapped = try expandAwayGifts(.object(["groups": list ?? .array([])]), gifts, at)
    return try (wrapped["groups"] ?? .array([])).decode([AwayGroup].self)
}

/// Counts and errors reported by the controller's callbacks.
@MainActor
private final class AwayLog {
    var shown = 0
    var done = 0
    var errors: [String] = []
}

/// Records `{ atMs: clock now, gift, quantity, sender }` for every play.
@MainActor
private final class AwayStubPlayer: EffectPlayer {
    private let clock: FakeGiftClock
    private(set) var played: [JSONValue] = []

    init(clock: FakeGiftClock) {
        self.clock = clock
    }

    func play(_ event: GiftEffectEvent) -> Int {
        var entry: [String: JSONValue] = [
            "atMs": .number(Double(clock.now)),
            "gift": .string(event.gift.id),
        ]
        if let quantity = event.quantity {
            entry["quantity"] = .number(Double(quantity))
        }
        if let sender = event.sender {
            entry["sender"] = .string(sender)
        }
        played.append(.object(entry))
        return played.count
    }

    func cancel(_ id: Int) {}
}
