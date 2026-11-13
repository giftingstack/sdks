package com.giftingstack.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.giftingstack.core.Gift
import com.giftingstack.core.GiftTransaction
import com.giftingstack.core.GiftTrayOptions
import com.giftingstack.core.GiftingApi
import com.giftingstack.core.Me
import com.giftingstack.core.ReceivedGift
import com.giftingstack.core.SendGiftInput
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The holder side of SPEC 20 (the keyboard swap), on the JVM through the [GiftTrayInputBinding] seam. */
class GiftTrayInputTest {
    private object NoApi : GiftingApi {
        override suspend fun getGifts(): List<Gift> = error("unused")

        override suspend fun getMe(): Me = error("unused")

        override suspend fun getReceivedGifts(user: String): List<ReceivedGift> = error("unused")

        override suspend fun sendGift(input: SendGiftInput): GiftTransaction = error("unused")
    }

    /** Records blur/focus and the open state the holder had at that moment (the order of SPEC 20.2). */
    private class Field(private val holder: () -> GiftTrayHolder) : GiftTrayInputBinding {
        val log = ArrayList<String>()

        override fun blur() {
            log.add("blur(open=${holder().isOpen})")
        }

        override fun focus() {
            log.add("focus(open=${holder().isOpen})")
            // The focus a "focus" step causes is itself an inputFocus event (SPEC 20.2): keep, keep.
            holder().onInputFocus()
        }
    }

    private fun holder(open: Boolean? = null, changes: MutableList<Boolean>? = null) =
        GiftTrayHolder(GiftTrayOptions(NoApi, "bob"), CoroutineScope(Job()), open, changes?.let { c -> { v: Boolean -> c.add(v) } })

    @Test
    fun withoutAFieldNothingChanges() {
        val h = holder()
        assertTrue("default open, as before", h.isOpen)
        assertFalse(h.inputBound)
        assertFalse(h.toggle())
        assertTrue(h.toggle())
        assertFalse(holder(open = false).isOpen)
    }

    @Test
    fun aBoundFieldMakesTheDefaultClosedWithoutTellingOnOpenChange() {
        val changes = ArrayList<Boolean>()
        val h = holder(changes = changes)
        val f = Field { h }
        h.bindInput(f)
        assertTrue(h.inputBound)
        assertFalse("starts closed (SPEC 20.3)", h.isOpen)
        assertEquals("nothing was shown, nothing is told", emptyList<Boolean>(), changes)
        assertEquals(emptyList<String>(), f.log)
    }

    @Test
    fun anExplicitOpenWins() {
        val h = holder(open = true)
        h.bindInput(Field { h })
        assertTrue(h.isOpen)
        val g = holder(open = false)
        g.bindInput(Field { g })
        assertFalse(g.isOpen)
    }

    @Test
    fun anOpenBeforeTheBindingIsKept() {
        val h = holder()
        h.close()
        h.open()
        h.bindInput(Field { h })
        assertTrue("the host already chose", h.isOpen)
    }

    @Test
    fun theButtonSwapsBlurBeforeOpenAndCloseBeforeFocus() {
        val changes = ArrayList<Boolean>()
        val h = holder(changes = changes)
        val f = Field { h }
        h.bindInput(f)
        assertTrue(h.toggle())
        assertEquals(listOf("blur(open=false)"), f.log)
        assertFalse(h.toggle())
        assertEquals(listOf("blur(open=false)", "focus(open=false)"), f.log)
        assertEquals(listOf(true, false), changes)
        assertFalse("the focus it caused keeps the tray closed", h.isOpen)
    }

    @Test
    fun theFieldsFocusClosesWithoutMovingFocus() {
        val h = holder()
        val f = Field { h }
        h.bindInput(f)
        h.onInputFocus()
        assertFalse(h.isOpen)
        h.toggle()
        f.log.clear()
        h.onInputFocus()
        assertFalse(h.isOpen)
        assertEquals(emptyList<String>(), f.log)
    }

    @Test
    fun openBlursFirstCloseDoesNotFocus() {
        val h = holder()
        val f = Field { h }
        h.bindInput(f)
        assertTrue(h.open())
        assertEquals(listOf("blur(open=false)"), f.log)
        h.open()
        assertEquals("already open: no second blur", 1, f.log.size)
        assertFalse(h.close())
        assertEquals(1, f.log.size)
    }

    @Test
    fun anUnboundFieldIsNeverFocused() {
        val h = holder()
        val f = Field { h }
        val unbind = h.bindInput(f)
        h.toggle()
        unbind()
        unbind()
        assertFalse(h.inputBound)
        assertFalse("a plain toggle again", h.toggle())
        assertEquals(listOf("blur(open=false)"), f.log)
    }

    @Test
    fun aNewerBindingReplacesTheOlder() {
        val h = holder()
        val a = Field { h }
        val b = Field { h }
        val unbindA = h.bindInput(a)
        h.bindInput(b)
        unbindA()
        assertTrue("b is still bound", h.inputBound)
        h.toggle()
        assertEquals(emptyList<String>(), a.log)
        assertEquals(listOf("blur(open=false)"), b.log)
    }

    @Test
    fun keyboardHeightKeepsTheLastRealKeyboard() {
        val h = holder()
        assertNull(h.keyboardHeight)
        assertEquals("fallback", 300.dp, h.keyboardPlaceHeight(800.dp))
        assertEquals("fallback capped at 60 %", 240.dp, h.keyboardPlaceHeight(400.dp))
        h.recordKeyboardHeight(44.dp)
        assertNull("an accessory bar is not a keyboard", h.keyboardHeight)
        h.recordKeyboardHeight(336.dp)
        h.recordKeyboardHeight(0.dp)
        assertEquals("kept when the keyboard goes down", 336.dp, h.keyboardHeight)
        assertEquals(336.dp, h.keyboardPlaceHeight(800.dp))
        assertEquals(336.dp, h.keyboardPlaceHeight(null))
        assertEquals("capped at 60 % of the container", 300.dp, h.keyboardPlaceHeight(500.dp))
        h.recordKeyboardHeight(120.dp)
        assertEquals("the threshold counts", 120.dp, h.keyboardHeight)
    }

    @Test
    fun giftButtonLooks() {
        val t = GiftingTheme()
        assertEquals(GiftButtonColors(Color.Transparent, t.accent), giftButtonColors(t, filled = false, active = false))
        assertEquals(GiftButtonColors(t.accent, t.accentText), giftButtonColors(t, filled = true, active = false))
        assertEquals(GiftButtonColors(t.selected, t.accent), giftButtonColors(t, filled = true, active = true))
        assertEquals(GiftButtonColors(t.selected, t.accent), giftButtonColors(t, filled = false, active = true))
        assertEquals(GiftButtonMetrics(32f, 22f * 32f / 36f), giftButtonMetrics(GiftButtonSize.Small))
        assertEquals(GiftButtonMetrics(36f, 22f), giftButtonMetrics(GiftButtonSize.Medium))
        assertEquals(GiftButtonMetrics(44f, 22f * 44f / 36f), giftButtonMetrics(GiftButtonSize.Large))
        assertEquals(1f, giftIconFitScale(10f, 10f, 22f), 0f)
        assertEquals(0.044f, giftIconFitScale(500f, 300f, 22f), 1e-6f)
        assertEquals(0.5f, giftIconFitScale(20f, 44f, 22f), 1e-6f)
        assertNull(giftButtonState(null))
        val h = holder(open = false)
        assertEquals("collapsed", giftButtonState(h))
        h.open()
        assertEquals("expanded", giftButtonState(h))
    }
}
