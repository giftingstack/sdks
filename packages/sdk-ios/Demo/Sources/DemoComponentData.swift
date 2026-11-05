import Foundation
import GiftingStack

/// Demo-only mock data for the gift walls, the "while you were away" card and the leaderboard,
/// ported from packages/sdk-js/demo/shared.ts so every platform shows the same numbers.
/// Everything here is what YOUR server would hold; the SDK only reads it through the client.
enum DemoComponentData {
    /// Ten gifts a post might have received (counts from big to small, in catalog order).
    private static let wallCounts = [48, 31, 17, 12, 9, 6, 4, 3, 2, 1]

    /// The wall of `receiver` (and `reference`): catalog gifts with seeded counts, plus `extra`
    /// (gifts that arrived in this session, by gift id).
    static func wall(_ receiver: String, reference: String?, gifts: [Gift], extra: [String: Int]) -> [ReceivedGift] {
        let seed = PixelData.hash("\(receiver)|\(reference ?? "")")
        let kinds = reference == nil ? 12 : 10
        var out: [ReceivedGift] = []
        for (index, gift) in gifts.prefix(kinds).enumerated() {
            let shift = UInt32(min(index, 31))
            let factor = 1 + Int((seed >> shift) % 5)
            var base = wallCounts[index % 10] * factor
            if reference == nil {
                // A profile wall: bigger numbers (the web divides by 0.4).
                base = Int((Double(base) / 0.4).rounded())
            }
            let summary = GiftSummary(id: gift.id, name: gift.name, iconUrl: gift.iconUrl)
            out.append(ReceivedGift(gift: summary, count: base + (extra[gift.id] ?? 0)))
        }
        // The first post is full; the others are quieter: five kinds, or all.
        if let ref = reference, ref != "post_42", seed % 3 == 0 {
            out = Array(out.prefix(5))
        }
        // Gifts of this session that are not among the seeded kinds come after them.
        let shown = Set(out.map { $0.gift.id })
        for id in extra.keys.sorted() where !shown.contains(id) {
            guard let gift = gifts.first(where: { $0.id == id }), let count = extra[id] else {
                continue
            }
            let summary = GiftSummary(id: gift.id, name: gift.name, iconUrl: gift.iconUrl)
            out.append(ReceivedGift(gift: summary, count: count))
        }
        return out
    }

    private static func awayGift(_ gift: Gift) -> AwayGift {
        AwayGift(
            id: gift.id,
            name: gift.name,
            price: gift.price,
            iconUrl: gift.iconUrl,
            animationUrl: gift.animationUrl
        )
    }

    /// What arrived while "ava" was away: five groups, one sender deleted (`user: nil`, shown
    /// as "Someone").
    static func awaySummary(cursor: String, gifts: [Gift]) -> AwaySummary {
        let plan: [(String, Int, [(String?, Int)])] = [
            ("sun-dragon", 1, [("zoe", 1)]),
            ("treasure-chest", 3, [("mateo", 2), ("caleb", 1)]),
            ("magic-hat", 20, [("mateo", 9), (nil, 4), ("emma", 3)]),
            ("heart-latte", 50, [("dana", 30), ("ethan", 15), ("caleb", 5)]),
            ("cool-star", 3, [("emma", 3)]),
        ]
        var groups: [AwayGroup] = []
        // Per sender (nil: the deleted one): count and units, in the order first seen.
        var order: [String?] = []
        var counts: [String: Int] = [:]
        var units: [String: Int] = [:]
        for entry in plan {
            guard let gift = gifts.first(where: { $0.id == entry.0 }) else {
                continue
            }
            let senders = entry.2.map { AwaySender(user: $0.0, count: $0.1) }
            let senderCount = entry.0 == "magic-hat" ? 6 : entry.2.count
            groups.append(AwayGroup(
                gift: awayGift(gift),
                count: entry.1,
                units: gift.price * entry.1,
                senderCount: senderCount,
                senders: senders
            ))
            for sender in entry.2 {
                let key = sender.0 ?? ""
                if counts[key] == nil {
                    order.append(sender.0)
                }
                counts[key] = (counts[key] ?? 0) + sender.1
                units[key] = (units[key] ?? 0) + sender.1 * gift.price
            }
        }
        groups.sort { a, b in
            a.units != b.units ? a.units > b.units : a.gift.id < b.gift.id
        }
        var top: [AwayTopSender] = []
        for user in order {
            let key = user ?? ""
            top.append(AwayTopSender(user: user, count: counts[key] ?? 0, units: units[key] ?? 0))
        }
        top.sort { a, b in
            a.count != b.count ? a.count > b.count : a.units > b.units
        }
        let now = Date()
        let since = now.addingTimeInterval(-(2 * 86_400 + 3 * 3_600))
        let format = ISO8601DateFormatter()
        return AwaySummary(
            user: PixelData.me,
            since: format.string(from: since),
            until: format.string(from: now),
            cursor: cursor,
            truncated: false,
            totalGifts: groups.reduce(0) { $0 + $1.count },
            totalUnits: groups.reduce(0) { $0 + $1.units },
            senderCount: 7,
            groups: groups,
            topSenders: Array(top.prefix(5))
        )
    }

    static func emptyAway(cursor: String) -> AwaySummary {
        let now = ISO8601DateFormatter().string(from: Date())
        return AwaySummary(
            user: PixelData.me,
            since: now,
            until: now,
            cursor: cursor,
            truncated: false,
            totalGifts: 0,
            totalUnits: 0,
            senderCount: 0,
            groups: [],
            topSenders: []
        )
    }

    /// External id, `week` coins, tie group (equal groups score the same).
    private static let boardBase: [(String, Int, Int)] = [
        ("zoe", 54_000, 1),
        ("mateo", 41_000, 2),
        ("caleb", 41_000, 2),
        ("dana", 33_500, 3),
        ("ethan", 28_200, 4),
        ("emma", 19_900, 5),
        ("sofia", 19_900, 5),
        ("ben", 12_300, 6),
        ("aisha", 9_800, 7),
        ("kai", 7_200, 8),
        ("daphne", 5_100, 9),
        ("oliver", 3_900, 10),
        ("ella", 2_450, 11),
        ("mia", 1_800, 12),
        ("theo", 640, 13),
    ]

    private static func factor(_ period: LeaderboardPeriod) -> Double {
        switch period {
        case .day:
            return 0.12
        case .week:
            return 1
        case .month:
            return 3.4
        case .all:
            return 21
        }
    }

    private static func periodLabel(_ period: LeaderboardPeriod) -> String {
        switch period {
        case .day:
            return "2026-10-11"
        case .week:
            return "2026-W41"
        case .month:
            return "2026-10"
        case .all:
            return "all"
        }
    }

    /// A board as the server computes it: sorted by the metric, competition ranks (1, 2, 2, 4),
    /// the top `limit` rows, and the viewer "ava" outside the rows (#417, so pinned).
    static func leaderboard(_ board: LeaderboardBoard, query: LeaderboardQuery, hidden: Bool) -> Leaderboard {
        let period = query.period ?? .week
        let metric = query.metric ?? .units
        let limit = max(1, min(100, query.limit ?? 10))
        let f = factor(period) * (board == .receivers ? 0.8 : 1)
        let still = period == .week && board == .senders
        var scored: [(user: String, units: Int, gifts: Int, index: Int)] = []
        for (index, entry) in boardBase.enumerated() {
            let group = entry.2
            let nudge = Double(Int(PixelData.hash("\(group)|\(period.rawValue)|\(board.rawValue)") % 31) - 15) / 100
            let jitter = 1 + (still ? 0 : nudge)
            let units = max(1, Int((Double(entry.1) * f * jitter).rounded()))
            let avg = 40 + (group * 37) % 160
            let extra = PixelData.hash(entry.0) % 3 == 0 ? 0 : group % 2
            let gifts = max(1, Int((Double(units) / Double(avg)).rounded())) + extra
            scored.append((user: entry.0, units: units, gifts: gifts, index: index))
        }
        let sorted = scored.sorted { a, b in
            let x = metric == .gifts ? a.gifts : a.units
            let y = metric == .gifts ? b.gifts : b.units
            return x != y ? x > y : a.index < b.index
        }
        var rows: [LeaderboardEntry] = []
        var rank = 0
        var previous: Int?
        for (index, entry) in sorted.enumerated() {
            let score = metric == .gifts ? entry.gifts : entry.units
            if previous != score {
                rank = index + 1
                previous = score
            }
            if rows.count < limit {
                rows.append(LeaderboardEntry(rank: rank, user: entry.user, gifts: entry.gifts, units: entry.units))
            }
        }
        var me: LeaderboardMe?
        if query.includeMe != false {
            me = LeaderboardMe(user: PixelData.me, rank: 417, gifts: 3, units: 120, hidden: hidden)
        }
        return Leaderboard(
            board: board.rawValue,
            period: period.rawValue,
            metric: metric.rawValue,
            label: periodLabel(period),
            startsAt: nil,
            endsAt: nil,
            asOf: ISO8601DateFormatter().string(from: Date()),
            data: rows,
            hasMore: sorted.count > limit,
            me: me
        )
    }
}
