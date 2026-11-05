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
        PixelContent(model: model, effects: model.effects, tray: model.tray)
    }
}

@MainActor
private struct PixelContent: View {
    @ObservedObject var model: PixelModel
    @ObservedObject var effects: GiftEffectController
    @ObservedObject var tray: GiftTrayModel

    /// The tray sheet's visible height (the notice sits above it).
    @State private var trayInset: CGFloat = 0

    /// Lets the visual check below move the sheet; the normal demo never calls it.
    @State private var trayHandle = GiftTrayHandle()

    init(model: PixelModel, effects: GiftEffectController, tray: GiftTrayModel) {
        self.model = model
        self.effects = effects
        self.tray = tray
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
                    tabContent(palette, theme)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    PixelTabBar(model: model, palette: palette)
                        .accessibilityHidden(tray.isOpen)
                }

                // Always there: a closed tray is invisible and takes no touches.
                trayLayer(model.trayPost ?? PixelData.posts[0], theme: theme, bottomInset: bottomInset)
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

    /// Above the open tray, else above the tab bar.
    private func noticeBottom(_ bottomInset: CGFloat) -> CGFloat {
        if tray.isOpen && trayInset > 0 {
            return trayInset + 16
        }
        return 56 + bottomInset + 16
    }

    @ViewBuilder
    private func tabContent(_ palette: PixelPalette, _ theme: GiftingTheme) -> some View {
        switch model.tab {
        case .feed:
            PixelFeedTab(model: model, palette: palette, theme: theme)
        case .live:
            PixelLiveTab(model: model, room: model.room, palette: palette)
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
            title: "Gift \(PixelData.firstName(post.author))",
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
}
