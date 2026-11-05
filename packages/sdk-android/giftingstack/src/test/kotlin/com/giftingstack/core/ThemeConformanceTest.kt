package com.giftingstack.core

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import kotlin.math.floor

/** theme.json: contrast ratios, the contrast rule for presets and themeFromAccent, invalid accents. */
class ThemeConformanceTest {
    private val file = Fixtures.conformance("theme.json")

    private fun token(t: GiftThemeTokens, name: String): String =
        when (name) {
            "background" -> t.background
            "surface" -> t.surface
            "border" -> t.border
            "text" -> t.text
            "muted" -> t.muted
            "accent" -> t.accent
            "accentText" -> t.accentText
            "coin" -> t.coin
            "coinText" -> t.coinText
            "selected" -> t.selected
            "danger" -> t.danger
            "noticeText" -> t.noticeText
            "comboText" -> t.comboText
            "noticeBigBackground" -> t.noticeBigBackground
            "noticeBigText" -> t.noticeBigText
            "glow" -> t.glow
            else -> error("unknown token $name")
        }

    private fun checkRules(label: String, t: GiftThemeTokens) {
        for (r in file.getValue("rules").arr()) {
            val o = r.obj()
            val ratio = contrastRatio(token(t, o.string("fg")), token(t, o.string("bg")))
            assertTrue("$label ${o.string("fg")}/${o.string("bg")} = $ratio < ${o.getValue("min")}", ratio >= o.getValue("min").jsonPrimitive.double)
        }
    }

    @Test
    fun contrastRatiosRoundedToTwoDecimals() {
        for (c in file.getValue("contrast").arr()) {
            val o = c.obj()
            val raw = contrastRatio(o.string("a"), o.string("b"))
            val rounded = floor(raw * 100 + 0.5) / 100
            assertEquals("${o.string("a")} on ${o.string("b")}", o.getValue("ratio").jsonPrimitive.double, rounded, 0.0)
        }
    }

    @Test
    fun presetsMeetEveryRule() {
        val presets = mapOf("darkTheme" to darkThemeTokens, "lightTheme" to lightThemeTokens)
        for (p in file.getValue("presets").arr()) checkRules(p.jsonPrimitive.content, presets.getValue(p.jsonPrimitive.content))
    }

    @Test
    fun themeFromAccentMeetsEveryRuleAndKeepsTheAccent() {
        val modes = file.getValue("modes").arr().map { it.jsonPrimitive.content }
        for (a in file.getValue("accents").arr()) {
            val o: JsonObject = a.obj()
            for (m in modes) {
                val mode = if (m == "dark") ThemeMode.Dark else ThemeMode.Light
                val t = themeFromAccent(o.string("accent"), mode)
                assertEquals("accent of ${o.string("accent")} $m", o.string("normalized"), t.accent)
                checkRules("themeFromAccent(${o.string("accent")}, $m)", t)
            }
        }
    }

    @Test
    fun threeHundredRandomAccentsMeetTheRule() {
        val rnd = java.util.Random(2026)
        repeat(300) {
            val accent = "#" + (rnd.nextInt(0x1000000)).toString(16).padStart(6, '0')
            for (mode in ThemeMode.entries) checkRules("themeFromAccent($accent, $mode)", themeFromAccent(accent, mode))
        }
    }

    @Test
    fun invalidAccentsThrow() {
        for (v in file.getValue("invalid").arr()) {
            val value = v.jsonPrimitive.content
            try {
                themeFromAccent(value, ThemeMode.Dark)
                fail("themeFromAccent('$value') must throw")
            } catch (_: IllegalArgumentException) {
                // expected
            }
        }
    }

    @Test
    fun contrastPairsHelperAgreesWithTheRules() {
        for (t in listOf(darkThemeTokens, lightThemeTokens, themeFromAccent("#ff4f9a", ThemeMode.Light))) {
            for (p in themeContrastPairs(t)) assertTrue(p.name, contrastRatio(p.fg, p.bg) >= p.min)
        }
    }
}
