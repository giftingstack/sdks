import Foundation

// API models of the gift wall, the away summary and the leaderboard (spec sections 14-16).
// As in Models.swift: Swift property names, the API's snake_case keys, decoding ignores unknown
// fields, encoding is written by hand so nullable fields are sent as JSON `null`.

// MARK: - Gift walls (spec 14)

/// One wall of the batch call: a receiver's profile wall, or one post's wall with `reference`.
public struct GiftWallQueryItem: Codable, Sendable, Equatable, Hashable {
    public var receiver: String
    /// Your own context id the gifts were sent with (for example a post id). nil: profile wall.
    public var reference: String?

    public init(receiver: String, reference: String? = nil) {
        self.receiver = receiver
        self.reference = reference
    }

    enum CodingKeys: String, CodingKey {
        case receiver
        case reference
    }

    /// A nil reference is left OUT of the JSON (the API's profile wall).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(receiver, forKey: .receiver)
        try c.encodeIfPresent(reference, forKey: .reference)
    }
}

/// One answer of `POST /v1/client/gift-walls/query`, in the order of the request.
public struct GiftWallResult: Codable, Sendable, Equatable, Hashable {
    public var receiver: String
    public var reference: String?
    /// Counters per gift, in catalog order. Empty for unknown users.
    public var gifts: [ReceivedGift]

    public init(receiver: String, reference: String? = nil, gifts: [ReceivedGift]) {
        self.receiver = receiver
        self.reference = reference
        self.gifts = gifts
    }

    enum CodingKeys: String, CodingKey {
        case receiver
        case reference
        case gifts
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(receiver, forKey: .receiver)
        try c.encode(reference, forKey: .reference)
        try c.encode(gifts, forKey: .gifts)
    }
}

// MARK: - Away summary (spec 15)

/// Query of `getAway`. Fields left nil are not sent.
public struct AwayQuery: Sendable, Equatable, Hashable {
    /// An opaque `cursor` from an earlier summary. Overrides the stored cursor for this read.
    public var since: String?
    /// Most gift groups to return, 1 to 10. Server default 5.
    public var maxGroups: Int?

    public init(since: String? = nil, maxGroups: Int? = nil) {
        self.since = since
        self.maxGroups = maxGroups
    }
}

/// Who sent a group. `user == nil`: deleted senders, all merged into one entry.
public struct AwaySender: Codable, Sendable, Equatable, Hashable {
    public var user: String?
    public var count: Int

    public init(user: String?, count: Int) {
        self.user = user
        self.count = count
    }

    enum CodingKeys: String, CodingKey {
        case user
        case count
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(user, forKey: .user)
        try c.encode(count, forKey: .count)
    }
}

/// One of the summary's `top_senders`.
public struct AwayTopSender: Codable, Sendable, Equatable, Hashable {
    public var user: String?
    public var count: Int
    public var units: Int

    public init(user: String?, count: Int, units: Int) {
        self.user = user
        self.count = count
        self.units = units
    }

    enum CodingKeys: String, CodingKey {
        case user
        case count
        case units
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(user, forKey: .user)
        try c.encode(count, forKey: .count)
        try c.encode(units, forKey: .units)
    }
}

/// The gift of an away group: `{ id, name, price, icon_url, animation_url }`.
public struct AwayGift: Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var name: String
    /// Today's catalog price: the effect tier matches the tray's.
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

/// All gifts of one kind that arrived while the person was away.
public struct AwayGroup: Codable, Sendable, Equatable, Hashable {
    public var gift: AwayGift
    /// Number of gifts (sum of quantities).
    public var count: Int
    /// Value in your own coin units. A display counter, never a balance.
    public var units: Int
    /// Distinct people who sent this gift.
    public var senderCount: Int
    /// At most 3, by count.
    public var senders: [AwaySender]

    public init(gift: AwayGift, count: Int, units: Int, senderCount: Int, senders: [AwaySender]) {
        self.gift = gift
        self.count = count
        self.units = units
        self.senderCount = senderCount
        self.senders = senders
    }

    enum CodingKeys: String, CodingKey {
        case gift
        case count
        case units
        case senderCount = "sender_count"
        case senders
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(gift, forKey: .gift)
        try c.encode(count, forKey: .count)
        try c.encode(units, forKey: .units)
        try c.encode(senderCount, forKey: .senderCount)
        try c.encode(senders, forKey: .senders)
    }
}

/// What `GET /v1/client/me/away` returns: gifts received since the person last looked.
public struct AwaySummary: Codable, Sendable, Equatable, Hashable {
    public var user: String
    public var since: String
    public var until: String
    /// Send this to `ackAway` once the summary was shown. Unchanged when nothing is new.
    public var cursor: String?
    /// More than 2,000 gifts arrived: the totals are lower bounds ("2,000+").
    public var truncated: Bool
    public var totalGifts: Int
    public var totalUnits: Int
    public var senderCount: Int
    /// Biggest first (by units), at most `maxGroups`.
    public var groups: [AwayGroup]
    /// At most 5, by count.
    public var topSenders: [AwayTopSender]

    public init(
        user: String,
        since: String,
        until: String,
        cursor: String?,
        truncated: Bool,
        totalGifts: Int,
        totalUnits: Int,
        senderCount: Int,
        groups: [AwayGroup],
        topSenders: [AwayTopSender]
    ) {
        self.user = user
        self.since = since
        self.until = until
        self.cursor = cursor
        self.truncated = truncated
        self.totalGifts = totalGifts
        self.totalUnits = totalUnits
        self.senderCount = senderCount
        self.groups = groups
        self.topSenders = topSenders
    }

    enum CodingKeys: String, CodingKey {
        case user
        case since
        case until
        case cursor
        case truncated
        case totalGifts = "total_gifts"
        case totalUnits = "total_units"
        case senderCount = "sender_count"
        case groups
        case topSenders = "top_senders"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(user, forKey: .user)
        try c.encode(since, forKey: .since)
        try c.encode(until, forKey: .until)
        try c.encode(cursor, forKey: .cursor)
        try c.encode(truncated, forKey: .truncated)
        try c.encode(totalGifts, forKey: .totalGifts)
        try c.encode(totalUnits, forKey: .totalUnits)
        try c.encode(senderCount, forKey: .senderCount)
        try c.encode(groups, forKey: .groups)
        try c.encode(topSenders, forKey: .topSenders)
    }
}

// MARK: - Leaderboards (spec 16)

public enum LeaderboardBoard: String, Codable, Sendable, CaseIterable, Hashable {
    case senders
    case receivers
}

public enum LeaderboardPeriod: String, Codable, Sendable, CaseIterable, Hashable {
    case day
    case week
    case month
    case all
}

public enum LeaderboardMetric: String, Codable, Sendable, CaseIterable, Hashable {
    case units
    case gifts
}

/// Query of `getLeaderboard`. Fields left nil are not sent.
public struct LeaderboardQuery: Sendable, Equatable, Hashable {
    /// Default `week` (server).
    public var period: LeaderboardPeriod?
    /// Default `units` (server).
    public var metric: LeaderboardMetric?
    /// `YYYY-MM-DD`, any day inside the wanted period (UTC). Default today. Ignored for `all`.
    public var at: String?
    /// 1 to 100. Default 10 (server).
    public var limit: Int?
    /// `false` leaves out the `me` block. nil or true: the default (not sent).
    public var includeMe: Bool?

    public init(
        period: LeaderboardPeriod? = nil,
        metric: LeaderboardMetric? = nil,
        at: String? = nil,
        limit: Int? = nil,
        includeMe: Bool? = nil
    ) {
        self.period = period
        self.metric = metric
        self.at = at
        self.limit = limit
        self.includeMe = includeMe
    }
}

/// One row. `rank` is the competition rank on the metric (1, 2, 2, 4), computed by the server.
public struct LeaderboardEntry: Codable, Sendable, Equatable, Hashable {
    public var rank: Int
    public var user: String
    public var gifts: Int
    public var units: Int

    public init(rank: Int, user: String, gifts: Int, units: Int) {
        self.rank = rank
        self.user = user
        self.gifts = gifts
        self.units = units
    }
}

/// The signed-in viewer's own position.
public struct LeaderboardMe: Codable, Sendable, Equatable, Hashable {
    public var user: String
    /// Exact within the top 1,000, else nil ("1,000+"). Also nil without a score or when hidden.
    public var rank: Int?
    public var gifts: Int
    public var units: Int
    public var hidden: Bool

    public init(user: String, rank: Int?, gifts: Int, units: Int, hidden: Bool) {
        self.user = user
        self.rank = rank
        self.gifts = gifts
        self.units = units
        self.hidden = hidden
    }

    enum CodingKeys: String, CodingKey {
        case user
        case rank
        case gifts
        case units
        case hidden
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(user, forKey: .user)
        try c.encode(rank, forKey: .rank)
        try c.encode(gifts, forKey: .gifts)
        try c.encode(units, forKey: .units)
        try c.encode(hidden, forKey: .hidden)
    }
}

/// What `GET /v1/client/leaderboards/{board}` returns. `board`, `period` and `metric` stay
/// strings (as `GiftTransaction.status`), so a new value never fails decoding.
public struct Leaderboard: Codable, Sendable, Equatable, Hashable {
    /// `"senders"` or `"receivers"`.
    public var board: String
    /// `"day"`, `"week"`, `"month"` or `"all"`.
    public var period: String
    /// `"units"` or `"gifts"`.
    public var metric: String
    /// `2026-10-11`, `2026-W41`, `2026-10` or `all`.
    public var label: String
    public var startsAt: String?
    public var endsAt: String?
    public var asOf: String
    public var data: [LeaderboardEntry]
    public var hasMore: Bool
    public var me: LeaderboardMe?

    public init(
        board: String,
        period: String,
        metric: String,
        label: String,
        startsAt: String? = nil,
        endsAt: String? = nil,
        asOf: String,
        data: [LeaderboardEntry],
        hasMore: Bool,
        me: LeaderboardMe? = nil
    ) {
        self.board = board
        self.period = period
        self.metric = metric
        self.label = label
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.asOf = asOf
        self.data = data
        self.hasMore = hasMore
        self.me = me
    }

    enum CodingKeys: String, CodingKey {
        case board
        case period
        case metric
        case label
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case asOf = "as_of"
        case data
        case hasMore = "has_more"
        case me
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(board, forKey: .board)
        try c.encode(period, forKey: .period)
        try c.encode(metric, forKey: .metric)
        try c.encode(label, forKey: .label)
        try c.encode(startsAt, forKey: .startsAt)
        try c.encode(endsAt, forKey: .endsAt)
        try c.encode(asOf, forKey: .asOf)
        try c.encode(data, forKey: .data)
        try c.encode(hasMore, forKey: .hasMore)
        try c.encode(me, forKey: .me)
    }
}
