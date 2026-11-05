#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI

/// The gifts the signed-in user received in the last 24 hours, newest first (spec 19.3): one row
/// per gift with the sender's initial avatar, "Name sent you Gift" (and " x3" above one), the gift
/// icon and the age on the right. It loads the first page itself, shows "Show more" while there
/// are older gifts, "No gifts in the last 24 hours" when empty and "Could not load gifts" with
/// "Try again" after a failure. Reversed gifts are hidden. The rows are a plain stack: put the
/// inbox in a `ScrollView` when it can be taller than the screen.
@MainActor
public struct GiftInbox: View {
    @ObservedObject private var model: GiftInboxModel
    private let theme: GiftingTheme
    private let labels: GiftLabels

    /// - Parameters:
    ///   - model: loads and holds the pages.
    ///   - theme: uses `surface`, `text`, `muted`, `accent`, `accentText`, `coin`, `border`.
    ///   - labels: `inboxSentYou`, `inboxQuantity`, `inboxEmpty`, `inboxError`, `showMore`,
    ///     `tryAgain`, `loading` and `someone`.
    public init(
        model: GiftInboxModel,
        theme: GiftingTheme = GiftingTheme(),
        labels: GiftLabels = GiftLabels()
    ) {
        self.model = model
        self.theme = theme
        self.labels = labels
    }

    public var body: some View {
        content(model.state)
            .onAppear {
                model.load()
            }
    }

    @ViewBuilder
    private func content(_ state: GiftInboxState) -> some View {
        switch state.status {
        case .loading:
            skeleton
        case .error:
            VStack(spacing: 10) {
                Text(verbatim: labels.inboxError)
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
            Text(verbatim: labels.inboxEmpty)
                .font(.system(size: 14))
                .foregroundColor(theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        case .ready:
            list(state)
        }
    }

    /// Loading: a few grey rows.
    private var skeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 10) {
                    Circle().fill(theme.border).frame(width: 36, height: 36)
                    RoundedRectangle(cornerRadius: 4).fill(theme.border).frame(width: 140, height: 12)
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4).fill(theme.border).frame(width: 28, height: 12)
                }
                .padding(.horizontal, 10)
                .frame(height: 56)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: labels.loading))
    }

    private func list(_ state: GiftInboxState) -> some View {
        let nowMs = Int((Date().timeIntervalSince1970 * 1000).rounded())
        let rows = model.rows(nowMs: nowMs, someone: labels.someone)
        return VStack(spacing: 0) {
            ForEach(rows) { row in
                rowView(row)
            }
            if state.hasMore {
                showMore(state)
            }
        }
    }

    private func sentence(_ row: InboxRow) -> String {
        var text = row.senderName + " " + labels.inboxSentYou + " " + row.giftName
        if row.quantity > 1 {
            text += fillLabel(labels.inboxQuantity, ["n": String(row.quantity)])
        }
        return text
    }

    private func rowView(_ row: InboxRow) -> some View {
        let avatarUrl: String? = row.sender.flatMap { model.names[$0]?.avatarUrl }
        return HStack(spacing: 10) {
            GiftAvatar(name: row.senderName, url: avatarUrl, size: 36, theme: theme)
            sentenceText(row)
                .font(.system(size: 14))
                .foregroundColor(theme.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            giftIcon(row)
            Text(verbatim: row.time)
                .font(.system(size: 12))
                .foregroundColor(theme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: sentence(row) + ", " + row.time))
    }

    private func sentenceText(_ row: InboxRow) -> Text {
        var rest = " " + labels.inboxSentYou + " " + row.giftName
        if row.quantity > 1 {
            rest += fillLabel(labels.inboxQuantity, ["n": String(row.quantity)])
        }
        return Text(verbatim: row.senderName).fontWeight(.bold) + Text(verbatim: rest)
    }

    @ViewBuilder
    private func giftIcon(_ row: InboxRow) -> some View {
        if row.iconUrl != nil {
            GiftPicture(url: row.iconUrl, size: 32)
                .id(row.iconUrl ?? "")
        } else {
            Circle()
                .fill(theme.coin)
                .frame(width: 24, height: 24)
                .frame(width: 32, height: 32)
        }
    }

    private func showMore(_ state: GiftInboxState) -> some View {
        Button {
            model.loadMore()
        } label: {
            Text(verbatim: labels.showMore)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.text)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(Capsule().fill(theme.surface))
                .overlay(Capsule().stroke(theme.border, lineWidth: 1))
                .opacity(state.loadingMore ? 0.5 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(state.loadingMore)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
#endif
