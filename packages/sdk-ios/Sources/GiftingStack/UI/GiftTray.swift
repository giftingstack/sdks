#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI

/// A tray of gifts with the balance and a Send button (spec section 9). Presentational: you pass
/// data and callbacks, usually from a `GiftTrayModel`.
///
/// Since spec 9.1 it is a draggable bottom sheet by default (`sheet: true`): it fills the area it
/// is given (usually the whole screen, over your content) and sits at its bottom; touches above the
/// sheet reach your screen. `sheet: false` keeps the fixed tray that takes its own height.
@MainActor
/// Moves a tray's sheet from your code: give the same handle to GiftTray(handle:) and call
/// snapTo, for example to lower the tray when the person taps outside it.
public final class GiftTrayHandle {
    private var controller: TraySheetController?

    public init() {}

    /// Moves the sheet to snap (animated unless Reduce Motion is on). Nothing happens before the
    /// tray appears or for a tray with sheet: false.
    public func snapTo(_ snap: SheetSnap) {
        controller?.snapTo(snap)
    }

    func attach(_ controller: TraySheetController) {
        self.controller = controller
    }
}

public struct GiftTray: View {
    let gifts: [Gift]
    let balance: Int
    let onSend: (Gift) -> Void
    let onTopUp: (() -> Void)?
    let title: String
    let coinName: String
    let sendLabel: String
    let notEnoughLabel: String
    let getCoinsLabel: String
    let columns: Int
    let gridMaxHeight: CGFloat
    let disabled: Bool
    let bottomPadding: CGFloat
    let theme: GiftingTheme
    let useSheet: Bool
    let snaps: SheetSnaps?
    let onSnapChange: ((SheetSnap) -> Void)?
    let onInsetChange: ((CGFloat) -> Void)?
    let onSelect: ((Gift) -> Void)?
    let testMode: Bool?
    let testModeLabel: String
    let collapseOnSelect: Bool
    let handle: GiftTrayHandle?
    /// Spec 9.4: shown (true, default) or hidden. Resolved by the initialisers (`open ?? tray.isOpen ?? true`).
    let isOpen: Bool
    let scrim: Bool
    let scrimTap: ScrimTap
    let onDismiss: (() -> Void)?
    let initialSnap: SheetSnap
    /// Closes the model of `GiftTray(tray:)` when a scrim tap dismisses and `open` was not given.
    var closeOwnTray: (() -> Void)?

    /// What the models that are alive report about the token (`GiftTrayModel.testMode`).
    @ObservedObject private var testModeFollow = GiftTrayTestModeRegistry.shared
    @State var selectedId: String?
    @State var gridHeight: CGFloat = 0
    @State var trayWidth: CGFloat = 0
    // Sheet measurements and gesture (GiftTray+Sheet.swift).
    @StateObject var sheetModel: TraySheetModel
    @State var containerHeight: CGFloat = 0
    @State var topBlockHeight: CGFloat = 0
    @State var footerHeight: CGFloat = 0
    @State var rowHeight: CGFloat = 0
    /// Set a moment after the first complete measurement: until then the sheet is not drawn and
    /// every move is a jump, so it never slides about behind a footer that is already in place.
    @State var sheetShown = false
    /// Whether the tray is open NOW, kept in state for the delayed work of the sheet. `isOpen` is a plain
    /// property: an `onChange` action, and every `Task` it starts, may still hold the previous render's
    /// value, which kept a reopened tray (toggle on the same receiver) open but never shown.
    @State var sheetOpen = false
    @State var sheetDrag: SheetDragState?
    @State var lastDragEnd = Date.distantPast
    /// True while the sheet's drag gesture runs; SwiftUI resets it on end AND on cancel, so an
    /// interrupted drag (no `onEnded`) is still closed.
    @GestureState var sheetTouching = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// - Parameters:
    ///   - onTopUp: shows "+ Coins" and, when the balance is too low, a "Get coins" button.
    ///   - defaultSelectedId: the gift selected first. Default: the first gift.
    ///   - bottomPadding: padding under the Send button (add the safe area inset here). Default 14.
    ///   - sheet: a draggable bottom sheet (default). Read once.
    ///   - initialSnap: `.peek`, `.default` (default) or `.expanded` (90 % of the area).
    ///   - snaps: snap heights as fractions of the area; nil fields keep the defaults.
    ///   - onSnapChange: the settled state changed (release, tap on the handle, accessibility).
    ///   - onInsetChange: the sheet's visible height, live while dragging and the target of a
    ///     snap. Pass `inset + gap` to the effect layer's `noticeBottom`.
    ///   - onSelect: the person picked a gift.
    ///   - testMode: the "Test mode" badge after the title. nil (default) follows the token: it shows while a
    ///     `GiftTrayModel` that is alive reports a test key (`me.livemode == false`). `true` always shows it (also
    ///     without a model), `false` never. With your own `GiftTrayController` pass `state.testMode`.
    ///   - testModeLabel: the badge's text (shown in capitals).
    ///   - collapseOnSelect: picking a gift lowers the sheet to peek (the picked gift and Send), so
    ///     what is behind it stays in sight, for example a live stream. The handle (or a drag up)
    ///     brings the grid back. Sheet only. Default false.
    ///   - handle: lets your code move the sheet (snapTo), see GiftTrayHandle.
    ///   - open: (sheet) shown or hidden. nil (default): `tray.isOpen` for `GiftTray(tray:)`, else true. Closed, the
    ///     sheet, the footer and the scrim are invisible, take no touches, are out of the accessibility tree and
    ///     `onInsetChange` says 0; opening shows the sheet again at `initialSnap` (spec 9.4). When you pass it, the tray
    ///     never closes itself: react in `onDismiss`.
    ///   - scrim: (sheet) a black dim (0.4) behind the sheet over the whole area the tray fills, above your screen. It
    ///     fades in with the sheet (200 ms, at once with Reduce Motion), is hidden at peek and takes the touches above the
    ///     sheet while it shows (accessibility button "Close gift tray"). Default false.
    ///   - scrimTap: what a tap on the dim does: `.lower` (default) lowers the sheet to peek, and from peek dismisses;
    ///     `.dismiss` dismisses from every state. A dismissal closes the `tray` model (when `open` was not given) and
    ///     then calls `onDismiss`.
    ///   - onDismiss: a tap on the dim asked to close. With a `tray` it is already closed when this runs.
    public init(
        gifts: [Gift],
        balance: Int,
        onSend: @escaping (Gift) -> Void,
        onTopUp: (() -> Void)? = nil,
        title: String = "Send a gift",
        coinName: String = "coins",
        sendLabel: String = "Send",
        notEnoughLabel: String = "Not enough coins",
        getCoinsLabel: String = "Get coins",
        columns: Int = 4,
        gridMaxHeight: CGFloat = 230,
        defaultSelectedId: String? = nil,
        disabled: Bool = false,
        bottomPadding: CGFloat = 14,
        theme: GiftingTheme = GiftingTheme(),
        sheet: Bool = true,
        initialSnap: SheetSnap = .default,
        snaps: SheetSnaps? = nil,
        onSnapChange: ((SheetSnap) -> Void)? = nil,
        onInsetChange: ((CGFloat) -> Void)? = nil,
        onSelect: ((Gift) -> Void)? = nil,
        testMode: Bool? = nil,
        testModeLabel: String = "Test mode",
        collapseOnSelect: Bool = false,
        handle: GiftTrayHandle? = nil,
        open: Bool? = nil,
        scrim: Bool = false,
        scrimTap: ScrimTap = .lower,
        onDismiss: (() -> Void)? = nil
    ) {
        self.gifts = gifts
        self.balance = balance
        self.onSend = onSend
        self.onTopUp = onTopUp
        self.title = title
        self.coinName = coinName
        self.sendLabel = sendLabel
        self.notEnoughLabel = notEnoughLabel
        self.getCoinsLabel = getCoinsLabel
        self.columns = max(1, columns)
        self.gridMaxHeight = gridMaxHeight
        self.disabled = disabled
        self.bottomPadding = bottomPadding
        self.theme = theme
        self.useSheet = sheet
        self.snaps = snaps
        self.onSnapChange = onSnapChange
        self.onInsetChange = onInsetChange
        self.onSelect = onSelect
        self.testMode = testMode
        self.testModeLabel = testModeLabel
        self.collapseOnSelect = collapseOnSelect
        self.handle = handle
        self.isOpen = open ?? true
        self.scrim = scrim
        self.scrimTap = scrimTap
        self.onDismiss = onDismiss
        self.initialSnap = initialSnap
        _selectedId = State(initialValue: defaultSelectedId ?? gifts.first?.id)
        _sheetModel = StateObject(wrappedValue: TraySheetModel(initialSnap: initialSnap))
    }

    /// A tray fed by your `GiftTrayModel`: `GiftTray(tray: tray)` takes the gifts, the balance, Send and the
    /// "Test mode" badge from it (keep the model in a `@StateObject` so the view is rebuilt when it changes).
    /// Anything you pass yourself wins; every other parameter is the one of the main initialiser.
    ///   - testMode: nil follows the model: a test token shows the badge (also after `tray.stop()`, for as long as
    ///     this view lives); `true` / `false` force it.
    @MainActor
    public init(
        tray: GiftTrayModel,
        gifts: [Gift]? = nil,
        balance: Int? = nil,
        onSend: ((Gift) -> Void)? = nil,
        onTopUp: (() -> Void)? = nil,
        title: String = "Send a gift",
        coinName: String = "coins",
        sendLabel: String = "Send",
        notEnoughLabel: String = "Not enough coins",
        getCoinsLabel: String = "Get coins",
        columns: Int = 4,
        gridMaxHeight: CGFloat = 230,
        defaultSelectedId: String? = nil,
        disabled: Bool = false,
        bottomPadding: CGFloat = 14,
        theme: GiftingTheme = GiftingTheme(),
        sheet: Bool = true,
        initialSnap: SheetSnap = .default,
        snaps: SheetSnaps? = nil,
        onSnapChange: ((SheetSnap) -> Void)? = nil,
        onInsetChange: ((CGFloat) -> Void)? = nil,
        onSelect: ((Gift) -> Void)? = nil,
        testMode: Bool? = nil,
        testModeLabel: String = "Test mode",
        collapseOnSelect: Bool = false,
        handle: GiftTrayHandle? = nil,
        open: Bool? = nil,
        scrim: Bool = false,
        scrimTap: ScrimTap = .lower,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            gifts: gifts ?? tray.gifts,
            balance: balance ?? tray.balance,
            onSend: onSend ?? { [weak tray] gift in tray?.send(gift) },
            onTopUp: onTopUp,
            title: title,
            coinName: coinName,
            sendLabel: sendLabel,
            notEnoughLabel: notEnoughLabel,
            getCoinsLabel: getCoinsLabel,
            columns: columns,
            gridMaxHeight: gridMaxHeight,
            defaultSelectedId: defaultSelectedId,
            disabled: disabled,
            bottomPadding: bottomPadding,
            theme: theme,
            sheet: sheet,
            initialSnap: initialSnap,
            snaps: snaps,
            onSnapChange: onSnapChange,
            onInsetChange: onInsetChange,
            onSelect: onSelect,
            // A test token is a sticky "true" for this view; otherwise the registry (the live models) decides.
            testMode: testMode ?? (tray.testMode ? true : nil),
            testModeLabel: testModeLabel,
            collapseOnSelect: collapseOnSelect,
            handle: handle,
            open: open ?? tray.isOpen,
            scrim: scrim,
            scrimTap: scrimTap,
            onDismiss: onDismiss
        )
        // `open` given: the host owns the state and never has it closed behind its back.
        if open == nil {
            closeOwnTray = { [weak tray] in tray?.close() }
        }
    }

    /// The gift shown as selected: the chosen one, else the first gift.
    var selected: Gift? {
        gifts.first(where: { $0.id == selectedId }) ?? gifts.first
    }

    var button: SendButtonState {
        sendButtonState(
            gifts: gifts,
            selectedId: selectedId,
            balance: balance,
            disabled: disabled,
            canTopUp: onTopUp != nil
        )
    }

    /// The badge: an explicit `testMode` wins, else what the token says.
    var showsTestMode: Bool {
        testMode ?? testModeFollow.active
    }

    var bigPicture: String? {
        selected?.animationUrl ?? selected?.iconUrl
    }

    /// Icon size like the web tray: `min(72, 78 % of the cell)`.
    static func iconSize(gridWidth: CGFloat, columns: Int) -> CGFloat {
        guard gridWidth > 0 else {
            return 48
        }
        let cell = gridWidth / CGFloat(max(1, columns)) - 8
        return max(24, min(72, cell * 0.78))
    }

    public var body: some View {
        Group {
            if useSheet {
                sheetBody
            } else {
                fixedBody
            }
        }
        .onAppear {
            handle?.attach(sheetModel.controller)
            prefetchIcons()
            prefetchGiftPicture(bigPicture)
        }
        .onChange(of: gifts) { _ in
            prefetchIcons()
            prefetchGiftPicture(bigPicture)
        }
        .onChange(of: selectedId) { _ in
            prefetchGiftPicture(bigPicture)
        }
    }

    // MARK: - Fixed tray (sheet: false)

    private var fixedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            fixedGrid
            sendButton
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, bottomPadding)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TrayWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(TrayWidthKey.self) { width in
            trayWidth = width
        }
        .background(
            TopRoundedRectangle(radius: 24)
                .fill(theme.surface)
        )
        .overlay(
            TopRoundedRectangle(radius: 24)
                .stroke(theme.border, lineWidth: 0.5)
        )
    }

    private var fixedGrid: some View {
        let items = Array(repeating: GridItem(.flexible(), spacing: 0), count: columns)
        let icon = GiftTray.iconSize(gridWidth: trayWidth - 28, columns: columns)
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: items, spacing: 0) {
                ForEach(gifts) { gift in
                    Button {
                        select(gift)
                    } label: {
                        cellContent(gift, iconSize: icon)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel(Text(verbatim: cellLabel(gift)))
                    .accessibilityAddTraits(gift.id == selected?.id ? [.isButton, .isSelected] : [.isButton])
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: GridHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .frame(height: min(max(gridHeight, 1), gridMaxHeight))
        .onPreferenceChange(GridHeightKey.self) { height in
            gridHeight = height
        }
    }

    // MARK: - Shared parts

    var header: some View {
        HStack(spacing: 10) {
            Text(verbatim: title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(theme.text)
                // One line, ends with "…" (SPEC 9): the badge and the balance never overlap it, and a long or
                // translated title never changes the peek height.
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsTestMode {
                // SPEC 9: the same colours on every platform, whatever the theme.
                Text(verbatim: testModeLabel.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .kerning(0.4)
                    .foregroundColor(Color(red: 0x1A / 255, green: 0x13 / 255, blue: 0))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(red: 0xF5 / 255, green: 0xA5 / 255, blue: 0x24 / 255))
                    )
                    .fixedSize()
                    .accessibilityIdentifier("gift-test-mode")
            }

            HStack(spacing: 6) {
                Circle().fill(theme.coin).frame(width: 14, height: 14)
                Color.clear
                    .frame(width: 1, height: 1)
                    .modifier(CountingNumber(value: Double(balance), color: theme.text))
                    .animation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.6), value: balance)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Capsule().fill(theme.background))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Balance: \(formatCoins(balance)) \(coinName)"))

            if let onTopUp = onTopUp {
                Button(action: onTopUp) {
                    Text(verbatim: "+ Coins")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(theme.coin)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "Get more \(coinName)"))
            }
        }
    }

    /// One cell's look (icon, price), without the tap handling.
    func cellContent(_ gift: Gift, iconSize: CGFloat) -> some View {
        let isSelected = gift.id == selected?.id
        return VStack(spacing: 2) {
            if gift.iconUrl != nil {
                GiftPicture(url: gift.iconUrl, size: iconSize)
                    .id(gift.iconUrl ?? "")
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.border)
                    .frame(width: iconSize, height: iconSize)
            }
            priceRow(gift.price)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? theme.selected : theme.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }

    func priceRow(_ price: Int) -> some View {
        HStack(spacing: 3) {
            Circle().fill(theme.coin).frame(width: 9, height: 9)
            Text(verbatim: formatCoins(price))
                .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                .foregroundColor(theme.text)
        }
    }

    func cellLabel(_ gift: Gift) -> String {
        "\(gift.name), \(formatCoins(gift.price)) \(coinName)"
    }

    func select(_ gift: Gift) {
        selectedId = gift.id
        onSelect?(gift)
        if collapseOnSelect && useSheet {
            sheetModel.controller.snapTo(.peek)
        }
    }

    var sendButton: some View {
        let state = button
        let label: String
        switch state.label {
        case .send:
            label = sendLabel
        case .getCoins:
            label = getCoinsLabel
        case .notEnough:
            label = notEnoughLabel
        }
        let background: Color = state.pressable ? (state.broke ? theme.coin : theme.accent) : theme.border
        let foreground: Color = state.broke && state.pressable ? theme.coinText : theme.accentText
        let spoken = selected.map { "\(label): \($0.name)" } ?? label
        return Button {
            press(state)
        } label: {
            Text(verbatim: label)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(background))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!state.pressable)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    private func press(_ state: SendButtonState) {
        guard let gift = selected else {
            return
        }
        switch state.action {
        case .topUp:
            onTopUp?()
        case .send:
            onSend(gift)
        case .noAction:
            break
        }
    }

    private func prefetchIcons() {
        for gift in gifts {
            prefetchGiftPicture(gift.iconUrl)
        }
    }
}

/// The shown balance counts to its new value (600 ms, ease-out cubic), rounded every frame.
struct CountingNumber: ViewModifier, Animatable {
    var value: Double
    let color: Color

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text(verbatim: formatCoins(Int(value.rounded())))
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .foregroundColor(color)
            .fixedSize()
    }
}

struct GridHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TrayWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A rectangle with only the top corners rounded (iOS 15 has no built-in one).
struct TopRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
#endif
