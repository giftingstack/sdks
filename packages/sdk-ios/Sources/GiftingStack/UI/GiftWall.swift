#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI

/// Chip size of a `GiftWall`: `sm` icon 16 / text 11 / height 20, `md` icon 20 / text 12.5 /
/// height 24 (spec 14.5).
public enum GiftWallSize: String, Sendable, Hashable {
    case sm
    case md
}

/// What `renderChip` receives for one gift chip.
public struct WallChipContext {
    public let gift: GiftSummary
    /// The exact count.
    public let count: Int
    /// The count as the default chip shows it (`1.2K`).
    public let countText: String
    /// The resolved theme, so your chip can match the rest.
    public let theme: GiftingTheme
}

/// Loads one wall through the shared `GiftWallLoader` and publishes its counters.
@MainActor
final class GiftWallModel: ObservableObject {
    /// nil while loading (skeleton chips).
    @Published private(set) var gifts: [ReceivedGift]?
    private var generation = 0

    /// (Re)start for a wall: a fresh cache hit at once, else a request (fading in when it lands).
    func begin(_ loader: GiftWallLoader, user: String, reference: String?, animate: Bool, onError: ((GiftingError) -> Void)?) {
        generation += 1
        if let cached = loader.peek(user, reference: reference) {
            gifts = cached
            return
        }
        gifts = nil
        load(loader, user: user, reference: reference, animate: animate, onError: onError)
    }

    /// `refreshKey` changed: ask the server again; what is shown stays until the answer.
    func refetch(_ loader: GiftWallLoader, user: String, reference: String?, onError: ((GiftingError) -> Void)?) {
        loader.invalidate(user, reference: reference)
        load(loader, user: user, reference: reference, animate: false, onError: onError)
    }

    private func load(_ loader: GiftWallLoader, user: String, reference: String?, animate: Bool, onError: ((GiftingError) -> Void)?) {
        generation += 1
        let token = generation
        Task { [weak self] in
            do {
                let list = try await loader.load(user, reference: reference)
                guard let self = self, token == self.generation else {
                    return
                }
                if animate {
                    withAnimation(.easeOut(duration: 0.12)) {
                        self.gifts = list
                    }
                } else {
                    self.gifts = list
                }
            } catch {
                guard let self = self, token == self.generation else {
                    return
                }
                // A wall is decoration: keep what is shown (nothing, on the first load).
                if self.gifts == nil {
                    self.gifts = []
                }
                onError?(asGiftingError(error))
            }
        }
    }
}

/// The wall being shown: a new one starts over.
private struct GiftWallKey: Equatable {
    let user: String
    let reference: String?
}

/// Gift chips under a post or on a profile: `[rose 12] [heart 3] [+37]` (spec 14.5). Read-only;
/// with `onPressChip` each chip is a button. The walls of a screen share one `GiftWallLoader`:
/// calls made within 50 ms share one request and each answer is reused for a minute. Nothing is
/// drawn when there is nothing to show or the request failed (a wall is decoration).
///
/// ```swift
/// let walls = GiftWallLoader(client: client)   // one per app or screen
/// GiftWall(loader: walls, user: post.author, reference: post.id)
/// ```
@MainActor
public struct GiftWall: View {
    private let loader: GiftWallLoader
    private let user: String
    private let reference: String?
    private let maxChips: Int
    private let order: WallOrder
    private let size: GiftWallSize
    private let data: [ReceivedGift]?
    private let refreshKey: AnyHashable?
    private let renderChip: ((WallChipContext) -> AnyView?)?
    private let onPressChip: ((GiftSummary) -> Void)?
    private let onError: ((GiftingError) -> Void)?
    private let theme: GiftingTheme
    private let labels: GiftLabels

    @StateObject private var model: GiftWallModel
    @State private var width: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - loader: shared by every wall of the screen (`GiftWallLoader(client:)`).
    ///   - user: the receiver's external id.
    ///   - reference: your content id (for example a post id). nil: the person's profile wall.
    ///   - max: chips shown, the overflow chip included. Default 6.
    ///   - order: `.count` (default, most received first) or `.catalog` (the server's order).
    ///   - data: preloaded counters: no request is made.
    ///   - refreshKey: change it to ask the server again (for example after the person sent a gift).
    ///   - renderChip: draws the inside of each gift chip yourself (return `AnyView(...)`). The wall
    ///     still loads, orders and caps the chips and keeps the chip capsule, its spoken label and
    ///     the press. Return nil to draw the default icon and count. The "+37" overflow chip is not
    ///     passed. Chip widths for line wrapping are estimated from the default chip, so keep a
    ///     custom chip about as wide.
    ///   - onPressChip: makes every gift chip a button.
    ///   - onError: a wall never shows an error; it comes here.
    ///   - theme: uses `surface`, `border`, `text`, `muted` (and `coin` for a gift without icon).
    public init(
        loader: GiftWallLoader,
        user: String,
        reference: String? = nil,
        max: Int = defaultWallMax,
        order: WallOrder = .count,
        size: GiftWallSize = .md,
        data: [ReceivedGift]? = nil,
        refreshKey: AnyHashable? = nil,
        renderChip: ((WallChipContext) -> AnyView?)? = nil,
        onPressChip: ((GiftSummary) -> Void)? = nil,
        onError: ((GiftingError) -> Void)? = nil,
        theme: GiftingTheme = GiftingTheme(),
        labels: GiftLabels = GiftLabels()
    ) {
        self.loader = loader
        self.user = user
        self.reference = reference
        self.maxChips = max
        self.order = order
        self.size = size
        self.data = data
        self.refreshKey = refreshKey
        self.renderChip = renderChip
        self.onPressChip = onPressChip
        self.onError = onError
        self.theme = theme
        self.labels = labels
        _model = StateObject(wrappedValue: GiftWallModel())
    }

    private var iconSize: CGFloat {
        size == .sm ? 16 : 20
    }

    private var fontSize: CGFloat {
        size == .sm ? 11 : 12.5
    }

    private var chipHeight: CGFloat {
        size == .sm ? 20 : 24
    }

    private var wallKey: GiftWallKey {
        GiftWallKey(user: user, reference: reference)
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ComponentWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(ComponentWidthKey.self) { value in
                width = value
            }
            .onAppear {
                start()
            }
            .onChange(of: wallKey) { _ in
                start()
            }
            .onChange(of: refreshKey) { _ in
                if data == nil {
                    model.refetch(loader, user: user, reference: reference, onError: onError)
                }
            }
    }

    private func start() {
        if data == nil {
            model.begin(loader, user: user, reference: reference, animate: !reduceMotion, onError: onError)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let gifts = data ?? model.gifts {
            chipRows(wallChips(gifts, max: maxChips, order: order))
        } else {
            skeleton
        }
    }

    /// Loading: three static grey chips.
    private var skeleton: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule()
                    .fill(theme.border)
                    .frame(width: 44, height: chipHeight)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func chipRows(_ chips: [WallChip]) -> some View {
        if chips.isEmpty {
            if !labels.emptyText.isEmpty {
                Text(verbatim: labels.emptyText)
                    .font(.system(size: fontSize))
                    .foregroundColor(theme.muted)
            }
        } else {
            let texts = chips.map { chipText($0) }
            let tappable = onPressChip != nil
            let widths = texts.map { text -> CGFloat in
                let w = estimatedChipWidth(text: text, iconSize: iconSize, fontSize: fontSize)
                return tappable ? Swift.max(44, w) : w
            }
            let rows = wrapIntoRows(widths, width: width, spacing: 6)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<rows.count, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(rows[r], id: \.self) { i in
                            chipView(chips[i], text: texts[i])
                        }
                    }
                }
            }
            .transition(.opacity)
            .accessibilityElement(children: tappable ? AccessibilityChildBehavior.contain : AccessibilityChildBehavior.ignore)
            .accessibilityLabel(Text(verbatim: summary(chips)))
        }
    }

    private func chipText(_ chip: WallChip) -> String {
        switch chip {
        case .gift(_, let count):
            return formatCount(count, labels: labels.countLabels)
        case .overflow(let count, _):
            return "+" + formatCount(count, labels: labels.countLabels)
        }
    }

    @ViewBuilder
    private func chipView(_ chip: WallChip, text: String) -> some View {
        switch chip {
        case .gift(let gift, let count):
            if let press = onPressChip {
                Button {
                    press(gift)
                } label: {
                    giftChip(gift, count: count, text: text)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: fillLabel(labels.wallChip, ["name": gift.name, "count": groupThousands(count)])))
            } else {
                giftChip(gift, count: count, text: text)
            }
        case .overflow:
            Text(verbatim: text)
                .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
                .foregroundColor(theme.muted)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(height: chipHeight)
                .background(Capsule().fill(theme.surface))
                .overlay(Capsule().stroke(theme.border, lineWidth: 1))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func giftChip(_ gift: GiftSummary, count: Int, text: String) -> some View {
        if let custom = renderChip?(WallChipContext(gift: gift, count: count, countText: text, theme: theme)) {
            custom
                .padding(.horizontal, 8)
                .frame(minHeight: chipHeight)
                .background(Capsule().fill(theme.surface))
                .overlay(Capsule().stroke(theme.border, lineWidth: 1))
        } else {
            defaultGiftChip(gift, text: text)
        }
    }

    private func defaultGiftChip(_ gift: GiftSummary, text: String) -> some View {
        GiftCountChip(
            iconUrl: gift.iconUrl,
            text: text,
            iconSize: iconSize,
            fontSize: fontSize,
            height: chipHeight,
            theme: theme
        )
    }

    /// `"Gifts: 12 Roses, 3 Hearts, and 37 more"`.
    private func summary(_ chips: [WallChip]) -> String {
        var parts: [String] = []
        var more = ""
        for chip in chips {
            switch chip {
            case .gift(let gift, let count):
                let name = gift.name + (count > 1 ? labels.plural : "")
                parts.append(groupThousands(count) + " " + name)
            case .overflow(let count, _):
                more = fillLabel(labels.wallMore, ["n": groupThousands(count)])
            }
        }
        if !more.isEmpty {
            parts.append(more)
        }
        return fillLabel(labels.wallSummary, ["list": parts.joined(separator: ", ")])
    }
}
#endif
