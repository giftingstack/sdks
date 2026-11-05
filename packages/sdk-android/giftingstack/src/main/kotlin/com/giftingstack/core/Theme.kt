package com.giftingstack.core

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * Theme tokens as plain strings (`#rrggbb`, or `rgba(r, g, b, a)` for the notice background), two
 * ready palettes and [themeFromAccent] (spec section 9.2). Pure arithmetic, no Compose: the UI
 * turns the tokens into colours with `GiftingTheme.from`. Port of
 * `packages/sdk-js/src/core/theme.ts`.
 */
data class GiftThemeTokens(
    /** Cells and the balance pill. */
    val background: String,
    /** The tray. */
    val surface: String,
    val border: String,
    val text: String,
    val muted: String,
    val accent: String,
    /** Text on [accent] (the Send button). */
    val accentText: String,
    /** Coin discs, "+ Coins" and the "Get coins" button. */
    val coin: String,
    /** Text on [coin] (the "Get coins" button). */
    val coinText: String,
    /** Background of the selected cell. */
    val selected: String,
    val danger: String,
    val noticeBackground: String,
    val noticeText: String,
    /** The combo counter ("x3") on a small or medium notice. */
    val comboText: String,
    /** Notice for large gifts. */
    val noticeBigBackground: String,
    val noticeBigText: String,
    /** Colour of the light rays and sparks of large gifts. */
    val glow: String,
)

enum class ThemeMode { Dark, Light }

/** The original 1.0 look (the three newer tokens keep the old fixed colours). */
val defaultThemeTokens =
    GiftThemeTokens(
        background = "#14141f",
        surface = "#1e1e2e",
        border = "#2d2d44",
        text = "#f4f2ff",
        muted = "#a3a1c2",
        accent = "#8b7bff",
        accentText = "#ffffff",
        coin = "#ffd27a",
        coinText = "#2a1600",
        selected = "#221f45",
        danger = "#ff8fa3",
        noticeBackground = "rgba(123, 107, 255, 0.92)",
        noticeText = "#ffffff",
        comboText = "#fff3c4",
        noticeBigBackground = "#e8a93a",
        noticeBigText = "#2a1600",
        glow = "#ffdc8c",
    )

/** The dark preset: a slightly deeper accent so the white Send label reaches 4.5:1. */
val darkThemeTokens = defaultThemeTokens.copy(accent = "#6d5cf0", noticeBackground = "rgba(109, 92, 240, 0.92)")

val lightThemeTokens =
    GiftThemeTokens(
        background = "#f1eff8",
        surface = "#ffffff",
        border = "#dcd8ea",
        text = "#1c1a2e",
        muted = "#5f5b78",
        accent = "#6a54e8",
        accentText = "#ffffff",
        coin = "#9a6300",
        coinText = "#ffffff",
        selected = "#e6e1ff",
        danger = "#c4204a",
        noticeBackground = "rgba(106, 84, 232, 0.94)",
        noticeText = "#ffffff",
        comboText = "#fff3c4",
        noticeBigBackground = "#e8a93a",
        noticeBigText = "#2a1600",
        glow = "#ffcf66",
    )

// ------------------------------------------------------------------ colour arithmetic

private val HEX = Regex("^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")

/** `#rgb` or `#rrggbb` (any case) to 0..255 channels; anything else is null. */
fun parseHex(hex: String): IntArray? {
    val m = HEX.matchEntire(hex.trim()) ?: return null
    val g = m.groupValues[1]
    val h = if (g.length == 3) g.map { "$it$it" }.joinToString("") else g
    return IntArray(3) { h.substring(it * 2, it * 2 + 2).toInt(16) }
}

private fun roundHalfUpToInt(v: Double): Int = floor(v + 0.5).toInt()

fun toHex(r: Double, g: Double, b: Double): String =
    "#" + listOf(r, g, b).joinToString("") { roundHalfUpToInt(min(255.0, max(0.0, it))).toString(16).padStart(2, '0') }

/** WCAG 2 relative luminance of an opaque colour, 0 (black) to 1 (white). */
fun relativeLuminance(hex: String): Double {
    val rgb = parseHex(hex) ?: throw IllegalArgumentException("Not a hex colour: $hex")
    val (r, g, b) =
        rgb.map {
            val c = it / 255.0
            if (c <= 0.04045) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
        }
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

/** WCAG 2 contrast ratio of two opaque colours, 1 to 21. */
fun contrastRatio(a: String, b: String): Double {
    val la = relativeLuminance(a)
    val lb = relativeLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/** [a] moved towards [b] by [t] (0 = a, 1 = b), channel by channel. */
fun mixHex(a: String, b: String, t: Double): String {
    val x = parseHex(a)!!
    val y = parseHex(b)!!
    return toHex(x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t)
}

/**
 * [fg] itself if it reaches [minRatio] against [bg]; otherwise [fg] moved step by step (5 %)
 * towards white or black, whichever is further from [bg], until it does.
 */
fun ensureContrast(fg: String, bg: String, minRatio: Double): String {
    if (contrastRatio(fg, bg) >= minRatio) return fg
    val target = if (relativeLuminance(bg) > 0.18) "#000000" else "#ffffff"
    var t = 0.05
    while (t < 1) {
        val c = mixHex(fg, target, t)
        if (contrastRatio(c, bg) >= minRatio) return c
        t += 0.05
    }
    return target
}

/** White or black, whichever contrasts more with [bg] (always at least 4.58:1). */
fun readableOn(bg: String): String = if (contrastRatio("#ffffff", bg) >= contrastRatio("#000000", bg)) "#ffffff" else "#000000"

/**
 * A whole theme from one brand colour. The accent is kept (as lower-case `#rrggbb`); every other
 * token is derived so text stays readable (4.5:1). Throws [IllegalArgumentException] for
 * anything but `#rgb` / `#rrggbb`.
 */
fun themeFromAccent(accent: String, mode: ThemeMode = ThemeMode.Dark): GiftThemeTokens {
    val rgb = parseHex(accent) ?: throw IllegalArgumentException("themeFromAccent: not a hex colour: $accent")
    val a = toHex(rgb[0].toDouble(), rgb[1].toDouble(), rgb[2].toDouble())
    val dark = mode == ThemeMode.Dark
    val surface = if (dark) mixHex("#17171f", a, 0.1) else "#ffffff"
    val background = if (dark) mixHex("#0d0d14", a, 0.06) else mixHex("#f4f4f7", a, 0.06)
    val selected = if (dark) mixHex(surface, a, 0.22) else mixHex("#ffffff", a, 0.16)
    // Text must read on the surface, the background and the selected cell: check the hardest one.
    fun fit(fg: String): String = listOf(surface, background, selected).fold(fg) { c, bg -> ensureContrast(c, bg, 4.5) }
    val text = fit(if (dark) mixHex("#ffffff", a, 0.05) else mixHex("#16151f", a, 0.08))
    val muted = fit(if (dark) mixHex("#b0afc0", a, 0.15) else mixHex("#5c5b6b", a, 0.15))
    val coin = if (dark) "#ffd27a" else fit("#9a6300")
    val accentText = readableOn(a)
    return GiftThemeTokens(
        background = background,
        surface = surface,
        border = if (dark) mixHex("#2a2a35", a, 0.25) else mixHex("#dedee6", a, 0.2),
        text = text,
        muted = muted,
        accent = a,
        accentText = accentText,
        coin = coin,
        coinText = readableOn(coin),
        selected = selected,
        danger = if (dark) "#ff8fa3" else "#c4204a",
        noticeBackground = "rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, 0.92)",
        noticeText = accentText,
        comboText = if (accentText == "#ffffff") "#fff3c4" else accentText,
        noticeBigBackground = "#e8a93a",
        noticeBigText = "#2a1600",
        glow = "#ffdc8c",
    )
}

data class ThemeContrastPair(val name: String, val fg: String, val bg: String, val min: Double)

/** The text/background pairs the contrast rule covers (spec 9.2), with their minimum ratio. */
fun themeContrastPairs(t: GiftThemeTokens): List<ThemeContrastPair> =
    listOf(
        ThemeContrastPair("text/surface", t.text, t.surface, 4.5),
        ThemeContrastPair("text/background", t.text, t.background, 4.5),
        ThemeContrastPair("text/selected", t.text, t.selected, 4.5),
        ThemeContrastPair("muted/surface", t.muted, t.surface, 4.5),
        ThemeContrastPair("coin/surface", t.coin, t.surface, 4.5),
        ThemeContrastPair("accentText/accent", t.accentText, t.accent, 4.5),
        ThemeContrastPair("coinText/coin", t.coinText, t.coin, 4.5),
        ThemeContrastPair("noticeText/accent", t.noticeText, t.accent, 4.5),
        ThemeContrastPair("noticeBigText/noticeBigBackground", t.noticeBigText, t.noticeBigBackground, 4.5),
    )
