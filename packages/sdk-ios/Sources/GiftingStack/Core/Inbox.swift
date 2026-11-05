import Foundation

// The gift inbox (spec section 19): the models of `GET /v1/client/me/inbox` and the pure helpers
// `inboxTimeLabel`, `inboxRows` and `inboxUnread`. As in ComponentModels.swift: Swift property
// names, the API's snake_case keys, decoding ignores unknown fields, encoding is written by hand
// so nullable fields are sent as JSON `null`.

/// Query of `getInbox`. Fields left nil are not sent (`cursor` first, then `limit`).
public struct InboxQuery: Sendable, Equatable, Hashable {
    /// The `next_cursor` of the previous page.
    public var cursor: String?
    /// Rows per page, 1 to 100. Server default 20.
    public var limit: Int?

    public init(cursor: String? = nil, limit: Int? = nil) {
        self.cursor = cursor
        self.limit = limit
    }
}

/// The gift of an inbox row: `{ id, name, price, icon_url, animation_url }`.
public struct InboxGift: Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var name: String
    /// Today's catalog price.
    public var price: Int
    public var iconUrl: String?
    public var animationUrl: String?

    public init(id: String, name: String, price: Int, iconUrl: String? = nil, animationUrl: String? = nil) {
        self.id = id
        self.name = name
        self.price = price
        self.iconUrl = iconUrl
        self.animationUrl = animationUrl
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case price
        case iconUrl = "icon_url"
        case animationUrl = "animation_url"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(price, forKey: .price)
        try c.encode(iconUrl, forKey: .iconUrl)
        try c.encode(animationUrl, forKey: .animationUrl)
    }
}

/// One gift the signed-in user received (never carries the message, metadata or reference).
public struct InboxItem: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// The gift transaction (`gtx_...`).
    public var id: String
    /// ISO time.
    public var createdAt: String
    /// External id of the sender; nil = a deleted sender.
    public var sender: String?
    public var gift: InboxGift
    public var quantity: Int
    /// Value of the gift (price x quantity) when it was sent.
    public var units: Int
    /// `completed` or `reversed` (the UI hides reversed gifts).
    public var status: String

    public init(
        id: String,
        createdAt: String,
        sender: String?,
        gift: InboxGift,
        quantity: Int,
        units: Int,
        status: String = "completed"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sender = sender
        self.gift = gift
        self.quantity = quantity
        self.units = units
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case sender
        case gift
        case quantity
        case units
        case status
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(sender, forKey: .sender)
        try c.encode(gift, forKey: .gift)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(units, forKey: .units)
        try c.encode(status, forKey: .status)
    }
}

/// What `GET /v1/client/me/inbox` returns: one page of the last 24 hours, newest first.
public struct Inbox: Codable, Sendable, Equatable, Hashable {
    public var user: String
    /// Start of the window (24 hours ago).
    public var since: String
    /// When the page was read.
    public var until: String
    public var data: [InboxItem]
    public var hasMore: Bool
    /// Pass it as `InboxQuery.cursor` for the next (older) page.
    public var nextCursor: String?

    public init(
        user: String,
        since: String,
        until: String,
        data: [InboxItem],
        hasMore: Bool,
        nextCursor: String? = nil
    ) {
        self.user = user
        self.since = since
        self.until = until
        self.data = data
        self.hasMore = hasMore
        self.nextCursor = nextCursor
    }

    enum CodingKeys: String, CodingKey {
        case user
        case since
        case until
        case data
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(user, forKey: .user)
        try c.encode(since, forKey: .since)
        try c.encode(until, forKey: .until)
        try c.encode(data, forKey: .data)
        try c.encode(hasMore, forKey: .hasMore)
        try c.encode(nextCursor, forKey: .nextCursor)
    }
}

/// One row of the inbox list (reversed gifts are not rows).
public struct InboxRow: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    /// The display name, `"Someone"` for a deleted sender, else the sender id.
    public let senderName: String
    public let giftName: String
    public let quantity: Int
    /// `now`, `5m`, `3h` or `1d`.
    public let time: String
    public let iconUrl: String?
    /// The sender id (nil: deleted).
    public let sender: String?

    public init(
        id: String,
        senderName: String,
        giftName: String,
        quantity: Int,
        time: String,
        iconUrl: String?,
        sender: String?
    ) {
        self.id = id
        self.senderName = senderName
        self.giftName = giftName
        self.quantity = quantity
        self.time = time
        self.iconUrl = iconUrl
        self.sender = sender
    }
}

/// Epoch milliseconds of an ISO time (with or without fractional seconds); nil when it does not parse.
public func inboxParseTime(_ iso: String) -> Int? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: iso)
    if date == nil {
        formatter.formatOptions = [.withInternetDateTime]
        date = formatter.date(from: iso)
    }
    guard let found = date else {
        return nil
    }
    return Int((found.timeIntervalSince1970 * 1000).rounded())
}

/// The age of a gift (spec 19.2): `d = nowMs - createdAtMs`; under a minute (also negative) is
/// `now`, then `Nm`, `Nh`, `Nd`.
public func inboxTimeLabel(createdAtMs: Int, nowMs: Int) -> String {
    let d = nowMs - createdAtMs
    if d < 60_000 {
        return "now"
    }
    if d < 3_600_000 {
        return String(d / 60_000) + "m"
    }
    if d < 86_400_000 {
        return String(d / 3_600_000) + "h"
    }
    return String(d / 86_400_000) + "d"
}

/// The rows of a page list (spec 19.2): reversed gifts dropped, order kept. `names` maps sender
/// ids to display names (missing: the id; a nil sender: `someone`). A `created_at` that does not
/// parse counts as "now".
public func inboxRows(_ items: [InboxItem], nowMs: Int, names: [String: String], someone: String = "Someone") -> [InboxRow] {
    var rows: [InboxRow] = []
    for item in items where item.status != "reversed" {
        var senderName = someone
        if let id = item.sender {
            senderName = names[id] ?? id
        }
        let created = inboxParseTime(item.createdAt) ?? nowMs
        rows.append(InboxRow(
            id: item.id,
            senderName: senderName,
            giftName: item.gift.name,
            quantity: item.quantity,
            time: inboxTimeLabel(createdAtMs: created, nowMs: nowMs),
            iconUrl: item.gift.iconUrl,
            sender: item.sender
        ))
    }
    return rows
}

/// How many completed gifts are strictly newer than `lastSeenMs` (all of them when nil), for an
/// app's own badge (spec 19.2).
public func inboxUnread(_ items: [InboxItem], lastSeenMs: Int?) -> Int {
    var count = 0
    for item in items where item.status == "completed" {
        guard let created = inboxParseTime(item.createdAt) else {
            continue
        }
        if let seen = lastSeenMs, created <= seen {
            continue
        }
        count += 1
    }
    return count
}
