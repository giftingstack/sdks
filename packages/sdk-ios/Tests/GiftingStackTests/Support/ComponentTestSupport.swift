import Foundation
import XCTest
@testable import GiftingStack

/// One timer of the fake clock.
private struct FakeTimer {
    let id: Int
    let due: Int
    let fire: () -> Void
}

/// The fake clock of conformance/README.md ("Component fixtures"): starts at 0; `advance(ms)`
/// fires every timer due up to the new time, earliest first (equal due times: the order they
/// were set), with the clock set to each timer's due time while it runs.
@MainActor
final class FakeGiftClock: GiftClock {
    private(set) var now = 0
    private var seq = 0
    private var timers: [FakeTimer] = []

    var nowMs: Int {
        now
    }

    func schedule(afterMs ms: Int, _ fire: @escaping () -> Void) -> Int {
        seq += 1
        timers.append(FakeTimer(id: seq, due: now + max(0, ms), fire: fire))
        return seq
    }

    func cancel(_ handle: Int) {
        timers.removeAll { $0.id == handle }
    }

    private func next(_ limit: Int) -> FakeTimer? {
        var best: FakeTimer?
        for t in timers where t.due <= limit {
            if let b = best {
                if t.due < b.due || (t.due == b.due && t.id < b.id) {
                    best = t
                }
            } else {
                best = t
            }
        }
        return best
    }

    /// Fires the timers due now.
    func runDue() {
        while let t = next(now) {
            cancel(t.id)
            t.fire()
        }
    }

    func advance(_ ms: Int) {
        let target = now + ms
        while let t = next(target) {
            now = t.due
            cancel(t.id)
            t.fire()
        }
        now = target
    }

    /// "After every step the runner lets pending asynchronous work run, then fires the timers
    /// due at the current time, and repeats this until nothing changes." Everything runs on the
    /// main actor; the short sleeps also let any executor hop come back.
    func settle() async {
        for _ in 0..<4 {
            for _ in 0..<25 {
                await Task.yield()
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
            runDue()
        }
    }
}

/// The SDK error built from a fixture's `{ status, type, message, requestId? }`.
func fixtureError(_ e: JSONValue, _ at: String) throws -> GiftingError {
    GiftingError(
        status: try XCTUnwrap(e["status"]?.intValue, "\(at): error status"),
        type: try XCTUnwrap(e["type"]?.stringValue, "\(at): error type"),
        message: try XCTUnwrap(e["message"]?.stringValue, "\(at): error message"),
        requestId: e["requestId"]?.stringValue
    )
}

/// A string, or JSON null for nil.
func optionalString(_ value: String?) -> JSONValue {
    guard let value = value else {
        return .null
    }
    return .string(value)
}

/// A number, or JSON null for nil.
func optionalNumber(_ value: Int?) -> JSONValue {
    guard let value = value else {
        return .null
    }
    return .number(Double(value))
}

/// Fails for every key of `object` that is not in `known` (the runner would silently skip it).
func assertKnownKeys(_ object: JSONValue?, _ known: Set<String>, _ what: String) {
    for key in (object?.objectValue ?? [:]).keys where !known.contains(key) {
        XCTFail("\(what): the runner does not know key \(key)")
    }
}

/// A client whose every call waits until a step settles it (oldest call of a method first),
/// recording each call as `{ method, args }`.
@MainActor
final class ScriptedComponentClient: GiftAwayAPI, GiftLeaderboardAPI {
    enum Waiter {
        case away(CheckedContinuation<AwaySummary, Error>)
        case ack(CheckedContinuation<Void, Error>)
        case board(CheckedContinuation<Leaderboard, Error>)
    }

    struct PendingCall {
        let method: String
        let waiter: Waiter
    }

    private(set) var pending: [PendingCall] = []
    private(set) var calls: [JSONValue] = []

    func getAway(_ query: AwayQuery) async throws -> AwaySummary {
        var args: [String: JSONValue] = [:]
        if let since = query.since {
            args["since"] = .string(since)
        }
        if let maxGroups = query.maxGroups {
            args["maxGroups"] = .number(Double(maxGroups))
        }
        calls.append(.object(["method": .string("getAway"), "args": .object(args)]))
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<AwaySummary, Error>) in
            pending.append(PendingCall(method: "getAway", waiter: .away(c)))
        }
    }

    func ackAway(_ cursor: String) async throws {
        calls.append(.object(["method": .string("ackAway"), "args": .object(["cursor": .string(cursor)])]))
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            pending.append(PendingCall(method: "ackAway", waiter: .ack(c)))
        }
    }

    func getLeaderboard(_ board: LeaderboardBoard, query: LeaderboardQuery) async throws -> Leaderboard {
        var q: [String: JSONValue] = [:]
        if let period = query.period {
            q["period"] = .string(period.rawValue)
        }
        if let metric = query.metric {
            q["metric"] = .string(metric.rawValue)
        }
        if let at = query.at {
            q["at"] = .string(at)
        }
        if let limit = query.limit {
            q["limit"] = .number(Double(limit))
        }
        if let includeMe = query.includeMe {
            q["includeMe"] = .bool(includeMe)
        }
        let args: JSONValue = .object(["board": .string(board.rawValue), "query": .object(q)])
        calls.append(.object(["method": .string("getLeaderboard"), "args": args]))
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Leaderboard, Error>) in
            pending.append(PendingCall(method: "getLeaderboard", waiter: .board(c)))
        }
    }

    func resolveAway(_ summary: AwaySummary, at: String) throws {
        let call = try take("getAway", at)
        if case .away(let c) = call.waiter {
            c.resume(returning: summary)
        }
    }

    func resolveAck(at: String) throws {
        let call = try take("ackAway", at)
        if case .ack(let c) = call.waiter {
            c.resume(returning: ())
        }
    }

    func resolveBoard(_ value: Leaderboard, at: String) throws {
        let call = try take("getLeaderboard", at)
        if case .board(let c) = call.waiter {
            c.resume(returning: value)
        }
    }

    /// Fails the OLDEST pending call of `method`.
    func reject(_ method: String, error: Error, at: String) throws {
        let call = try take(method, at)
        switch call.waiter {
        case .away(let c):
            c.resume(throwing: error)
        case .ack(let c):
            c.resume(throwing: error)
        case .board(let c):
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
