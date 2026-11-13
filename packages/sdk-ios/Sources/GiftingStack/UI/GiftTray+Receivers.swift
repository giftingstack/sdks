#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI

/// The "Send to" row of a battle tray (spec 21.3): the label, then every side (a 30 pt avatar in a 2 pt ring of the
/// side colour; the selected side adds an outer ring and its name), scrolling sideways when they do not fit, and
/// scrolled so the selected side is always in sight. A tap picks the side; it does not send and does not move the
/// sheet.
extension GiftTray {
    /// Avatar, side ring (2 pt) and the picked side's outer ring (2 pt).
    static let receiverAvatarSize: CGFloat = 30

    /// The row is drawn for two or more sides only (one side: the send simply goes to it).
    var showsReceiverRow: Bool {
        receivers.count >= 2
    }

    /// The side shown as picked: `selectedReceiver` (the model's `receiver`), else this view's own pick, else the
    /// first side.
    var shownReceiver: String? {
        resolveReceiver(ids: receivers.map { $0.id }, selected: selectedReceiver ?? receiverPick)
    }

    /// Touch height of a side (the chip itself stays avatar-wide when unselected).
    static let receiverTouchHeight: CGFloat = 44

    var receiverRow: some View {
        let current = shownReceiver
        let ids = receivers.map { $0.id }
        return HStack(spacing: 8) {
            Text(verbatim: sendToLabel)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(theme.muted)
                .lineLimit(1)
                .fixedSize()
                // The group itself carries the label for VoiceOver.
                .accessibilityHidden(true)
            // The row's OWN reader: scrolling it moves only this row, never the sheet or the grid (spec 21.3).
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(receivers.indices, id: \.self) { index in
                            receiverSide(receivers[index], index: index, picked: receivers[index].id == current)
                                .id(receivers[index].id)
                        }
                    }
                }
                .frame(height: GiftTray.receiverTouchHeight)
                // The selected side is always in sight: on appearing, on a new pick and on a new list.
                .onAppear {
                    // After the first layout, or the reader has no frames to scroll to yet.
                    DispatchQueue.main.async { revealReceiver(shownReceiver, proxy: proxy, animated: false) }
                }
                .onChange(of: current) { next in
                    revealReceiver(next, proxy: proxy, animated: true)
                }
                .onChange(of: ids) { _ in
                    DispatchQueue.main.async { revealReceiver(shownReceiver, proxy: proxy, animated: true) }
                }
                .onChange(of: isOpen) { open in
                    if open {
                        DispatchQueue.main.async { revealReceiver(shownReceiver, proxy: proxy, animated: false) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: sendToLabel))
        .accessibilityIdentifier("gift-send-to")
    }

    private func receiverSide(_ receiver: TrayReceiver, index: Int, picked: Bool) -> some View {
        let side = receiverSideColor(receiver, index: index)
        let size = GiftTray.receiverAvatarSize
        return Button {
            pickReceiver(receiver.id)
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    // The picked side's outer ring, in the text colour, around the side ring.
                    if picked {
                        Circle()
                            .strokeBorder(theme.text, lineWidth: 2)
                            .frame(width: size + 8, height: size + 8)
                    }
                    Circle()
                        .strokeBorder(side.color, lineWidth: 2)
                        .frame(width: size + 4, height: size + 4)
                    receiverAvatar(receiver, side: side)
                        .frame(width: size, height: size)
                }
                // Unselected: 34 pt wide (avatar + side ring), so four sides fit a 375 pt phone.
                .frame(width: picked ? size + 8 : size + 4, height: size + 8)
                // Only the selected side shows its name (spec 21.3: four sides fit a 375 pt phone).
                if picked {
                    Text(verbatim: receiver.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(theme.accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 72, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        // The button's label already says the name.
                        .accessibilityHidden(true)
                }
            }
            .opacity(picked ? 1 : 0.55)
            // A 44 pt tall touch area without widening the chip.
            .frame(minHeight: GiftTray.receiverTouchHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A radio of the group: its name and whether it is the picked one.
        .accessibilityLabel(Text(verbatim: receiver.name))
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("gift-send-to-\(receiver.id)")
    }

    @ViewBuilder
    private func receiverAvatar(_ receiver: TrayReceiver, side: (color: Color, text: Color)) -> some View {
        let size = GiftTray.receiverAvatarSize
        let letter = ZStack {
            Circle().fill(side.color)
            Text(verbatim: giftInitial(receiver.name))
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(side.text)
        }
        if let link = receiver.avatarUrl, let target = URL(string: link) {
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

    /// Scrolls the row (its own reader, the least distance) so the whole selected chip is in sight; animated unless
    /// reduced motion or `animated` is false. Nothing else scrolls.
    private func revealReceiver(_ id: String?, proxy: ScrollViewProxy, animated: Bool) {
        guard let id = id, receivers.contains(where: { $0.id == id }) else { return }
        if animated && !reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: nil) }
        } else {
            proxy.scrollTo(id, anchor: nil)
        }
    }

    /// A tap: the view keeps the pick and tells the host when it changed.
    private func pickReceiver(_ id: String) {
        let before = shownReceiver
        receiverPick = id
        if id != before {
            onSelectReceiver?(id)
        }
    }

    /// The side colour (spec 21.3): the receiver's `color`, else the battle palette (SPEC 18.7) of the side's place:
    /// the theme's accent, its coin colour, teal, pink, then the same again. The letter's colour reads on it.
    func receiverSideColor(_ receiver: TrayReceiver, index: Int) -> (color: Color, text: Color) {
        if let own = receiver.color, let color = Color(giftingCSS: own) {
            return (color: color, text: battleReadableOn(own) == "#000000" ? Color.black : Color.white)
        }
        let place = index % (2 + battleExtraColors.count)
        if place == 0 {
            return (color: theme.accent, text: theme.accentText)
        }
        if place == 1 {
            return (color: theme.coin, text: theme.coinText)
        }
        let extra = battleExtraColors[place - 2]
        return (
            color: Color(giftingCSS: extra) ?? theme.accent,
            text: battleReadableOn(extra) == "#000000" ? Color.black : Color.white
        )
    }
}
#endif
