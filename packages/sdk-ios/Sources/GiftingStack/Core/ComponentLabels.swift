import Foundation

/// Every visible and spoken word of the gift wall, the "while you were away" card and the
/// leaderboard (same keys and English defaults as the web and React Native components). Change
/// any of them for a translation. `{x}` marks a place a value goes.
public struct GiftLabels: Sendable, Equatable {
    /// Count suffixes of `formatCount`.
    public var thousand = "K"
    public var million = "M"
    /// A deleted sender.
    public var someone = "Someone"

    /// Wall: the row as one element. `{list}` = `"12 Roses, 3 Hearts"`, then `wallMore`.
    public var wallSummary = "Gifts: {list}"
    /// Wall: the end of `{list}` when more gifts exist.
    public var wallMore = "and {n} more"
    /// Wall: a tappable chip, for example `"Rose, 12"`.
    public var wallChip = "{name}, {count}"
    /// Wall: added to a gift name when its count is above 1 (`"12 Roses"`).
    public var plural = "s"
    /// Wall: text shown when nothing was received. Empty (default): the wall draws nothing.
    public var emptyText = ""

    /// Away card.
    public var awayTitle = "While you were away"
    /// `{gifts}` and `{people}` are `giftOne`/`giftOther` and `personOne`/`personOther`.
    public var awaySummary = "{gifts} from {people}"
    public var awayAnnounce = "You received {summary} while you were away"
    public var giftOne = "{n} gift"
    public var giftOther = "{n} gifts"
    public var personOne = "{n} person"
    public var personOther = "{n} people"
    public var dismiss = "Dismiss"

    /// Leaderboard tabs and empty texts, by period.
    public var tabs: [LeaderboardPeriod: String] = [
        .day: "Today", .week: "This week", .month: "This month", .all: "All time",
    ]
    public var empty: [LeaderboardPeriod: String] = [
        .day: "No gifts yet today",
        .week: "No gifts yet this week",
        .month: "No gifts yet this month",
        .all: "No gifts yet",
    ]
    /// Metric switch. Empty (default): the capitalised `coinName`.
    public var metricUnits = ""
    public var metricGifts = "Gifts"
    public var metricSwitch = "Ranked by"
    public var giftsWord = "gifts"
    public var error = "Could not load the leaderboard."
    public var tryAgain = "Try again"
    /// `{rank}` is `"#417"` or `rankOverflow`.
    public var pinned = "You: {rank}"
    public var pinnedSpoken = "Your rank: {rank}, {score}"
    public var rowSpoken = "Rank {rank}, {name}, {score}"
    public var rankOverflow = "1,000+"
    public var loading = "Loading"
    public var updating = "Updating"
    /// Spoken name of the period tabs.
    public var periodSwitch = "Period"

    /// Gift inbox (spec 19.3): the row reads `"{name} {inboxSentYou} {gift}"` plus `inboxQuantity`.
    public var inboxSentYou = "sent you"
    /// Added after the gift name when the quantity is above 1. `{n}` is the quantity.
    public var inboxQuantity = " x{n}"
    public var inboxEmpty = "No gifts in the last 24 hours"
    public var inboxError = "Could not load gifts"
    public var showMore = "Show more"

    public init() {}

    /// The tab title of a period (the English default when missing from `tabs`).
    public func tab(_ period: LeaderboardPeriod) -> String {
        if let text = tabs[period] {
            return text
        }
        return GiftLabels.englishTabs[period] ?? period.rawValue
    }

    /// The empty text of a period (the English default when missing from `empty`).
    public func emptyMessage(for period: LeaderboardPeriod) -> String {
        if let text = empty[period] {
            return text
        }
        return GiftLabels.englishEmpty[period] ?? ""
    }

    /// `K` and `M` for `formatCount`.
    public var countLabels: CountLabels {
        CountLabels(thousand: thousand, million: million)
    }

    private static let englishTabs: [LeaderboardPeriod: String] = [
        .day: "Today", .week: "This week", .month: "This month", .all: "All time",
    ]
    private static let englishEmpty: [LeaderboardPeriod: String] = [
        .day: "No gifts yet today",
        .week: "No gifts yet this week",
        .month: "No gifts yet this month",
        .all: "No gifts yet",
    ]
}

/// `fillLabel("Rank {rank}", ["rank": "1"])` -> `"Rank 1"`. Unknown `{keys}` stay as they are.
public func fillLabel(_ template: String, _ values: [String: String]) -> String {
    var out = ""
    var rest = Substring(template)
    while let open = rest.firstIndex(of: "{") {
        out.append(contentsOf: rest[rest.startIndex..<open])
        let afterOpen = rest.index(after: open)
        guard let close = rest[afterOpen...].firstIndex(of: "}") else {
            out.append(contentsOf: rest[open...])
            return out
        }
        let key = String(rest[afterOpen..<close])
        if let value = values[key] {
            out.append(contentsOf: value)
        } else {
            out.append(contentsOf: rest[open...close])
        }
        rest = rest[rest.index(after: close)...]
    }
    out.append(contentsOf: rest)
    return out
}
