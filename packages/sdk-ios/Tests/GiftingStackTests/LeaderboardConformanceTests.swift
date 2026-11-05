import Foundation
import XCTest
@testable import GiftingStack

/// conformance/leaderboard.json (spec 16): leaderboardRankLabel, pinnedMe, the medal tokens and
/// their contrast, the LeaderboardController with a fake clock and a scripted client, and the
/// `client` section (getLeaderboard, the 503 retry).
@MainActor
final class LeaderboardConformanceTests: XCTestCase {
    private static let topKeys: Set<String> = ["description", "pollMs", "rankLabel", "pin", "rankColors", "boards", "controller", "client"]
    private static let optionKeys: Set<String> = ["board", "periods", "initialPeriod", "metric", "limit", "includeMe"]
    private static let stepKeys: Set<String> = ["start", "setPeriod", "setMetric", "refresh", "dispose", "advance", "resolve", "reject", "expect"]
    private static let expectKeys: Set<String> = [
        "status", "period", "periods", "metric", "rows", "asOf", "refreshing", "error", "pinned", "calls", "pending", "errors",
    ]

    func testFileHasOnlyKnownSections() throws {
        let f = try Fixtures.conformance("leaderboard.json")
        assertKnownKeys(f, LeaderboardConformanceTests.topKeys, "[leaderboard.json]")
    }

    // MARK: - pollMs

    func testPollMs() throws {
        let f = try Fixtures.conformance("leaderboard.json")
        let poll = f["pollMs"]
        assertKnownKeys(poll, ["description", "minPollMs", "cases"], "[leaderboard.json pollMs]")
        XCTAssertEqual(leaderboardMinPollMs, poll?["minPollMs"]?.intValue)
        for c in try Fixtures.list(poll?["cases"], "leaderboard.json pollMs") {
            let at = "[leaderboard.json pollMs] \(c)"
            assertKnownKeys(c, ["refreshIntervalMs", "expect"], at)
            XCTAssertEqual(leaderboardPollMs(c["refreshIntervalMs"]?.intValue), c["expect"]?.intValue, at)
        }
    }

    // MARK: - rankLabel

    func testRankLabel() throws {
        let f = try Fixtures.conformance("leaderboard.json")
        for c in try Fixtures.list(f["rankLabel"], "leaderboard.json rankLabel") {
            let at = "[leaderboard.json rankLabel] \(c)"
            assertKnownKeys(c, ["rank", "labels", "expect"], at)
            assertKnownKeys(c["labels"], ["overflow"], "\(at) labels")
            let rank = c["rank"]?.intValue
            let label: String
            if let overflow = c["labels"]?["overflow"]?.stringValue {
                label = leaderboardRankLabel(rank, overflow: overflow)
            } else {
                label = leaderboardRankLabel(rank)
            }
            XCTAssertEqual(label, c["expect"]?.stringValue, at)
        }
    }

    // MARK: - pin

    func testPin() throws {
        let f = try Fixtures.conformance("leaderboard.json")
        for c in try Fixtures.list(f["pin"], "leaderboard.json pin") {
            let name = c["name"]?.stringValue ?? "?"
            let at = "[leaderboard.json pin] \(name)"
            assertKnownKeys(c, ["name", "description", "metric", "limit", "data", "me", "expect"], at)
            let wire: JSONValue = .object([
                "board": .string("senders"),
                "period": .string("week"),
                "metric": c["metric"] ?? .string("units"),
                "label": .string("2026-W41"),
                "starts_at": .null,
                "ends_at": .null,
                "as_of": .string("2026-10-11T07:30:00.000Z"),
                "data": c["data"] ?? .array([]),
                "has_more": .bool(false),
                "me": c["me"] ?? .null,
            ])
            let board = try wire.decode(Leaderboard.self)
            let limit = try XCTUnwrap(c["limit"]?.intValue, "\(at): limit")
            let expected = try XCTUnwrap(c["expect"]?.boolValue, "\(at): expect")
            let pinned = pinnedMe(board, limit: limit)
            XCTAssertEqual(pinned != nil, expected, "\(at): pinned")
            if expected, let me = pinned {
                assertJSONEqual(try JSONValue.of(me), c["me"] ?? .null, "\(at) me")
            }
        }
    }

    // MARK: - rankColors

    func testRankColorsAndContrast() throws {
        let f = try Fixtures.conformance("leaderboard.json")
        let rc = try XCTUnwrap(f["rankColors"], "leaderboard.json rankColors")
        assertKnownKeys(rc, ["tokens", "text", "min", "themes"], "[leaderboard.json rankColors]")
        let colors = GiftRankColors.standard
        let actual: JSONValue = .object([
            "rank1": .string(colors.rank1),
            "rank2": .string(colors.rank2),
            "rank3": .string(colors.rank3),
        ])
        let tokens = try XCTUnwrap(rc["tokens"], "rankColors tokens")
        assertJSONEqual(actual, tokens, "[leaderboard.json rankColors] tokens")
        let textToken = try XCTUnwrap(rc["text"]?.stringValue, "rankColors text")
        let minimum = try XCTUnwrap(rc["min"]?.doubleValue, "rankColors min")
        for themeName in try Fixtures.list(rc["themes"], "rankColors themes") {
            let name = try XCTUnwrap(themeName.stringValue)
            let theme: GiftTheme
            switch name {
            case "defaultTheme":
                theme = GiftTheme.defaultTheme
            case "darkTheme":
                theme = GiftTheme.darkTheme
            case "lightTheme":
                theme = GiftTheme.lightTheme
            default:
                XCTFail("[leaderboard.json rankColors] unknown theme \(name)")
                continue
            }
            let text = try XCTUnwrap(theme.token(textToken), "unknown token \(textToken)")
            for (token, color) in tokens.objectValue ?? [:] {
                let hex = color.stringValue ?? ""
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(hex, text),
                    minimum,
                    "[leaderboard.json rankColors] \(name).\(textToken) on \(token)"
                )
            }
        }
    }

    // MARK: - controller

    func testController() async throws {
        let f = try Fixtures.conformance("leaderboard.json")
        let boards = try XCTUnwrap(f["boards"]?.objectValue, "leaderboard.json boards")
        for s in try Fixtures.list(f["controller"], "leaderboard.json controller") {
            try await runController(s, boards: boards)
        }
    }

    private func runController(_ s: JSONValue, boards: [String: JSONValue]) async throws {
        let name = s["name"]?.stringValue ?? "?"
        let context = "[leaderboard.json controller] \(name)"
        assertKnownKeys(s, ["name", "description", "options", "steps"], context)
        let o = s["options"]
        assertKnownKeys(o, LeaderboardConformanceTests.optionKeys, "\(context) options")
        let clock = FakeGiftClock()
        let client = ScriptedComponentClient()
        let log = BoardErrorLog()

        var board = LeaderboardBoard.senders
        if let raw = o?["board"]?.stringValue {
            board = try XCTUnwrap(LeaderboardBoard(rawValue: raw), "\(context): board \(raw)")
        }
        var periods: [LeaderboardPeriod] = []
        for p in o?["periods"]?.arrayValue ?? [] {
            let raw = p.stringValue ?? ""
            periods.append(try XCTUnwrap(LeaderboardPeriod(rawValue: raw), "\(context): period \(raw)"))
        }
        var initialPeriod = LeaderboardPeriod.week
        if let raw = o?["initialPeriod"]?.stringValue {
            initialPeriod = try XCTUnwrap(LeaderboardPeriod(rawValue: raw), "\(context): initialPeriod \(raw)")
        }
        var metric: LeaderboardMetric?
        if let raw = o?["metric"]?.stringValue {
            metric = try XCTUnwrap(LeaderboardMetric(rawValue: raw), "\(context): metric \(raw)")
        }
        let controller = LeaderboardController(
            client: client,
            board: board,
            periods: periods,
            initialPeriod: initialPeriod,
            metric: metric,
            limit: o?["limit"]?.intValue ?? defaultLeaderboardLimit,
            includeMe: o?["includeMe"]?.boolValue ?? true,
            clock: clock,
            onError: { e in log.errors.append(e.type) }
        )

        for (index, step) in try Fixtures.list(s["steps"], "\(name) steps").enumerated() {
            let at = "\(context) step \(index + 1)"
            assertKnownKeys(step, LeaderboardConformanceTests.stepKeys, at)
            if step["start"]?.boolValue == true {
                controller.start()
            } else if let raw = step["setPeriod"]?.stringValue {
                controller.setPeriod(try XCTUnwrap(LeaderboardPeriod(rawValue: raw), "\(at): period \(raw)"))
            } else if let raw = step["setMetric"]?.stringValue {
                controller.setMetric(try XCTUnwrap(LeaderboardMetric(rawValue: raw), "\(at): metric \(raw)"))
            } else if step["refresh"]?.boolValue == true {
                controller.refresh()
            } else if step["dispose"]?.boolValue == true {
                controller.dispose()
            } else if let ms = step["advance"]?.intValue {
                clock.advance(ms)
            } else if let resolve = step["resolve"] {
                let method = try XCTUnwrap(resolve["method"]?.stringValue, at)
                XCTAssertEqual(method, "getLeaderboard", "\(at): method")
                let key = try XCTUnwrap(resolve["value"]?.stringValue, "\(at): board key")
                let value = try XCTUnwrap(boards[key], "\(at): unknown board \(key)").decode(Leaderboard.self)
                try client.resolveBoard(value, at: at)
            } else if let reject = step["reject"] {
                let method = try XCTUnwrap(reject["method"]?.stringValue, at)
                try client.reject(method, error: try fixtureError(try XCTUnwrap(reject["error"], at), at), at: at)
            } else if let x = step["expect"] {
                assertKnownKeys(x, LeaderboardConformanceTests.expectKeys, at)
                let state = controller.state
                if let expected = x["status"] {
                    assertJSONEqual(.string(state.status.rawValue), expected, "\(at) status")
                }
                if let expected = x["period"] {
                    assertJSONEqual(.string(state.period.rawValue), expected, "\(at) period")
                }
                if let expected = x["periods"] {
                    assertJSONEqual(.array(state.periods.map { .string($0.rawValue) }), expected, "\(at) periods")
                }
                if let expected = x["metric"] {
                    assertJSONEqual(.string(state.metric.rawValue), expected, "\(at) metric")
                }
                if let expected = x["rows"] {
                    var rows = JSONValue.null
                    if let data = state.data {
                        rows = .array(data.data.map { .string($0.user) })
                    }
                    assertJSONEqual(rows, expected, "\(at) rows")
                }
                if let expected = x["asOf"] {
                    let asOf = state.data?.asOf
                    assertJSONEqual(asOf.map { JSONValue.string($0) } ?? .null, expected, "\(at) asOf")
                }
                if let expected = x["refreshing"] {
                    assertJSONEqual(.bool(state.refreshing), expected, "\(at) refreshing")
                }
                if let expected = x["error"] {
                    let type = state.error?.type
                    assertJSONEqual(type.map { JSONValue.string($0) } ?? .null, expected, "\(at) error")
                }
                if let expected = x["pinned"] {
                    let user = state.pinned?.user
                    assertJSONEqual(user.map { JSONValue.string($0) } ?? .null, expected, "\(at) pinned")
                }
                if let expected = x["calls"] {
                    assertJSONEqual(.array(client.calls), expected, "\(at) calls")
                }
                if let expected = x["pending"] {
                    assertJSONEqual(.number(Double(client.pending.count)), expected, "\(at) pending")
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

    func testClientSection() async throws {
        let f = try Fixtures.conformance("leaderboard.json")
        for s in try Fixtures.list(f["client"], "leaderboard.json client") {
            try await runClientScenario(s, fixture: "leaderboard.json")
        }
    }
}

/// `onError` types reported by the controller.
@MainActor
private final class BoardErrorLog {
    var errors: [String] = []
}
