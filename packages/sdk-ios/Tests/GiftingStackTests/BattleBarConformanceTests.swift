import Foundation
import XCTest
@testable import GiftingStack

/// battle-bar.json (SPEC 18.7): the numbers every platform is held to. Contract:
/// conformance/README.md ("Battle bar"); the reference runner is the "conformance:
/// battle-bar.json" block of packages/sdk-js/test/battle-bar-core.test.ts.
final class BattleBarConformanceTests: XCTestCase {
    private func labels(_ c: JSONValue) -> BattleBarLabels {
        var out = BattleBarLabels()
        guard let m = c["labels"]?.objectValue else {
            return out
        }
        if let v = m["vs"]?.stringValue { out.vs = v }
        if let v = m["final"]?.stringValue { out.finalText = v }
        if let v = m["wins"]?.stringValue { out.wins = v }
        if let v = m["draw"]?.stringValue { out.draw = v }
        if let v = m["spoken"]?.stringValue { out.spoken = v }
        if let v = m["side"]?.stringValue { out.side = v }
        if let v = m["thousand"]?.stringValue { out.thousand = v }
        if let v = m["million"]?.stringValue { out.million = v }
        return out
    }

    func testTheFixtureHasCases() throws {
        let f = try Fixtures.conformance("battle-bar.json")
        XCTAssertGreaterThan(try Fixtures.list(f["score"], "score").count, 4)
        XCTAssertGreaterThan(try Fixtures.list(f["clock"], "clock").count, 4)
        XCTAssertGreaterThan(try Fixtures.list(f["model"], "model").count, 10)
        XCTAssertGreaterThan(try Fixtures.list(f["gains"], "gains").count, 3)
        XCTAssertGreaterThan(try Fixtures.list(f["colors"], "colors").count, 5)
    }

    func testScore() throws {
        let f = try Fixtures.conformance("battle-bar.json")
        for c in try Fixtures.list(f["score"], "battle-bar.json score") {
            let units = try XCTUnwrap(c["units"]?.intValue)
            XCTAssertEqual(formatBattleScore(units, labels: labels(c)), c["expect"]?.stringValue, "score \(units)")
        }
    }

    func testClock() throws {
        let f = try Fixtures.conformance("battle-bar.json")
        for c in try Fixtures.list(f["clock"], "battle-bar.json clock") {
            let ms = try XCTUnwrap(c["remainingMs"]?.intValue)
            XCTAssertEqual(formatBattleClock(ms), c["expect"]?.stringValue, "clock \(ms)")
        }
    }

    func testModel() throws {
        let f = try Fixtures.conformance("battle-bar.json")
        for c in try Fixtures.list(f["model"], "battle-bar.json model") {
            let at = "[battle-bar.json model] \(c["name"]?.stringValue ?? "?")"
            let frame = JSONValue.object(["t": .string("scores"), "battle": try XCTUnwrap(c["battle"], at)])
            let text = String(decoding: try frame.data(), as: UTF8.self)
            guard case .scores(let parsed?)? = parseRoomFrame(text) else {
                throw FixtureError(description: "\(at): battle does not parse")
            }
            let names = c["names"]?.objectValue ?? [:]
            let model = battleBarModel(
                battleView(parsed, serverNow: c["serverNow"]?.intValue),
                nameOf: { names[$0]?.stringValue ?? $0 },
                labels: labels(c)
            )
            let expected = try XCTUnwrap(c["expect"], at)
            if expected.isNull {
                XCTAssertNil(model, at)
                continue
            }
            let m = try XCTUnwrap(model, at)
            for (key, want) in expected.objectValue ?? [:] {
                switch key {
                case "pct":
                    XCTAssertEqual(m.pct, want.doubleValue ?? -1, accuracy: 1e-6, "\(at) pct")
                case "clock":
                    XCTAssertEqual(m.clock, want.stringValue, "\(at) clock")
                case "urgent":
                    XCTAssertEqual(m.urgent, want.boolValue, "\(at) urgent")
                case "final":
                    XCTAssertEqual(m.isFinal, want.boolValue, "\(at) final")
                case "winner":
                    XCTAssertEqual(m.winner, want.stringValue, "\(at) winner")
                case "banner":
                    XCTAssertEqual(m.banner, want.stringValue, "\(at) banner")
                case "spoken":
                    XCTAssertEqual(m.spoken, want.stringValue, "\(at) spoken")
                case "sides":
                    for (i, sideWant) in (want.arrayValue ?? []).enumerated() {
                        let s = m.sides[i]
                        for (k, v) in sideWant.objectValue ?? [:] {
                            let here = "\(at) sides[\(i)].\(k)"
                            switch k {
                            case "id": XCTAssertEqual(s.id, v.stringValue, here)
                            case "name": XCTAssertEqual(s.name, v.stringValue, here)
                            case "units": XCTAssertEqual(s.units, v.intValue, here)
                            case "score": XCTAssertEqual(s.score, v.stringValue, here)
                            case "spoken": XCTAssertEqual(s.spoken, v.stringValue, here)
                            case "leads": XCTAssertEqual(s.leads, v.boolValue, here)
                            case "won": XCTAssertEqual(s.won, v.boolValue, here)
                            case "lost": XCTAssertEqual(s.lost, v.boolValue, here)
                            default: XCTFail("\(here): unknown key")
                            }
                        }
                    }
                default:
                    XCTFail("\(at): unknown expect key \(key)")
                }
            }
        }
    }

    func testGains() throws {
        let f = try Fixtures.conformance("battle-bar.json")
        for c in try Fixtures.list(f["gains"], "battle-bar.json gains") {
            let before = c["before"]?.arrayValue?.compactMap { $0.intValue }
            let after = (c["after"]?.arrayValue ?? []).compactMap { $0.intValue }
            let expected = (c["expect"]?.arrayValue ?? []).compactMap { $0.boolValue }
            XCTAssertEqual(battleGains(before: before, after: after), expected, "gains \(String(describing: before)) -> \(after)")
        }
    }

    func testColors() throws {
        let f = try Fixtures.conformance("battle-bar.json")
        for c in try Fixtures.list(f["colors"], "battle-bar.json colors") {
            let at = "[battle-bar.json colors] \(c["name"]?.stringValue ?? "?")"
            let theme: GiftTheme
            switch c["theme"]?.stringValue {
            case "dark": theme = GiftTheme.darkTheme
            case "light": theme = GiftTheme.lightTheme
            default: theme = GiftTheme.defaultTheme
            }
            let over = c["override"]?.arrayValue?.compactMap { $0.stringValue }
            let got = battleSideColors(theme, override: over)
            let want = (c["expect"]?.arrayValue ?? []).map {
                SideColor(color: $0["color"]?.stringValue ?? "", text: $0["text"]?.stringValue ?? "")
            }
            XCTAssertEqual(got, want, at)
        }
    }
}
