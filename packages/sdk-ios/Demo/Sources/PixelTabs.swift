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

/// Live: a gift room with a battle (Mia vs Theo). Everyone watching sees every gift sent with this
/// room id. `GiftRoomModel` plays the others' gifts in the effect layer and publishes the viewer
/// count and the battle; the SDK's `GiftBattleBar` draws it.
@MainActor
struct PixelLiveTab: View {
    @ObservedObject var model: PixelModel
    @ObservedObject var room: GiftRoomModel
    let palette: PixelPalette

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                PixelTitle(text: "Live", palette: palette)
                VStack(alignment: .leading, spacing: 10) {
                    stage
                    HStack(spacing: 10) {
                        PixelAvatar(user: PixelData.liveHost, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: "\(PixelData.firstName(PixelData.liveHost)) vs \(PixelData.firstName(PixelData.liveRival))")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(palette.text)
                            Text(verbatim: "Evening stream battle")
                                .font(.system(size: 12))
                                .foregroundColor(palette.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    // The SDK's battle bar: follows the room and ticks its own clock.
                    GiftBattleBar(
                        room: room,
                        users: [
                            PixelData.liveHost: BattleBarUser(name: PixelData.firstName(PixelData.liveHost)),
                            PixelData.liveRival: BattleBarUser(name: PixelData.firstName(PixelData.liveRival)),
                        ],
                        reducedMotion: model.reducedMotion,
                        theme: model.theme.gifting
                    )
                    // Each side's Gift button sits under that side of the bar.
                    HStack(spacing: 8) {
                        giftButton(PixelData.livePost)
                        Spacer(minLength: 0)
                        giftButton(PixelData.rivalPost)
                    }
                    Text(verbatim: stateText)
                        .font(.system(size: 12))
                        .foregroundColor(palette.muted)
                    feed
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(palette.card))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.line, lineWidth: 1))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .onAppear {
            model.joinLive()
        }
        .onDisappear {
            model.leaveLive()
        }
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
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func giftButton(_ post: PixelPost) -> some View {
        Button {
            // The Gift button opens the tray, and closes it again (the SDK's toggle()).
            model.giftButton(post, roomId: PixelData.liveRoom)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(verbatim: "Gift \(PixelData.firstName(post.author))")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(palette.accent)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(Capsule().fill(palette.background))
            .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Send \(PixelData.firstName(post.author)) a gift in the room"))
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.roomFeed) { item in
                (Text(verbatim: item.sender).fontWeight(.bold)
                    + Text(verbatim: " sent \(item.what)" + (item.to.map { " to \($0)" } ?? "")))
                    .font(.system(size: 13))
                    .foregroundColor(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
