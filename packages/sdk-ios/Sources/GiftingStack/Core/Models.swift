import Foundation

// API models. Property names use Swift case; the JSON keys stay the API's snake_case.
// Decoding ignores unknown fields (synthesized `init(from:)`). Encoding is written by hand so
// nullable fields are sent as JSON `null`, exactly as the API sends them (the synthesized
// encoder would drop them).

/// A gift as the app sees it (`GET /v1/client/gifts`).
public struct Gift: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var description: String?
    /// In your own coin units.
    public var price: Int
    /// The 256 px picture.
    public var iconUrl: String?
    /// The 512 px picture shown in the effect.
    public var animationUrl: String?
    public var sortOrder: Int

    public init(
        id: String,
        name: String,
        description: String? = nil,
        price: Int,
        iconUrl: String? = nil,
        animationUrl: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.price = price
        self.iconUrl = iconUrl
        self.animationUrl = animationUrl
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case price
        case iconUrl = "icon_url"
        case animationUrl = "animation_url"
        case sortOrder = "sort_order"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(price, forKey: .price)
        try c.encode(iconUrl, forKey: .iconUrl)
        try c.encode(animationUrl, forKey: .animationUrl)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

/// The signed-in user and their balance (`GET /v1/client/me`).
public struct Me: Codable, Sendable, Equatable, Hashable {
    public var user: String
    public var balance: Int
    /// `false`: the token was made with a test key (the test environment allows 50 users and
    /// 5,000 operations a month; the tray shows "Test mode"). Nil from older servers.
    public var livemode: Bool?

    public init(user: String, balance: Int, livemode: Bool? = nil) {
        self.user = user
        self.balance = balance
        self.livemode = livemode
    }
}

/// The short gift object inside received gifts and transactions: `{ id, name, icon_url }`.
public struct GiftSummary: Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var iconUrl: String?

    public init(id: String, name: String, iconUrl: String? = nil) {
        self.id = id
        self.name = name
        self.iconUrl = iconUrl
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case iconUrl = "icon_url"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(iconUrl, forKey: .iconUrl)
    }
}

/// `GET /v1/client/users/{user}/received-gifts` items.
public struct ReceivedGift: Codable, Sendable, Equatable, Hashable {
    public var gift: GiftSummary
    public var count: Int

    public init(gift: GiftSummary, count: Int) {
        self.gift = gift
        self.count = count
    }
}

/// What `POST /v1/client/gift-transactions` returns.
public struct GiftTransaction: Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var sender: String
    public var receiver: String
    public var gift: GiftSummary
    public var quantity: Int
    public var unitPrice: Int
    public var total: Int
    public var message: String?
    public var reference: String?
    /// `"completed"` or `"reversed"`. Kept as a string so a new status never fails decoding.
    public var status: String
    /// ISO 8601, kept as the API sent it.
    public var createdAt: String
    public var senderBalanceAfter: Int

    public init(
        id: String,
        sender: String,
        receiver: String,
        gift: GiftSummary,
        quantity: Int,
        unitPrice: Int,
        total: Int,
        message: String? = nil,
        reference: String? = nil,
        status: String,
        createdAt: String,
        senderBalanceAfter: Int
    ) {
        self.id = id
        self.sender = sender
        self.receiver = receiver
        self.gift = gift
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.total = total
        self.message = message
        self.reference = reference
        self.status = status
        self.createdAt = createdAt
        self.senderBalanceAfter = senderBalanceAfter
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sender
        case receiver
        case gift
        case quantity
        case unitPrice = "unit_price"
        case total
        case message
        case reference
        case status
        case createdAt = "created_at"
        case senderBalanceAfter = "sender_balance_after"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sender, forKey: .sender)
        try c.encode(receiver, forKey: .receiver)
        try c.encode(gift, forKey: .gift)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(unitPrice, forKey: .unitPrice)
        try c.encode(total, forKey: .total)
        try c.encode(message, forKey: .message)
        try c.encode(reference, forKey: .reference)
        try c.encode(status, forKey: .status)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(senderBalanceAfter, forKey: .senderBalanceAfter)
    }
}

/// Input of `sendGift`. Fields left `nil` are not sent.
public struct SendGiftInput: Sendable, Equatable, Hashable {
    public var receiver: String
    public var giftId: String
    /// 1 to 1000. Default 1 (server side).
    public var quantity: Int?
    /// Up to 280 characters.
    public var message: String?
    /// Your own context id, for example the post the gift is on.
    public var reference: String?
    /// A room id (SPEC 17.1): everyone in that room sees the gift's effect. Sent as `room_id`.
    public var roomId: String?
    /// Identifies this send. The client makes one per call; pass your own only if you retry
    /// across app restarts. Never sent in the body.
    public var idempotencyKey: String?

    public init(
        receiver: String,
        giftId: String,
        quantity: Int? = nil,
        message: String? = nil,
        reference: String? = nil,
        roomId: String? = nil,
        idempotencyKey: String? = nil
    ) {
        self.receiver = receiver
        self.giftId = giftId
        self.quantity = quantity
        self.message = message
        self.reference = reference
        self.roomId = roomId
        self.idempotencyKey = idempotencyKey
    }
}

/// What an effect player needs to show a gift.
public struct GiftEffectEvent: Codable, Sendable, Equatable, Hashable {
    public struct GiftInfo: Codable, Sendable, Equatable, Hashable {
        public var id: String
        public var name: String
        public var price: Int
        /// Large picture shown with the effect (512 px). Falls back to the icon.
        public var image: String?
        /// Small picture for the notice (the 256 px icon). Falls back to `image`.
        public var icon: String?

        public init(id: String, name: String, price: Int, image: String?, icon: String? = nil) {
            self.id = id
            self.name = name
            self.price = price
            self.image = image
            self.icon = icon
        }

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case price
            case image
            case icon
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(price, forKey: .price)
            try c.encode(image, forKey: .image)
            try c.encode(icon, forKey: .icon)
        }
    }

    public var gift: GiftInfo
    /// Who sent it, shown in the notice. Default "Someone".
    public var sender: String?
    /// How many were sent in this one send. Default 1.
    public var quantity: Int?

    public init(gift: GiftInfo, sender: String? = nil, quantity: Int? = nil) {
        self.gift = gift
        self.sender = sender
        self.quantity = quantity
    }

    /// The event for a catalog gift: the big picture is `animationUrl ?? iconUrl`, the notice
    /// picture is `iconUrl` (the one the tray already shows).
    public init(gift: Gift, sender: String? = nil, quantity: Int? = nil) {
        self.gift = GiftInfo(
            id: gift.id,
            name: gift.name,
            price: gift.price,
            image: gift.animationUrl ?? gift.iconUrl,
            icon: gift.iconUrl
        )
        self.sender = sender
        self.quantity = quantity
    }

    enum CodingKeys: String, CodingKey {
        case gift
        case sender
        case quantity
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(gift, forKey: .gift)
        try c.encodeIfPresent(sender, forKey: .sender)
        try c.encodeIfPresent(quantity, forKey: .quantity)
    }
}
