import GiftingStack
import SwiftUI

/// A section title of a tab.
struct PixelTitle: View {
    let text: String
    let palette: PixelPalette

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 22, weight: .heavy))
            .foregroundColor(palette.text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Feed: the posts, each with a Gift button and its wall.
@MainActor
struct PixelFeedTab: View {
    @ObservedObject var model: PixelModel
    let palette: PixelPalette
    let theme: GiftingTheme

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 14) {
                ForEach(PixelData.posts) { post in
                    PixelPostCard(model: model, post: post, palette: palette, theme: theme)
                }
                Text(verbatim: "Pixel is an example app built on the GiftingStack SDK. Hold the Pixel logo for the developer menu.")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
    }
}

/// Live: a gift room, plain or with a battle (Mia vs Theo). Everyone watching sees every gift sent with this
/// room id. `GiftRoomModel` plays the others' gifts in the effect layer and publishes the viewer
/// count and the battle; the SDK's `GiftBattleBar` draws it. One gift button (SPEC 21.5): the comment
/// bar's `GiftButton` opens the tray with a "Send to" row of the round's sides, and a tap on a side of
/// the bar opens it with that side picked. The comment column over the stream colours a gift line with
/// the receiving side's colour.
@MainActor
struct PixelLiveTab: View {
    @ObservedObject var model: PixelModel
    @ObservedObject var room: GiftRoomModel
    @ObservedObject var tray: GiftTrayModel
    /// The comment field's focus, owned by `PixelContent` (it hides the tab bar while you type).
    let typing: FocusState<Bool>.Binding
    /// How far the comment bar rises: to the keyboard's top while typing, to the tray's top edge while the tray is
    /// open (its `onInsetChange`).
    let lift: CGFloat
    let palette: PixelPalette
    let theme: GiftingTheme

    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    PixelTitle(text: "Live", palette: palette)
                    // The three modes: a plain "Live room" (one host), "Battle" (two hosts) and "Battle 4+" (four hosts
                    // in every round, a free-for-all).
                    HStack(spacing: 8) {
                        ForEach(PixelLiveMode.allCases) { mode in
                            modeButton(mode.rawValue, on: model.liveMode == mode) { model.setLiveMode(mode) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        stage
                        HStack(spacing: 10) {
                            PixelAvatar(user: PixelData.liveHost, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: hosts.map { PixelData.firstName($0) }.joined(separator: model.liveMode == .battle ? " vs " : ", "))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(palette.text)
                                Text(verbatim: subtitle)
                                    .font(.system(size: 12))
                                    .foregroundColor(palette.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        if model.liveMode != .room {
                            // The SDK's battle bar: follows the room and ticks its own clock. A tap on a side picks it in
                            // the tray and opens the tray (SPEC 21.4); the colours are the tray row's and the column's.
                            GiftBattleBar(
                                room: room,
                                users: Dictionary(
                                    uniqueKeysWithValues: PixelData.liveHosts.map { ($0, BattleBarUser(name: PixelData.firstName($0))) }
                                ),
                                sideColors: model.liveSideColors(count: 8),
                                reducedMotion: model.reducedMotion,
                                theme: model.theme.gifting,
                                onPressSide: { id in model.pressSide(id) }
                            )
                        }
                        Text(verbatim: hint)
                            .font(.system(size: 12))
                            .foregroundColor(palette.muted)
                        Text(verbatim: stateText)
                            .font(.system(size: 12))
                            .foregroundColor(palette.muted)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18).fill(palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.line, lineWidth: 1))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            commentBar
                .padding(.bottom, lift)
                .animation(.easeOut(duration: 0.25), value: lift)
        }
        .onAppear {
            model.joinLive()
        }
        .onDisappear {
            model.leaveLive()
        }
    }

    /// The line under the host's name, by mode.
    private var subtitle: String {
        switch model.liveMode {
        case .room:
            return "Evening stream"
        case .battle:
            return "Evening stream battle"
        case .battle4:
            return "Four creators in one round: every side has its own colour"
        }
    }

    /// How to send a gift, by mode (no bar to tap in the plain room).
    private var hint: String {
        if model.liveMode == .room {
            return "Tap the gift button below to send \(PixelData.firstName(PixelData.liveHost)) a gift."
        }
        return "Tap a side of the bar, or the gift button below, to send a gift."
    }

    private var stateText: String {
        switch room.state.status {
        case .open:
            return "You are in the room: everyone watching sees every gift."
        case .closed:
            return "Left the room."
        default:
            return "Connecting..."
        }
    }

    private var stage: some View {
        ZStack(alignment: .top) {
            PixelArtView(kind: .aurora)
                .accessibilityHidden(true)
            HStack {
                Text(verbatim: "LIVE")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(Color.white)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(Color(giftingHex: 0xE5384F)))
                Spacer(minLength: 0)
                Text(verbatim: room.viewers.map { "\(formatCoins($0)) watching" } ?? "...")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.white)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
            }
            .padding(10)
        }
        .frame(height: 210)
        .overlay(column, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// The live comment column over the stream: the newest lines at the bottom, comments and gifts in one column.
    private var column: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(model.roomFeed.prefix(5).reversed())) { item in
                line(item)
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
        .padding(10)
        .animation(.easeOut(duration: 0.2), value: model.roomFeed.first?.id)
    }

    /// One line. A gift line takes the receiving side's colour (its border, dot and the side's name).
    private func line(_ item: PixelRoomFeedItem) -> some View {
        let side: Color? = item.comment ? nil : model.liveSideColor(for: item.receiverId)
        let sender = Text(verbatim: item.sender).fontWeight(.bold)
        let words: Text
        if item.comment {
            words = sender + Text(verbatim: " \(item.what)")
        } else if let to = item.to {
            words = sender + Text(verbatim: " sent \(item.what) to ") + Text(verbatim: to).fontWeight(.bold).foregroundColor(side ?? Color.white)
        } else {
            words = sender + Text(verbatim: " sent \(item.what)")
        }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !item.comment {
                Image(systemName: "gift.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(side ?? Color(giftingHex: 0xFFC83D))
            }
            words
                .font(.system(size: 12))
                .foregroundColor(Color.white)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(side ?? Color.clear, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    /// The comment bar (the app's own live chat): its text field with the SDK's gift button inside, and its own Send.
    /// The gift button swaps the keyboard and the tray (SPEC 20); the tray picks the side (SPEC 21).
    private var commentBar: some View {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            HStack(spacing: 0) {
                TextField("Add a comment", text: $text)
                    .giftTrayInput(tray, focused: typing)
                    .submitLabel(.send)
                    .onSubmit {
                        send()
                    }
                    .font(.system(size: 15))
                    .foregroundColor(palette.text)
                    .padding(.leading, 14)
                    .accessibilityLabel(Text(verbatim: "Comment"))
                GiftButton(tray: tray, theme: theme)
            }
            .background(Capsule().fill(palette.card))
            .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(palette.accent))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .opacity(empty ? 0.5 : 1)
            .accessibilityLabel(Text(verbatim: "Send comment"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.background)
        .overlay(Rectangle().fill(palette.line).frame(height: 1), alignment: .top)
    }

    private func send() {
        model.sendComment(text)
        text = ""
    }

    /// The hosts of the mode the tab is in: one, two, or all four.
    private var hosts: [String] {
        model.liveHostsOnScreen
    }

    private func modeButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(on ? Color.white : palette.text)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Capsule().fill(on ? palette.accent : palette.card))
                .overlay(Capsule().stroke(on ? palette.accent : palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Top: gifters (senders) or creators (receivers), with your own row pinned.
@MainActor
struct PixelTopTab: View {
    @ObservedObject var model: PixelModel
    let palette: PixelPalette
    let theme: GiftingTheme

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                PixelTitle(text: "Top", palette: palette)
                HStack(spacing: 6) {
                    segment(.senders, "Top gifters")
                    segment(.receivers, "Top creators")
                }
                board
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18).fill(palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.line, lineWidth: 1))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var board: some View {
        if model.board == .senders {
            GiftLeaderboard(model: model.senders, metricToggle: true, highlightUser: PixelData.me, theme: theme)
        } else {
            GiftLeaderboard(model: model.receivers, metricToggle: true, highlightUser: PixelData.me, theme: theme)
        }
    }

    private func segment(_ value: LeaderboardBoard, _ title: String) -> some View {
        let on = model.board == value
        return Button {
            model.board = value
        } label: {
            Text(verbatim: title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(on ? Color.white : palette.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(on ? palette.accent : palette.card))
                .overlay(Capsule().stroke(palette.line, lineWidth: on ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
    }
}

/// Inbox: the SDK's `GiftInbox` (who sent the signed-in user which gift in the last 24 hours,
/// newest first, "Show more" for older ones).
@MainActor
struct PixelInboxTab: View {
    @ObservedObject var model: PixelModel
    let palette: PixelPalette
    let theme: GiftingTheme

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                PixelTitle(text: "Inbox", palette: palette)
                GiftInbox(model: model.inbox, theme: theme)
                    .background(RoundedRectangle(cornerRadius: 18).fill(palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }
}

/// Me: the signed-in demo user (ava): balance, "Get coins", received-gifts wall, visibility.
@MainActor
struct PixelMeTab: View {
    @ObservedObject var model: PixelModel
    let palette: PixelPalette
    let theme: GiftingTheme

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [palette.accent, palette.accent2]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: 90)
                    .accessibilityHidden(true)
                HStack(spacing: 12) {
                    PixelAvatar(user: PixelData.me, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: PixelData.displayName(PixelData.me))
                            .font(.system(size: 19, weight: .heavy))
                            .foregroundColor(palette.text)
                        Text(verbatim: "@ava")
                            .font(.system(size: 13))
                            .foregroundColor(palette.muted)
                    }
                }
                HStack(spacing: 0) {
                    stat(formatCoins(model.received), "Gifts received")
                    stat("1.2K", "Followers")
                    stat("318", "Following")
                }
                balance
                Text(verbatim: "Gifts received")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(palette.text)
                GiftWall(
                    loader: model.walls,
                    user: PixelData.me,
                    max: 8,
                    refreshKey: AnyHashable(model.wallRefresh(PixelData.me, nil)),
                    theme: theme
                )
                Toggle(isOn: Binding(get: { model.hidden }, set: { value in model.setHidden(value) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Hide me from leaderboards")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(palette.text)
                        Text(verbatim: "Others will not see your rank")
                            .font(.system(size: 12))
                            .foregroundColor(palette.muted)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.line, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value)
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(palette.text)
            Text(verbatim: label)
                .font(.system(size: 12))
                .foregroundColor(palette.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var balance: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Your coins")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                Text(verbatim: formatCoins(model.balance))
                    .font(.system(size: 24, weight: .heavy).monospacedDigit())
                    .foregroundColor(palette.text)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button {
                model.storeOpen = true
            } label: {
                Text(verbatim: "Get coins")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(Capsule().fill(palette.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.background))
    }
}
