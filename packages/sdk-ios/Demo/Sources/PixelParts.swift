import GiftingStack
import SwiftUI

/// A round initial avatar in the person's colour (the demo has no avatar host).
struct PixelAvatar: View {
    let user: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(giftingHex: PixelData.color(user)))
            Text(verbatim: PixelData.initial(user))
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(Color.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The app logo: four squares on a gradient, and the name.
struct PixelLogo: View {
    let palette: PixelPalette

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color(giftingHex: 0x8B7BFF), Color(giftingHex: 0xFF5FA2)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        square(1)
                        square(0.7)
                    }
                    HStack(spacing: 4) {
                        square(0.7)
                        square(0.45)
                    }
                }
            }
            .frame(width: 28, height: 28)
            Text(verbatim: "Pixel")
                .font(.system(size: 20, weight: .heavy))
                .foregroundColor(palette.text)
        }
    }

    private func square(_ alpha: Double) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white.opacity(alpha))
            .frame(width: 6, height: 6)
    }
}

/// The top bar: the logo (hold it 1 s for the developer menu) and the coin chip.
@MainActor
struct PixelHeader: View {
    @ObservedObject var model: PixelModel
    let palette: PixelPalette

    var body: some View {
        HStack(spacing: 10) {
            PixelLogo(palette: palette)
                .contentShape(Rectangle())
                .gesture(
                    LongPressGesture(minimumDuration: 1)
                        .onEnded { _ in
                            model.devMenuOpen = true
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "Pixel"))
                .accessibilityAction(named: Text(verbatim: "Developer menu")) {
                    model.devMenuOpen = true
                }
            Spacer(minLength: 8)
            Button {
                model.storeOpen = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(giftingHex: 0xFFC83D))
                        .frame(width: 12, height: 12)
                    Text(verbatim: formatCoins(model.balance))
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundColor(palette.text)
                    Text(verbatim: "+")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(palette.accent)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Capsule().fill(palette.card))
                .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(formatCoins(model.balance)) coins. Get coins"))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(palette.background)
        .overlay(Rectangle().fill(palette.line).frame(height: 1), alignment: .bottom)
    }
}

/// Shown while the mock client is told to fail.
struct PixelOfflineBanner: View {
    var body: some View {
        Text(verbatim: "You are offline. Gifts and updates will resume when you reconnect.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Color(giftingHex: 0xC2453D))
            .accessibilityAddTraits(.isStaticText)
    }
}

/// The bottom tab bar: Feed, Top, Inbox (with an unread badge), Me.
@MainActor
struct PixelTabBar: View {
    @ObservedObject var model: PixelModel
    let palette: PixelPalette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PixelTab.allCases) { tab in
                Button {
                    model.select(tab)
                } label: {
                    item(tab)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: label(tab)))
                .accessibilityAddTraits(model.tab == tab ? [.isButton, .isSelected] : [.isButton])
            }
        }
        .padding(.top, 4)
        .background(palette.card.ignoresSafeArea(edges: .bottom))
        .overlay(Rectangle().fill(palette.line).frame(height: 1), alignment: .top)
    }

    private func label(_ tab: PixelTab) -> String {
        if tab == .inbox && model.unread > 0 {
            return "Inbox, \(model.unread) new"
        }
        return tab.rawValue
    }

    private func item(_ tab: PixelTab) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 30, height: 24)
                if tab == .inbox && model.unread > 0 {
                    Text(verbatim: model.unread > 99 ? "99+" : "\(model.unread)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Capsule().fill(palette.accent2))
                        .offset(x: 10, y: -6)
                }
            }
            Text(verbatim: tab.rawValue)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(model.tab == tab ? palette.accent : palette.muted)
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(Rectangle())
    }
}

/// A post: author, picture, text, Like and Gift, and the post's gift wall.
@MainActor
struct PixelPostCard: View {
    @ObservedObject var model: PixelModel
    let post: PixelPost
    let palette: PixelPalette
    let theme: GiftingTheme

    @State private var liked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PixelAvatar(user: post.author, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: PixelData.displayName(post.author))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(palette.text)
                    Text(verbatim: post.ago)
                        .font(.system(size: 12))
                        .foregroundColor(palette.muted)
                }
                Spacer(minLength: 0)
            }
            PixelArtView(kind: post.art)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            Text(verbatim: post.text)
                .font(.system(size: 15))
                .foregroundColor(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    liked.toggle()
                } label: {
                    pill(
                        symbol: liked ? "heart.fill" : "heart",
                        text: formatCoins(post.likes + (liked ? 1 : 0)),
                        tint: liked ? palette.accent2 : palette.text
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: liked ? "Liked" : "Like"))
                Button {
                    // The Gift button opens the tray, and closes it again (the SDK's toggle()).
                    model.giftButton(post)
                } label: {
                    pill(symbol: "gift.fill", text: "Gift", tint: palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "Send \(PixelData.firstName(post.author)) a gift"))
                Spacer(minLength: 0)
            }
            // The post's gift wall: a chip opens the tray with that gift picked.
            GiftWall(
                loader: model.walls,
                user: post.author,
                reference: post.id,
                refreshKey: AnyHashable(model.wallRefresh(post.author, post.id)),
                onPressChip: { chip in
                    model.openTray(post, giftId: chip.id)
                },
                theme: theme
            )
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.line, lineWidth: 1))
    }

    private func pill(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
            Text(verbatim: text)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(tint)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Capsule().fill(palette.background))
        .overlay(Capsule().stroke(palette.line, lineWidth: 1))
        .contentShape(Capsule())
    }
}
