package com.giftingstack.ui

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import com.giftingstack.core.GiftThemeTokens
import com.giftingstack.core.ThemeMode
import com.giftingstack.core.darkThemeTokens
import com.giftingstack.core.lightThemeTokens
import com.giftingstack.core.parseHex
import com.giftingstack.core.themeFromAccent

/**
 * Colors used by the tray and the effects (spec sections 9 and 9.2). Override any of them. The
 * defaults are the 1.0 look; [Dark] and [Light] are the ready palettes and [fromAccent] builds a
 * readable theme (4.5:1 text) from one brand colour. The arithmetic lives in `core/Theme.kt`.
 */
@Immutable
data class GiftingTheme(
    val background: Color = Color(0xFF14141F),
    val surface: Color = Color(0xFF1E1E2E),
    val border: Color = Color(0xFF2D2D44),
    val text: Color = Color(0xFFF4F2FF),
    val muted: Color = Color(0xFFA3A1C2),
    val accent: Color = Color(0xFF8B7BFF),
    val accentText: Color = Color(0xFFFFFFFF),
    val coin: Color = Color(0xFFFFD27A),
    val danger: Color = Color(0xFFFF8FA3),
    /** rgba(123, 107, 255, 0.92) */
    val noticeBackground: Color = Color(0xEB7B6BFF),
    val noticeText: Color = Color(0xFFFFFFFF),
    /** Notice for large gifts. */
    val noticeBigBackground: Color = Color(0xFFE8A93A),
    val noticeBigText: Color = Color(0xFF2A1600),
    /** Color of the light rays, the glow and most sparks. */
    val glow: Color = Color(0xFFFFDC8C),
    /** Text on [coin] (the "Get coins" button). */
    val coinText: Color = Color(0xFF2A1600),
    /** Background of the selected cell. */
    val selected: Color = Color(0xFF221F45),
    /** The combo counter ("x3") on a small or medium notice. */
    val comboText: Color = Color(0xFFFFF3C4),
) {
    companion object {
        /** The dark preset: a slightly deeper accent, so the white Send label reaches 4.5:1. */
        val Dark: GiftingTheme by lazy { from(darkThemeTokens) }

        /** A light preset; every text pair is at least 4.5:1. */
        val Light: GiftingTheme by lazy { from(lightThemeTokens) }

        /** A whole readable theme from one brand colour (`#rgb` or `#rrggbb`; anything else throws). */
        fun fromAccent(accent: String, dark: Boolean = true): GiftingTheme =
            from(themeFromAccent(accent, if (dark) ThemeMode.Dark else ThemeMode.Light))

        /** Turns the pure tokens (`#rrggbb`, `rgba(r, g, b, a)`) into colours. */
        fun from(t: GiftThemeTokens): GiftingTheme =
            GiftingTheme(
                background = tokenColor(t.background),
                surface = tokenColor(t.surface),
                border = tokenColor(t.border),
                text = tokenColor(t.text),
                muted = tokenColor(t.muted),
                accent = tokenColor(t.accent),
                accentText = tokenColor(t.accentText),
                coin = tokenColor(t.coin),
                danger = tokenColor(t.danger),
                noticeBackground = tokenColor(t.noticeBackground),
                noticeText = tokenColor(t.noticeText),
                noticeBigBackground = tokenColor(t.noticeBigBackground),
                noticeBigText = tokenColor(t.noticeBigText),
                glow = tokenColor(t.glow),
                coinText = tokenColor(t.coinText),
                selected = tokenColor(t.selected),
                comboText = tokenColor(t.comboText),
            )
    }
}

private val RGBA = Regex("""^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*([0-9.]+)\s*)?\)$""")

/** `#rgb`, `#rrggbb` or `rgba(r, g, b, a)` to a [Color]. */
internal fun tokenColor(value: String): Color {
    parseHex(value)?.let { return Color(it[0], it[1], it[2]) }
    val m = RGBA.matchEntire(value.trim()) ?: throw IllegalArgumentException("Not a colour: $value")
    val (r, g, b) = m.destructured
    val a = m.groupValues[4].ifEmpty { "1" }.toFloat()
    return Color(r.toInt().coerceIn(0, 255), g.toInt().coerceIn(0, 255), b.toInt().coerceIn(0, 255), (a.coerceIn(0f, 1f) * 255f + 0.5f).toInt())
}

/** A [Color] as a token string [tokenColor] reads back: `#rrggbb`, or `rgba(r, g, b, a)` when it is not opaque. */
internal fun colorCss(c: Color): String {
    val v = c.toArgb()
    val a = (v ushr 24) and 0xFF
    if (a == 0xFF) return "#" + (v and 0xFFFFFF).toString(16).padStart(6, '0')
    return "rgba(${(v shr 16) and 0xFF}, ${(v shr 8) and 0xFF}, ${v and 0xFF}, ${"%.3f".format(java.util.Locale.ROOT, a / 255f)})"
}

typealias GiftTheme = GiftingTheme
