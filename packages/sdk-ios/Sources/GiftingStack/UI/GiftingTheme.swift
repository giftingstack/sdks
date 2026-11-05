#if canImport(SwiftUI)
import SwiftUI

/// Colours used by the tray, the effects and the notice (spec sections 9 and 9.2). Override any
/// of them, or start from a preset: `.dark`, `.light`, `GiftingTheme.fromAccent("#ff4f9a")`.
public struct GiftingTheme {
    public var background: Color
    public var surface: Color
    public var border: Color
    public var text: Color
    public var muted: Color
    public var accent: Color
    public var accentText: Color
    public var coin: Color
    public var danger: Color
    public var noticeBackground: Color
    public var noticeText: Color
    /// Notice for large gifts.
    public var noticeBigBackground: Color
    public var noticeBigText: Color
    /// Light rays, glow and most sparks.
    public var glow: Color
    /// Label on the "Get coins" button.
    public var coinText: Color
    /// Background of the selected cell.
    public var selected: Color
    /// The combo counter ("x3") on a small or medium notice.
    public var comboText: Color

    public init(
        background: Color = Color(giftingHex: 0x14141F),
        surface: Color = Color(giftingHex: 0x1E1E2E),
        border: Color = Color(giftingHex: 0x2D2D44),
        text: Color = Color(giftingHex: 0xF4F2FF),
        muted: Color = Color(giftingHex: 0xA3A1C2),
        accent: Color = Color(giftingHex: 0x8B7BFF),
        accentText: Color = Color(giftingHex: 0xFFFFFF),
        coin: Color = Color(giftingHex: 0xFFD27A),
        danger: Color = Color(giftingHex: 0xFF8FA3),
        noticeBackground: Color = Color(giftingHex: 0x7B6BFF, opacity: 0.92),
        noticeText: Color = Color(giftingHex: 0xFFFFFF),
        noticeBigBackground: Color = Color(giftingHex: 0xE8A93A),
        noticeBigText: Color = Color(giftingHex: 0x2A1600),
        glow: Color = Color(giftingHex: 0xFFDC8C),
        coinText: Color = Color(giftingHex: 0x2A1600),
        selected: Color = Color(giftingHex: 0x221F45),
        comboText: Color = Color(giftingHex: 0xFFF3C4)
    ) {
        self.background = background
        self.surface = surface
        self.border = border
        self.text = text
        self.muted = muted
        self.accent = accent
        self.accentText = accentText
        self.coin = coin
        self.danger = danger
        self.noticeBackground = noticeBackground
        self.noticeText = noticeText
        self.noticeBigBackground = noticeBigBackground
        self.noticeBigText = noticeBigText
        self.glow = glow
        self.coinText = coinText
        self.selected = selected
        self.comboText = comboText
    }

    /// The colours of a `GiftTheme` (the pure token strings of spec 9.2). A token that is not a
    /// colour string falls back to the default of that token.
    public init(_ theme: GiftTheme) {
        let d = GiftTheme.defaultTheme
        func color(_ value: String, _ fallback: String) -> Color {
            Color(giftingCSS: value) ?? Color(giftingCSS: fallback) ?? Color.black
        }
        self.init(
            background: color(theme.background, d.background),
            surface: color(theme.surface, d.surface),
            border: color(theme.border, d.border),
            text: color(theme.text, d.text),
            muted: color(theme.muted, d.muted),
            accent: color(theme.accent, d.accent),
            accentText: color(theme.accentText, d.accentText),
            coin: color(theme.coin, d.coin),
            danger: color(theme.danger, d.danger),
            noticeBackground: color(theme.noticeBackground, d.noticeBackground),
            noticeText: color(theme.noticeText, d.noticeText),
            noticeBigBackground: color(theme.noticeBigBackground, d.noticeBigBackground),
            noticeBigText: color(theme.noticeBigText, d.noticeBigText),
            glow: color(theme.glow, d.glow),
            coinText: color(theme.coinText, d.coinText),
            selected: color(theme.selected, d.selected),
            comboText: color(theme.comboText, d.comboText)
        )
    }

    /// The defaults from the spec (the 1.0 look).
    public static let standard = GiftingTheme()
    /// `darkTheme`: the default look with an accent the white Send label reads on (4.7:1).
    public static let dark = GiftingTheme(GiftTheme.darkTheme)
    /// `lightTheme`: every text pair at least 4.5:1.
    public static let light = GiftingTheme(GiftTheme.lightTheme)

    /// A whole readable theme from one brand colour (`#rgb` / `#rrggbb`; anything else throws).
    public static func fromAccent(_ accent: String, mode: ThemeMode = .dark) throws -> GiftingTheme {
        GiftingTheme(try themeFromAccent(accent, mode: mode))
    }
}

extension Color {
    /// `0xRRGGBB` in sRGB.
    public init(giftingHex hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// `#rgb`, `#rrggbb` or `rgba(r, g, b, a)` (the theme token formats); nil for anything else.
    public init?(giftingCSS value: String) {
        if let rgb = parseHexColor(value) {
            self.init(.sRGB, red: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255, opacity: 1)
            return
        }
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("rgba("), trimmed.hasSuffix(")") else {
            return nil
        }
        let inner = trimmed.dropFirst(5).dropLast()
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4,
              let r = Double(parts[0]),
              let g = Double(parts[1]),
              let b = Double(parts[2]),
              let a = Double(parts[3]) else {
            return nil
        }
        self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}
#endif
