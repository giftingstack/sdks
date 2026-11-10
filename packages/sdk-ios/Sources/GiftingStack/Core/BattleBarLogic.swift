import Foundation

// What the battle bar (SPEC 18.7) shows, as plain data: the split, the clock, the winner, the
// words and the two side colours. Pure Foundation, no UI. Port of
// `packages/sdk-js/src/core/battleBar.ts`; fixture `battle-bar.json`.

/// Every word of the bar. `{name}`, `{a}`, `{b}` mark a place a value goes.
public struct BattleBarLabels: Sendable, Equatable, Hashable {
    /// The small "VS" over the clock.
    public var vs: String
    /// The clock when the round has ended.
    public var finalText: String
    /// Below the bar when a side won.
    public var wins: String
    /// Below the bar when the round ended level.
    public var draw: String
    /// The spoken summary: `{a}, {b}`, each side `side`.
    public var spoken: String
    /// One side, spoken.
    public var side: String
    /// Count suffixes, as in `formatCount`.
    public var thousand: String
    public var million: String

    public init(
        vs: String = "VS",
        finalText: String = "Final",
        wins: String = "{name} wins the round",
        draw: String = "Draw: nobody wins this round",
        spoken: String = "{a}, {b}",
        side: String = "{name} {score}",
        thousand: String = "K",
        million: String = "M"
    ) {
        self.vs = vs
        self.finalText = finalText
        self.wins = wins
        self.draw = draw
        self.spoken = spoken
        self.side = side
        self.thousand = thousand
        self.million = million
    }
}

/// Seconds left on the clock at which it turns urgent.
public let battleUrgentSeconds = 10
/// The boundary never leaves this band, so both sides stay visible (percent of the bar).
public let battleMinSharePct = 6.0

/// A score for the bar: `9,999` in full, then `10K`, `1.2M`.
public func formatBattleScore(_ n: Int, labels: BattleBarLabels = BattleBarLabels()) -> String {
    if n >= 10_000 {
        return formatCount(n, labels: CountLabels(thousand: labels.thousand, million: labels.million))
    }
    return groupThousands(max(0, n))
}

/// Whole seconds, rounded up (a countdown).
private func battleCeilSeconds(_ ms: Int) -> Int {
    Int((Double(ms) / 1000).rounded(.up))
}

/// `m:ss`, rounded up like a countdown.
public func formatBattleClock(_ remainingMs: Int) -> String {
    let secs = max(0, battleCeilSeconds(remainingMs))
    let rest = secs % 60
    return "\(secs / 60):" + (rest < 10 ? "0\(rest)" : "\(rest)")
}

/// One side of the bar.
public struct BattleBarSide: Sendable, Equatable, Hashable {
    public var id: String
    /// The display name (the id when unknown).
    public var name: String
    /// The full score.
    public var units: Int
    /// The short form (`135K`).
    public var score: String
    /// Spoken: `Mia 1,800`.
    public var spoken: String
    /// This side leads while the round is open, or won it.
    public var leads: Bool
    /// The round ended and this side led.
    public var won: Bool
    /// The round ended and the other side led.
    public var lost: Bool
}

/// The bar for one `BattleView`.
public struct BattleBarModel: Sendable, Equatable, Hashable {
    /// Every side, in the server's order: two or more (up to the API's 8).
    public var sides: [BattleBarSide]
    /// The first side's part of the bar, percent, kept inside the visible band (`pcts[0]`).
    public var pct: Double
    /// Every side's part of the bar, percent, summing to 100; none under `battleMinSharePct`
    /// (see `battleSegmentPcts`).
    public var pcts: [Double]
    /// `m:ss`, or the `finalText` label once the round ended.
    public var clock: String
    /// Under `battleUrgentSeconds` and still open.
    public var urgent: Bool
    /// The round has ended.
    public var isFinal: Bool
    /// The winning receiver once ended, else nil (also nil for a draw).
    public var winner: String?
    /// The line under the bar once the round ended; empty before.
    public var banner: String
    /// One sentence for a screen reader: both sides and their scores.
    public var spoken: String
}

/// Every side's part of a bar, percent (SPEC 18.7): `share x 100`, but no side under
/// `battleMinSharePct`: such a side is held at the minimum and the rest share what is left in
/// proportion to their shares, repeated until every part is visible. Sums to 100.
public func battleSegmentPcts(_ shares: [Double]) -> [Double] {
    let n = shares.count
    var pinned = [Bool](repeating: false, count: n)
    var out = [Double](repeating: 0, count: n)
    while true {
        let free = (0..<n).filter { !pinned[$0] }
        let left = 100 - battleMinSharePct * Double(n - free.count)
        let sum = free.reduce(0.0) { $0 + shares[$1] }
        var again = false
        for i in free {
            out[i] = sum > 0 ? shares[i] / sum * left : left / Double(free.count)
            if out[i] < battleMinSharePct {
                pinned[i] = true
                again = true
            }
        }
        if !again {
            break
        }
        for i in 0..<n where pinned[i] {
            out[i] = battleMinSharePct
        }
    }
    for i in 0..<n where pinned[i] {
        out[i] = battleMinSharePct
    }
    return out
}

/// The bar for `view`, or nil when it has fewer than two sides (a round with one receiver has
/// nothing to compare). Every side is a cell of the bar (a free-for-all of up to 8); two sides look
/// exactly as the versus always did.
public func battleBarModel(
    _ view: BattleView?,
    nameOf: (String) -> String = { $0 },
    labels: BattleBarLabels = BattleBarLabels()
) -> BattleBarModel? {
    guard let view = view, view.sides.count >= 2 else {
        return nil
    }
    let ended = !view.open
    func side(_ s: BattleSide) -> BattleBarSide {
        let name = nameOf(s.id)
        return BattleBarSide(
            id: s.id,
            name: name,
            units: s.units,
            score: formatBattleScore(s.units, labels: labels),
            spoken: fillLabel(labels.side, ["name": name, "score": groupThousands(s.units)]),
            leads: view.leader == s.id,
            won: ended && view.leader == s.id,
            lost: ended && view.leader != nil && view.leader != s.id
        )
    }
    let sides = view.sides.map(side)
    let secs = battleCeilSeconds(view.remainingMs)
    let winner = ended ? view.leader : nil
    var banner = ""
    if ended {
        if let winner = winner {
            banner = fillLabel(labels.wins, ["name": sides.first(where: { $0.id == winner })?.name ?? winner])
        } else {
            banner = labels.draw
        }
    }
    let pct = min(100 - battleMinSharePct, max(battleMinSharePct, view.sides[0].share * 100))
    let pcts = sides.count == 2 ? [pct, 100 - pct] : battleSegmentPcts(view.sides.map { $0.share })
    // Two sides: the `spoken` label (`{a}, {b}`); more: every side's text joined by ", ".
    let spoken = sides.count == 2
        ? fillLabel(labels.spoken, ["a": sides[0].spoken, "b": sides[1].spoken])
        : sides.map { $0.spoken }.joined(separator: ", ")
    return BattleBarModel(
        sides: sides,
        pct: sides.count == 2 ? pct : pcts[0],
        pcts: pcts,
        clock: ended ? labels.finalText : formatBattleClock(view.remainingMs),
        urgent: !ended && secs <= battleUrgentSeconds,
        isFinal: ended,
        winner: winner,
        banner: banner,
        spoken: spoken
    )
}

/// A colour and the text colour that reads on it, as `#rrggbb` strings (the colour is as given).
public struct SideColor: Sendable, Equatable, Hashable {
    public var color: String
    public var text: String

    public init(color: String, text: String) {
        self.color = color
        self.text = text
    }
}

/// White or black, whichever contrasts more with `hex`; an unreadable colour string counts as white.
public func battleReadableOn(_ hex: String) -> String {
    if parseHexColor(hex) == nil {
        return "#ffffff"
    }
    return readableOn(hex)
}

/// The third and fourth side colour of the default palette (teal, pink); the fifth side starts over
/// with the theme's accent.
public let battleExtraColors = ["#2ec4b6", "#ff5d8f"]

/// The colour of every side of a bar or notice (SPEC 18.7, 7.4): side `i` takes `override[i]` when the
/// app gave one (text picked by contrast), else the default palette: the theme's accent, its coin colour
/// (each with the theme's own text colour on it, already 4.5:1 in both presets), then
/// `battleExtraColors`, then the same four again.
public func battleSidePalette(_ theme: GiftTheme, count: Int, override: [String]? = nil) -> [SideColor] {
    let defaults =
        [
            SideColor(color: theme.accent, text: theme.accentText),
            SideColor(color: theme.coin, text: theme.coinText),
        ] + battleExtraColors.map { SideColor(color: $0, text: battleReadableOn($0)) }
    return (0..<count).map { i in
        if let o = override, i < o.count, !o[i].isEmpty {
            return SideColor(color: o[i], text: battleReadableOn(o[i]))
        }
        return defaults[i % defaults.count]
    }
}

/// The two side colours: the theme's accent against its coin colour (each with the theme's own text
/// colour on it, already 4.5:1 in both presets), or `override` (text picked by contrast).
/// `battleSidePalette` for any number of sides.
public func battleSideColors(_ theme: GiftTheme, override: [String]? = nil) -> [SideColor] {
    battleSidePalette(theme, count: 2, override: override)
}

/// Which sides gained score since `before` (to pulse them). `before` nil: nobody pulses.
public func battleGains(before: [Int]?, after: [Int]) -> [Bool] {
    after.enumerated().map { index, units in
        guard let before = before else {
            return false
        }
        return units > (index < before.count ? before[index] : units)
    }
}
