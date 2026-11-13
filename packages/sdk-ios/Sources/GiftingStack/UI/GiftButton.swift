#if canImport(SwiftUI) && canImport(ImageIO)
import Foundation
import SwiftUI

/// The three fixed sizes of `GiftButton` (spec 20.4): the circle's diameter in points. The host cannot pick
/// another size.
public enum GiftButtonSize: Equatable, Sendable {
    case small
    case medium
    case large

    /// The circle's diameter: 32, 36 or 44.
    var circle: CGFloat {
        switch self {
        case .small: return 32
        case .medium: return 36
        case .large: return 44
        }
    }

    /// The glyph box (a square): `22 * circle / 36`, so 19.56, 22 or 26.89.
    var glyphBox: CGFloat {
        22 * circle / 36
    }
}

/// A small round button with a gift glyph for the app's message bar, next to its text field or emoji
/// button (spec 20.4). With `tray` a press is `tray.toggle()` (the keyboard swap when the field is bound with
/// `.giftTrayInput`) and the button shows the tray's open state; `onPress` runs after the toggle (without
/// `tray` it is the only action).
///
/// ```swift
/// HStack {
///     TextField("Message", text: $text).giftTrayInput(tray, focused: $typing)
///     GiftButton(tray: tray)
///     Button("Send") { ... }
/// }
/// ```
@MainActor
public struct GiftButton: View {
    let tray: GiftTrayModel?
    let label: String
    let filled: Bool
    let size: GiftButtonSize
    let icon: ((Color) -> AnyView)?
    let disabled: Bool
    let theme: GiftingTheme
    let onPress: (() -> Void)?

    /// - Parameters:
    ///   - tray: a press toggles it; the button is "active" (and "expanded" for VoiceOver) while it is open.
    ///   - label: the accessibility label. Default "Send a gift".
    ///   - filled: an `accent` circle with an `accentText` glyph; default false (no background, `accent` glyph,
    ///     like an emoji button).
    ///   - size: one of three fixed sizes, `.small` (32 pt), `.medium` (36 pt, default) or `.large` (44 pt); the
    ///     touch area is at least 44 x 44.
    ///   - icon: replaces the gift glyph. It is given the glyph's colour (`accent` when plain or active,
    ///     `accentText` when filled), drawn centred in the fixed glyph box (`22 * size / 36` square) and fitted
    ///     into it: it keeps the size it asks for, is scaled down (never up) when that is bigger than the box, and
    ///     is clipped to the box, so it can never enlarge the button. Without `icon` the gift glyph is drawn.
    ///   - disabled: half opacity, no presses.
    ///   - theme: the tray's colours.
    ///   - onPress: called after the toggle.
    public init(
        tray: GiftTrayModel? = nil,
        label: String = "Send a gift",
        filled: Bool = false,
        size: GiftButtonSize = .medium,
        icon: ((Color) -> AnyView)? = nil,
        disabled: Bool = false,
        theme: GiftingTheme = GiftingTheme(),
        onPress: (() -> Void)? = nil
    ) {
        self.tray = tray
        self.label = label
        self.filled = filled
        self.size = size
        self.icon = icon
        self.disabled = disabled
        self.theme = theme
        self.onPress = onPress
    }

    public var body: some View {
        if let tray = tray {
            GiftButtonFollowingTray(tray: tray, button: self)
        } else {
            face(active: nil)
        }
    }

    /// `active`: nil without a tray, else whether the tray is open.
    func face(active: Bool?) -> some View {
        let isActive = active ?? false
        let background: Color = isActive ? theme.selected : (filled ? theme.accent : Color.clear)
        let glyphColor: Color = GiftButton.glyphColor(theme: theme, filled: filled, active: isActive)
        let circle = size.circle
        let glyph = size.glyphBox
        return Button {
            press()
        } label: {
            ZStack {
                Circle().fill(background)
                if let icon = icon {
                    // The host's glyph: it keeps its own size, is scaled down into the box and clipped to it.
                    FittedIcon(box: glyph, content: icon(glyphColor))
                } else {
                    GiftGlyph()
                        .stroke(
                            glyphColor,
                            style: StrokeStyle(lineWidth: 1.8 * glyph / 24, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: glyph, height: glyph)
                }
            }
            .frame(width: circle, height: circle)
            // The circle stays its fixed size; the touch area is at least 44 x 44.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: active.map { $0 ? "expanded" : "collapsed" } ?? ""))
        .accessibilityIdentifier("gift-button")
    }

    /// The glyph's colour: `accentText` when filled and not active, else `accent`.
    static func glyphColor(theme: GiftingTheme, filled: Bool, active: Bool) -> Color {
        active ? theme.accent : (filled ? theme.accentText : theme.accent)
    }

    /// The scale that fits a width x height icon into a box x box glyph box: down only, never up, aspect ratio
    /// kept (spec 20.4).
    static func iconFitScale(width: CGFloat, height: CGFloat, box: CGFloat) -> CGFloat {
        if width <= 0 || height <= 0 {
            return 1
        }
        return min(1, box / width, box / height)
    }

    /// A press: `tray.toggle()`, then `onPress`. Nothing while disabled.
    func press() {
        if disabled {
            return
        }
        tray?.toggle()
        onPress?()
    }
}

/// Draws `content` centred in a `box` x `box` area at the size it asks for, scaled down to fit (never up) and
/// clipped, so a host's icon can never change the size of the button (spec 20.4).
@MainActor
struct FittedIcon: View {
    let box: CGFloat
    let content: AnyView
    @State private var natural: CGSize = .zero

    var body: some View {
        content
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: FittedIconSizeKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(FittedIconSizeKey.self) { size in
                natural = size
            }
            .scaleEffect(GiftButton.iconFitScale(width: natural.width, height: natural.height, box: box))
            .frame(width: box, height: box)
            .clipped()
    }
}

/// The size `FittedIcon` measured for its content.
struct FittedIconSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Redraws the button when its tray opens or closes.
@MainActor
struct GiftButtonFollowingTray: View {
    @ObservedObject var tray: GiftTrayModel
    let button: GiftButton

    var body: some View {
        button.face(active: tray.isOpen)
    }
}

/// The gift glyph of spec 20.4, in a 24 x 24 box scaled to the rect: two rects (box and lid), the ribbon and
/// two bows. Stroke it (width 1.8 in box units, round caps and joins).
struct GiftGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.minX + (rect.width - 24 * s) / 2
        let oy = rect.minY + (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }
        var path = Path()
        // rect (4,11)-(20,21): the box.
        path.addRect(CGRect(origin: p(4, 11), size: CGSize(width: 16 * s, height: 10 * s)))
        // rect (3,7)-(21,11): the lid.
        path.addRect(CGRect(origin: p(3, 7), size: CGSize(width: 18 * s, height: 4 * s)))
        // line (12,7)-(12,21): the ribbon.
        path.move(to: p(12, 7))
        path.addLine(to: p(12, 21))
        // Left bow: M12 7 C10 7 8 6 8 4.5 C8 3 10 3 12 7
        path.move(to: p(12, 7))
        path.addCurve(to: p(8, 4.5), control1: p(10, 7), control2: p(8, 6))
        path.addCurve(to: p(12, 7), control1: p(8, 3), control2: p(10, 3))
        // Right bow: M12 7 C14 7 16 6 16 4.5 C16 3 14 3 12 7
        path.move(to: p(12, 7))
        path.addCurve(to: p(16, 4.5), control1: p(14, 7), control2: p(16, 6))
        path.addCurve(to: p(12, 7), control1: p(16, 3), control2: p(14, 3))
        return path
    }
}
#endif
