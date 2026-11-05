import Foundation
import XCTest
@testable import GiftingStack

/// conformance/tiers.json and conformance/combo.json (conformance/README.md).
final class TiersAndComboConformanceTests: XCTestCase {
    func testTiersJSONCases() throws {
        let f = try Fixtures.conformance("tiers.json")
        for (index, c) in try Fixtures.list(f["cases"], "tiers.json cases").enumerated() {
            let context = "[tiers.json] case \(index + 1) \(c)"
            let price = try XCTUnwrap(c["price"]?.doubleValue, context)
            let thresholds = try thresholdsFrom(c["thresholds"])
            let expected = try XCTUnwrap(c["tier"]?.stringValue, context)
            XCTAssertEqual(tierFor(price, thresholds: thresholds).rawValue, expected, context)
        }
    }

    func testTiersJSONRecipes() throws {
        let f = try Fixtures.conformance("tiers.json")
        for c in try Fixtures.list(f["recipes"], "tiers.json recipes") {
            let tierName = try XCTUnwrap(c["tier"]?.stringValue)
            let qualityName = try XCTUnwrap(c["quality"]?.stringValue)
            let context = "[tiers.json] recipe \(tierName)/\(qualityName)"
            let tier = try XCTUnwrap(EffectTier(rawValue: tierName), context)
            let quality = try XCTUnwrap(EffectQuality(rawValue: qualityName), context)
            let recipe = try JSONValue.of(recipeFor(tier, quality: quality))
            let expect = try XCTUnwrap(c["expect"]?.objectValue, context)
            XCTAssertFalse(expect.isEmpty, context)
            for (key, value) in expect {
                let actual = try XCTUnwrap(recipe[key], "\(context): recipe has no field \(key)")
                assertJSONEqual(actual, value, "\(context).\(key)")
            }
        }
    }

    func testComboJSONScenarios() throws {
        let f = try Fixtures.conformance("combo.json")
        for s in try Fixtures.list(f["scenarios"], "combo.json scenarios") {
            let name = s["name"]?.stringValue ?? "?"
            let tracker: ComboTracker
            if let window = s["windowMs"]?.intValue {
                tracker = ComboTracker(windowMs: window)
            } else {
                tracker = ComboTracker()
            }
            for (index, step) in try Fixtures.list(s["steps"], "\(name) steps").enumerated() {
                let context = "[combo.json] \(name) step \(index + 1)"
                if step["reset"]?.boolValue == true {
                    tracker.reset()
                    continue
                }
                let hit = try XCTUnwrap(step["hit"]?.arrayValue, context)
                XCTAssertEqual(hit.count, 3, context)
                let sender = try XCTUnwrap(hit[0].stringValue, context)
                let giftId = try XCTUnwrap(hit[1].stringValue, context)
                let at = try XCTUnwrap(hit[2].doubleValue, context)
                let count = try XCTUnwrap(step["count"]?.intValue, context)
                XCTAssertEqual(tracker.hit(sender: sender, giftId: giftId, now: at), count, context)
            }
        }
    }

    func testTraySendButtonCases() throws {
        let f = try Fixtures.conformance("tray.json")
        let block = try XCTUnwrap(f["sendButton"], "tray.json sendButton")
        for c in try Fixtures.list(block["cases"], "sendButton cases") {
            let context = "[tray.json sendButton] \(c["name"]?.stringValue ?? "?")"
            let input = try XCTUnwrap(c["input"], context)
            var gifts: [Gift] = []
            for g in input["gifts"]?.arrayValue ?? [] {
                let id = try XCTUnwrap(g["id"]?.stringValue, context)
                let price = try XCTUnwrap(g["price"]?.intValue, context)
                gifts.append(Gift(id: id, name: id, price: price))
            }
            let state = sendButtonState(
                gifts: gifts,
                selectedId: input["selectedId"]?.stringValue,
                balance: try XCTUnwrap(input["balance"]?.intValue, context),
                disabled: input["disabled"]?.boolValue ?? false,
                canTopUp: input["canTopUp"]?.boolValue ?? false
            )
            let actual: JSONValue = .object([
                "selectedId": state.selectedId.map { JSONValue.string($0) } ?? .null,
                "broke": .bool(state.broke),
                "label": .string(state.label.rawValue),
                "pressable": .bool(state.pressable),
                "action": .string(state.action.rawValue),
            ])
            assertJSONEqual(actual, try XCTUnwrap(c["expect"], context), context)
        }
    }

    private func thresholdsFrom(_ value: JSONValue?) throws -> TierThresholds {
        guard let object = value?.objectValue else {
            return TierThresholds()
        }
        var t = TierThresholds()
        if let medium = object["mediumFrom"]?.intValue {
            t.mediumFrom = medium
        }
        if let large = object["largeFrom"]?.intValue {
            t.largeFrom = large
        }
        return t
    }
}
