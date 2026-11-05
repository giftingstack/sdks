import Foundation
import XCTest
@testable import GiftingStack

/// conformance/tray.json scenarios: the GiftTrayController with a scripted client whose every
/// call stays pending until a step settles it.
@MainActor
final class TrayConformanceTests: XCTestCase {
    private static let expectKeys: Set<String> = [
        "balance", "user", "loading", "testMode", "gifts", "error", "played", "playedCount", "cancelled",
        "sent", "errors", "prefetched", "pending", "lastCall", "callCount",
    ]

    func testEveryTrayScenario() async throws {
        let f = try Fixtures.conformance("tray.json")
        let gifts = try XCTUnwrap(f["gifts"]?.objectValue, "tray.json gifts")
        let transactions = try XCTUnwrap(f["transactions"]?.objectValue, "tray.json transactions")
        for s in try Fixtures.list(f["scenarios"], "tray.json scenarios") {
            try await runScenario(s, gifts: gifts, transactions: transactions)
        }
    }

    private func runScenario(
        _ s: JSONValue,
        gifts: [String: JSONValue],
        transactions: [String: JSONValue]
    ) async throws {
        let name = s["name"]?.stringValue ?? "?"
        let options = s["options"] ?? .object([:])
        let client = ScriptedTrayClient()
        let player = StubEffectPlayer()
        var prefetched: [String] = []
        var sent: [String] = []
        var errors: [String] = []

        let playOn: PlayOn
        if let raw = options["playOn"]?.stringValue {
            playOn = try XCTUnwrap(PlayOn(rawValue: raw), "[tray.json] \(name): playOn")
        } else {
            playOn = .tap
        }
        let effects: (() -> (any EffectPlayer)?)?
        if options["effects"]?.boolValue == false {
            effects = nil
        } else {
            effects = { player }
        }
        let controller = GiftTrayController(
            client: client,
            receiver: options["receiver"]?.stringValue ?? "",
            effects: effects,
            playOn: playOn,
            reference: options["reference"]?.stringValue,
            onSent: { tx in sent.append(tx.id) },
            onError: { e in errors.append(e.type) },
            prefetch: { url in prefetched.append(url) }
        )

        for (index, step) in try Fixtures.list(s["steps"], "\(name) steps").enumerated() {
            let at = "[tray.json] \(name) step \(index + 1)"
            if step["mount"]?.boolValue == true || step["refresh"]?.boolValue == true {
                Task { await controller.refresh() }
            } else if step["dispose"]?.boolValue == true {
                controller.dispose()
            } else if let key = step["send"]?.stringValue {
                let gift = try XCTUnwrap(gifts[key], "\(at): unknown gift \(key)").decode(Gift.self)
                Task { await controller.send(gift) }
            } else if let resolve = step["resolve"] {
                let method = try XCTUnwrap(resolve["method"]?.stringValue, at)
                let value = resolve["value"] ?? .null
                try client.resolve(method, value: value, gifts: gifts, transactions: transactions, at: at)
            } else if let reject = step["reject"] {
                let method = try XCTUnwrap(reject["method"]?.stringValue, at)
                let error = try XCTUnwrap(reject["error"], at)
                try client.reject(method, error: makeError(error, at), at: at)
            } else if let x = step["expect"]?.objectValue {
                for key in x.keys where !TrayConformanceTests.expectKeys.contains(key) {
                    XCTFail("\(at): the runner does not know expect key \(key)")
                }
                let state = controller.state
                if let balance = x["balance"] {
                    assertJSONEqual(.number(Double(state.balance)), balance, "\(at) balance")
                }
                if let user = x["user"] {
                    assertJSONEqual(state.user.map { JSONValue.string($0) } ?? .null, user, "\(at) user")
                }
                if let loading = x["loading"] {
                    assertJSONEqual(.bool(state.loading), loading, "\(at) loading")
                }
                if let testMode = x["testMode"] {
                    assertJSONEqual(.bool(state.testMode), testMode, "(at) testMode")
                }
                if let ids = x["gifts"] {
                    assertJSONEqual(.array(state.gifts.map { .string($0.id) }), ids, "\(at) gifts")
                }
                if let expectedError = x["error"] {
                    if expectedError.isNull {
                        XCTAssertNil(state.error, "\(at) error should be null")
                    } else if let error = state.error {
                        // Subset match: only the listed fields.
                        let all = errorFields(error)
                        for (key, value) in expectedError.objectValue ?? [:] {
                            assertJSONEqual(all[key] ?? .null, value, "\(at) error.\(key)")
                        }
                    } else {
                        XCTFail("\(at) error: expected \(expectedError), got null")
                    }
                }
                if let played = x["played"] {
                    assertJSONEqual(.array(try player.playedJSON()), played, "\(at) played")
                }
                if let count = x["playedCount"] {
                    assertJSONEqual(.number(Double(player.played.count)), count, "\(at) playedCount")
                }
                if let cancelled = x["cancelled"] {
                    assertJSONEqual(.array(player.cancelled.map { .number(Double($0)) }), cancelled, "\(at) cancelled")
                }
                if let expected = x["sent"] {
                    assertJSONEqual(.array(sent.map { .string($0) }), expected, "\(at) sent")
                }
                if let expected = x["errors"] {
                    assertJSONEqual(.array(errors.map { .string($0) }), expected, "\(at) errors")
                }
                if let expected = x["prefetched"] {
                    assertJSONEqual(.array(prefetched.map { .string($0) }), expected, "\(at) prefetched")
                }
                if let expected = x["pending"] {
                    assertJSONEqual(.array(client.pending.map { .string($0.method) }), expected, "\(at) pending")
                }
                if let expected = x["lastCall"] {
                    assertJSONEqual(client.calls.last ?? .null, expected, "\(at) lastCall")
                }
                if let expected = x["callCount"] {
                    var counts: [String: JSONValue] = [:]
                    for call in client.calls {
                        let method = call["method"]?.stringValue ?? "?"
                        counts[method] = .number((counts[method]?.doubleValue ?? 0) + 1)
                    }
                    assertJSONEqual(.object(counts), expected, "\(at) callCount")
                }
            } else {
                XCTFail("\(at): unknown step \(step)")
            }
            await drain()
        }
    }

    /// "After every step the runner lets all pending asynchronous work run until nothing more
    /// can run, without advancing any clock." Everything here runs on the main actor; the short
    /// sleeps also let any executor hop come back before the next step.
    private func drain() async {
        for _ in 0..<4 {
            for _ in 0..<25 {
                await Task.yield()
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func makeError(_ e: JSONValue, _ at: String) throws -> Error {
        if let message = e["plain"]?.stringValue {
            return PlainError(message: message)
        }
        return GiftingError(
            status: try XCTUnwrap(e["status"]?.intValue, at),
            type: try XCTUnwrap(e["type"]?.stringValue, at),
            message: try XCTUnwrap(e["message"]?.stringValue, at),
            requestId: e["requestId"]?.stringValue
        )
    }

    private func errorFields(_ e: GiftingError) -> [String: JSONValue] {
        [
            "status": .number(Double(e.status)),
            "type": .string(e.type),
            "message": .string(e.message),
            "requestId": e.requestId.map { JSONValue.string($0) } ?? .null,
            "retryable": .bool(e.retryable),
            "insufficientBalance": .bool(e.insufficientBalance),
        ]
    }
}

/// "Any other exception whose message is `boom`".
struct PlainError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

/// Plays return 1, 2, 3, ... and are recorded; cancels are recorded.
@MainActor
final class StubEffectPlayer: EffectPlayer {
    var played: [(id: Int, event: GiftEffectEvent)] = []
    var cancelled: [Int] = []

    func play(_ event: GiftEffectEvent) -> Int {
        let id = played.count + 1
        played.append((id: id, event: event))
        return id
    }

    func cancel(_ id: Int) {
        cancelled.append(id)
    }

    /// `{ id, event }` with the event as wire-style JSON.
    func playedJSON() throws -> [JSONValue] {
        var out: [JSONValue] = []
        for entry in played {
            let event = try JSONValue.of(entry.event)
            out.append(.object(["id": .number(Double(entry.id)), "event": event]))
        }
        return out
    }
}

/// A client whose every call waits until the test resolves or rejects it.
@MainActor
final class ScriptedTrayClient: GiftingAPI {
    enum Waiter {
        case gifts(CheckedContinuation<[Gift], Error>)
        case me(CheckedContinuation<Me, Error>)
        case received(CheckedContinuation<[ReceivedGift], Error>)
        case send(CheckedContinuation<GiftTransaction, Error>)
    }

    struct PendingCall {
        let method: String
        let waiter: Waiter
    }

    private(set) var pending: [PendingCall] = []
    /// `{ method, args }` per call, args with absent fields dropped.
    private(set) var calls: [JSONValue] = []

    func getGifts() async throws -> [Gift] {
        calls.append(.object(["method": .string("getGifts")]))
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<[Gift], Error>) in
            pending.append(PendingCall(method: "getGifts", waiter: .gifts(c)))
        }
    }

    func getMe() async throws -> Me {
        calls.append(.object(["method": .string("getMe")]))
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Me, Error>) in
            pending.append(PendingCall(method: "getMe", waiter: .me(c)))
        }
    }

    func getReceivedGifts(_ user: String) async throws -> [ReceivedGift] {
        calls.append(.object(["method": .string("getReceivedGifts"), "args": .object(["user": .string(user)])]))
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<[ReceivedGift], Error>) in
            pending.append(PendingCall(method: "getReceivedGifts", waiter: .received(c)))
        }
    }

    func sendGift(_ input: SendGiftInput) async throws -> GiftTransaction {
        var args: [String: JSONValue] = [
            "receiver": .string(input.receiver),
            "giftId": .string(input.giftId),
        ]
        if let quantity = input.quantity {
            args["quantity"] = .number(Double(quantity))
        }
        if let message = input.message {
            args["message"] = .string(message)
        }
        if let reference = input.reference {
            args["reference"] = .string(reference)
        }
        if let roomId = input.roomId {
            args["roomId"] = .string(roomId)
        }
        if let key = input.idempotencyKey {
            args["idempotencyKey"] = .string(key)
        }
        calls.append(.object(["method": .string("sendGift"), "args": .object(args)]))
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<GiftTransaction, Error>) in
            pending.append(PendingCall(method: "sendGift", waiter: .send(c)))
        }
    }

    /// Completes the OLDEST pending call of `method`.
    func resolve(
        _ method: String,
        value: JSONValue,
        gifts: [String: JSONValue],
        transactions: [String: JSONValue],
        at: String
    ) throws {
        let call = try take(method, at)
        switch call.waiter {
        case .gifts(let c):
            var list: [Gift] = []
            for key in value.arrayValue ?? [] {
                let k = key.stringValue ?? ""
                list.append(try XCTUnwrap(gifts[k], "\(at): unknown gift \(k)").decode(Gift.self))
            }
            c.resume(returning: list)
        case .me(let c):
            c.resume(returning: try value.decode(Me.self))
        case .received(let c):
            c.resume(returning: try value.decode([ReceivedGift].self))
        case .send(let c):
            if let key = value.stringValue {
                c.resume(returning: try XCTUnwrap(transactions[key], "\(at): unknown transaction \(key)").decode(GiftTransaction.self))
            } else {
                c.resume(returning: try value.decode(GiftTransaction.self))
            }
        }
    }

    /// Fails the OLDEST pending call of `method`.
    func reject(_ method: String, error: Error, at: String) throws {
        let call = try take(method, at)
        switch call.waiter {
        case .gifts(let c):
            c.resume(throwing: error)
        case .me(let c):
            c.resume(throwing: error)
        case .received(let c):
            c.resume(throwing: error)
        case .send(let c):
            c.resume(throwing: error)
        }
    }

    private func take(_ method: String, _ at: String) throws -> PendingCall {
        guard let index = pending.firstIndex(where: { $0.method == method }) else {
            throw FixtureError(description: "\(at): no pending \(method) (pending: \(pending.map { $0.method }))")
        }
        return pending.remove(at: index)
    }
}
