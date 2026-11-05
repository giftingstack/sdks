package com.giftingstack.ui

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The Compose theme turns the pure tokens (core/Theme.kt, driven by theme.json) into colours. */
class ThemeUiTest {
    @Test fun defaultsKeepTheOneDotZeroLook() {
        val d = GiftingTheme()
        assertEquals(Color(0xFF14141F), d.background)
        assertEquals(Color(0xFF2A1600), d.coinText)
        assertEquals(Color(0xFF221F45), d.selected)
        assertEquals(Color(0xFFFFF3C4), d.comboText)
    }

    @Test fun tokenColorParsesHexAndRgba() {
        assertEquals(Color(0xFF8B7BFF), tokenColor("#8b7bff"))
        assertEquals(Color(0xFFFF8800), tokenColor("#f80"))
        assertEquals(Color(123, 107, 255, 235), tokenColor("rgba(123, 107, 255, 0.92)"))
        assertEquals(Color(0xFFFFFFFF), tokenColor("rgb(255, 255, 255)"))
        try {
            tokenColor("red")
            fail("must throw")
        } catch (_: IllegalArgumentException) {
        }
    }

    @Test fun presetsAndFromAccentAreBuiltFromTheTokens() {
        assertEquals(Color(0xFF6D5CF0), GiftingTheme.Dark.accent)
        assertEquals(Color(0xFFFFFFFF), GiftingTheme.Light.surface)
        val t = GiftingTheme.fromAccent("#ff4f9a", dark = false)
        assertEquals(Color(0xFFFF4F9A), t.accent)
        assertEquals(Color(0xFFFFFFFF), t.surface)
        try {
            GiftingTheme.fromAccent("pink")
            fail("must throw")
        } catch (_: IllegalArgumentException) {
        }
    }

    @Test fun trayIconsAreMinOf72DpAnd78PercentOfTheCell() {
        assertEquals(0.78f, ICON_CELL_FRACTION, 0f)
        assertEquals(72, ICON_MAX_DP)
        // A 4-column tray on a 360 dp phone: cell ~ (360 - 28) / 4 - 8 = 75 dp, so 58.5 dp icons.
        val cell = (360 - 28) / 4f - 8
        assertTrue(minOf(ICON_MAX_DP.toFloat(), cell * ICON_CELL_FRACTION) < 72f)
    }
}
