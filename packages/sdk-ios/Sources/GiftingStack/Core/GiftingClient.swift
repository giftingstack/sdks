import Foundation

/// Returns a client token for the signed-in user. Your own server creates it with
/// `POST /v1/client-tokens`. Called again with `forceRefresh == true` when a token is rejected.
/// Errors thrown here reach the caller unchanged.
public typealias GiftingTokenProvider = @Sendable (_ forceRefresh: Bool) async throws -> String

/// The four client calls. `GiftingClient` implements it; the tray state holder takes any
/// implementation (a mock in previews and tests).
public protocol GiftingAPI: Sendable {
    func getGifts() async throws -> [Gift]
    func getMe() async throws -> Me
    func getReceivedGifts(_ user: String) async throws -> [ReceivedGift]
    func sendGift(_ input: SendGiftInput) async throws -> GiftTransaction
}

/// The gift wall's batch call (spec 14.1). `GiftingClient` implements it.
public protocol GiftWallAPI: Sendable {
    func queryGiftWalls(_ items: [GiftWallQueryItem]) async throws -> [GiftWallResult]
}

/// The away summary's two calls (spec 15.1). `GiftingClient` implements them.
public protocol GiftAwayAPI: Sendable {
    func getAway(_ query: AwayQuery) async throws -> AwaySummary
    func ackAway(_ cursor: String) async throws
}

/// The leaderboard's call (spec 16.1). `GiftingClient` implements it.
public protocol GiftLeaderboardAPI: Sendable {
    func getLeaderboard(_ board: LeaderboardBoard, query: LeaderboardQuery) async throws -> Leaderboard
}

/// The gift inbox's call (spec 19.1). `GiftingClient` implements it.
public protocol GiftInboxAPI: Sendable {
    func getInbox(_ query: InboxQuery) async throws -> Inbox
}

public extension GiftInboxAPI {
    /// `getInbox` without a query: the first page.
    func getInbox() async throws -> Inbox {
        try await getInbox(InboxQuery())
    }
}

/// Talks to `/v1/client` with a client token (spec section 3).
public struct GiftingClient: GiftingAPI, GiftWallAPI, GiftAwayAPI, GiftLeaderboardAPI, GiftInboxAPI {
    public static let defaultBaseURL = "https://api.giftingstack.com"

    /// The base URL without trailing slashes.
    public let baseURL: String
    private let getToken: GiftingTokenProvider
    private let transport: any GiftingTransport
    private let platform: String
    private let os: String?

    /// The header the app-facing API reads where the app runs from (information only).
    public static let platformHeader = "X-GiftingStack-Platform"
    /// The header with the phone's operating system, ios or android (information only).
    public static let osHeader = "X-GiftingStack-OS"

    /// - Parameters:
    ///   - transport: the HTTP layer. Default: `URLSessionTransport(timeout: timeout)`.
    ///   - timeout: time allowed for one HTTP attempt, in seconds (default 20, 0 = the URLSession
    ///     defaults). A slower attempt ends the call with the same `network_error` as a lost
    ///     connection, never retried (SPEC 3.4). Only used by the default transport.
    ///   - platform: where the app runs, sent as X-GiftingStack-Platform so the dashboard shows
    ///     which platforms gifts are sent from (information only). Default ios.
    ///   - os: the phone's operating system, sent as X-GiftingStack-OS (information only).
    ///     Default ios; nil sends none.
    ///   - allowInsecure: lets a `http://` base URL to a host that is not on this device through (a
    ///     staging proxy on your LAN). Without it only https and localhost, 127.0.0.1, ::1 and 10.0.2.2
    ///     work: any other `http://` base URL is a programmer error and stops the app right here with a
    ///     `precondition` failure that names the option (SPEC 3.1: the bearer token would travel in clear
    ///     text). Never for a production app.
    public init(
        getToken: @escaping GiftingTokenProvider,
        baseURL: String? = nil,
        transport: (any GiftingTransport)? = nil,
        timeout: TimeInterval = defaultRequestTimeout,
        platform: String = "ios",
        os: String? = "ios",
        allowInsecure: Bool = false
    ) {
        var base = baseURL ?? GiftingClient.defaultBaseURL
        while base.hasSuffix("/") {
            base.removeLast()
        }
        precondition(
            !SecureURL.isRefusedPlain(base, allowInsecure: allowInsecure),
            SecureURL.refusalMessage(base, what: "The base URL")
        )
        self.baseURL = base
        self.getToken = getToken
        self.transport = transport ?? URLSessionTransport(timeout: timeout)
        self.platform = platform
        self.os = os
    }

    public func getGifts() async throws -> [Gift] {
        let list = try await request(DataList<Gift>.self, method: "GET", path: "/v1/client/gifts")
        return list.data
    }

    public func getMe() async throws -> Me {
        try await request(Me.self, method: "GET", path: "/v1/client/me")
    }

    public func getReceivedGifts(_ user: String) async throws -> [ReceivedGift] {
        try await getReceivedGifts(user, reference: nil)
    }

    /// A user's gift counters: the profile wall, or with `reference` one post's wall (spec 14.1).
    /// No query string without a reference.
    public func getReceivedGifts(_ user: String, reference: String?) async throws -> [ReceivedGift] {
        let pairs: [(String, String?)] = [("reference", reference)]
        let base = "/v1/client/users/" + encodeURIComponent(user) + "/received-gifts"
        let path = base + clientQueryString(pairs)
        let list = try await request(DataList<ReceivedGift>.self, method: "GET", path: path)
        return list.data
    }

    /// Up to 25 walls in one call, answered in the same order. A read: no `Idempotency-Key`.
    /// An empty list makes no request.
    public func queryGiftWalls(_ items: [GiftWallQueryItem]) async throws -> [GiftWallResult] {
        if items.isEmpty {
            return []
        }
        let data = try JSONEncoder().encode(WallQueryBody(items: items))
        let list = try await request(
            DataList<GiftWallResult>.self,
            method: "POST",
            path: "/v1/client/gift-walls/query",
            body: data
        )
        return list.data
    }

    /// Gifts the signed-in user received since they last looked (spec 15.1). Query `since`
    /// then `max_groups`, each only when given.
    public func getAway(_ query: AwayQuery) async throws -> AwaySummary {
        var maxGroups: String?
        if let n = query.maxGroups {
            maxGroups = String(n)
        }
        let pairs: [(String, String?)] = [("since", query.since), ("max_groups", maxGroups)]
        let path = "/v1/client/me/away" + clientQueryString(pairs)
        return try await request(AwaySummary.self, method: "GET", path: path)
    }

    /// `getAway` without a query.
    public func getAway() async throws -> AwaySummary {
        try await getAway(AwayQuery())
    }

    /// Marks a summary as seen: send its `cursor` once it was shown. Success is a 204 whose body
    /// is never parsed. No `Idempotency-Key` (the PUT is idempotent and monotonic).
    public func ackAway(_ cursor: String) async throws {
        let data = try JSONEncoder().encode(AwayCursorBody(cursor: cursor))
        _ = try await perform(method: "PUT", path: "/v1/client/me/away/cursor", body: data, idempotencyKey: nil)
    }

    /// The gifts the signed-in user received in the last 24 hours, newest first (spec 19.1).
    /// Query `cursor` then `limit`, each only when given.
    public func getInbox(_ query: InboxQuery) async throws -> Inbox {
        var limit: String?
        if let n = query.limit {
            limit = String(n)
        }
        let pairs: [(String, String?)] = [("cursor", query.cursor), ("limit", limit)]
        let path = "/v1/client/me/inbox" + clientQueryString(pairs)
        return try await request(Inbox.self, method: "GET", path: path)
    }

    /// Top senders or receivers (spec 16.1). Query parameters in the fixed order `period`,
    /// `metric`, `at`, `limit`, `include_me` (only `include_me=false`), each only when given.
    public func getLeaderboard(_ board: LeaderboardBoard, query: LeaderboardQuery) async throws -> Leaderboard {
        var limit: String?
        if let n = query.limit {
            limit = String(n)
        }
        var includeMe: String?
        if query.includeMe == false {
            includeMe = "false"
        }
        let pairs: [(String, String?)] = [
            ("period", query.period?.rawValue),
            ("metric", query.metric?.rawValue),
            ("at", query.at),
            ("limit", limit),
            ("include_me", includeMe),
        ]
        let base = "/v1/client/leaderboards/" + encodeURIComponent(board.rawValue)
        let path = base + clientQueryString(pairs)
        return try await request(Leaderboard.self, method: "GET", path: path)
    }

    /// `getLeaderboard` without a query.
    public func getLeaderboard(_ board: LeaderboardBoard) async throws -> Leaderboard {
        try await getLeaderboard(board, query: LeaderboardQuery())
    }

    public func sendGift(_ input: SendGiftInput) async throws -> GiftTransaction {
        let body = SendGiftBody(
            receiver: input.receiver,
            giftId: input.giftId,
            quantity: input.quantity,
            message: input.message,
            reference: input.reference,
            roomId: input.roomId
        )
        let data = try JSONEncoder().encode(body)
        // One key per call, reused by the 401 repeat and the 5xx retry.
        let key = input.idempotencyKey ?? newIdempotencyKey()
        return try await request(
            GiftTransaction.self,
            method: "POST",
            path: "/v1/client/gift-transactions",
            body: data,
            idempotencyKey: key
        )
    }

    // MARK: - Attempts (spec 3.4)

    private func request<T: Decodable>(
        _ type: T.Type,
        method: String,
        path: String,
        body: Data? = nil,
        idempotencyKey: String? = nil
    ) async throws -> T {
        let response = try await perform(method: method, path: path, body: body, idempotencyKey: idempotencyKey)
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            // Not JSON (a proxy's HTML page, a cut-off body) or not the shape of the model: never
            // show its text (SPEC 3.5).
            throw GiftingError(
                status: response.status,
                type: "invalid_response",
                message: "Invalid response (\(response.status)).",
                requestId: response.header("X-Request-Id")
            )
        }
    }

    /// The attempts of spec 3.4; returns the 2xx response, throws a `GiftingError` otherwise.
    private func perform(
        method: String,
        path: String,
        body: Data?,
        idempotencyKey: String?
    ) async throws -> HTTPResponse {
        let repeat = LostConnectionRepeat()
        var token = try await getToken(false)
        var response = try await once(method: method, path: path, token: token, body: body, idempotencyKey: idempotencyKey, repeat: repeat)
        // A rejected token is usually just an expired one: get a fresh one and try once more.
        if response.status == 401 {
            token = try await getToken(true)
            response = try await once(method: method, path: path, token: token, body: body, idempotencyKey: idempotencyKey, repeat: repeat)
        }
        // One quiet retry for a server hiccup, same token, same key, no delay.
        if response.status >= 500 {
            response = try await once(method: method, path: path, token: token, body: body, idempotencyKey: idempotencyKey, repeat: repeat)
        }
        guard response.status >= 200 && response.status <= 299 else {
            throw GiftingClient.error(from: response)
        }
        return response
    }

    private func once(
        method: String,
        path: String,
        token: String,
        body: Data?,
        idempotencyKey: String?,
        repeat: LostConnectionRepeat
    ) async throws -> HTTPResponse {
        var headers: [String: String] = [
            "Authorization": "Bearer \(token)",
            GiftingClient.platformHeader: platform,
        ]
        if let os {
            headers[GiftingClient.osHeader] = os
        }
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        // An empty key sends no header, like the reference (spec open question 3).
        if let key = idempotencyKey, !key.isEmpty {
            headers["Idempotency-Key"] = key
        }
        let request = HTTPRequest(method: method, url: baseURL + path, headers: headers, body: body)
        do {
            return try await transport.send(request)
        } catch {
            // sendGift repeats ONE lost connection at once, same token, same key (the server replays it if the
            // first request arrived). Not our own timeout, not a GET, not a POST without a key (SPEC 3.4, R-18).
            let timedOut = (error as? URLError)?.code == .timedOut
            if let key = idempotencyKey, !key.isEmpty, !repeat.used, !timedOut, !(error is CancellationError) {
                repeat.used = true
                return try await once(
                    method: method, path: path, token: token, body: body, idempotencyKey: idempotencyKey, repeat: repeat
                )
            }
            throw GiftingError.network
        }
    }

    static func error(from response: HTTPResponse) -> GiftingError {
        let payload = (try? JSONDecoder().decode(ErrorEnvelope.self, from: response.body))?.error
        return GiftingError(
            status: response.status,
            type: payload?.type ?? "unknown_error",
            message: payload?.message ?? "Request failed (\(response.status)).",
            requestId: payload?.requestId ?? response.header("X-Request-Id")
        )
    }
}

/// A new idempotency key: a lower-case UUID v4.
public func newIdempotencyKey() -> String {
    UUID().uuidString.lowercased()
}

/// Exactly JavaScript's `encodeURIComponent`: UTF-8 percent-encoding of every byte except
/// `A-Z a-z 0-9 - _ . ! ~ * ' ( )`, upper-case hex digits.
func encodeURIComponent(_ text: String) -> String {
    let hex: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
    var out = ""
    for byte in text.utf8 {
        if isUnreservedURIByte(byte) {
            out.append(Character(Unicode.Scalar(byte)))
        } else {
            out.append("%")
            out.append(hex[Int(byte >> 4)])
            out.append(hex[Int(byte & 0x0F)])
        }
    }
    return out
}

private func isUnreservedURIByte(_ b: UInt8) -> Bool {
    switch b {
    case 0x41...0x5A, 0x61...0x7A, 0x30...0x39: // A-Z a-z 0-9
        return true
    case 0x2D, 0x5F, 0x2E, 0x21, 0x7E, 0x2A, 0x27, 0x28, 0x29: // - _ . ! ~ * ' ( )
        return true
    default:
        return false
    }
}

/// `?a=1&b=2` from the pairs whose value is given, in the order given, values encoded like
/// `encodeURIComponent`. Empty when nothing is given.
func clientQueryString(_ pairs: [(String, String?)]) -> String {
    var parts: [String] = []
    for pair in pairs {
        if let value = pair.1 {
            parts.append(pair.0 + "=" + encodeURIComponent(value))
        }
    }
    return parts.isEmpty ? "" : "?" + parts.joined(separator: "&")
}

// MARK: - Wire helpers

private struct DataList<Element: Decodable>: Decodable {
    let data: [Element]
}

private struct WallQueryBody: Encodable {
    let items: [GiftWallQueryItem]
}

private struct AwayCursorBody: Encodable {
    let cursor: String
}

private struct SendGiftBody: Encodable {
    let receiver: String
    let giftId: String
    let quantity: Int?
    let message: String?
    let reference: String?
    let roomId: String?

    enum CodingKeys: String, CodingKey {
        case receiver
        case giftId = "gift_id"
        case quantity
        case message
        case reference
        case roomId = "room_id"
    }

    // Absent fields are left OUT of the JSON (not null).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(receiver, forKey: .receiver)
        try c.encode(giftId, forKey: .giftId)
        try c.encodeIfPresent(quantity, forKey: .quantity)
        try c.encodeIfPresent(message, forKey: .message)
        try c.encodeIfPresent(reference, forKey: .reference)
        try c.encodeIfPresent(roomId, forKey: .roomId)
    }
}

/// `{ "error": { "type", "message", "request_id" } }`. Every part is optional; a field of the
/// wrong JSON type counts as missing.
private struct ErrorEnvelope: Decodable {
    let error: ErrorPayload?

    enum CodingKeys: String, CodingKey {
        case error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = (try? c.decodeIfPresent(ErrorPayload.self, forKey: .error)) ?? nil
    }
}

private struct ErrorPayload: Decodable {
    let type: String?
    let message: String?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case message
        case requestId = "request_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? nil
        message = (try? c.decodeIfPresent(String.self, forKey: .message)) ?? nil
        requestId = (try? c.decodeIfPresent(String.self, forKey: .requestId)) ?? nil
    }
}

/// One lost-connection repeat per call (SPEC 3.4, audit R-18), shared by the attempts of that call.
private final class LostConnectionRepeat: @unchecked Sendable {
    var used = false
}
