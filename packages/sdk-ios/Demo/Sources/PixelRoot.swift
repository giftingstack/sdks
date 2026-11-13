import GiftingStack
import SwiftUI

/// "Pixel": a pretend social app around the SDK, on a mock client. One example integration of
/// GiftingStack, not the product itself. What a customer would write: the effect layer, the tray,
/// one `GiftWall` per post, the `GiftAwaySummary` over the screen and a `GiftLeaderboard`.
/// Everything else (feed, tabs, coin store, developer menu) is the demo's own fake app.
@MainActor
struct PixelRoot: View {
    @StateObject private var model = PixelModel()

    var body: some View {
        PixelContent(model: model, effects: model.effects, tray: model.tray, chatTray: model.chatTray, liveTray: model.liveTray)
    }
}

@MainActor
private struct PixelContent: View {
    @ObservedObject var model: PixelModel
    @ObservedObject var effects: GiftEffectController
    @ObservedObject var tray: GiftTrayModel
    @ObservedObject var chatTray: GiftTrayModel
    @ObservedObject var liveTray: GiftTrayModel

    /// The tray sheet's visible height (the notice sits above it).
    @State private var trayInset: CGFloat = 0

    /// Lets the visual check below move the sheet; the normal demo never calls it.
    @State private var trayHandle = GiftTrayHandle()

    /// The Chat tab and the Live tab's comment bar (one is on screen at a time): the tray sheet's visible height,
    /// and the focus of the message field.
    @State private var chatInset: CGFloat = 0
    @FocusState private var chatTyping: Bool

    init(model: PixelModel, effects: GiftEffectController, tray: GiftTrayModel, chatTray: GiftTrayModel, liveTray: GiftTrayModel) {
        self.model = model
        self.effects = effects
        self.tray = tray
        self.chatTray = chatTray
        self.liveTray = liveTray
    }

    var body: some View {
        GeometryReader { geometry in
            let palette = model.theme.palette
            let theme = model.theme.gifting
            let bottomInset = geometry.safeAreaInsets.bottom
            ZStack {
                palette.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    PixelHeader(model: model, palette: palette)
                    if model.offline {
                        PixelOfflineBanner()
                    }
                    tabContent(palette, theme, bottomInset: bottomInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !chatBarUp {
                        PixelTabBar(model: model, palette: palette)
                            .accessibilityHidden(tray.isOpen)
                    }
                }

                // Always there: a closed tray is invisible and takes no touches.
                trayLayer(model.trayPost ?? PixelData.posts[0], theme: theme, bottomInset: bottomInset)
                // The Chat tab's tray, once its message field is bound (so it is closed from the start).
                if model.tab == .chat && chatTray.inputBound {
                    chatTrayLayer(chatTray, theme: theme, bottomInset: bottomInset, dim: false)
                }
                // The Live tab's tray: the comment bar's gift button, or a tap on a side of the battle bar.
                if model.tab == .live && liveTray.inputBound {
                    chatTrayLayer(liveTray, theme: theme, bottomInset: bottomInset, dim: true)
                }
                if tray.isOpen {
                    // The tab bar stays in view and in reach below the tray (the tray's Send
                    // button never sits on top of it).
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        PixelTabBar(model: model, palette: palette)
                    }
                }

                if model.storeOpen {
                    CoinStoreView(
                        bottomInset: bottomInset,
                        onBuy: { coins in model.buy(coins) },
                        onClose: { model.storeOpen = false }
                    )
                    .ignoresSafeArea()
                }

                // "While you were away": over the app, under the effect layer (the replay plays
                // over it). Touches pass through except on the card.
                GiftAwaySummary(model: model.away, theme: theme)

                if model.devMenuOpen {
                    PixelDevMenu(model: model, palette: palette)
                }

                GiftEffectLayer(
                    controller: effects,
                    quality: model.quality,
                    reducedMotion: model.reducedMotion,
                    noticeBottom: noticeBottom(bottomInset),
                    theme: theme
                )
                .ignoresSafeArea()
            }
        }
        // Only the Chat tab has a text field; it moves its own message bar above the keyboard (`chatLift`), so
        // the rest of the screen and `bottomInset` stay where they are while the keyboard is up.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(model.theme.isLight ? ColorScheme.light : ColorScheme.dark)
        .onAppear {
            model.start()
        }
        .task {
            // Visual check in CI (`xcrun simctl launch ... -gs-autoplay`): without the argument the
            // demo behaves exactly as before.
            guard ProcessInfo.processInfo.arguments.contains("-gs-autoplay") else {
                return
            }
            await runAutoplay()
        }
    }

    /// Opens the tray, moves the sheet through every height, closes it and opens it once more, on a
    /// fixed timeline, so a screen recording shows how the tray opens, drags and closes. Not part of
    /// the product.
    private func runAutoplay() async {
        func wait(_ seconds: Double) async {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        let post = PixelData.posts[0]
        await wait(2.0)
        model.openTray(post)
        await wait(2.5)
        trayHandle.snapTo(.expanded)
        await wait(2.0)
        trayHandle.snapTo(.peek)
        await wait(1.5)
        trayHandle.snapTo(.default)
        await wait(1.5)
        tray.close()
        await wait(1.5)
        model.openTray(post)
        await wait(2.5)
        tray.close()
    }

    /// Above the open tray, else above the tab bar (on the Chat and Live tabs: above the message bar).
    private func noticeBottom(_ bottomInset: CGFloat) -> CGFloat {
        if barTray != nil {
            let tabBar: CGFloat = chatBarUp ? 0 : 56
            let barTop: CGFloat = bottomInset + chatLift(bottomInset) + PixelContent.messageBarHeight + tabBar
            return barTop + 16
        }
        if tray.isOpen && trayInset > 0 {
            return trayInset + 16
        }
        return 56 + bottomInset + 16
    }

    /// About the height of the message bar of the Chat and Live tabs (for the notice).
    private static let messageBarHeight: CGFloat = 60

    /// The tray bound to the message bar of the tab on screen: the Chat tab's, or the Live tab's comment bar
    /// (SPEC 21.5). nil on the other tabs.
    private var barTray: GiftTrayModel? {
        switch model.tab {
        case .chat:
            return chatTray
        case .live:
            return liveTray
        default:
            return nil
        }
    }

    /// The Chat or Live tab while you type or while its tray is open: the tab bar makes room (like a messaging
    /// app), so the message bar sits right on the keyboard or the tray.
    private var chatBarUp: Bool {
        guard let bound = barTray else {
            return false
        }
        return chatTyping || bound.isOpen
    }

    /// How far the message bar rises: to the tray's top edge (`onInsetChange`), or to the keyboard's top while you
    /// type (the last keyboard height the tray model saw, 300 before the first).
    private func chatLift(_ bottomInset: CGFloat) -> CGFloat {
        guard let bound = barTray else {
            return 0
        }
        if bound.isOpen && chatInset > 0 {
            return max(0, chatInset - bottomInset)
        }
        if chatTyping {
            return max(0, CGFloat(bound.keyboardHeight ?? 300) - bottomInset)
        }
        return 0
    }

    @ViewBuilder
    private func tabContent(_ palette: PixelPalette, _ theme: GiftingTheme, bottomInset: CGFloat) -> some View {
        switch model.tab {
        case .feed:
            PixelFeedTab(model: model, palette: palette, theme: theme)
        case .live:
            PixelLiveTab(
                model: model,
                room: model.liveRoom,
                tray: liveTray,
                typing: $chatTyping,
                lift: chatLift(bottomInset),
                palette: palette,
                theme: theme
            )
        case .chat:
            PixelChatTab(
                model: model,
                tray: chatTray,
                typing: $chatTyping,
                lift: chatLift(bottomInset),
                palette: palette,
                theme: theme
            )
        case .top:
            PixelTopTab(model: model, palette: palette, theme: theme)
        case .inbox:
            PixelInboxTab(model: model, palette: palette, theme: theme)
        case .me:
            PixelMeTab(model: model, palette: palette, theme: theme)
        }
    }

    /// The tray for one post: a bottom sheet over a dimmed backdrop. Picking a gift lowers the
    /// sheet (collapseOnSelect) and the dim goes away while it is low; a tap on the dim closes the
    /// tray (scrimTap: .dismiss), and so does the Gift button (tray.toggle(), everywhere).
    private func trayLayer(_ post: PixelPost, theme: GiftingTheme, bottomInset: CGFloat) -> some View {
        GiftTray(
            // Gifts, balance, Send, the open state and the "Test mode" badge (the mock answers livemode false)
            // come from the model.
            tray: tray,
            onTopUp: { model.storeOpen = true },
            title: "Send a gift",
            defaultSelectedId: model.trayGiftId ?? model.selectedId,
            bottomPadding: 14 + bottomInset + 56,
            theme: theme,
            onInsetChange: { inset in trayInset = inset },
            onSelect: { gift in model.selectedId = gift.id },
            collapseOnSelect: true,
            handle: trayHandle,
            scrim: true,
            scrimTap: .dismiss
        )
        .ignoresSafeArea()
        .id(model.trayToken)
    }

    /// The tray of the Chat tab or of the Live tab's comment bar (SPEC 20.5): the message field is bound, so it opens
    /// in the keyboard's place (the Chat tab without a dim, the Live tab with one that a tap closes); picking
    /// a gift lowers it; `onInsetChange` lifts the message bar above it as the keyboard would. The live tray has
    /// `receivers`, so it shows its "Send to" row (SPEC 21).
    private func chatTrayLayer(_ bound: GiftTrayModel, theme: GiftingTheme, bottomInset: CGFloat, dim: Bool) -> some View {
        GiftTray(
            tray: bound,
            onTopUp: { model.storeOpen = true },
            bottomPadding: 14 + bottomInset,
            theme: theme,
            onInsetChange: { inset in chatInset = inset },
            collapseOnSelect: true,
            // The Live tab dims the stream and a tap on empty space closes the tray; the Chat tab keeps the
            // conversation in sight and touchable (no dim).
            scrim: dim,
            scrimTap: .dismiss
        )
        .ignoresSafeArea()
        .onDisappear {
            chatInset = 0
        }
    }
}
