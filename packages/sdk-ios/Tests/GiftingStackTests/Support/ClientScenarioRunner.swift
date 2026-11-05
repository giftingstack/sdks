import Foundation
import XCTest
@testable import GiftingStack

/// Keys a client scenario may have (conformance/README.md, "client.json"); anything else fails.
private let clientScenarioKeys: Set<String> = [
    "name", "description", "note", "baseUrl", "call", "tokens", "exchanges", "result", "error",
]

/// Runs one client scenario against a scripted transport and token provider. Shared by
/// client.json and the `client` sections of wall.json, away.json and leaderboard.json.
func runClientScenario(_ s: JSONValue, fixture: String) async throws {
    let name = s["name"]?.stringValue ?? "?"
    let context = "[\(fixture) client] \(name)"
    for key in (s.objectValue ?? [:]).keys where !clientScenarioKeys.contains(key) {
        XCTFail("\(context): the runner does not know scenario key \(key)")
    }
    let exchanges = s["exchanges"]?.arrayValue ?? []
    let tokens = s["tokens"]?.arrayValue ?? []
    let script = ScriptedHTTP(exchanges: exchanges, tokens: tokens)
    let tokenScript = script
    let client = GiftingClient(
        getToken: { forceRefresh in try tokenScript.nextToken(forceRefresh) },
        baseURL: s["baseUrl"]?.stringValue,
        transport: script
    )
    let call = try XCTUnwrap(s["call"], context)
    let method = try XCTUnwrap(call["method"]?.stringValue, context)
    let args = call["args"] ?? .object([:])

    var result: JSONValue?
    var failure: Error?
    do {
        result = try await callClient(client, method: method, args: args, context: context)
    } catch {
        failure = error
    }

    for problem in script.problems {
        XCTFail("\(context): \(problem)")
    }

    if let expectedError = s["error"] {
        guard let error = failure as? GiftingError else {
            XCTFail("\(context): expected a GiftingError, got \(String(describing: failure)) / result \(String(describing: result))")
            return
        }
        let actual: JSONValue = .object([
            "status": .number(Double(error.status)),
            "type": .string(error.type),
            "message": .string(error.message),
            "requestId": error.requestId.map { JSONValue.string($0) } ?? .null,
            "retryable": .bool(error.retryable),
            "insufficientBalance": .bool(error.insufficientBalance),
        ])
        assertJSONEqual(actual, expectedError, "\(context) error")
    } else if let failure = failure {
        XCTFail("\(context): unexpected failure \(failure)")
    } else {
        let expected = try XCTUnwrap(s["result"], "\(context): fixture has neither result nor error")
        assertJSONEqual(result ?? .null, expected, "\(context) result")
    }
    XCTAssertEqual(script.requestCount, exchanges.count, "\(context): requests made")
    XCTAssertEqual(script.tokenCount, tokens.count, "\(context): getToken calls")
}

/// The call under test; the returned value as wire JSON (`null` for a call that returns nothing).
private func callClient(_ client: GiftingClient, method: String, args: JSONValue, context: String) async throws -> JSONValue {
    switch method {
    case "getGifts":
        return try JSONValue.of(try await client.getGifts())
    case "getMe":
        return try JSONValue.of(try await client.getMe())
    case "getReceivedGifts":
        let user = try XCTUnwrap(args["user"]?.stringValue, context)
        if let reference = args["reference"] {
            return try JSONValue.of(try await client.getReceivedGifts(user, reference: reference.stringValue))
        }
        return try JSONValue.of(try await client.getReceivedGifts(user))
    case "sendGift":
        let input = try XCTUnwrap(args["input"], context)
        return try JSONValue.of(try await client.sendGift(try sendGiftInput(input, context)))
    case "queryGiftWalls":
        let items = try XCTUnwrap(args["items"]?.arrayValue, context)
        var list: [GiftWallQueryItem] = []
        for item in items {
            let receiver = try XCTUnwrap(item["receiver"]?.stringValue, context)
            list.append(GiftWallQueryItem(receiver: receiver, reference: item["reference"]?.stringValue))
        }
        return try JSONValue.of(try await client.queryGiftWalls(list))
    case "getAway":
        guard let query = args["query"] else {
            return try JSONValue.of(try await client.getAway())
        }
        let away = AwayQuery(since: query["since"]?.stringValue, maxGroups: query["maxGroups"]?.intValue)
        return try JSONValue.of(try await client.getAway(away))
    case "getInbox":
        guard let query = args["query"] else {
            return try JSONValue.of(try await client.getInbox())
        }
        let inbox = InboxQuery(cursor: query["cursor"]?.stringValue, limit: query["limit"]?.intValue)
        return try JSONValue.of(try await client.getInbox(inbox))
    case "ackAway":
        let cursor = try XCTUnwrap(args["cursor"]?.stringValue, context)
        try await client.ackAway(cursor)
        return .null
    case "getLeaderboard":
        let raw = try XCTUnwrap(args["board"]?.stringValue, context)
        let board = try XCTUnwrap(LeaderboardBoard(rawValue: raw), "\(context): board \(raw)")
        guard let query = args["query"] else {
            return try JSONValue.of(try await client.getLeaderboard(board))
        }
        return try JSONValue.of(try await client.getLeaderboard(board, query: try leaderboardQuery(query, context)))
    default:
        throw FixtureError(description: "\(context): unknown call \(method)")
    }
}

/// `SendGiftInput` from the fixture's SDK field names; a missing key is "not given".
func sendGiftInput(_ input: JSONValue, _ context: String) throws -> SendGiftInput {
    SendGiftInput(
        receiver: try XCTUnwrap(input["receiver"]?.stringValue, context),
        giftId: try XCTUnwrap(input["giftId"]?.stringValue, context),
        quantity: input["quantity"]?.intValue,
        message: input["message"]?.stringValue,
        reference: input["reference"]?.stringValue,
        roomId: input["roomId"]?.stringValue,
        idempotencyKey: input["idempotencyKey"]?.stringValue
    )
}

/// `LeaderboardQuery` from `{ period, metric, at, limit, includeMe }`; a missing key is "not given".
func leaderboardQuery(_ q: JSONValue, _ context: String) throws -> LeaderboardQuery {
    var query = LeaderboardQuery()
    if let raw = q["period"]?.stringValue {
        query.period = try XCTUnwrap(LeaderboardPeriod(rawValue: raw), "\(context): period \(raw)")
    }
    if let raw = q["metric"]?.stringValue {
        query.metric = try XCTUnwrap(LeaderboardMetric(rawValue: raw), "\(context): metric \(raw)")
    }
    query.at = q["at"]?.stringValue
    query.limit = q["limit"]?.intValue
    query.includeMe = q["includeMe"]?.boolValue
    return query
}
