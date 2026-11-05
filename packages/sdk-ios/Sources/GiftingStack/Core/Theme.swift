import Foundation

// Theme tokens as colour strings, two presets and `themeFromAccent` (spec section 9.2). Pure
// arithmetic, ported from `packages/sdk-js/src/core/theme.ts`. The SwiftUI `GiftingTheme` is
// built from a `GiftTheme` with `GiftingTheme(_:)`.

public enum ThemeMode: String, Sendable, Hashable {
    case dark
    case light
}

public struct ThemeError: Error, Sendable, Equatable, CustomStringConvertible {
    public let description: String
}

/// Every colour the tray and the notice draw: `#rrggbb`, or `rgba(r, g, b, a)` for the notice.
public struct GiftTheme: Sendable, Equatable, Hashable {
    public var background: String
    public var surface: String
    public var border: String
    public var text: String
    public var muted: String
    public var accent: String
    public var accentText: String
    public var coin: String
    public var coinText: String
    public var selected: String
    public var danger: String
    public var noticeBackground: String
    public var noticeText: String
    public var comboText: String
    public var noticeBigBackground: String
    public var noticeBigText: String
    public var glow: String

    public init(
        background: String = "#14141f",
        surface: String = "#1e1e2e",
        border: String = "#2d2d44",
        text: String = "#f4f2ff",
        muted: String = "#a3a1c2",
        accent: String = "#8b7bff",
        accentText: String = "#ffffff",
        coin: String = "#ffd27a",
        coinText: String = "#2a1600",
        selected: String = "#221f45",
        danger: String = "#ff8fa3",
        noticeBackground: String = "rgba(123, 107, 255, 0.92)",
        noticeText: String = "#ffffff",
        comboText: String = "#fff3c4",
        noticeBigBackground: String = "#e8a93a",
        noticeBigText: String = "#2a1600",
        glow: String = "#ffdc8c"
    ) {
        self.background = background
        self.surface = surface
        self.border = border
        self.text = text
        self.muted = muted
        self.accent = accent
        self.accentText = accentText
        self.coin = coin
        self.coinText = coinText
        self.selected = selected
        self.danger = danger
        self.noticeBackground = noticeBackground
        self.noticeText = noticeText
        self.comboText = comboText
        self.noticeBigBackground = noticeBigBackground
        self.noticeBigText = noticeBigText
        self.glow = glow
    }

    /// The 1.0 look (white on its accent is only 3.3:1; kept for existing apps).
    public static let defaultTheme = GiftTheme()

    /// The default look with a deeper accent, so the white Send label reaches 4.7:1.
    public static let darkTheme = GiftTheme(accent: "#6d5cf0", noticeBackground: "rgba(109, 92, 240, 0.92)")

    public static let lightTheme = GiftTheme(
        background: "#f1eff8",
        surface: "#ffffff",
        border: "#dcd8ea",
        text: "#1c1a2e",
        muted: "#5f5b78",
        accent: "#6a54e8",
        accentText: "#ffffff",
        coin: "#9a6300",
        coinText: "#ffffff",
        selected: "#e6e1ff",
        danger: "#c4204a",
        noticeBackground: "rgba(106, 84, 232, 0.94)",
        noticeText: "#ffffff",
        comboText: "#fff3c4",
        noticeBigBackground: "#e8a93a",
        noticeBigText: "#2a1600",
        glow: "#ffcf66"
    )

    /// A token by its spec name (`"text"`, `"coinText"`, ...), or nil for an unknown name.
    public func token(_ name: String) -> String? {
        switch name {
        case "background": return background
        case "surface": return surface
        case "border": return border
        case "text": return text
        case "muted": return muted
        case "accent": return accent
        case "accentText": return accentText
        case "coin": return coin
        case "coinText": return coinText
        case "selected": return selected
        case "danger": return danger
        case "noticeBackground": return noticeBackground
        case "noticeText": return noticeText
        case "comboText": return comboText
        case "noticeBigBackground": return noticeBigBackground
        case "noticeBigText": return noticeBigText
        case "glow": return glow
        default: return nil
        }
    }
}

// MARK: - Colour arithmetic

/// Red, green, blue in 0...255.
public struct ThemeRGB: Sendable, Equatable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// `#rgb` or `#rrggbb` (any case, surrounding spaces allowed); anything else is nil.
public func parseHexColor(_ hex: String) -> ThemeRGB? {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("#") else {
        return nil
    }
    let digits = Array(trimmed.dropFirst())
    guard digits.count == 3 || digits.count == 6 else {
        return nil
    }
    var values: [Double] = []
    for ch in digits {
        guard let v = ch.hexDigitValue, ch.isASCII else {
            return nil
        }
        values.append(Double(v))
    }
    if values.count == 3 {
        return ThemeRGB(r: values[0] * 17, g: values[1] * 17, b: values[2] * 17)
    }
    return ThemeRGB(
        r: values[0] * 16 + values[1],
        g: values[2] * 16 + values[3],
        b: values[4] * 16 + values[5]
    )
}

/// Lower-case `#rrggbb`; channels are clamped to 0...255 and rounded half up.
public func hexColor(_ rgb: ThemeRGB) -> String {
    func two(_ v: Double) -> String {
        let n = Int((min(255, max(0, v)) + 0.5).rounded(.down))
        let s = String(n, radix: 16)
        return s.count == 1 ? "0" + s : s
    }
    return "#" + two(rgb.r) + two(rgb.g) + two(rgb.b)
}

/// WCAG 2 relative luminance, 0 (black) to 1 (white). A colour that is not hex counts as black.
public func relativeLuminance(_ hex: String) -> Double {
    let rgb = parseHexColor(hex) ?? ThemeRGB(r: 0, g: 0, b: 0)
    func channel(_ v: Double) -> Double {
        let c = v / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(rgb.r) + 0.7152 * channel(rgb.g) + 0.0722 * channel(rgb.b)
}

/// WCAG 2 contrast ratio of two opaque colours, 1 to 21.
public func contrastRatio(_ a: String, _ b: String) -> Double {
    let la = relativeLuminance(a)
    let lb = relativeLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// `a` moved towards `b` by `t` (0 = a, 1 = b), channel by channel.
public func mixHexColor(_ a: String, _ b: String, _ t: Double) -> String {
    let x = parseHexColor(a) ?? ThemeRGB(r: 0, g: 0, b: 0)
    let y = parseHexColor(b) ?? ThemeRGB(r: 0, g: 0, b: 0)
    return hexColor(ThemeRGB(
        r: x.r + (y.r - x.r) * t,
        g: x.g + (y.g - x.g) * t,
        b: x.b + (y.b - x.b) * t
    ))
}

/// `fg` if it reaches `minimum` on `bg`; else `fg` moved in 5 % steps towards black (light `bg`)
/// or white until it does; pure black or white at the end.
public func ensureContrast(_ fg: String, _ bg: String, _ minimum: Double) -> String {
    if contrastRatio(fg, bg) >= minimum {
        return fg
    }
    let target = relativeLuminance(bg) > 0.18 ? "#000000" : "#ffffff"
    var t = 0.05
    while t < 1 {
        let c = mixHexColor(fg, target, t)
        if contrastRatio(c, bg) >= minimum {
            return c
        }
        t += 0.05
    }
    return target
}

/// White or black, whichever contrasts more with `bg`.
public func readableOn(_ bg: String) -> String {
    contrastRatio("#ffffff", bg) >= contrastRatio("#000000", bg) ? "#ffffff" : "#000000"
}

/// A whole readable theme from one brand colour (`#rgb` or `#rrggbb`, else it throws). The accent
/// is kept (as lower-case `#rrggbb`); every other token is derived so text stays at 4.5:1.
public func themeFromAccent(_ accent: String, mode: ThemeMode = .dark) throws -> GiftTheme {
    guard let rgb = parseHexColor(accent) else {
        throw ThemeError(description: "themeFromAccent: not a hex colour: \(accent)")
    }
    let a = hexColor(rgb)
    let dark = mode == .dark
    let surface = dark ? mixHexColor("#17171f", a, 0.1) : "#ffffff"
    let background = dark ? mixHexColor("#0d0d14", a, 0.06) : mixHexColor("#f4f4f7", a, 0.06)
    let selected = dark ? mixHexColor(surface, a, 0.22) : mixHexColor("#ffffff", a, 0.16)
    // Text must read on the surface, the background and the selected cell.
    func fit(_ fg: String) -> String {
        var c = fg
        for bg in [surface, background, selected] {
            c = ensureContrast(c, bg, 4.5)
        }
        return c
    }
    let text = fit(dark ? mixHexColor("#ffffff", a, 0.05) : mixHexColor("#16151f", a, 0.08))
    let muted = fit(dark ? mixHexColor("#b0afc0", a, 0.15) : mixHexColor("#5c5b6b", a, 0.15))
    let coin = dark ? "#ffd27a" : fit("#9a6300")
    let accentText = readableOn(a)
    let r = Int(rgb.r)
    let g = Int(rgb.g)
    let b = Int(rgb.b)
    return GiftTheme(
        background: background,
        surface: surface,
        border: dark ? mixHexColor("#2a2a35", a, 0.25) : mixHexColor("#dedee6", a, 0.2),
        text: text,
        muted: muted,
        accent: a,
        accentText: accentText,
        coin: coin,
        coinText: readableOn(coin),
        selected: selected,
        danger: dark ? "#ff8fa3" : "#c4204a",
        noticeBackground: "rgba(\(r), \(g), \(b), 0.92)",
        noticeText: accentText,
        comboText: accentText == "#ffffff" ? "#fff3c4" : accentText,
        noticeBigBackground: "#e8a93a",
        noticeBigText: "#2a1600",
        glow: "#ffdc8c"
    )
}
