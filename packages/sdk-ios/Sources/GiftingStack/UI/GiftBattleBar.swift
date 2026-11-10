#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI

/// A person as the bar shows them.
public struct BattleBarUser: Sendable, Equatable {
    public var name: String
    public var avatarUrl: String?

    public init(name: String, avatarUrl: String? = nil) {
        self.name = name
        self.avatarUrl = avatarUrl
    }
}

private let battleAvatar: CGFloat = 40
/// The default colours of the third and fourth side (SPEC 18.7); the palette then starts over.
private func battleExtraColor(_ index: Int) -> Color {
    Color(giftingCSS: battleExtraColors[index]) ?? Color.gray
}
private let battleGold = Color(giftingHex: 0xFFC83D)
/// `1 - (1 - t)^3`, the ease of the web and React Native bars, as a Bezier.
private func battleEaseOut(_ seconds: Double) -> Animation {
    Animation.timingCurve(0.33, 1, 0.68, 1, duration: seconds)
}

/// The battle bar of a round (SPEC 18.7): the receivers with their scores, a countdown, and a split
/// bar whose boundary slides as gifts arrive. Two sides are the classic versus; three or more (up to
/// 8) are a free-for-all: the clock, a row of cells, a bar of proportional segments. It draws
/// `battleView` only; your server starts and ends rounds. Nothing is drawn while the room has no
/// round with two sides. VoiceOver gets one element: the scores, then the result.
///
/// ```swift
/// GiftBattleBar(
///     room: room,
///     users: ["ava": BattleBarUser(name: "Ava"), "mateo": BattleBarUser(name: "Mateo")],
///     theme: .dark
/// )
/// ```
@MainActor
public struct GiftBattleBar: View {
    private let room: GiftRoomModel?
    private let view: BattleView?
    private let users: [String: BattleBarUser]
    private let sideColors: [String]?
    private let reducedMotion: Bool?
    private let tickMs: Int
    private let theme: GiftingTheme
    private let labels: BattleBarLabels

    /// Follows the round of `room` and refreshes the clock every `tickMs` while it is open.
    /// - Parameters:
    ///   - users: names and pictures of the receivers by id. Fallback: the id.
    ///   - sideColors: the side colours, one per side in order (`#rrggbb`, text picked by contrast).
    ///     Default: the theme's accent, its coin colour, then teal and pink, then the same again. A
    ///     shorter list keeps the default for the sides it does not name. Give the room the same list
    ///     (`GiftRoomModel(sideColors:)`).
    ///   - reducedMotion: nil (default): follows the system Reduce Motion setting. Reduced
    ///     motion: no sliding, counting or pulse.
    ///   - tickMs: how often the clock refreshes while a round is open. 0 = never.
    ///   - theme: uses `background`, `border`, `text`, `muted`, `accent`, `accentText`, `coin`,
    ///     `coinText` and `danger`.
    public init(
        room: GiftRoomModel,
        users: [String: BattleBarUser] = [:],
        sideColors: [String]? = nil,
        reducedMotion: Bool? = nil,
        tickMs: Int = 1_000,
        theme: GiftingTheme = GiftingTheme(),
        labels: BattleBarLabels = BattleBarLabels()
    ) {
        self.room = room
        self.view = nil
        self.users = users
        self.sideColors = sideColors
        self.reducedMotion = reducedMotion
        self.tickMs = tickMs
        self.theme = theme
        self.labels = labels
    }

    /// Draws a round you hold yourself (nil: nothing is drawn).
    public init(
        view: BattleView?,
        users: [String: BattleBarUser] = [:],
        sideColors: [String]? = nil,
        reducedMotion: Bool? = nil,
        theme: GiftingTheme = GiftingTheme(),
        labels: BattleBarLabels = BattleBarLabels()
    ) {
        self.room = nil
        self.view = view
        self.users = users
        self.sideColors = sideColors
        self.reducedMotion = reducedMotion
        self.tickMs = 0
        self.theme = theme
        self.labels = labels
    }

    public var body: some View {
        if let room = room {
            BattleBarRoomHost(
                room: room,
                tickMs: tickMs,
                users: users,
                sideColors: sideColors,
                reducedMotion: reducedMotion,
                theme: theme,
                labels: labels
            )
        } else {
            BattleBarDrawing(
                view: view,
                users: users,
                sideColors: sideColors,
                reducedMotion: reducedMotion,
                theme: theme,
                labels: labels
            )
        }
    }
}

/// Reads the room again when its battle changes (published) and on a timer while a round is open.
@MainActor
private struct BattleBarRoomHost: View {
    @ObservedObject var room: GiftRoomModel
    let tickMs: Int
    let users: [String: BattleBarUser]
    let sideColors: [String]?
    let reducedMotion: Bool?
    let theme: GiftingTheme
    let labels: BattleBarLabels

    var body: some View {
        let current = room.battle == nil ? nil : room.battleView()
        if tickMs > 0, current?.open == true {
            // The clock only needs a frame while a round is open.
            TimelineView(.periodic(from: Date(), by: Double(tickMs) / 1000)) { _ in
                drawing(room.battleView())
            }
        } else {
            drawing(current)
        }
    }

    private func drawing(_ view: BattleView?) -> some View {
        BattleBarDrawing(
            view: view,
            users: users,
            sideColors: sideColors,
            reducedMotion: reducedMotion,
            theme: theme,
            labels: labels
        )
    }
}

/// The pixels. Holds what the animations need: the last scores of the round (which side gained)
/// and the pulse of each side.
@MainActor
private struct BattleBarDrawing: View {
    let view: BattleView?
    let users: [String: BattleBarUser]
    let sideColors: [String]?
    let reducedMotion: Bool?
    let theme: GiftingTheme
    let labels: BattleBarLabels

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var lastRound: String?
    @State private var lastUnits: [Int]?
    @State private var pulsing: [Bool] = []
    @State private var announced = ""

    private var still: Bool {
        reducedMotion ?? systemReduceMotion
    }

    private var units: [Int] {
        (view?.sides ?? []).map { $0.units }
    }

    var body: some View {
        let model = battleBarModel(view, nameOf: { users[$0]?.name ?? $0 }, labels: labels)
        Group {
            if let model = model {
                content(model)
            } else {
                EmptyView()
            }
        }
        .onAppear {
            remember()
        }
        .onChange(of: units) { next in
            gained(next)
        }
        .onChange(of: model?.banner ?? "") { banner in
            // VoiceOver reads the result once, when the round ends.
            if !banner.isEmpty, banner != announced {
                announced = banner
                announceForAccessibility(banner)
            } else if banner.isEmpty {
                announced = ""
            }
        }
    }

    private func remember() {
        lastRound = view?.round
        lastUnits = view == nil ? nil : units
    }

    /// Pulses the sides that gained since the last frame of this round (never on the first
    /// frame of a round).
    private func gained(_ next: [Int]) {
        let before = (view?.round == lastRound) ? lastUnits : nil
        let gains = battleGains(before: before, after: next)
        lastRound = view?.round
        lastUnits = view == nil ? nil : next
        if still {
            return
        }
        if pulsing.count < next.count {
            pulsing += [Bool](repeating: false, count: next.count - pulsing.count)
        }
        for index in gains.indices where gains[index] && index < pulsing.count {
            withAnimation(.easeOut(duration: 0.2)) {
                pulsing[index] = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                withAnimation(.easeInOut(duration: 0.3)) {
                    pulsing[index] = false
                }
            }
        }
    }

    /// The colour of every side: the app's, else the default palette (SPEC 18.7).
    private func colors(_ model: BattleBarModel) -> [(color: Color, text: Color)] {
        let defaults: [(color: Color, text: Color)] = [
            (color: theme.accent, text: theme.accentText),
            (color: theme.coin, text: theme.coinText),
        ] + battleExtraColors.indices.map { index in
            (
                color: battleExtraColor(index),
                text: battleReadableOn(battleExtraColors[index]) == "#000000" ? Color.black : Color.white
            )
        }
        return model.sides.indices.map { index -> (color: Color, text: Color) in
            if let over = sideColors, index < over.count, let own = Color(giftingCSS: over[index]) {
                let text: Color = battleReadableOn(over[index]) == "#000000" ? Color.black : Color.white
                return (color: own, text: text)
            }
            return defaults[index % defaults.count]
        }
    }

    private func clockView(_ model: BattleBarModel) -> some View {
        let clockFill = model.isFinal ? theme.accent : theme.background
        let clockBorder = model.isFinal ? Color.clear : (model.urgent ? theme.danger : theme.border)
        let clockText = model.isFinal ? theme.accentText : (model.urgent ? theme.danger : theme.text)
        return VStack(spacing: 3) {
            Text(verbatim: labels.vs)
                .font(.system(size: 10, weight: .black))
                .kerning(1.8)
                .foregroundColor(theme.muted)
            Text(verbatim: model.clock)
                .font(.system(size: 13, weight: .heavy).monospacedDigit())
                .foregroundColor(clockText)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(minWidth: 52)
                .background(Capsule().fill(clockFill))
                .overlay(Capsule().stroke(clockBorder, lineWidth: 1))
        }
        .fixedSize()
    }

    private func content(_ model: BattleBarModel) -> some View {
        let pair = colors(model)
        let spoken = [model.spoken, model.banner].filter { !$0.isEmpty }.joined(separator: ". ")
        let multi = model.sides.count > 2
        return VStack(spacing: 10) {
            if multi {
                // Three or more sides: the clock, a row of cells, a bar of proportional segments.
                clockView(model)
                HStack(alignment: .top, spacing: 6) {
                    ForEach(model.sides.indices, id: \.self) { index in
                        cellView(model.sides[index], color: pair[index], user: users[model.sides[index].id], index: index, many: model.sides.count > 4)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                multiBar(model, colors: pair.map { $0.color })
            } else {
                HStack(alignment: .center, spacing: 8) {
                    sideView(model.sides[0], right: false, color: pair[0], user: users[model.sides[0].id], index: 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    clockView(model)
                    sideView(model.sides[1], right: true, color: pair[1], user: users[model.sides[1].id], index: 1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                splitBar(model, a: pair[0].color, b: pair[1].color)
            }
            if !model.banner.isEmpty {
                Text(verbatim: model.banner)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(theme.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    // MARK: - One cell of three or more sides

    /// A centred cell: avatar (36, 30 from five sides) over the name over the score.
    private func cellView(
        _ side: BattleBarSide,
        color: (color: Color, text: Color),
        user: BattleBarUser?,
        index: Int,
        many: Bool
    ) -> some View {
        let size: CGFloat = many ? 30 : 36
        let ring = side.won ? battleGold : color.color
        let avatar = ZStack {
            Circle().strokeBorder(ring, lineWidth: 2)
            avatarImage(side, color: color, url: user?.avatarUrl, size: size)
                .frame(width: size, height: size)
        }
        .frame(width: size + 8, height: size + 8)
        .overlay(
            Group {
                if side.won {
                    Text(verbatim: "\u{265B}")
                        .font(.system(size: 18))
                        .foregroundColor(battleGold)
                        .offset(y: -14)
                }
            },
            alignment: .top
        )
        return VStack(spacing: 4) {
            avatar
            Text(verbatim: side.name)
                .font(.system(size: many ? 11 : 12, weight: .bold))
                .foregroundColor(theme.text)
                .lineLimit(1)
            BattleCountingScore(value: Double(side.units), labels: labels)
                .font(.system(size: many ? 14 : 17, weight: .heavy).monospacedDigit())
                .foregroundColor(theme.text)
                .lineLimit(1)
                .animation(still ? nil : battleEaseOut(0.65), value: side.units)
        }
        .opacity(side.lost ? 0.5 : 1)
        .scaleEffect(index < pulsing.count && pulsing[index] ? 1.07 : 1)
    }

    // MARK: - One receiver

    private func sideView(
        _ side: BattleBarSide,
        right: Bool,
        color: (color: Color, text: Color),
        user: BattleBarUser?,
        index: Int
    ) -> some View {
        let ring = side.won ? battleGold : color.color
        let avatar = ZStack {
            Circle().strokeBorder(ring, lineWidth: 2)
            avatarImage(side, color: color, url: user?.avatarUrl)
                .frame(width: battleAvatar, height: battleAvatar)
        }
        .frame(width: battleAvatar + 8, height: battleAvatar + 8)
        .overlay(
            Group {
                if side.won {
                    Text(verbatim: "\u{265B}")
                        .font(.system(size: 18))
                        .foregroundColor(battleGold)
                        .offset(x: right ? -2 : 2, y: -14)
                }
            },
            alignment: right ? .topTrailing : .topLeading
        )
        let who = VStack(alignment: right ? .trailing : .leading, spacing: 0) {
            Text(verbatim: side.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(theme.text)
                .lineLimit(1)
            BattleCountingScore(value: Double(side.units), labels: labels)
                .font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundColor(theme.text)
                .lineLimit(1)
                .animation(still ? nil : battleEaseOut(0.65), value: side.units)
        }
        return HStack(spacing: 8) {
            if right {
                who
                avatar
            } else {
                avatar
                who
            }
        }
        .opacity(side.lost ? 0.5 : 1)
        .scaleEffect(index < pulsing.count && pulsing[index] ? 1.07 : 1)
    }

    @ViewBuilder
    private func avatarImage(
        _ side: BattleBarSide,
        color: (color: Color, text: Color),
        url: String?,
        size: CGFloat = battleAvatar
    ) -> some View {
        let letter = ZStack {
            Circle().fill(color.color)
            Text(verbatim: giftInitial(side.name))
                .font(.system(size: size == battleAvatar ? 18 : size * 0.45, weight: .heavy))
                .foregroundColor(color.text)
        }
        if let link = url, let target = URL(string: link) {
            ZStack {
                Circle().fill(theme.border)
                AsyncImage(url: target, content: { phase in
                    Group {
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else if phase.error != nil {
                            letter
                        } else {
                            Color.clear
                        }
                    }
                })
                .frame(width: size, height: size)
                .clipShape(Circle())
            }
        } else {
            letter
        }
    }

    // MARK: - The bar of three or more sides

    /// One segment per side, side `i` in `colors[i]` with the width `pcts[i]` percent, 2 pt white lines
    /// between them. Every width slides (800 ms, ease out cubic) unless reduced motion.
    private func multiBar(_ model: BattleBarModel, colors: [Color]) -> some View {
        GeometryReader { geo in
            let inner = max(0, geo.size.width - 2)
            HStack(spacing: 0) {
                ForEach(model.pcts.indices, id: \.self) { index in
                    Rectangle()
                        .fill(colors[index])
                        .frame(width: inner * CGFloat(model.pcts[index]) / 100, height: 14)
                        .overlay(
                            Rectangle().fill(Color.white).frame(width: index == 0 ? 0 : 2),
                            alignment: .leading
                        )
                }
            }
            .frame(width: inner, height: 14, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .offset(x: 1, y: 1)
            .frame(width: geo.size.width, height: 16, alignment: .topLeading)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border, lineWidth: 1))
            .animation(still ? nil : battleEaseOut(0.8), value: model.pcts)
        }
        .frame(height: 16)
    }

    // MARK: - The split bar

    private func splitBar(_ model: BattleBarModel, a: Color, b: Color) -> some View {
        GeometryReader { geo in
            let inner = max(0, geo.size.width - 2)
            let boundary = inner * CGFloat(model.pct) / 100
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(b)
                // Side A: rounded on the left only (a rounded rectangle plus a square right end).
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7).fill(a)
                    Rectangle()
                        .fill(a)
                        .frame(width: min(7, boundary / 2))
                        .frame(width: boundary, alignment: .trailing)
                }
                .frame(width: boundary, height: 14)
                .offset(x: 1, y: 1)
                RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border, lineWidth: 1)
            }
            // The track is exactly 16 high: the taller marker is an overlay so it never grows the
            // stack (it left a strip of the track's colour under side A).
            .frame(width: geo.size.width, height: 16, alignment: .topLeading)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 4, height: 26)
                    .shadow(color: theme.accent.opacity(0.9), radius: 4)
                    .opacity(model.isFinal ? 0.5 : 1)
                    .offset(x: 1 + boundary - 2, y: -4),
                alignment: .topLeading
            )
            .animation(still ? nil : battleEaseOut(0.8), value: model.pct)
        }
        .frame(height: 16)
    }
}

/// A score that counts up when its value changes inside an animation (SwiftUI interpolates
/// `animatableData`, and the text is rebuilt for every step, in the same short form as the bar).
private struct BattleCountingScore: View, Animatable {
    var value: Double
    let labels: BattleBarLabels

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: formatBattleScore(Int(value.rounded()), labels: labels))
    }
}
#endif
