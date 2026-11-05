import Foundation
import XCTest
@testable import GiftingStack

/// conformance/remote-recipes.json: parseRemoteRecipes, mergeRecipeSet and remoteRecipesUrl
/// (spec section 13), plus the limits table of SPEC.md 13.3.
final class RemoteRecipesConformanceTests: XCTestCase {
    func testParse() throws {
        let f = try Fixtures.conformance("remote-recipes.json")
        let embeddedDoc = try Fixtures.load("recipes.json")
        for c in try Fixtures.list(f["parse"], "remote-recipes.json parse") {
            let name = "[remote-recipes.json parse] \(c["name"]?.stringValue ?? "?")"
            let input = try XCTUnwrap(c["input"], "\(name): input")
            let doc: JSONValue = input == .string("@embedded") ? embeddedDoc : input
            let expect = try XCTUnwrap(c["expect"], "\(name): expect")
            let parsed = parseRemoteRecipes(RemoteRecipesConformanceTests.remote(doc))
            if expect.isNull {
                XCTAssertNil(parsed, "\(name): the document must be ignored")
                continue
            }
            guard let set = parsed else {
                XCTFail("\(name): the document was ignored")
                continue
            }
            var wanted = RemoteRecipesConformanceTests.patched(RemoteRecipesConformanceTests.embeddedSetJSON(embeddedDoc), expect)
            if case .object(var o) = wanted {
                o["specVersion"] = doc["specVersion"] ?? .null
                wanted = .object(o)
            }
            let actual = try RemoteRecipesConformanceTests.setJSON(set.recipeSet, specVersion: set.specVersion)
            assertJSONEqual(actual, wanted, name)
        }
    }

    func testMerge() throws {
        let f = try Fixtures.conformance("remote-recipes.json")
        let embeddedDoc = try Fixtures.load("recipes.json")
        for c in try Fixtures.list(f["merge"], "remote-recipes.json merge") {
            let name = "[remote-recipes.json merge] \(c["name"]?.stringValue ?? "?")"
            let remoteDoc = try XCTUnwrap(c["remote"], "\(name): remote")
            var remoteSet: RecipeSet?
            if !remoteDoc.isNull {
                remoteSet = parseRemoteRecipes(RemoteRecipesConformanceTests.remote(remoteDoc))?.recipeSet
            }
            let app = c["app"]
            let overrides = AppRecipeOverrides(
                mediumFrom: app?["thresholds"]?["mediumFrom"]?.intValue,
                largeFrom: app?["thresholds"]?["largeFrom"]?.intValue,
                comboWindowMs: app?["comboWindowMs"]?.intValue
            )
            let merged = mergeRecipeSet(embedded: RecipeSet.embedded(), remote: remoteSet, app: overrides)
            var expect = try XCTUnwrap(c["expect"]?.objectValue, "\(name): expect")
            switch expect["recipes"]?.stringValue ?? "" {
            case "embedded":
                expect["recipes"] = try XCTUnwrap(embeddedDoc["recipes"])
            case "remote":
                let remote = try XCTUnwrap(remoteSet, "\(name): expects a remote set")
                let remoteJSON = try RemoteRecipesConformanceTests.setJSON(remote, specVersion: nil)
                expect["recipes"] = remoteJSON["recipes"]
            default:
                XCTFail("\(name): recipes must be \"embedded\" or \"remote\"")
            }
            let actual = try RemoteRecipesConformanceTests.setJSON(merged, specVersion: nil)
            assertJSONEqual(actual, .object(expect), name)
        }
    }

    func testUrls() throws {
        let f = try Fixtures.conformance("remote-recipes.json")
        for c in try Fixtures.list(f["urls"], "remote-recipes.json urls") {
            let name = "[remote-recipes.json urls] \(c["name"]?.stringValue ?? "?")"
            let got = remoteRecipesUrl(c["url"]?.stringValue, version: c["version"]?.stringValue)
            let expect = try XCTUnwrap(c["expect"], "\(name): expect")
            if expect.isNull {
                XCTAssertNil(got, "\(name): remote recipes must be off")
            } else {
                XCTAssertEqual(got, expect.stringValue, name)
            }
        }
    }

    /// SPEC.md 13.3: the code's limits equal the table, and every embedded number lies inside.
    func testLimitsTableEqualsTheSpec() throws {
        let url = Fixtures.specDirectory.appendingPathComponent("SPEC.md")
        let spec = try String(contentsOf: url, encoding: .utf8)
        let start = try XCTUnwrap(spec.range(of: "### 13.3"), "SPEC.md has no section 13.3")
        let end = try XCTUnwrap(spec.range(of: "### 13.4"), "SPEC.md has no section 13.4")
        let section = spec[start.upperBound..<end.lowerBound]
        var rows: [(key: String, min: Double, max: Double, integer: Bool)] = []
        for line in section.split(separator: "\n") where line.hasPrefix("| `") {
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            XCTAssertEqual(cells.count, 4, "SPEC.md 13.3 row \(line)")
            if cells.count != 4 {
                continue
            }
            let key = cells[0].replacingOccurrences(of: "`", with: "")
            let min = try XCTUnwrap(Double(cells[1].replacingOccurrences(of: ",", with: "")), "min of \(key)")
            let max = try XCTUnwrap(Double(cells[2].replacingOccurrences(of: ",", with: "")), "max of \(key)")
            rows.append((key: key, min: min, max: max, integer: cells[3] == "yes"))
        }
        XCTAssertEqual(rows.count, RemoteRecipes.limits.count, "rows in SPEC.md 13.3")
        for (row, code) in zip(rows, RemoteRecipes.limits) {
            XCTAssertEqual(row.key, code.key)
            XCTAssertEqual(row.min, code.limit.min, row.key)
            XCTAssertEqual(row.max, code.limit.max, row.key)
            XCTAssertEqual(row.integer, code.limit.integer, row.key)
        }

        let embedded = RecipeSet.embedded()
        func inside(_ key: String, _ value: Double) {
            let l = RemoteRecipes.limit(key)
            XCTAssertTrue(value >= l.min && value <= l.max, "embedded \(key) \(value) outside \(l.min)...\(l.max)")
        }
        inside("mediumFrom", Double(embedded.thresholds.mediumFrom))
        inside("largeFrom", Double(embedded.thresholds.largeFrom))
        inside("comboWindowMs", Double(embedded.comboWindowMs))
        for quality in EffectQuality.allCases {
            for tier in EffectTier.allCases {
                let r = embedded.recipe(tier, quality: quality)
                inside("peakScale", r.peakScale)
                inside("flyInMs", Double(r.flyInMs))
                inside("holdMs", Double(r.holdMs))
                inside("flyOutMs", Double(r.flyOutMs))
                inside("sparks", Double(r.sparks))
                inside("sparkSpread", r.sparkSpread)
                inside("coins", Double(r.coins))
                inside("noticeMs", Double(r.noticeMs))
            }
        }
    }

    // MARK: - Helpers

    /// Fixture JSON to the SDK's JSON type.
    static func remote(_ v: JSONValue) -> RemoteJSON {
        switch v {
        case .null:
            return .null
        case .bool(let b):
            return .bool(b)
        case .number(let n):
            return .number(n)
        case .string(let s):
            return .string(s)
        case .array(let a):
            return .array(a.map { remote($0) })
        case .object(let o):
            return .object(o.mapValues { remote($0) })
        }
    }

    /// `{ thresholds, comboWindowMs, recipes }` of recipes.json.
    static func embeddedSetJSON(_ doc: JSONValue) -> JSONValue {
        .object([
            "thresholds": doc["thresholds"] ?? .null,
            "comboWindowMs": doc["comboWindowMs"] ?? .null,
            "recipes": doc["recipes"] ?? .null,
        ])
    }

    /// README: objects merge recursively, any other value replaces.
    static func patched(_ base: JSONValue, _ patch: JSONValue) -> JSONValue {
        guard case .object(var b) = base, case .object(let p) = patch else {
            return patch
        }
        for (key, value) in p {
            if let existing = b[key] {
                b[key] = patched(existing, value)
            } else {
                b[key] = value
            }
        }
        return .object(b)
    }

    /// A recipe set in the shape of recipes.json (plus `specVersion` when given).
    static func setJSON(_ set: RecipeSet, specVersion: String?) throws -> JSONValue {
        func table(_ t: RecipeTable) throws -> JSONValue {
            let small = try JSONValue.of(t.small)
            let medium = try JSONValue.of(t.medium)
            let large = try JSONValue.of(t.large)
            return .object(["small": small, "medium": medium, "large": large])
        }
        let high = try table(set.high)
        let low = try table(set.low)
        var o: [String: JSONValue] = [
            "thresholds": .object([
                "mediumFrom": .number(Double(set.thresholds.mediumFrom)),
                "largeFrom": .number(Double(set.thresholds.largeFrom)),
            ]),
            "comboWindowMs": .number(Double(set.comboWindowMs)),
            "recipes": .object(["high": high, "low": low]),
        ]
        if let version = specVersion {
            o["specVersion"] = .string(version)
        }
        return .object(o)
    }
}
