#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI

/// One top sender in `AwaySummaryContext.senders`.
public struct AwaySenderInfo {
    public let user: String?
    /// The display name (from `resolveUsers`), else the id.
    public let name: String
    public let avatarUrl: String?
    public let count: Int
}

/// What `renderSummary` receives: the data the card would show, already computed, and callbacks.
public struct AwaySummaryContext {
    public let summary: AwaySummary
    /// The card title, from the labels.
    public let title: String
    /// `"37 gifts from 12 people"`, as the default card shows it.
    public let headline: String
    /// `"37 gifts"` (`"2,000+ gifts"` when the count was capped).
    public let gifts: String
    /// `"12 people"`.
    public let people: String
    /// Top senders (the default card shows three), names from `resolveUsers` or the id.
    public let senders: [AwaySenderInfo]
    /// Close the card. Your own buttons call this: a tap on custom content does not dismiss.
    public let dismiss: () -> Void
    /// `ackOn: .manual`: mark the summary as seen.
    public let ack: () -> Void
    /// The resolved theme, so your card can match the rest.
    public let theme: GiftingTheme
}

/// "While you were away" (spec 15.5): a card with how many gifts arrived, the top senders and
/// the gifts, while the effect layer replays the biggest groups. Put it over your screen (it
/// fills the space it is given and takes touches only on the card), under the effect layer.
/// Tap or the close button dismisses it; it goes by itself when the replay has ended. Non-modal.
@MainActor
public struct GiftAwaySummary: View {
    @ObservedObject private var model: GiftAwayModel
    private let theme: GiftingTheme
    private let focusOnShow: Bool
    private let renderSummary: ((AwaySummaryContext) -> AnyView?)?

    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var cardFocused: Bool

    /// - Parameters:
    ///   - theme: the card uses `surface`, `text`, `muted`, `accent`, `accentText`, `border`.
    ///   - focusOnShow: move the VoiceOver focus to the card when it appears. Default false.
    ///   - renderSummary: draws the body of the card yourself (return `AnyView(...)`). The card
    ///     still checks, names the senders, keeps its frame (labelled with the title for VoiceOver),
    ///     the effect replay and the acknowledgement. Return nil to draw the default body. With your
    ///     body a tap does not dismiss and there is no close button: call `dismiss()`.
    public init(
        model: GiftAwayModel,
        theme: GiftingTheme = GiftingTheme(),
        focusOnShow: Bool = false,
        renderSummary: ((AwaySummaryContext) -> AnyView?)? = nil
    ) {
        self.model = model
        self.theme = theme
        self.focusOnShow = focusOnShow
        self.renderSummary = renderSummary
    }

    private var reduceMotion: Bool {
        model.reducedMotion ?? systemReduce
    }

    private var cardTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.identity
        }
        return AnyTransition.opacity
            .combined(with: AnyTransition.scale(scale: 0.97))
            .combined(with: AnyTransition.offset(x: 0, y: 16))
    }

    public var body: some View {
        ZStack {
            if let summary = model.card {
                card(summary)
                    .padding(.horizontal, 16)
                    .transition(cardTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.24), value: model.cardVersion)
        .onAppear {
            if model.autoCheck {
                model.check()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && model.autoCheck {
                model.foreground()
            }
        }
        .onChange(of: model.cardVersion) { _ in
            if focusOnShow && model.card != nil {
                cardFocused = true
            }
        }
    }

    private func card(_ summary: AwaySummary) -> AnyView {
        let labels = model.labels
        let gifts = awayCountText(summary.totalGifts, one: labels.giftOne, other: labels.giftOther, truncated: summary.truncated)
        let people = awayCountText(summary.senderCount, one: labels.personOne, other: labels.personOther, truncated: summary.truncated)
        let headline = fillLabel(labels.awaySummary, ["gifts": gifts, "people": people])
        let context = AwaySummaryContext(
            summary: summary,
            title: labels.awayTitle,
            headline: headline,
            gifts: gifts,
            people: people,
            senders: summary.topSenders.map { sender in
                AwaySenderInfo(
                    user: sender.user,
                    name: model.name(of: sender.user),
                    avatarUrl: sender.user.flatMap { model.names[$0]?.avatarUrl },
                    count: sender.count
                )
            },
            dismiss: { model.dismiss() },
            ack: { model.ack() },
            theme: theme
        )
        if let custom = renderSummary?(context) {
            return cardFrame(AnyView(custom), title: labels.awayTitle, dismissOnTap: false)
        }
        let senders = Array(summary.topSenders.prefix(3))
        let defaultBody = VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: labels.awayTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: headline)
                        .font(.system(size: 14))
                        .foregroundColor(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    model.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(theme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: labels.dismiss))
                .padding(.top, -10)
                .padding(.trailing, -10)
            }
            if !senders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<senders.count, id: \.self) { i in
                        senderRow(senders[i])
                    }
                }
            }
            if !summary.groups.isEmpty {
                HStack(spacing: 6) {
                    ForEach(0..<summary.groups.count, id: \.self) { i in
                        GiftCountChip(
                            iconUrl: summary.groups[i].gift.iconUrl,
                            text: formatCount(summary.groups[i].count, labels: labels.countLabels),
                            iconSize: 20,
                            fontSize: 12.5,
                            height: 24,
                            theme: theme
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: summary.groups[i].gift.name + ", " + groupThousands(summary.groups[i].count)))
                    }
                }
            }
        }
        return cardFrame(AnyView(defaultBody), title: labels.awayTitle, dismissOnTap: true)
    }

    /// The card's frame, kept for custom bodies too: padding, surface, border, shadow, the
    /// VoiceOver container labelled with the title and the focus target.
    private func cardFrame(_ content: AnyView, title: String, dismissOnTap: Bool) -> AnyView {
        let framed = content
            .padding(16)
            .frame(maxWidth: 360, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.border, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.3), radius: 18, x: 0, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        let tapped: AnyView
        if dismissOnTap {
            tapped = AnyView(framed.onTapGesture {
                model.dismiss()
            })
        } else {
            tapped = AnyView(framed)
        }
        return AnyView(
            tapped
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityFocused($cardFocused)
        )
    }

    private func senderRow(_ sender: AwayTopSender) -> some View {
        let name = model.name(of: sender.user)
        let picture: String? = sender.user.flatMap { model.names[$0]?.avatarUrl }
        return HStack(spacing: 10) {
            GiftAvatar(name: name, url: picture, size: 28, theme: theme)
            Text(verbatim: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: formatCount(sender.count, labels: model.labels.countLabels))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundColor(theme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name + ", " + groupThousands(sender.count)))
    }
}
#endif
