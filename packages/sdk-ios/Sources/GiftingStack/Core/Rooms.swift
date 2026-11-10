import Foundation

// Gift rooms, client side (SPEC section 17 is the wire protocol, section 18 the client rules,
// docs/design/gift-rooms.md the design). Ported line by line from
// packages/sdk-js/src/core/rooms.ts. Everything here is pure: the socket, the clock, the timers,
// the random source and the token are injected, so the fixtures `rooms-*.json` can drive it. The
// platform parts are `URLSessionRoomSocket` (transport) and `GiftRoomModel` (SwiftUI, app
// lifecycle).
//
// Pieces: `parseRoomFrame`/`roomHelloFrame` (protocol), `roomRetryDecision` (reconnect policy),
// `RoomEventFilter` (resume point, dedup, staleness, own gifts, tier filter), `roomGiftToEffect`
// (event -> `RoomGiftEvent`, whose `effectEvent` the effect layer plays) and `RoomClient` (the
// session state machine).

/// The only subprotocol; the client token rides as the second entry.
public let roomSubprotocol = "gs.v1"
public let defaultRoomsUrl = "wss://rt.giftingstack.com"
/// Events older than this (server clock) are dropped instead of played.
public let defaultRoomMaxReplayAgeMs = 10_000
/// Recent `tx` ids remembered for dedup.
public let roomDedupSize = 256
/// Full jitter: `random(0, min(30 s, 0.5 s x 2^attempt))`.
public let roomBackoffBaseMs = 500
public let roomBackoffMaxMs = 30_000
/// First retry after a drop (1006) or a server restart (1012): `random(0, 5 s)`.
public let roomFirstDropMaxMs = 5_000
/// A jittered wait is never shorter than this, so a draw of 0 cannot start a tight loop.
public let roomRetryFloorMs = 500
/// Reconnect attempts in a row (no socket that stayed open `roomStableMs` in between) before the
/// client gives up: the state becomes `closed` with the reason `roomReasonExhausted` and
/// `reconnectNow()` starts again with a fresh budget. About 3.5 minutes at the longest.
public let roomMaxAttempts = 12
/// `closed` reason after `roomMaxAttempts` failed attempts in a row.
public let roomReasonExhausted = "retries_exhausted"
/// `getToken` has this long, from the start of a connection, to answer (SPEC 18.5 step 1).
public let roomTokenMs = 20_000
/// A 4008 with `retry_after` never gives up; its wait grows up to this cap.
public let roomLimitedMaxMs = 300_000
/// Spread of the proactive token refresh (SPEC 18.5); `GiftRoomModel` sets it.
public let roomRefreshJitterMs = 120_000
/// Rate limited (4008) or room full (4009): wait at least this, at most 5 times in a row.
public let roomLimitedMinMs = 30_000
public let roomLimitedMaxRetries = 5
/// The attempt counters reset after a socket stayed open this long.
public let roomStableMs = 60_000
/// App heartbeat (`ping` text) after this long without any frame. `GiftRoomModel` turns it off:
/// `URLSessionRoomSocket` sends protocol pings instead.
public let roomHeartbeatMs = 45_000
/// No frame within this after `ping`, or no `welcome` this long after opening: the socket is dead.
public let roomDeadMs = 10_000
/// A socket never lives longer than this (design D8); the server closes it with 4001 anyway.
public let roomMaxLifetimeMs = 3_600_000
/// Reconnect with a fresh token this long before the server would close the socket.
public let roomRefreshAheadMs = 30_000

/// Close codes (SPEC 17.6).
public enum RoomCloseCode {
    public static let tokenExpired = 4001
    public static let forbidden = 4003
    public static let badRoomId = 4004
    public static let rateLimited = 4008
    public static let roomFull = 4009
    public static let plan = 4010
    public static let suspended = 4011
    public static let protocolError = 4400
}

/// The room id rule of SPEC 17.1: `^[A-Za-z0-9_.:-]{1,64}$`.
public func isValidRoomId(_ room: String) -> Bool {
    let bytes = Array(room.utf8)
    if bytes.isEmpty || bytes.count > 64 {
        return false
    }
    for b in bytes {
        switch b {
        case 0x41...0x5A, 0x61...0x7A, 0x30...0x39: // A-Z a-z 0-9
            continue
        case 0x5F, 0x2E, 0x3A, 0x2D: // _ . : -
            continue
        default:
            return false
        }
    }
    return true
}

// MARK: - Protocol

/// A `gift` event as the server sends it, unknown fields dropped.
public struct RoomGiftMessage: Sendable, Equatable, Hashable {
    public struct GiftInfo: Sendable, Equatable, Hashable {
        public var id: String
        public var name: String
        /// Unit price at send time: drives the tier.
        public var price: Int
        /// The wire `icon_url`; may be nil.
        public var iconUrl: String?

        public init(id: String, name: String, price: Int, iconUrl: String?) {
            self.id = id
            self.name = name
            self.price = price
            self.iconUrl = iconUrl
        }
    }

    public struct Sender: Sendable, Equatable, Hashable {
        public var id: String
        /// The sender's token claim `n`; nil when absent or empty.
        public var name: String?

        public init(id: String, name: String? = nil) {
            self.id = id
            self.name = name
        }
    }

    public struct Receiver: Sendable, Equatable, Hashable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    /// Per-room event id: the resume point.
    public var id: Int
    /// Commit time, epoch ms (server clock).
    public var at: Int
    /// Gift transaction id: the dedup key.
    public var tx: String
    public var gift: GiftInfo
    public var quantity: Int
    public var sender: Sender
    public var receiver: Receiver?

    public init(id: Int, at: Int, tx: String, gift: GiftInfo, quantity: Int, sender: Sender, receiver: Receiver?) {
        self.id = id
        self.at = at
        self.tx = tx
        self.gift = gift
        self.quantity = quantity
        self.sender = sender
        self.receiver = receiver
    }
}

/// One receiver's running total in a battle round (SPEC 17.8). Display counters only.
public struct RoomScoreEntry: Sendable, Equatable, Hashable {
    /// Receiver external id.
    public var id: String
    /// Sum of unit price x quantity of the counted gifts.
    public var units: Int
    /// Number of counted gifts.
    public var gifts: Int

    public init(id: String, units: Int, gifts: Int) {
        self.id = id
        self.units = units
        self.gifts = gifts
    }
}

/// A battle round with its scores, in the server's fixed order (the round's receivers first).
public struct RoomBattle: Sendable, Equatable, Hashable {
    public var round: String
    /// Epoch ms (server clock).
    public var started: Int
    /// Epoch ms (server clock): gifts from then on no longer count.
    public var ends: Int
    public var scores: [RoomScoreEntry]

    public init(round: String, started: Int, ends: Int, scores: [RoomScoreEntry]) {
        self.round = round
        self.started = started
        self.ends = ends
        self.scores = scores
    }
}

public struct RoomWelcomeMessage: Sendable, Equatable, Hashable {
    public var viewers: Int
    public var gap: Bool
    public var replay: [RoomGiftMessage]
    /// Seconds until the server closes the socket with 4001.
    public var ttl: Double
    /// Server time, epoch ms.
    public var now: Int
    /// The room's battle round; nil when there is none (or it was malformed).
    public var battle: RoomBattle?

    public init(viewers: Int, gap: Bool, replay: [RoomGiftMessage], ttl: Double, now: Int, battle: RoomBattle? = nil) {
        self.viewers = viewers
        self.gap = gap
        self.replay = replay
        self.ttl = ttl
        self.now = now
        self.battle = battle
    }
}

/// One server frame.
public enum RoomServerMessage: Sendable, Equatable, Hashable {
    case welcome(RoomWelcomeMessage)
    case gift(RoomGiftMessage)
    case viewers(Int)
    case batch([RoomGiftMessage])
    /// Battle scores changed (SPEC 17.8): a new snapshot of the round, or nil when it was removed.
    case scores(RoomBattle?)
    case pong
}

/// Untyped JSON for frames, close reasons and token claims. Numbers are Doubles (the wire ids
/// stay below 2^53); a JSON number never decodes as a Bool.
enum RoomJSON: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([RoomJSON])
    case object([String: RoomJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([RoomJSON].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: RoomJSON].self))
        }
    }

    /// The parsed text, or nil when it is not JSON.
    static func parse(_ text: String) -> RoomJSON? {
        try? JSONDecoder().decode(RoomJSON.self, from: Data(text.utf8))
    }

    var objectValue: [String: RoomJSON]? {
        if case .object(let o) = self {
            return o
        }
        return nil
    }

    var arrayValue: [RoomJSON]? {
        if case .array(let a) = self {
            return a
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let s) = self {
            return s
        }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let b) = self {
            return b
        }
        return nil
    }

    var numberValue: Double? {
        if case .number(let n) = self {
            return n
        }
        return nil
    }

    var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }
}

private let roomMaxSafeInteger: Double = 9_007_199_254_740_991

/// `Number.isSafeInteger(v)`.
private func roomSafeInteger(_ value: RoomJSON?) -> Int? {
    guard let n = value?.numberValue, abs(n) <= roomMaxSafeInteger, n.rounded(.towardZero) == n else {
        return nil
    }
    return Int(n)
}

/// A safe integer >= 0.
private func roomCount(_ value: RoomJSON?) -> Int? {
    guard let n = roomSafeInteger(value), n >= 0 else {
        return nil
    }
    return n
}

private func parseRoomGift(_ value: RoomJSON) -> RoomGiftMessage? {
    guard let v = value.objectValue, v["t"]?.stringValue == "gift" else {
        return nil
    }
    guard
        let id = roomCount(v["id"]),
        let at = roomCount(v["at"]),
        let tx = v["tx"]?.stringValue,
        !tx.isEmpty,
        let gift = v["gift"]?.objectValue,
        let giftId = gift["id"]?.stringValue,
        let giftName = gift["name"]?.stringValue,
        let price = roomCount(gift["price"]),
        let quantity = roomSafeInteger(v["quantity"]),
        quantity >= 1,
        let sender = v["sender"]?.objectValue,
        let senderId = sender["id"]?.stringValue
    else {
        return nil
    }
    var senderName: String?
    if let name = sender["name"]?.stringValue, !name.isEmpty {
        senderName = name
    }
    var receiver: RoomGiftMessage.Receiver?
    if let r = v["receiver"]?.objectValue, let receiverId = r["id"]?.stringValue {
        receiver = RoomGiftMessage.Receiver(id: receiverId)
    }
    return RoomGiftMessage(
        id: id,
        at: at,
        tx: tx,
        gift: RoomGiftMessage.GiftInfo(id: giftId, name: giftName, price: price, iconUrl: gift["icon_url"]?.stringValue),
        quantity: quantity,
        sender: RoomGiftMessage.Sender(id: senderId, name: senderName),
        receiver: receiver
    )
}

/// A battle object, or nil when malformed. Invalid score entries are dropped alone.
private func parseRoomBattle(_ value: RoomJSON?) -> RoomBattle? {
    guard
        let o = value?.objectValue,
        let round = o["round"]?.stringValue,
        !round.isEmpty,
        let started = roomCount(o["started"]),
        let ends = roomCount(o["ends"]),
        let list = o["scores"]?.arrayValue
    else {
        return nil
    }
    var scores: [RoomScoreEntry] = []
    for e in list {
        if
            let m = e.objectValue,
            let id = m["id"]?.stringValue,
            let units = roomCount(m["units"]),
            let gifts = roomCount(m["gifts"])
        {
            scores.append(RoomScoreEntry(id: id, units: units, gifts: gifts))
        }
    }
    return RoomBattle(round: round, started: started, ends: ends, scores: scores)
}

/// The valid gifts of a list (an invalid entry is dropped alone), or nil when it is not a list.
private func roomGiftList(_ value: RoomJSON?) -> [RoomGiftMessage]? {
    guard let list = value?.arrayValue else {
        return nil
    }
    return list.compactMap { parseRoomGift($0) }
}

/// One server frame, or nil for anything to ignore: not JSON, an unknown `t`, a known `t` with a
/// missing or mistyped required field. Unknown fields are dropped; inside `replay` and `events`
/// an invalid gift is dropped alone. The literal text `pong` is `.pong`.
public func parseRoomFrame(_ data: String) -> RoomServerMessage? {
    if data == "pong" {
        return .pong
    }
    guard let v = RoomJSON.parse(data)?.objectValue else {
        return nil
    }
    switch v["t"]?.stringValue {
    case "gift"?:
        return parseRoomGift(.object(v)).map { RoomServerMessage.gift($0) }
    case "welcome"?:
        // A missing (or null) replay is an empty one.
        var replay: [RoomGiftMessage]? = []
        if let raw = v["replay"], !raw.isNull {
            replay = roomGiftList(raw)
        }
        guard
            let viewers = roomCount(v["viewers"]),
            let gap = v["gap"]?.boolValue,
            let gifts = replay,
            let ttl = v["ttl"]?.numberValue,
            ttl >= 0,
            let now = roomCount(v["now"])
        else {
            return nil
        }
        return .welcome(
            RoomWelcomeMessage(viewers: viewers, gap: gap, replay: gifts, ttl: ttl, now: now, battle: parseRoomBattle(v["battle"]))
        )
    case "scores"?:
        // Only an explicit null removes the round; a missing key is junk.
        guard let raw = v["battle"] else {
            return nil
        }
        if raw.isNull {
            return .scores(nil)
        }
        guard let battle = parseRoomBattle(raw) else {
            return nil
        }
        return .scores(battle)
    case "viewers"?:
        guard let n = roomCount(v["n"]) else {
            return nil
        }
        return .viewers(n)
    case "batch"?:
        guard let events = roomGiftList(v["events"]) else {
            return nil
        }
        return .batch(events)
    default:
        return nil
    }
}

/// One side of a battle bar.
public struct BattleSide: Sendable, Equatable, Hashable {
    public var id: String
    public var units: Int
    public var gifts: Int
    /// `units / total`, 0...1; an equal split while nobody has scored.
    public var share: Double

    public init(id: String, units: Int, gifts: Int, share: Double) {
        self.id = id
        self.units = units
        self.gifts = gifts
        self.share = share
    }
}

/// What a battle bar shows (SPEC 18.6).
public struct BattleView: Sendable, Equatable, Hashable {
    public var round: String
    /// The round still counts: `started <= serverNow < ends`.
    public var open: Bool
    /// `max(0, ends - serverNow)`, ms.
    public var remainingMs: Int
    /// Sum of every side's `units`.
    public var total: Int
    /// The server's order (the round's receivers first): keep it for a stable left/right bar.
    public var sides: [BattleSide]
    /// The receiver with the most units; nil while nobody has scored or the top is tied.
    public var leader: String?

    public init(round: String, open: Bool, remainingMs: Int, total: Int, sides: [BattleSide], leader: String?) {
        self.round = round
        self.open = open
        self.remainingMs = remainingMs
        self.total = total
        self.sides = sides
        self.leader = leader
    }
}

/// What a battle bar shows (SPEC 18.6), pure. `serverNow` is the server clock (`RoomClient` keeps
/// the offset from the last welcome); nil (no welcome yet) reads as the round's start.
public func battleView(_ battle: RoomBattle, serverNow: Int?) -> BattleView {
    computeBattleView(battle, serverNow)
}

/// The body of `battleView`; `RoomClient.battleView()` calls this (its own method name would
/// shadow the global function inside the class).
func computeBattleView(_ battle: RoomBattle, _ serverNow: Int?) -> BattleView {
    let now = serverNow ?? battle.started
    let total = battle.scores.reduce(0) { $0 + $1.units }
    let n = battle.scores.count
    let sides = battle.scores.map { e in
        BattleSide(id: e.id, units: e.units, gifts: e.gifts, share: total > 0 ? Double(e.units) / Double(total) : 1.0 / Double(n))
    }
    var leader: String?
    var best = 0
    var tied = false
    for e in battle.scores {
        if e.units > best {
            best = e.units
            leader = e.id
            tied = false
        } else if e.units == best && best > 0 {
            tied = true
        }
    }
    return BattleView(
        round: battle.round,
        open: now >= battle.started && now < battle.ends,
        remainingMs: max(0, battle.ends - now),
        total: total,
        sides: sides,
        leader: tied ? nil : leader
    )
}

/// The first frame after open: `{"t":"hello","v":1,"last":<id|null>}`, keys in this order.
public func roomHelloFrame(_ last: Int?) -> String {
    let lastText = last.map { String($0) } ?? "null"
    return "{\"t\":\"hello\",\"v\":1,\"last\":" + lastText + "}"
}

/// `wss://rt.giftingstack.com/v1/rooms/<room>` (trailing slashes of `baseUrl` removed, the room
/// id encoded like `encodeURIComponent`).
public func roomUrl(_ room: String, baseUrl: String = defaultRoomsUrl) -> String {
    var base = baseUrl
    while base.hasSuffix("/") {
        base.removeLast()
    }
    return base + "/v1/rooms/" + encodeURIComponent(room)
}

/// The value of a base64url digit, or nil.
private func roomBase64UrlValue(_ b: UInt8) -> Int? {
    switch b {
    case 0x41...0x5A: // A-Z
        return Int(b) - 0x41
    case 0x61...0x7A: // a-z
        return Int(b) - 0x61 + 26
    case 0x30...0x39: // 0-9
        return Int(b) - 0x30 + 52
    case 0x2D: // -
        return 62
    case 0x5F: // _
        return 63
    default:
        return nil
    }
}

/// The user a client token was minted for (claim `u`), or nil when the token is not a
/// GiftingStack client token (`gs_ct_<base64url(JSON)>.<sig>`). Used only to skip the user's
/// own gifts; the token is not verified here (the server does that).
public func roomTokenUser(_ token: String) -> String? {
    let prefix = "gs_ct_"
    guard token.hasPrefix(prefix) else {
        return nil
    }
    // `^gs_ct_([A-Za-z0-9_-]+)\.`: the base64url run right after the prefix, then a dot.
    var digits: [Int] = []
    var dot = false
    for b in token.utf8.dropFirst(prefix.utf8.count) {
        if b == 0x2E {
            dot = true
            break
        }
        guard let value = roomBase64UrlValue(b) else {
            return nil
        }
        digits.append(value)
    }
    guard dot, !digits.isEmpty else {
        return nil
    }
    var bits = 0
    var acc = 0
    var bytes: [UInt8] = []
    for value in digits {
        acc = ((acc << 6) | value) & 0xFFFF
        bits += 6
        if bits >= 8 {
            bits -= 8
            bytes.append(UInt8((acc >> bits) & 0xFF))
        }
    }
    // Invalid UTF-8 is not a token (the reference's decodeURIComponent throws).
    guard let text = String(bytes: bytes, encoding: .utf8) else {
        return nil
    }
    return RoomJSON.parse(text)?.objectValue?["u"]?.stringValue
}

// MARK: - Reconnect policy

/// What to do after a socket closed (SPEC 18.3).
public enum RoomRetryDecision: Sendable, Equatable, Hashable {
    /// Closed. `resumable`: the client stopped by its own rule, not because the server said it is
    /// final, so `reconnectNow()` may start again. `exhausted`: `roomMaxAttempts` failed attempts
    /// in a row. A final close is `.stop()`.
    case stop(resumable: Bool = false, exhausted: Bool = false)
    /// Reconnect after `delayMs`. `refreshToken`: ask `getToken` with `forceRefresh == true`
    /// first. `limited`: a rate-limit/room-full wait (counts against the 5 such waits).
    case retry(delayMs: Int, refreshToken: Bool, limited: Bool)
}

/// `roomRetryFloorMs + floor(random() * (cap - floor))`: a jittered wait is never below the floor.
private func roomJitter(_ cap: Double, _ random: () -> Double) -> Int {
    roomRetryFloorMs + Int((random() * max(0, cap - Double(roomRetryFloorMs))).rounded(.down))
}

/// `jitter(min(30,000, 500 x 2^attempt))`.
private func roomBackoff(_ attempt: Int, _ random: () -> Double) -> Int {
    let grown = Double(roomBackoffBaseMs) * pow(2.0, Double(max(0, attempt)))
    return roomJitter(min(Double(roomBackoffMaxMs), grown), random)
}

/// `retry_after` of a JSON close reason, in whole seconds; 0 when absent or not a count.
private func roomRetryAfterSeconds(_ reason: String) -> Int {
    roomCount(RoomJSON.parse(reason)?.objectValue?["retry_after"]) ?? 0
}

/// Wait after a 4008 that carried `retry_after` (seconds): `max(30 s, retry_after)` doubled per wait
/// already in a row (`limited`), plus up to 25 % jitter, never above 5 minutes. Calls `random` once.
public func roomRateLimitedDelayMs(retryAfterS: Int, limited: Int, random: () -> Double) -> Int {
    // Clamping first changes nothing (the result is capped anyway) and keeps the product small.
    let base = min(roomLimitedMaxMs, max(roomLimitedMinMs, min(retryAfterS, roomLimitedMaxMs) * 1000))
    let grown = min(roomLimitedMaxMs, base * (1 << min(max(0, limited), 16)))
    return min(roomLimitedMaxMs, grown + Int((random() * Double(grown / 4)).rounded(.down)))
}

/// What to do after a socket closed (SPEC 18.3). `attempt`: failed connections in a row before
/// this one (0 = the first since a stable socket); `limited`: 4008/4009 waits in a row before
/// this one. `random` returns [0, 1) and is called at most once, only for a jittered delay.
public func roomRetryDecision(
    code: Int,
    reason: String,
    attempt: Int,
    limited: Int,
    random: () -> Double
) -> RoomRetryDecision {
    switch code {
    case 4003, 4004, 4010, 4400: // forbidden, bad room id, plan, protocol error
        return .stop()
    case RoomCloseCode.suspended: // project suspended: the app decides
        return .stop(resumable: true)
    case 4008, 4009: // rate limited, room full
        if code == RoomCloseCode.roomFull && reason == "replaced" {
            return .stop()
        }
        let retryAfter = roomRetryAfterSeconds(reason)
        if code == RoomCloseCode.rateLimited && retryAfter > 0 {
            // A platform limit that lifts by itself: grows, never gives up (and is not counted
            // against the attempt ceiling).
            return .retry(
                delayMs: roomRateLimitedDelayMs(retryAfterS: retryAfter, limited: limited, random: random),
                refreshToken: false,
                limited: true
            )
        }
        if limited >= roomLimitedMaxRetries {
            return .stop(resumable: true)
        }
        return .retry(
            delayMs: max(roomLimitedMinMs, retryAfter * 1000),
            refreshToken: false,
            limited: true
        )
    default:
        break
    }
    if attempt >= roomMaxAttempts {
        return .stop(resumable: true, exhausted: true)
    }
    switch code {
    case 4001: // token expired
        return .retry(
            delayMs: attempt == 0 ? 0 : roomBackoff(attempt, random),
            refreshToken: true,
            limited: false
        )
    case 1006, 1012:
        return .retry(
            delayMs: attempt == 0 ? roomJitter(Double(roomFirstDropMaxMs), random) : roomBackoff(attempt, random),
            refreshToken: false,
            limited: false
        )
    default:
        return .retry(delayMs: roomBackoff(attempt, random), refreshToken: false, limited: false)
    }
}

// MARK: - Filter

private func roomTierRank(_ tier: EffectTier) -> Int {
    switch tier {
    case .small:
        return 0
    case .medium:
        return 1
    case .large:
        return 2
    }
}

public struct RoomEventFilterOptions: Sendable, Equatable {
    /// The signed-in user (token claim `u`): with `skipOwn`, their gifts are not played again.
    public var user: String?
    /// Default true: the sender's own tray already played the effect on tap.
    public var skipOwn: Bool
    /// Default 10,000. Events at least this old (server clock) are dropped.
    public var maxReplayAgeMs: Int
    /// Viewer-side filter: only gifts of this tier or bigger. Default `.small` (all).
    public var minTier: EffectTier
    public var thresholds: TierThresholds

    public init(
        user: String? = nil,
        skipOwn: Bool = true,
        maxReplayAgeMs: Int = defaultRoomMaxReplayAgeMs,
        minTier: EffectTier = .small,
        thresholds: TierThresholds = TierThresholds()
    ) {
        self.user = user
        self.skipOwn = skipOwn
        self.maxReplayAgeMs = maxReplayAgeMs
        self.minTier = minTier
        self.thresholds = thresholds
    }
}

public struct RoomFilterResult: Sendable, Equatable {
    /// The gifts to play, in order.
    public var events: [RoomGiftMessage]
    /// `welcome.gap`: events may have been missed. Always false for live frames.
    public var gap: Bool

    public init(events: [RoomGiftMessage], gap: Bool) {
        self.events = events
        self.gap = gap
    }
}

/// Decides which received gifts reach the app (SPEC 18.2). Keeps the resume point `last` (id of
/// the last gift received, played or not) and the last 256 `tx` across reconnects. Each gift, in
/// order: `last = id`; a `tx` seen before is dropped; then (the `tx` is remembered) a gift whose
/// age `serverNow - at` is at least `maxReplayAgeMs` is dropped, then the user's own gift
/// (`skipOwn`), then a gift below `minTier`. `serverNow` is `welcome.now` for the replay and
/// `welcome.now + (localNow - local time of the welcome)` for live gifts.
public final class RoomEventFilter {
    public var options: RoomEventFilterOptions
    /// Resume point sent in `hello`.
    public private(set) var last: Int?
    private var seen = Set<String>()
    private var order: [String] = []
    /// `welcome.now - local time of the welcome`; nil before the first welcome.
    private var offset: Int?

    public init(options: RoomEventFilterOptions = RoomEventFilterOptions()) {
        self.options = options
    }

    /// The `tx` ids remembered, oldest first.
    public func seenTx() -> [String] {
        order
    }

    /// Server time now, from the last welcome; nil before the first one.
    public func serverNow(localNow: Int) -> Int? {
        guard let offset = offset else {
            return nil
        }
        return localNow + offset
    }

    public func welcome(_ msg: RoomWelcomeMessage, localNow: Int) -> RoomFilterResult {
        offset = msg.now - localNow
        return RoomFilterResult(events: pass(msg.replay, serverNow: msg.now), gap: msg.gap)
    }

    /// A live `gift` or `batch`. Before any welcome nothing passes (the server never does that).
    public func live(_ events: [RoomGiftMessage], localNow: Int) -> RoomFilterResult {
        guard let offset = offset else {
            return RoomFilterResult(events: [], gap: false)
        }
        return RoomFilterResult(events: pass(events, serverNow: localNow + offset), gap: false)
    }

    private func pass(_ events: [RoomGiftMessage], serverNow: Int) -> [RoomGiftMessage] {
        let o = options
        let minRank = roomTierRank(o.minTier)
        var out: [RoomGiftMessage] = []
        for e in events {
            last = e.id
            if seen.contains(e.tx) {
                continue
            }
            remember(e.tx)
            if serverNow - e.at >= o.maxReplayAgeMs {
                continue
            }
            if o.skipOwn, let user = o.user, e.sender.id == user {
                continue
            }
            if roomTierRank(tierFor(e.gift.price, thresholds: o.thresholds)) < minRank {
                continue
            }
            out.append(e)
        }
        return out
    }

    private func remember(_ tx: String) {
        seen.insert(tx)
        order.append(tx)
        while order.count > roomDedupSize {
            seen.remove(order.removeFirst())
        }
    }
}

// MARK: - Mapping

/// A room gift ready for the effect layer: play `effectEvent`.
public struct RoomGiftEvent: Sendable, Equatable, Hashable {
    /// Name and price from the event; `image` the catalog's big picture, else an icon; `icon`
    /// the event's icon, else the catalog's.
    public var gift: GiftEffectEvent.GiftInfo
    /// Shown in the notice: the name claim, else `resolveName`, else nil (the layer's "Someone").
    public var sender: String?
    public var quantity: Int
    /// Event id (the resume point).
    public var id: Int
    /// Gift transaction id.
    public var tx: String
    /// Commit time, epoch ms (server clock).
    public var at: Int
    /// The sender's external id.
    public var senderId: String
    /// The sender's display name from their token (claim `n`), else nil.
    public var senderName: String?
    public var receiverId: String?
    /// Came in the `welcome` replay after a (re)connect, not live.
    public var replayed: Bool
    /// Only in a battle (SPEC 18.4): the receiving side, nil otherwise.
    public var receiver: GiftEffectReceiver?

    public init(
        gift: GiftEffectEvent.GiftInfo,
        sender: String?,
        quantity: Int,
        id: Int,
        tx: String,
        at: Int,
        senderId: String,
        senderName: String?,
        receiverId: String?,
        replayed: Bool,
        receiver: GiftEffectReceiver? = nil
    ) {
        self.gift = gift
        self.sender = sender
        self.quantity = quantity
        self.id = id
        self.tx = tx
        self.at = at
        self.senderId = senderId
        self.senderName = senderName
        self.receiverId = receiverId
        self.replayed = replayed
        self.receiver = receiver
    }

    /// What `GiftEffectController.play` takes.
    public var effectEvent: GiftEffectEvent {
        GiftEffectEvent(gift: gift, sender: sender, quantity: quantity, receiver: receiver)
    }
}

/// Turns a room gift into what the effect layer plays (SPEC 18.4): name and price from the event
/// (the price at send time drives the tier); `image` = the catalog gift's `animationUrl`, else
/// its `iconUrl`, else the event's `icon_url`; `icon` = the event's `icon_url`, else the
/// catalog's; `sender` = the name claim, else `resolveName(sender id)` (empty counts as
/// nothing), else nil (the effect layer then shows "Someone"). With a `battle` of two or more
/// sides and the receiver one of the first two, `receiver` = name (`resolveName`, else the id),
/// side and colour (`sideColors`, the bar's pair as colour strings).
public func roomGiftToEffect(
    _ msg: RoomGiftMessage,
    catalog: [Gift]? = nil,
    resolveName: ((String) -> String?)? = nil,
    replayed: Bool = false,
    battle: RoomBattle? = nil,
    sideColors: [String]? = nil
) -> RoomGiftEvent {
    let known = catalog?.first(where: { $0.id == msg.gift.id })
    let image = known?.animationUrl ?? known?.iconUrl ?? msg.gift.iconUrl
    let icon = msg.gift.iconUrl ?? known?.iconUrl
    let senderName = msg.sender.name
    var sender = senderName
    if sender == nil, let resolve = resolveName {
        if let resolved = resolve(msg.sender.id), !resolved.isEmpty {
            sender = resolved
        }
    }
    return RoomGiftEvent(
        gift: GiftEffectEvent.GiftInfo(id: msg.gift.id, name: msg.gift.name, price: msg.gift.price, image: image, icon: icon),
        sender: sender,
        quantity: msg.quantity,
        id: msg.id,
        tx: msg.tx,
        at: msg.at,
        senderId: msg.sender.id,
        senderName: senderName,
        receiverId: msg.receiver?.id,
        replayed: replayed,
        receiver: battleReceiver(msg.receiver?.id, at: msg.at, battle: battle, resolveName: resolveName, sideColors: sideColors)
    )
}

/// The receiving side of a gift in a battle (SPEC 18.4), or nil. Only a gift of the round itself counts:
/// `battle.started <= at < battle.ends` (a replayed gift from before the round, or one at the end or later,
/// is no battle gift), the battle has two or more sides and `id` is one of the first two.
/// `RoomClient.receiverFor` is this for "now"; the tray uses it for the user's own gifts.
public func battleReceiver(
    _ id: String?,
    at: Int,
    battle: RoomBattle?,
    resolveName: ((String) -> String?)?,
    sideColors: [String]?
) -> GiftEffectReceiver? {
    guard let id = id, !id.isEmpty, let round = battle, round.scores.count >= 2,
          at >= round.started, at < round.ends else { return nil }
    let scores = round.scores
    guard let side = scores.firstIndex(where: { $0.id == id }) else { return nil }
    var name = ""
    if let resolved = resolveName?(id), !resolved.isEmpty { name = resolved }
    let color = sideColors.flatMap { side < $0.count ? $0[side] : nil }
    return GiftEffectReceiver(name: name.isEmpty ? id : name, side: side, color: color)
}

// MARK: - Session

/// What a platform transport implements: one WebSocket, text frames only.
@MainActor
public protocol RoomSocket: AnyObject {
    func send(_ text: String)
    /// Close the socket. After this the client ignores every callback of this socket.
    func close(code: Int, reason: String)
}

/// The socket's callbacks, all on the main actor.
public struct RoomSocketHandlers {
    public let onOpen: @MainActor () -> Void
    /// Text frames only; a transport drops binary frames.
    public let onMessage: @MainActor (String) -> Void
    /// Exactly once per socket (an error before or after open is a close with 1006).
    public let onClose: @MainActor (Int, String) -> Void

    public init(
        onOpen: @escaping @MainActor () -> Void,
        onMessage: @escaping @MainActor (String) -> Void,
        onClose: @escaping @MainActor (Int, String) -> Void
    ) {
        self.onOpen = onOpen
        self.onMessage = onMessage
        self.onClose = onClose
    }
}

/// Opens `url` with the WebSocket protocols `["gs.v1", token]`. Throwing counts as a close 1006.
public typealias RoomSocketFactory = @MainActor (_ url: String, _ protocols: [String], _ handlers: RoomSocketHandlers) throws -> any RoomSocket

public enum RoomStatus: String, Sendable, Hashable {
    case idle
    case connecting
    case open
    case reconnecting
    case paused
    case closed
}

public struct RoomState: Sendable, Equatable {
    public var status: RoomStatus
    /// Failed connections in a row.
    public var attempt: Int
    /// `reconnecting`: the wait before the next attempt, ms. Else nil.
    public var retryInMs: Int?
    /// `closed`: the close code (1000 after `leave()`), else the last close code seen or nil.
    public var code: Int?
    public var reason: String?
    /// Approximate viewer count from the server; nil before the first welcome.
    public var viewers: Int?

    public init(
        status: RoomStatus = .idle,
        attempt: Int = 0,
        retryInMs: Int? = nil,
        code: Int? = nil,
        reason: String? = nil,
        viewers: Int? = nil
    ) {
        self.status = status
        self.attempt = attempt
        self.retryInMs = retryInMs
        self.code = code
        self.reason = reason
        self.viewers = viewers
    }
}

/// One room membership (SPEC 18): connects, says hello, plays what the filter lets through,
/// reconnects with backoff and resume, refreshes the token, keeps a heartbeat. Never throws into
/// the app. SwiftUI apps use `GiftRoomModel`, which wraps it with the real socket.
///
/// idle -start-> connecting -welcome-> open -drop-> reconnecting -> connecting ...;
/// `pause()` (app in background) -> paused -`resume()`-> connecting; `leave()` or a final close
/// code -> closed (terminal).
///
/// Settings and callbacks are plain properties, read when used, so they may change at any time.
@MainActor
public final class RoomClient {
    public let room: String
    /// The same token function as the client's. Mint the token with `rooms` and `name` (SPEC 17.2).
    public var getToken: GiftingTokenProvider
    /// Default `wss://rt.giftingstack.com`. A plain `ws://` url to a host that is not on this device
    /// (localhost, 127.0.0.1, ::1, 10.0.2.2) stops the app with a `precondition` failure, when the client
    /// is created and when this changes, unless `allowInsecure` is true (SPEC 3.1, audit R-07).
    public var url: String? {
        didSet { checkURL() }
    }
    /// Lets a plain `ws://` url to another host through. Default false.
    public var allowInsecure: Bool {
        didSet { checkURL() }
    }
    /// The signed-in user for own-skip. nil: the token's `u` claim.
    public var user: String? {
        didSet { syncFilter() }
    }
    public var skipOwn: Bool {
        didSet { syncFilter() }
    }
    public var maxReplayAgeMs: Int {
        didSet { syncFilter() }
    }
    public var minTier: EffectTier {
        didSet { syncFilter() }
    }
    public var thresholds: TierThresholds {
        didSet { syncFilter() }
    }
    /// The app's gift catalog: supplies the big picture.
    public var catalog: [Gift]?
    /// The catalog, read at each event (wins over `catalog`).
    public var getCatalog: (() -> [Gift]?)?
    /// Display name of a sender without a name claim. Return nil for the default.
    public var resolveName: ((String) -> String?)?
    /// The border colours of the two battle sides in the gift notice (the bar's pair as colour
    /// strings). nil: the theme's accent and coin colour.
    public var sideColors: [String]?
    public var onEvent: ((RoomGiftEvent) -> Void)?
    public var onViewers: ((Int) -> Void)?
    public var onGap: (() -> Void)?
    public var onState: ((RoomState) -> Void)?
    /// Battle scores changed (SPEC 18.6): a new snapshot, or nil when the round was removed.
    public var onBattle: ((RoomBattle?) -> Void)?
    /// App heartbeat interval: `ping` text after this long without frames. 0 turns it off for
    /// transports with protocol pings (`URLSessionRoomSocket`). Read when a welcome arrives.
    public var heartbeatMs: Int
    /// The proactive token refresh happens `random(0, refreshJitterMs)` earlier than 30 s before the
    /// socket's end, so viewers that joined together do not all reconnect in the same second.
    /// Default 0 (exact timing, as in the fixtures); `GiftRoomModel` sets `roomRefreshJitterMs`.
    public var refreshJitterMs: Int

    public let filter: RoomEventFilter
    public private(set) var state = RoomState()
    /// The room's battle round as last received (SPEC 18.6): from `welcome`, then each `scores`
    /// frame. Kept across reconnects until the next welcome; nil when there is none.
    public private(set) var battle: RoomBattle?

    private let socketFactory: RoomSocketFactory
    private let clock: any GiftClock
    private let random: () -> Double
    private var listeners: [(token: Int, callback: (RoomState) -> Void)] = []
    private var eventListeners: [(token: Int, callback: (RoomGiftEvent) -> Void)] = []
    private var battleListeners: [(token: Int, callback: (RoomBattle?) -> Void)] = []
    private var nextListenerToken = 0
    /// Bumped whenever the current socket or token request stops mattering.
    private var gen = 0
    private var socket: (any RoomSocket)?
    private var limited = 0
    /// The wait now running is a 4008/4009 one: the platform said when to come back (SPEC 18.5 step 6, R-15).
    private var waitIsLimited = false
    /// The last close was a stop by the client's own rule (SPEC 18.3): `reconnectNow()` may restart.
    private var resumable = false
    private var refreshNext = false
    private var tokenUser: String?
    private var openedAt: Int?
    private var lastFrameAt = 0
    private var timers: [TimerName: Int] = [:]

    private enum TimerName: Hashable {
        case retry
        case dead
        case beat
        case refresh
    }

    /// - Parameters:
    ///   - room: room id, `^[A-Za-z0-9_.:-]{1,64}$`.
    ///   - socket: opens one WebSocket. `GiftRoomModel` passes `urlSessionRoomSocketFactory()`.
    ///   - clock: timers and the local clock. Default: the system clock.
    ///   - random: [0, 1). Default: `Double.random(in: 0..<1)`.
    public init(
        room: String,
        getToken: @escaping GiftingTokenProvider,
        socket: @escaping RoomSocketFactory,
        url: String? = nil,
        user: String? = nil,
        skipOwn: Bool = true,
        maxReplayAgeMs: Int = defaultRoomMaxReplayAgeMs,
        minTier: EffectTier = .small,
        thresholds: TierThresholds = TierThresholds(),
        catalog: [Gift]? = nil,
        getCatalog: (() -> [Gift]?)? = nil,
        resolveName: ((String) -> String?)? = nil,
        sideColors: [String]? = nil,
        onEvent: ((RoomGiftEvent) -> Void)? = nil,
        onViewers: ((Int) -> Void)? = nil,
        onGap: (() -> Void)? = nil,
        onState: ((RoomState) -> Void)? = nil,
        heartbeatMs: Int = roomHeartbeatMs,
        refreshJitterMs: Int = 0,
        clock: (any GiftClock)? = nil,
        random: (() -> Double)? = nil,
        allowInsecure: Bool = false
    ) {
        self.room = room
        self.getToken = getToken
        self.socketFactory = socket
        self.url = url
        self.allowInsecure = allowInsecure
        self.user = user
        self.skipOwn = skipOwn
        self.maxReplayAgeMs = maxReplayAgeMs
        self.minTier = minTier
        self.thresholds = thresholds
        self.catalog = catalog
        self.getCatalog = getCatalog
        self.resolveName = resolveName
        self.sideColors = sideColors
        self.onEvent = onEvent
        self.onViewers = onViewers
        self.onGap = onGap
        self.onState = onState
        self.heartbeatMs = heartbeatMs
        self.refreshJitterMs = refreshJitterMs
        if let clock = clock {
            self.clock = clock
        } else {
            self.clock = SystemGiftClock()
        }
        if let random = random {
            self.random = random
        } else {
            self.random = { Double.random(in: 0..<1) }
        }
        self.filter = RoomEventFilter(
            options: RoomEventFilterOptions(
                user: user,
                skipOwn: skipOwn,
                maxReplayAgeMs: maxReplayAgeMs,
                minTier: minTier,
                thresholds: thresholds
            )
        )
        checkURL()
    }

    /// SPEC 3.1: a plain `ws://` url to a host that is not on this device is a programmer error.
    private func checkURL() {
        guard let url = url else {
            return
        }
        precondition(
            !SecureURL.isRefusedPlain(url, allowInsecure: allowInsecure),
            SecureURL.refusalMessage(url, what: "The rooms url")
        )
    }

    /// Calls `listener` after every state change. Returns a function that stops it.
    @discardableResult
    public func subscribe(_ listener: @escaping (RoomState) -> Void) -> () -> Void {
        let token = nextListenerToken
        nextListenerToken += 1
        listeners.append((token: token, callback: listener))
        return { [weak self] in
            self?.listeners.removeAll { $0.token == token }
        }
    }

    /// Every gift that passes the filter, after `onEvent`. Returns a function that stops it.
    @discardableResult
    public func subscribeEvents(_ listener: @escaping (RoomGiftEvent) -> Void) -> () -> Void {
        let token = nextListenerToken
        nextListenerToken += 1
        eventListeners.append((token: token, callback: listener))
        return { [weak self] in
            self?.eventListeners.removeAll { $0.token == token }
        }
    }

    /// Calls `listener` when the battle changes (a new snapshot, or nil when the round was
    /// removed). Returns a function that stops it.
    @discardableResult
    public func subscribeBattle(_ listener: @escaping (RoomBattle?) -> Void) -> () -> Void {
        let token = nextListenerToken
        nextListenerToken += 1
        battleListeners.append((token: token, callback: listener))
        return { [weak self] in
            self?.battleListeners.removeAll { $0.token == token }
        }
    }

    /// Server time now (from the last welcome), nil before the first welcome.
    public func serverNow() -> Int? {
        filter.serverNow(localNow: clock.nowMs)
    }

    /// The battle side `user` is on right now (SPEC 18.4), for the gifts this app plays itself: give it to the
    /// tray as `receiverOf` so the user's own gift says who got it too. nil outside a round or when `user` is
    /// no side.
    public func receiverFor(_ user: String) -> GiftEffectReceiver? {
        battleReceiver(
            user,
            at: serverNow() ?? clock.nowMs,
            battle: battle,
            resolveName: resolveName,
            sideColors: sideColors
        )
    }

    /// `battleView` of the current round at the server's time now, nil without a round.
    public func battleView() -> BattleView? {
        guard let battle = battle else {
            return nil
        }
        return computeBattleView(battle, serverNow())
    }

    /// Connect. Only from idle; a bad room id closes at once with 4004 and opens nothing.
    public func start() {
        if state.status != .idle {
            return
        }
        if !isValidRoomId(room) {
            finish(RoomCloseCode.badRoomId, "bad_room_id")
            return
        }
        connect()
    }

    /// Leave the room for good: closes with 1000, no callbacks after this.
    public func leave() {
        if state.status == .closed {
            return
        }
        finish(1000, "left")
    }

    /// App went to the background: close (1000), keep `last` and the dedup set, no retry.
    public func pause() {
        let s = state.status
        if s == .idle || s == .closed || s == .paused {
            return
        }
        drop()
        update { $0.status = .paused; $0.retryInMs = nil }
    }

    /// Back in the foreground: reconnect now with `last`. Only from paused.
    public func resume() {
        if state.status != .paused {
            return
        }
        connect()
    }

    /// The network is back (or the user asked): skip a pending backoff wait (never a 4008/4009 one: the
    /// platform said when to come back, SPEC 18.5 step 6). After a stop by the
    /// client's own rule (`retries_exhausted`, 4011, the 4008/4009 limit) it starts again with a
    /// fresh attempt budget. Nothing else changes.
    public func reconnectNow() {
        if state.status == .closed && resumable {
            resumable = false
            limited = 0
            update { $0.attempt = 0 }
            connect()
            return
        }
        if state.status != .reconnecting {
            return
        }
        // Never skip a 4008/4009 wait: skipping it would send every viewer back at once and defeat the limit.
        if waitIsLimited {
            return
        }
        clear(.retry)
        connect()
    }

    public func dispose() {
        leave()
    }

    // MARK: - Internals

    private func update(_ change: (inout RoomState) -> Void) {
        var next = state
        change(&next)
        state = next
        onState?(next)
        for entry in listeners {
            entry.callback(next)
        }
    }

    /// `user` option, else the token's `u` claim.
    private func syncFilter() {
        filter.options = RoomEventFilterOptions(
            user: user ?? tokenUser,
            skipOwn: skipOwn,
            maxReplayAgeMs: maxReplayAgeMs,
            minTier: minTier,
            thresholds: thresholds
        )
    }

    private func later(_ name: TimerName, _ ms: Int, _ fire: @escaping () -> Void) {
        clear(name)
        let handle = clock.schedule(afterMs: ms) { [weak self] in
            self?.timers[name] = nil
            fire()
        }
        timers[name] = handle
    }

    private func clear(_ name: TimerName) {
        if let handle = timers.removeValue(forKey: name) {
            clock.cancel(handle)
        }
    }

    private func clearAll() {
        for name in Array(timers.keys) {
            clear(name)
        }
    }

    /// Forget the current socket (closing it with 1000) and any token request in flight.
    private func drop() {
        gen += 1
        clearAll()
        let s = socket
        socket = nil
        openedAt = nil
        s?.close(code: 1000, reason: "client")
    }

    private func finish(_ code: Int, _ reason: String) {
        drop()
        resumable = false
        update {
            $0.status = .closed
            $0.retryInMs = nil
            $0.code = code
            $0.reason = reason
        }
    }

    private func connect() {
        drop()
        let gen = self.gen
        let refresh = refreshNext
        refreshNext = false
        update { $0.status = .connecting; $0.retryInMs = nil }
        // A `getToken` that never answers must not keep the room connecting forever.
        later(.dead, roomTokenMs) { [weak self] in
            self?.dead(gen)
        }
        let getToken = self.getToken
        Task { [weak self] in
            var token: String?
            do {
                token = try await getToken(refresh)
            } catch {
                token = nil
            }
            guard let self = self, gen == self.gen else {
                return
            }
            if let token = token {
                self.open(token, gen)
            } else {
                // No token (the app's server is down, the user signed out): retry like a network error.
                self.closed(gen, 1006, "token_failed")
            }
        }
    }

    private func open(_ token: String, _ gen: Int) {
        tokenUser = roomTokenUser(token)
        syncFilter()
        let target = roomUrl(room, baseUrl: url ?? defaultRoomsUrl)
        let handlers = RoomSocketHandlers(
            onOpen: { [weak self] in
                guard let self = self, gen == self.gen, self.socket != nil else {
                    return
                }
                self.lastFrameAt = self.clock.nowMs
                self.sendFrame(roomHelloFrame(self.filter.last))
            },
            onMessage: { [weak self] data in
                guard let self = self, gen == self.gen else {
                    return
                }
                self.message(data, gen)
            },
            onClose: { [weak self] code, reason in
                guard let self = self, gen == self.gen else {
                    return
                }
                self.socket = nil
                self.closed(gen, code, reason)
            }
        )
        do {
            socket = try socketFactory(target, [roomSubprotocol, token], handlers)
        } catch {
            closed(gen, 1006, "socket_failed")
            return
        }
        // From creation to `welcome`: the same 10 s as a missing pong.
        later(.dead, roomDeadMs) { [weak self] in
            self?.dead(gen)
        }
    }

    private func sendFrame(_ data: String) {
        socket?.send(data)
    }

    private func message(_ data: String, _ gen: Int) {
        let now = clock.nowMs
        lastFrameAt = now
        if state.status == .open {
            clear(.dead)
        }
        guard let msg = parseRoomFrame(data) else {
            return
        }
        switch msg {
        case .welcome(let welcome):
            clear(.dead)
            openedAt = now
            let ttlMs = min(welcome.ttl * 1000, Double(roomMaxLifetimeMs))
            if ttlMs > Double(roomRefreshAheadMs) {
                let left = Int(ttlMs - Double(roomRefreshAheadMs))
                let spread = min(refreshJitterMs, left / 2)
                let early = spread > 0 ? Int((random() * Double(spread)).rounded(.down)) : 0
                later(.refresh, left - early) { [weak self] in
                    guard let self = self, gen == self.gen else {
                        return
                    }
                    self.refreshNext = true
                    self.connect()
                }
            }
            beat(gen)
            update {
                $0.status = .open
                $0.viewers = welcome.viewers
                $0.retryInMs = nil
            }
            onViewers?(welcome.viewers)
            let result = filter.welcome(welcome, localNow: now)
            setBattle(welcome.battle)
            if result.gap {
                onGap?()
            }
            emit(result.events, replayed: true, gen)
        case .gift(let gift):
            emit(filter.live([gift], localNow: now).events, replayed: false, gen)
        case .batch(let events):
            emit(filter.live(events, localNow: now).events, replayed: false, gen)
        case .viewers(let n):
            update { $0.viewers = n }
            onViewers?(n)
        case .scores(let next):
            if state.status == .open {
                setBattle(next)
            }
        case .pong:
            break
        }
    }

    private func setBattle(_ next: RoomBattle?) {
        if next == nil && battle == nil {
            return
        }
        battle = next
        onBattle?(next)
        for entry in battleListeners {
            entry.callback(next)
        }
    }

    private func emit(_ events: [RoomGiftMessage], replayed: Bool, _ gen: Int) {
        for e in events {
            if gen != self.gen {
                return
            }
            let event = roomGiftToEffect(
                e,
                catalog: getCatalog?() ?? catalog,
                resolveName: resolveName,
                replayed: replayed,
                battle: battle,
                sideColors: sideColors
            )
            onEvent?(event)
            for entry in eventListeners {
                entry.callback(event)
            }
        }
    }

    /// Heartbeat: `ping` after `heartbeatMs` without frames; the next frame must come within 10 s.
    private func beat(_ gen: Int) {
        let every = heartbeatMs
        if every <= 0 {
            return
        }
        let wait = max(0, lastFrameAt + every - clock.nowMs)
        later(.beat, wait) { [weak self] in
            guard let self = self, gen == self.gen else {
                return
            }
            if self.clock.nowMs - self.lastFrameAt >= every {
                self.sendFrame("ping")
                self.later(.dead, roomDeadMs) { [weak self] in
                    self?.dead(gen)
                }
                self.lastFrameAt = self.clock.nowMs
            }
            self.beat(gen)
        }
    }

    /// No token, no welcome or no answer to `ping` in time: drop the socket and retry like a 1006
    /// (reason `token_timeout` while no socket exists yet, else `timeout`).
    private func dead(_ gen: Int) {
        if gen != self.gen {
            return
        }
        let s = socket
        socket = nil
        s?.close(code: 1000, reason: "timeout")
        closed(gen, 1006, s != nil ? "timeout" : "token_timeout")
    }

    private func closed(_ gen: Int, _ code: Int, _ reason: String) {
        if gen != self.gen {
            return
        }
        var stable = false
        if let opened = openedAt {
            stable = clock.nowMs - opened >= roomStableMs
        }
        drop()
        if stable {
            limited = 0
        }
        let attempt = stable ? 0 : state.attempt
        let decision = roomRetryDecision(code: code, reason: reason, attempt: attempt, limited: limited, random: random)
        switch decision {
        case .stop(let isResumable, let isExhausted):
            resumable = isResumable
            update {
                $0.status = .closed
                $0.retryInMs = nil
                $0.code = code
                $0.reason = isExhausted ? roomReasonExhausted : reason
                $0.attempt = attempt
            }
        case .retry(let delayMs, let refreshToken, let isLimited):
            limited = isLimited ? limited + 1 : 0
            waitIsLimited = isLimited
            refreshNext = refreshToken
            update {
                $0.status = .reconnecting
                $0.attempt = attempt + 1
                $0.retryInMs = delayMs
                $0.code = code
                $0.reason = reason
            }
            let next = self.gen
            later(.retry, delayMs) { [weak self] in
                guard let self = self, next == self.gen else {
                    return
                }
                self.connect()
            }
        }
    }
}
