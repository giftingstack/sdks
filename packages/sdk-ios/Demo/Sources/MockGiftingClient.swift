import Foundation
import GiftingStack

/// A stand-in for GiftingStack that lives in the app: same shapes and errors as `/v1/client`, a
/// quarter second of fake network delay. The coin store CREDITS coins (what your server does after
/// a purchase: `POST /v1/users/{id}/credit`); "Reset demo" goes back to 60,000. The developer
/// menu's mock failure switch makes every call fail like a lost connection. Swap it for
/// `GiftingClient(getToken:)` to talk to the real API.
actor MockGiftingClient: GiftingAPI, GiftWallAPI, GiftAwayAPI, GiftLeaderboardAPI, GiftInboxAPI {
    static let startBalance = 60_000
    static let latencyNanos: UInt64 = 250_000_000

    private var balance = MockGiftingClient.startBalance
    private var gifts: [Gift] = demoGifts
    private var sent: [String: GiftTransaction] = [:]
    /// Gifts that reached a wall in this session, per `receiver|reference`, by gift id.
    private var extra: [String: [String: Int]] = [:]
    private var offline = false
    private var hidden = false
    /// `armAway()` arms one summary; acknowledging it disarms it.
    private var awayArmed = false
    private var awayRound = 0
    /// The gifts "ava" received, newest first: the seeded ones plus the incoming ones of this
    /// session.
    private var received: [InboxItem] = MockGiftingClient.seedReceived()
    private var receivedCount = 0

    /// Back to the start (the developer menu's "Reset demo").
    func reset() {
        balance = MockGiftingClient.startBalance
        sent = [:]
        extra = [:]
        hidden = false
        awayArmed = false
        received = MockGiftingClient.seedReceived()
        receivedCount = 0
    }

    // MARK: - Gift inbox

    /// A gift from someone else reaches the signed-in user (what your server would store for
    /// `GET /v1/client/me/inbox`).
    func addInbox(_ gift: Gift, sender: String?, quantity: Int) {
        receivedCount += 1
        received.insert(
            InboxItem(
                id: "gtx_demo_in_\(receivedCount)",
                createdAt: MockGiftingClient.iso(Date()),
                sender: sender,
                gift: InboxGift(id: gift.id, name: gift.name, price: gift.price, iconUrl: gift.iconUrl, animationUrl: gift.animationUrl),
                quantity: quantity,
                units: gift.price * quantity,
                status: "completed"
            ),
            at: 0
        )
    }

    /// The last 24 hours, newest first, in pages: the cursor is `ib1.<offset>`.
    func getInbox(_ query: InboxQuery) async throws -> Inbox {
        try await wait(MockGiftingClient.latencyNanos)
        let now = Date()
        let since = now.addingTimeInterval(-86_400)
        let sinceText = MockGiftingClient.iso(since)
        let window = received.filter { $0.createdAt >= sinceText }
        var offset = 0
        if let cursor = query.cursor, cursor.hasPrefix("ib1."), let n = Int(cursor.dropFirst(4)) {
            offset = max(0, n)
        }
        let limit = min(100, max(1, query.limit ?? 20))
        let end = min(window.count, offset + limit)
        let page = offset < end ? Array(window[offset..<end]) : []
        let more = end < window.count
        return Inbox(
            user: PixelData.me,
            since: sinceText,
            until: MockGiftingClient.iso(now),
            data: page,
            hasMore: more,
            nextCursor: more ? "ib1.\(end)" : nil
        )
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Gifts received before the demo started: from 40 minutes to 23 hours ago, one from a
    /// deleted sender and one reversed (the list hides it).
    private static func seedReceived() -> [InboxItem] {
        // (sender, gift, quantity, minutes ago, status)
        let plan: [(String?, String, Int, Int, String)] = [
            ("zoe", "heart-latte", 2, 40, "completed"),
            ("mateo", "pink-tulip", 1, 95, "completed"),
            (nil, "magic-hat", 1, 180, "completed"),
            ("caleb", "bear-boba", 3, 240, "completed"),
            ("dana", "cool-star", 1, 300, "reversed"),
            ("emma", "treasure-chest", 1, 420, "completed"),
            ("ethan", "pink-tulip", 5, 600, "completed"),
            ("sofia", "rainbow-gem", 1, 800, "completed"),
            ("ben", "heart-latte", 1, 960, "completed"),
            ("aisha", "bear-boba", 2, 1_100, "completed"),
            ("kai", "magic-hat", 1, 1_250, "completed"),
            ("oliver", "pink-tulip", 1, 1_380, "completed"),
        ]
        let now = Date()
        var out: [InboxItem] = []
        for (index, row) in plan.enumerated() {
            guard let gift = demoGifts.first(where: { $0.id == row.1 }) else {
                continue
            }
            out.append(InboxItem(
                id: "gtx_demo_seed_\(index)",
                createdAt: iso(now.addingTimeInterval(-Double(row.3) * 60)),
                sender: row.0,
                gift: InboxGift(id: gift.id, name: gift.name, price: gift.price, iconUrl: gift.iconUrl, animationUrl: gift.animationUrl),
                quantity: row.2,
                units: gift.price * row.2,
                status: row.4
            ))
        }
        return out
    }

    /// Adds coins, like your server after a purchase in your own store.
    func credit(_ coins: Int) {
        balance += max(0, coins)
    }

    /// The catalog the next `getGifts` returns (the live library once it loaded).
    func setGifts(_ list: [Gift]) {
        gifts = list
    }

    /// The mock failure switch: every call fails like a lost connection.
    func setOffline(_ value: Bool) {
        offline = value
    }

    /// The "Hide me from leaderboards" flag of the signed-in person.
    func setHidden(_ value: Bool) {
        hidden = value
    }

    /// Gifts that reached a wall from elsewhere (an incoming gift, "Wall +5").
    func addToWall(_ receiver: String, giftId: String, quantity: Int, reference: String?) {
        let key = "\(receiver)|\(reference ?? "")"
        var mine = extra[key] ?? [:]
        mine[giftId] = (mine[giftId] ?? 0) + quantity
        extra[key] = mine
    }

    private func wait(_ nanos: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanos)
        if offline {
            throw GiftingError(status: 0, type: "network_error", message: "You are offline.")
        }
    }

    func getGifts() async throws -> [Gift] {
        try await wait(MockGiftingClient.latencyNanos)
        return gifts
    }

    func getMe() async throws -> Me {
        try await wait(MockGiftingClient.latencyNanos / 2)
        // livemode false = a test key: the tray shows its "Test mode" badge by itself (SPEC 9), like a real test app.
        return Me(user: PixelData.me, balance: balance, livemode: false)
    }

    func getReceivedGifts(_ user: String) async throws -> [ReceivedGift] {
        try await wait(MockGiftingClient.latencyNanos)
        return DemoComponentData.wall(user, reference: nil, gifts: gifts, extra: extra["\(user)|"] ?? [:])
    }

    func sendGift(_ input: SendGiftInput) async throws -> GiftTransaction {
        try await wait(MockGiftingClient.latencyNanos)
        let key = input.idempotencyKey ?? newIdempotencyKey()
        if let again = sent[key] {
            return again
        }
        guard let gift = gifts.first(where: { $0.id == input.giftId }) else {
            throw GiftingError(status: 404, type: "not_found", message: "Gift not found.")
        }
        let quantity = input.quantity ?? 1
        let total = gift.price * quantity
        if balance < total {
            throw GiftingError(status: 422, type: "insufficient_balance", message: "Insufficient balance.")
        }
        balance -= total
        addToWall(input.receiver, giftId: gift.id, quantity: quantity, reference: input.reference)
        let tx = GiftTransaction(
            id: "gtx_\(key)",
            sender: PixelData.me,
            receiver: input.receiver,
            gift: GiftSummary(id: gift.id, name: gift.name, iconUrl: gift.iconUrl),
            quantity: quantity,
            unitPrice: gift.price,
            total: total,
            message: input.message,
            reference: input.reference,
            status: "completed",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            senderBalanceAfter: balance
        )
        sent[key] = tx
        return tx
    }

    // MARK: - Gift walls

    func queryGiftWalls(_ items: [GiftWallQueryItem]) async throws -> [GiftWallResult] {
        if items.isEmpty {
            return []
        }
        try await wait(MockGiftingClient.latencyNanos)
        var walls: [GiftWallResult] = []
        for item in items {
            let key = "\(item.receiver)|\(item.reference ?? "")"
            let list = DemoComponentData.wall(item.receiver, reference: item.reference, gifts: gifts, extra: extra[key] ?? [:])
            walls.append(GiftWallResult(receiver: item.receiver, reference: item.reference, gifts: list))
        }
        return walls
    }

    // MARK: - While you were away

    /// The next `getAway` returns a full summary (until it is acknowledged).
    func armAway() {
        awayRound += 1
        awayArmed = true
    }

    func getAway(_ query: AwayQuery) async throws -> AwaySummary {
        try await wait(MockGiftingClient.latencyNanos)
        let cursor = "aw1.demo.\(awayRound)"
        if awayArmed {
            return DemoComponentData.awaySummary(cursor: cursor, gifts: gifts)
        }
        return DemoComponentData.emptyAway(cursor: cursor)
    }

    func ackAway(_ cursor: String) async throws {
        try await wait(MockGiftingClient.latencyNanos / 2)
        if cursor == "aw1.demo.\(awayRound)" {
            awayArmed = false
        }
    }

    // MARK: - Leaderboard

    func getLeaderboard(_ board: LeaderboardBoard, query: LeaderboardQuery) async throws -> Leaderboard {
        try await wait(MockGiftingClient.latencyNanos * 2)
        return DemoComponentData.leaderboard(board, query: query, hidden: hidden)
    }
}
