import Foundation
import XCTest
@testable import GiftingStack

/// The six rooms-*.json fixtures (SPEC sections 17-18), ported from
/// packages/sdk-js/test/rooms-conformance.test.ts. Contract: conformance/README.md ("Rooms
/// fixtures").
@MainActor
final class RoomsConformanceTests: XCTestCase {
    // MARK: - rooms-protocol.json

    func testProtocol() throws {
        let f = try Fixtures.conformance("rooms-protocol.json")
        assertKnownKeys(f, ["description", "parse", "hello", "url", "tokenUser"], "[rooms-protocol.json]")
        for c in try Fixtures.list(f["parse"], "rooms-protocol.json parse") {
            let at = "[rooms-protocol.json parse] \(c["name"]?.stringValue ?? "?")"
            assertKnownKeys(c, ["name", "frame", "text", "expect"], at)
            let text = try roomFrameText(c, at)
            let expected = try XCTUnwrap(c["expect"], at)
            assertJSONEqual(roomMessageJSON(parseRoomFrame(text)), expected, at)
        }
        for c in try Fixtures.list(f["hello"], "rooms-protocol.json hello") {
            let at = "[rooms-protocol.json hello] \(c)"
            let frame = roomHelloFrame(c["last"]?.intValue)
            let parsed = try JSONValue.parse(Data(frame.utf8))
            let expected = try XCTUnwrap(c["expect"], at)
            assertJSONEqual(parsed, expected, at)
        }
        for c in try Fixtures.list(f["url"], "rooms-protocol.json url") {
            let at = "[rooms-protocol.json url] \(c)"
            let room = try XCTUnwrap(c["room"]?.stringValue, at)
            let url = roomUrl(room, baseUrl: c["baseUrl"]?.stringValue ?? defaultRoomsUrl)
            XCTAssertEqual(url, c["expect"]?.stringValue, at)
        }
        for c in try Fixtures.list(f["tokenUser"], "rooms-protocol.json tokenUser") {
            let token = try XCTUnwrap(c["token"]?.stringValue, "tokenUser")
            assertJSONEqual(optionalString(roomTokenUser(token)), c["expect"] ?? .null, "[rooms-protocol.json tokenUser] \(token)")
        }
    }

    // MARK: - rooms-battle.json

    func testBattle() throws {
        let f = try Fixtures.conformance("rooms-battle.json")
        assertKnownKeys(f, ["description", "parse", "view"], "[rooms-battle.json]")
        let parseCases = try Fixtures.list(f["parse"], "rooms-battle.json parse")
        XCTAssertGreaterThan(parseCases.count, 6)
        for c in parseCases {
            let at = "[rooms-battle.json parse] \(c["name"]?.stringValue ?? "?")"
            assertKnownKeys(c, ["name", "frame", "text", "expect"], at)
            let text = try roomFrameText(c, at)
            let expected = try XCTUnwrap(c["expect"], at)
            assertJSONEqual(roomMessageJSON(parseRoomFrame(text)), expected, at)
        }
        let viewCases = try Fixtures.list(f["view"], "rooms-battle.json view")
        XCTAssertGreaterThan(viewCases.count, 4)
        for c in viewCases {
            let at = "[rooms-battle.json view] \(c["name"]?.stringValue ?? "?")"
            assertKnownKeys(c, ["name", "battle", "serverNow", "expect"], at)
            let frame = JSONValue.object(["t": .string("scores"), "battle": try XCTUnwrap(c["battle"], at)])
            guard case .scores(let parsed?)? = parseRoomFrame(try roomJSONText(frame)) else {
                throw FixtureError(description: "\(at): battle does not parse")
            }
            let view = battleView(parsed, serverNow: c["serverNow"]?.intValue)
            assertJSONEqual(battleViewJSON(view), try XCTUnwrap(c["expect"], at), at)
        }
    }

    // MARK: - rooms-reconnect.json

    func testReconnect() throws {
        let f = try Fixtures.conformance("rooms-reconnect.json")
        for c in try Fixtures.list(f["cases"], "rooms-reconnect.json cases") {
            let at = "[rooms-reconnect.json] \(c["name"]?.stringValue ?? "?")"
            assertKnownKeys(c, ["name", "code", "reason", "attempt", "limited", "random", "expect"], at)
            let given = c["random"]?.doubleValue
            let code = try XCTUnwrap(c["code"]?.intValue, at)
            let attempt = try XCTUnwrap(c["attempt"]?.intValue, at)
            let limited = try XCTUnwrap(c["limited"]?.intValue, at)
            let expected = try XCTUnwrap(c["expect"], at)
            var calls = 0
            let decision = roomRetryDecision(
                code: code,
                reason: c["reason"]?.stringValue ?? "",
                attempt: attempt,
                limited: limited,
                random: {
                    calls += 1
                    if given == nil {
                        XCTFail("\(at): random() called but the case gives none")
                    }
                    return given ?? 0.5
                }
            )
            assertJSONEqual(roomDecisionJSON(decision), expected, at)
            XCTAssertLessThanOrEqual(calls, 1, "\(at): random() called more than once")
        }
    }

    // MARK: - rooms-filter.json

    func testFilter() throws {
        let f = try Fixtures.conformance("rooms-filter.json")
        assertKnownKeys(f, ["description", "events", "scenarios"], "[rooms-filter.json]")
        let named = try XCTUnwrap(f["events"]?.objectValue, "rooms-filter.json events")
        func ev(_ name: JSONValue, _ at: String) throws -> RoomGiftMessage {
            let key = try XCTUnwrap(name.stringValue, "\(at): event name")
            let raw = try XCTUnwrap(named[key], "\(at): no event \(key)")
            let text = try roomJSONText(raw)
            guard case .gift(let gift)? = parseRoomFrame(text) else {
                throw FixtureError(description: "\(at): event \(key) does not parse as a gift")
            }
            return gift
        }
        for s in try Fixtures.list(f["scenarios"], "rooms-filter.json scenarios") {
            let name = s["name"]?.stringValue ?? "?"
            assertKnownKeys(s, ["name", "description", "options", "steps"], "[rooms-filter.json] \(name)")
            let options = try roomFilterOptions(s["options"], "[rooms-filter.json] \(name)")
            let filter = RoomEventFilter(options: options)
            var fills = 0
            var serverOffset = 0
            for (i, step) in try Fixtures.list(s["steps"], "\(name) steps").enumerated() {
                let at = "[rooms-filter.json] \(name): step \(i + 1)"
                assertKnownKeys(step, ["name", "welcome", "live", "batch", "fill", "at", "expect"], at)
                let local = try XCTUnwrap(step["at"]?.intValue, "\(at): at")
                let result: RoomFilterResult
                if let w = step["welcome"] {
                    let now = try XCTUnwrap(w["now"]?.intValue, "\(at): welcome.now")
                    serverOffset = now - local
                    let replay = try (w["replay"]?.arrayValue ?? []).map { try ev($0, at) }
                    let message = RoomWelcomeMessage(
                        viewers: w["viewers"]?.intValue ?? 0,
                        gap: w["gap"]?.boolValue ?? false,
                        replay: replay,
                        ttl: w["ttl"]?.doubleValue ?? 0,
                        now: now
                    )
                    result = filter.welcome(message, localNow: local)
                } else if let live = step["live"]?.arrayValue {
                    let gifts = try live.map { try ev($0, at) }
                    result = filter.live(gifts, localNow: local)
                } else if let batch = step["batch"]?.arrayValue {
                    // A wire `batch` frame: parsed, then its gifts go through `live` in order.
                    var gifts: [JSONValue] = []
                    for n in batch {
                        let key = try XCTUnwrap(n.stringValue, "\(at): batch name")
                        let raw = try XCTUnwrap(named[key], "\(at): no event \(key)")
                        gifts.append(raw)
                    }
                    let frame = JSONValue.object(["t": .string("batch"), "events": .array(gifts)])
                    let text = try roomJSONText(frame)
                    guard case .batch(let events)? = parseRoomFrame(text) else {
                        throw FixtureError(description: "\(at): batch frame does not parse as a batch")
                    }
                    result = filter.live(events, localNow: local)
                } else if let n = step["fill"]?.intValue {
                    var list: [RoomGiftMessage] = []
                    for _ in 0..<n {
                        fills += 1
                        list.append(
                            RoomGiftMessage(
                                id: 1000 + fills,
                                at: local + serverOffset,
                                tx: "gtx_fill_\(fills)",
                                gift: RoomGiftMessage.GiftInfo(id: "rose", name: "Rose", price: 10, iconUrl: nil),
                                quantity: 1,
                                sender: RoomGiftMessage.Sender(id: "filler"),
                                receiver: RoomGiftMessage.Receiver(id: "host")
                            )
                        )
                    }
                    result = filter.live(list, localNow: local)
                } else {
                    throw FixtureError(description: "\(at): unknown step")
                }
                let x = step["expect"]
                assertKnownKeys(x, ["passed", "last", "gap"], "\(at) expect")
                if let passed = x?["passed"] {
                    assertJSONEqual(.array(result.events.map { .string($0.tx) }), passed, "\(at) passed")
                }
                if let last = x?["last"] {
                    assertJSONEqual(optionalNumber(filter.last), last, "\(at) last")
                }
                if let gap = x?["gap"] {
                    assertJSONEqual(.bool(result.gap), gap, "\(at) gap")
                }
            }
        }
    }

    // MARK: - rooms-mapping.json

    func testMapping() throws {
        let f = try Fixtures.conformance("rooms-mapping.json")
        assertKnownKeys(f, ["description", "catalog", "cases"], "[rooms-mapping.json]")
        let catalog = try XCTUnwrap(f["catalog"], "rooms-mapping.json catalog").decode([Gift].self)
        for c in try Fixtures.list(f["cases"], "rooms-mapping.json cases") {
            let at = "[rooms-mapping.json] \(c["name"]?.stringValue ?? "?")"
            assertKnownKeys(c, ["name", "event", "catalog", "names", "replayed", "expect"], at)
            let event = try XCTUnwrap(c["event"], at)
            let text = try roomJSONText(event)
            let expected = try XCTUnwrap(c["expect"], at)
            guard case .gift(let msg)? = parseRoomFrame(text) else {
                XCTFail("\(at): event does not parse as a gift")
                continue
            }
            var resolve: ((String) -> String?)?
            if let names = c["names"]?.objectValue {
                resolve = { id in names[id]?.stringValue }
            }
            let out = roomGiftToEffect(
                msg,
                catalog: c["catalog"]?.boolValue == true ? catalog : nil,
                resolveName: resolve,
                replayed: c["replayed"]?.boolValue ?? false
            )
            assertJSONEqual(roomEventJSON(out), expected, at)
        }
    }

    // MARK: - rooms-session.json

    func testSession() async throws {
        let f = try Fixtures.conformance("rooms-session.json")
        assertKnownKeys(f, ["description", "scenarios"], "[rooms-session.json]")
        for s in try Fixtures.list(f["scenarios"], "rooms-session.json scenarios") {
            try await runSessionScenario(s)
        }
    }

    private func runSessionScenario(_ s: JSONValue) async throws {
        let name = s["name"]?.stringValue ?? "?"
        let where_ = "[rooms-session.json] \(name)"
        assertKnownKeys(s, ["name", "description", "options", "steps", "random"], where_)
        let o = s["options"]
        assertKnownKeys(o, ["room", "user", "skipOwn", "heartbeatMs", "refreshJitterMs", "maxReplayAgeMs", "minTier", "url"], "\(where_) options")
        let clock = FakeGiftClock()
        let script = RoomSessionScript()
        let log = RoomSessionLog()
        let random = RoomRandomScript(s["random"]?.arrayValue?.compactMap { $0.doubleValue }, where_)
        var minTier = EffectTier.small
        if let raw = o?["minTier"]?.stringValue {
            minTier = try XCTUnwrap(EffectTier(rawValue: raw), "\(where_): minTier \(raw)")
        }
        let roomId = try XCTUnwrap(o?["room"]?.stringValue, "\(where_): options.room")
        let room = RoomClient(
            room: roomId,
            getToken: { force in
                try await script.token(force)
            },
            socket: { url, protocols, handlers in
                script.open(url, protocols, handlers)
            },
            url: o?["url"]?.stringValue,
            user: o?["user"]?.stringValue,
            skipOwn: o?["skipOwn"]?.boolValue ?? true,
            maxReplayAgeMs: o?["maxReplayAgeMs"]?.intValue ?? defaultRoomMaxReplayAgeMs,
            minTier: minTier,
            onEvent: { event in
                log.events.append(event)
            },
            onViewers: { n in
                log.viewers.append(n)
            },
            onGap: {
                log.gaps += 1
            },
            heartbeatMs: o?["heartbeatMs"]?.intValue ?? roomHeartbeatMs,
            refreshJitterMs: o?["refreshJitterMs"]?.intValue ?? 0,
            clock: clock,
            random: {
                random.next()
            }
        )

        for (i, step) in try Fixtures.list(s["steps"], "\(name) steps").enumerated() {
            let at = "\(where_): step \(i + 1)"
            assertKnownKeys(
                step,
                ["name", "start", "leave", "pause", "resume", "reconnectNow", "advance", "token", "tokenFail", "open", "receive", "close", "expect"],
                at
            )
            if step["start"]?.boolValue == true {
                room.start()
            } else if step["leave"]?.boolValue == true {
                room.leave()
            } else if step["pause"]?.boolValue == true {
                room.pause()
            } else if step["resume"]?.boolValue == true {
                room.resume()
            } else if step["reconnectNow"]?.boolValue == true {
                room.reconnectNow()
            } else if let ms = step["advance"]?.intValue {
                clock.advance(ms)
            } else if let token = step["token"]?.stringValue {
                try script.resolveToken(token, at)
            } else if step["tokenFail"]?.boolValue == true {
                try script.failToken(at)
            } else if step["open"]?.boolValue == true {
                try script.newest(at).handlers.onOpen()
            } else if let receive = step["receive"] {
                let text = try receive.stringValue ?? roomJSONText(receive)
                try script.newest(at).handlers.onMessage(text)
            } else if let close = step["close"] {
                let code = try XCTUnwrap(close["code"]?.intValue, "\(at): close.code")
                try script.newest(at).handlers.onClose(code, close["reason"]?.stringValue ?? "")
            } else if step["expect"] == nil {
                throw FixtureError(description: "\(at): unknown step \(step)")
            }
            await clock.settle()

            guard let x = step["expect"] else {
                continue
            }
            assertKnownKeys(x, ["state", "tokens", "sockets", "events", "viewers", "gaps"], "\(at) expect")
            if let want = x["state"]?.objectValue {
                let got = roomStateJSON(room.state)
                for (key, value) in want {
                    assertJSONEqual(got[key] ?? .null, value, "\(at) state.\(key)")
                }
            }
            if let want = x["tokens"] {
                assertJSONEqual(.array(script.tokens.map { .bool($0) }), want, "\(at) tokens")
            }
            if let want = x["sockets"]?.arrayValue {
                XCTAssertEqual(script.sockets.count, want.count, "\(at) socket count")
                for (k, expected) in want.enumerated() where k < script.sockets.count {
                    let sock = script.sockets[k]
                    let got: [String: JSONValue] = [
                        "url": .string(sock.url),
                        "protocols": .array(sock.protocols.map { .string($0) }),
                        "sent": .array(sock.sent),
                        "closed": sock.closed,
                    ]
                    for (key, value) in expected.objectValue ?? [:] {
                        assertJSONEqual(got[key] ?? .null, value, "\(at) sockets[\(k)].\(key)")
                    }
                }
            }
            if let want = x["events"]?.arrayValue {
                var got: [JSONValue] = []
                for (k, e) in log.events.enumerated() {
                    var item: [String: JSONValue] = [
                        "tx": .string(e.tx),
                        "sender": optionalString(e.sender),
                        "replayed": .bool(e.replayed),
                    ]
                    // `quantity` is compared only where the fixture lists it.
                    if k < want.count, want[k]["quantity"] != nil {
                        item["quantity"] = .number(Double(e.quantity))
                    }
                    got.append(.object(item))
                }
                assertJSONEqual(.array(got), .array(want), "\(at) events")
            }
            if let want = x["viewers"] {
                assertJSONEqual(.array(log.viewers.map { .number(Double($0)) }), want, "\(at) viewers")
            }
            if let want = x["gaps"]?.intValue {
                XCTAssertEqual(log.gaps, want, "\(at) gaps")
            }
        }
    }
}

// MARK: - Session doubles

/// A socket that records what the client did with it.
@MainActor
final class FakeRoomSocket: RoomSocket {
    let url: String
    let protocols: [String]
    let handlers: RoomSocketHandlers
    /// Each frame parsed as JSON, or the text when it is not JSON (`"ping"`).
    private(set) var sent: [JSONValue] = []
    /// `{ code, reason }` of the client's own close, else null.
    private(set) var closed: JSONValue = .null

    init(url: String, protocols: [String], handlers: RoomSocketHandlers) {
        self.url = url
        self.protocols = protocols
        self.handlers = handlers
    }

    func send(_ text: String) {
        if let value = try? JSONValue.parse(Data(text.utf8)) {
            sent.append(value)
        } else {
            sent.append(.string(text))
        }
    }

    func close(code: Int, reason: String) {
        closed = .object(["code": .number(Double(code)), "reason": .string(reason)])
    }
}

/// A scripted `getToken` (every call recorded and left pending) and socket factory.
@MainActor
final class RoomSessionScript {
    private(set) var tokens: [Bool] = []
    private var pending: [CheckedContinuation<String, Error>] = []
    private(set) var sockets: [FakeRoomSocket] = []

    func token(_ forceRefresh: Bool) async throws -> String {
        tokens.append(forceRefresh)
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            pending.append(c)
        }
    }

    func open(_ url: String, _ protocols: [String], _ handlers: RoomSocketHandlers) -> FakeRoomSocket {
        let socket = FakeRoomSocket(url: url, protocols: protocols, handlers: handlers)
        sockets.append(socket)
        return socket
    }

    /// Resolves the OLDEST pending `getToken`.
    func resolveToken(_ token: String, _ at: String) throws {
        guard !pending.isEmpty else {
            throw FixtureError(description: "\(at): no pending getToken")
        }
        pending.removeFirst().resume(returning: token)
    }

    /// Fails the OLDEST pending `getToken`.
    func failToken(_ at: String) throws {
        guard !pending.isEmpty else {
            throw FixtureError(description: "\(at): no pending getToken")
        }
        pending.removeFirst().resume(throwing: FixtureError(description: "token server down"))
    }

    func newest(_ at: String) throws -> FakeRoomSocket {
        guard let socket = sockets.last else {
            throw FixtureError(description: "\(at): no socket")
        }
        return socket
    }
}

@MainActor
final class RoomSessionLog {
    var events: [RoomGiftEvent] = []
    var viewers: [Int] = []
    var gaps = 0
}

/// The `random` list consumed in order (a call beyond it fails); no list: always 0.5.
final class RoomRandomScript {
    private let values: [Double]?
    private let context: String
    private var index = 0

    init(_ values: [Double]?, _ context: String) {
        self.values = values
        self.context = context
    }

    func next() -> Double {
        guard let values = values else {
            return 0.5
        }
        guard index < values.count else {
            XCTFail("\(context): random() call \(index + 1) beyond the list")
            return 0.5
        }
        let value = values[index]
        index += 1
        return value
    }
}

// MARK: - JSON helpers

/// A fixture frame: `text` as written, else the JSON text of `frame`.
func roomFrameText(_ c: JSONValue, _ at: String) throws -> String {
    if let text = c["text"]?.stringValue {
        return text
    }
    let frame = try XCTUnwrap(c["frame"], "\(at): frame")
    return try roomJSONText(frame)
}

/// The JSON text of a fixture value.
func roomJSONText(_ value: JSONValue) throws -> String {
    String(decoding: try value.data(), as: UTF8.self)
}

/// A parsed gift in the wire names of SPEC 17.4 (`receiver: null` when missing).
func roomGiftJSON(_ g: RoomGiftMessage) -> JSONValue {
    var sender: [String: JSONValue] = ["id": .string(g.sender.id)]
    if let name = g.sender.name {
        sender["name"] = .string(name)
    }
    var receiver = JSONValue.null
    if let r = g.receiver {
        receiver = .object(["id": .string(r.id)])
    }
    return .object([
        "t": .string("gift"),
        "id": .number(Double(g.id)),
        "at": .number(Double(g.at)),
        "tx": .string(g.tx),
        "gift": .object([
            "id": .string(g.gift.id),
            "name": .string(g.gift.name),
            "price": .number(Double(g.gift.price)),
            "icon_url": optionalString(g.gift.iconUrl),
        ]),
        "quantity": .number(Double(g.quantity)),
        "sender": .object(sender),
        "receiver": receiver,
    ])
}

/// A battle round in the wire names of SPEC 17.8.
func roomBattleJSON(_ b: RoomBattle) -> JSONValue {
    .object([
        "round": .string(b.round),
        "started": .number(Double(b.started)),
        "ends": .number(Double(b.ends)),
        "scores": .array(
            b.scores.map {
                .object(["id": .string($0.id), "units": .number(Double($0.units)), "gifts": .number(Double($0.gifts))])
            }
        ),
    ])
}

/// A battle view in the fixture's shape.
func battleViewJSON(_ v: BattleView) -> JSONValue {
    .object([
        "round": .string(v.round),
        "open": .bool(v.open),
        "remainingMs": .number(Double(v.remainingMs)),
        "total": .number(Double(v.total)),
        "sides": .array(
            v.sides.map {
                .object([
                    "id": .string($0.id),
                    "units": .number(Double($0.units)),
                    "gifts": .number(Double($0.gifts)),
                    "share": .number($0.share),
                ])
            }
        ),
        "leader": optionalString(v.leader),
    ])
}

/// A parsed message in the wire names, or null for an ignored frame.
func roomMessageJSON(_ message: RoomServerMessage?) -> JSONValue {
    guard let message = message else {
        return .null
    }
    switch message {
    case .gift(let g):
        return roomGiftJSON(g)
    case .welcome(let w):
        var out: [String: JSONValue] = [
            "t": .string("welcome"),
            "viewers": .number(Double(w.viewers)),
            "gap": .bool(w.gap),
            "replay": .array(w.replay.map { roomGiftJSON($0) }),
            "ttl": .number(w.ttl),
            "now": .number(Double(w.now)),
        ]
        if let battle = w.battle {
            out["battle"] = roomBattleJSON(battle)
        }
        return .object(out)
    case .scores(let battle):
        return .object(["t": .string("scores"), "battle": battle.map { roomBattleJSON($0) } ?? .null])
    case .viewers(let n):
        return .object(["t": .string("viewers"), "n": .number(Double(n))])
    case .batch(let events):
        return .object(["t": .string("batch"), "events": .array(events.map { roomGiftJSON($0) })])
    case .pong:
        return .object(["t": .string("pong")])
    }
}

func roomDecisionJSON(_ d: RoomRetryDecision) -> JSONValue {
    switch d {
    case .stop(let resumable, let exhausted):
        var out: [String: JSONValue] = ["retry": .bool(false)]
        if resumable {
            out["resumable"] = .bool(true)
        }
        if exhausted {
            out["exhausted"] = .bool(true)
        }
        return .object(out)
    case .retry(let delayMs, let refreshToken, let limited):
        return .object([
            "retry": .bool(true),
            "delayMs": .number(Double(delayMs)),
            "refreshToken": .bool(refreshToken),
            "limited": .bool(limited),
        ])
    }
}

/// A mapped event; `sender` only when present (a missing key means absent).
func roomEventJSON(_ e: RoomGiftEvent) -> JSONValue {
    var out: [String: JSONValue] = [
        "gift": .object([
            "id": .string(e.gift.id),
            "name": .string(e.gift.name),
            "price": .number(Double(e.gift.price)),
            "image": optionalString(e.gift.image),
            "icon": optionalString(e.gift.icon),
        ]),
        "quantity": .number(Double(e.quantity)),
        "id": .number(Double(e.id)),
        "tx": .string(e.tx),
        "at": .number(Double(e.at)),
        "senderId": .string(e.senderId),
        "senderName": optionalString(e.senderName),
        "receiverId": optionalString(e.receiverId),
        "replayed": .bool(e.replayed),
    ]
    if let sender = e.sender {
        out["sender"] = .string(sender)
    }
    return .object(out)
}

func roomStateJSON(_ s: RoomState) -> [String: JSONValue] {
    [
        "status": .string(s.status.rawValue),
        "attempt": .number(Double(s.attempt)),
        "retryInMs": optionalNumber(s.retryInMs),
        "code": optionalNumber(s.code),
        "reason": optionalString(s.reason),
        "viewers": optionalNumber(s.viewers),
    ]
}

/// `RoomEventFilterOptions` from `{ user, skipOwn, maxReplayAgeMs, minTier, thresholds }`.
func roomFilterOptions(_ o: JSONValue?, _ at: String) throws -> RoomEventFilterOptions {
    assertKnownKeys(o, ["user", "skipOwn", "maxReplayAgeMs", "minTier", "thresholds"], "\(at) options")
    assertKnownKeys(o?["thresholds"], ["mediumFrom", "largeFrom"], "\(at) thresholds")
    var options = RoomEventFilterOptions()
    options.user = o?["user"]?.stringValue
    if let skip = o?["skipOwn"]?.boolValue {
        options.skipOwn = skip
    }
    if let ms = o?["maxReplayAgeMs"]?.intValue {
        options.maxReplayAgeMs = ms
    }
    if let raw = o?["minTier"]?.stringValue {
        options.minTier = try XCTUnwrap(EffectTier(rawValue: raw), "\(at): minTier \(raw)")
    }
    if let t = o?["thresholds"] {
        options.thresholds = TierThresholds(
            mediumFrom: t["mediumFrom"]?.intValue ?? GiftingSpec.defaultMediumFrom,
            largeFrom: t["largeFrom"]?.intValue ?? GiftingSpec.defaultLargeFrom
        )
    }
    return options
}
