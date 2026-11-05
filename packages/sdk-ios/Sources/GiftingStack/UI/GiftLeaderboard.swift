#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI

/// What `renderRow` receives for one ranked row.
public struct LeaderboardRowContext {
    public let entry: LeaderboardEntry
    public let rank: Int
    /// The display name (from `resolveUsers`), else the id.
    public let name: String
    public let avatarUrl: String?
    public let metric: LeaderboardMetric
    /// The score for the shown metric: coins (`.units`) or gifts.
    public let score: Int
    /// The score as the default row shows it (`54K`).
    public let scoreText: String
    /// Whether this is the highlighted (signed-in) person.
    public let isMe: Bool
    /// The resolved theme, so your row can match the rest.
    public let theme: GiftingTheme
}

/// Top senders or receivers, by coins or by gifts, for today, this week, this month or all time
/// (spec 16.4). Tabs, an optional metric switch, rows with a medal disc for ranks 1 to 3, the
/// viewer's own row highlighted, or pinned under the list ("You: #417") when it is outside the
/// shown rows. A failed first load shows a message and "Try again". The rows are a plain stack:
/// put the board in a `ScrollView` when it can be taller than the screen.
@MainActor
public struct GiftLeaderboard: View {
    @ObservedObject private var model: GiftLeaderboardModel
    private let metricToggle: Bool
    private let highlightUser: String?
    private let renderRow: ((LeaderboardRowContext) -> AnyView?)?
    private let onPressUser: ((String) -> Void)?
    private let theme: GiftingTheme
    private let labels: GiftLabels
    private let coinName: String
    private let rankColors: GiftRankColors

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - metricToggle: show the coins / gifts switch. Default false.
    ///   - highlightUser: the row to highlight. nil (default): the signed-in viewer (`me.user`).
    ///   - renderRow: draws the inside of each ranked row yourself (return `AnyView(...)`). The
    ///     board still loads, orders, names, highlights and pins; it keeps the row container, its
    ///     spoken label and the press. Return nil to draw the default rank, avatar, name and score.
    ///     The pinned "You: #417" row stays the default. A custom row may be taller than 52 pt.
    ///   - onPressUser: makes every row a button.
    ///   - theme: uses `surface`, `text`, `muted`, `accent`, `accentText`, `selected`, `coin`,
    ///     `border`, and `noticeBigText` for the number on a medal.
    ///   - coinName: the currency in spoken labels and the metric switch. Default "coins".
    ///   - rankColors: the medal discs (spec 16.2). Default `GiftRankColors.standard`.
    public init(
        model: GiftLeaderboardModel,
        metricToggle: Bool = false,
        highlightUser: String? = nil,
        renderRow: ((LeaderboardRowContext) -> AnyView?)? = nil,
        onPressUser: ((String) -> Void)? = nil,
        theme: GiftingTheme = GiftingTheme(),
        labels: GiftLabels = GiftLabels(),
        coinName: String = "coins",
        rankColors: GiftRankColors = GiftRankColors.standard
    ) {
        self.model = model
        self.metricToggle = metricToggle
        self.highlightUser = highlightUser
        self.renderRow = renderRow
        self.onPressUser = onPressUser
        self.theme = theme
        self.labels = labels
        self.coinName = coinName
        self.rankColors = rankColors
    }

    public var body: some View {
        let state = model.state
        return VStack(alignment: .leading, spacing: 10) {
            if state.periods.count > 1 {
                tabs(state)
            }
            if metricToggle {
                metricSwitch(state)
            }
            if state.periods.count <= 1 && !metricToggle && state.refreshing {
                HStack {
                    Spacer(minLength: 0)
                    spinner
                }
            }
            content(state)
        }
        .onAppear {
            model.start()
        }
        .onDisappear {
            model.stop()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var spinner: some View {
        if !reduceMotion {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 20, height: 20)
                .accessibilityLabel(Text(verbatim: labels.updating))
        }
    }

    private func tabs(_ state: LeaderboardState) -> some View {
        HStack(spacing: 4) {
            ForEach(state.periods, id: \.self) { period in
                let selected = period == state.period
                Button {
                    model.setPeriod(period)
                } label: {
                    Text(verbatim: labels.tab(period))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selected ? theme.accentText : theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Capsule().fill(selected ? theme.accent : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
            }
            if state.refreshing && !metricToggle {
                spinner
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: labels.periodSwitch))
    }

    private var unitsTitle: String {
        if !labels.metricUnits.isEmpty {
            return labels.metricUnits
        }
        return coinName.prefix(1).uppercased() + String(coinName.dropFirst())
    }

    private func metricSwitch(_ state: LeaderboardState) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: labels.metricSwitch)
                .font(.system(size: 12))
                .foregroundColor(theme.muted)
            metricButton(.units, title: unitsTitle, state: state)
            metricButton(.gifts, title: labels.metricGifts, state: state)
            Spacer(minLength: 0)
            if state.refreshing {
                spinner
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: labels.metricSwitch))
    }

    private func metricButton(_ metric: LeaderboardMetric, title: String, state: LeaderboardState) -> some View {
        let selected = state.metric == metric
        return Button {
            model.setMetric(metric)
        } label: {
            Text(verbatim: title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selected ? theme.accentText : theme.text)
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .background(Capsule().fill(selected ? theme.accent : theme.surface))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: - Body

    @ViewBuilder
    private func content(_ state: LeaderboardState) -> some View {
        switch state.status {
        case .loading:
            skeleton
        case .error:
            VStack(spacing: 10) {
                Text(verbatim: labels.error)
                    .font(.system(size: 14))
                    .foregroundColor(theme.text)
                    .multilineTextAlignment(.center)
                Button {
                    model.refresh()
                } label: {
                    Text(verbatim: labels.tryAgain)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(theme.accentText)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(theme.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        case .empty:
            Text(verbatim: labels.emptyMessage(for: state.period))
                .font(.system(size: 14))
                .foregroundColor(theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        case .ready:
            if let data = state.data {
                if isWaitingForNames(data, pinned: state.pinned) {
                    skeleton
                } else {
                    rows(data, pinned: state.pinned)
                }
            }
        }
    }

    private func isWaitingForNames(_ data: Leaderboard, pinned: LeaderboardMe?) -> Bool {
        if data.data.contains(where: { model.asking.contains($0.user) }) {
            return true
        }
        if let me = pinned, model.asking.contains(me.user) {
            return true
        }
        return false
    }

    /// Loading: `limit` grey rows.
    private var skeleton: some View {
        let count = max(1, min(100, model.controller.limit))
        return VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 10) {
                    Circle().fill(theme.border).frame(width: 28, height: 28)
                    Circle().fill(theme.border).frame(width: 32, height: 32)
                    RoundedRectangle(cornerRadius: 4).fill(theme.border).frame(width: 110, height: 12)
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4).fill(theme.border).frame(width: 44, height: 12)
                }
                .padding(.horizontal, 10)
                .frame(height: 52)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: labels.loading))
    }

    private func rows(_ board: Leaderboard, pinned: LeaderboardMe?) -> some View {
        let mine = highlightUser ?? board.me?.user
        return VStack(spacing: 0) {
            ForEach(0..<board.data.count, id: \.self) { i in
                row(board.data[i], board: board, mine: board.data[i].user == mine)
            }
            if let me = pinned {
                pinnedRow(me, board: board)
                    .padding(.top, 6)
            }
        }
    }

    private func isGifts(_ board: Leaderboard) -> Bool {
        board.metric == "gifts"
    }

    /// `"54,000 coins"` or `"120 gifts"`: the score as it is spoken.
    private func spokenScore(_ n: Int, gifts: Bool) -> String {
        groupThousands(n) + " " + (gifts ? labels.giftsWord : coinName)
    }

    @ViewBuilder
    private func row(_ entry: LeaderboardEntry, board: Leaderboard, mine: Bool) -> some View {
        let gifts = isGifts(board)
        let score = gifts ? entry.gifts : entry.units
        let name = model.name(of: entry.user)
        let spoken = fillLabel(labels.rowSpoken, [
            "rank": String(entry.rank),
            "name": name,
            "score": spokenScore(score, gifts: gifts),
        ])
        if let press = onPressUser {
            Button {
                press(entry.user)
            } label: {
                rowBody(entry, name: name, score: score, gifts: gifts, mine: mine)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: spoken))
        } else {
            rowBody(entry, name: name, score: score, gifts: gifts, mine: mine)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: spoken))
        }
    }

    @ViewBuilder
    private func rowBody(_ entry: LeaderboardEntry, name: String, score: Int, gifts: Bool, mine: Bool) -> some View {
        let context = LeaderboardRowContext(
            entry: entry,
            rank: entry.rank,
            name: name,
            avatarUrl: model.names[entry.user]?.avatarUrl,
            metric: gifts ? .gifts : .units,
            score: score,
            scoreText: gifts ? groupThousands(score) : formatCount(score, labels: labels.countLabels),
            isMe: mine,
            theme: theme
        )
        if let custom = renderRow?(context) {
            custom
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(mine ? theme.selected : Color.clear))
                .contentShape(Rectangle())
        } else {
            defaultRowBody(entry, name: name, score: score, gifts: gifts, mine: mine)
        }
    }

    private func defaultRowBody(_ entry: LeaderboardEntry, name: String, score: Int, gifts: Bool, mine: Bool) -> some View {
        HStack(spacing: 10) {
            rankBadge(entry.rank)
            GiftAvatar(name: name, url: model.names[entry.user]?.avatarUrl, size: 32, theme: theme)
            Text(verbatim: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            scoreView(score, gifts: gifts)
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 12).fill(mine ? theme.selected : Color.clear))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rankBadge(_ rank: Int) -> some View {
        if let hex = rankColors.color(for: rank) {
            ZStack {
                Circle().fill(Color(giftingCSS: hex) ?? theme.coin)
                Text(verbatim: String(rank))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundColor(theme.noticeBigText)
            }
            .frame(width: 28, height: 28)
        } else {
            Text(verbatim: String(rank))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundColor(theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 28, height: 28)
        }
    }

    private func scoreView(_ n: Int, gifts: Bool) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: formatCount(n, labels: labels.countLabels))
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundColor(theme.text)
            if gifts {
                Text(verbatim: labels.giftsWord)
                    .font(.system(size: 12))
                    .foregroundColor(theme.muted)
            } else {
                Circle().fill(theme.coin).frame(width: 10, height: 10)
            }
        }
    }

    private func pinnedRow(_ me: LeaderboardMe, board: Leaderboard) -> some View {
        let gifts = isGifts(board)
        let score = gifts ? me.gifts : me.units
        let rankText = leaderboardRankLabel(me.rank, overflow: labels.rankOverflow)
        var spokenRank = labels.rankOverflow
        if let rank = me.rank {
            spokenRank = groupThousands(rank)
        }
        let spoken = fillLabel(labels.pinnedSpoken, ["rank": spokenRank, "score": spokenScore(score, gifts: gifts)])
        return HStack(spacing: 10) {
            Text(verbatim: fillLabel(labels.pinned, ["rank": rankText]))
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundColor(theme.text)
                .lineLimit(1)
            Text(verbatim: model.name(of: me.user))
                .font(.system(size: 14))
                .foregroundColor(theme.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            scoreView(score, gifts: gifts)
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.selected))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.accent, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }
}
#endif
