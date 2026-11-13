package com.giftingstack.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotFocused
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
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
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

private object NoApi : GiftingApi {
    override suspend fun getGifts(): List<Gift> = error("unused")

    override suspend fun getMe(): Me = error("unused")

    override suspend fun getReceivedGifts(user: String): List<ReceivedGift> = error("unused")

    override suspend fun sendGift(input: SendGiftInput): GiftTransaction = error("unused")
}

private fun stateIs(value: String) = SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, value)

/** SPEC 20.4 and the field binding of 20.3. Needs a device or an emulator (`connectedDebugAndroidTest`). */
class GiftButtonTest {
    @get:Rule val rule = createComposeRule()

    private fun holder(open: Boolean? = null) = GiftTrayHolder(GiftTrayOptions(NoApi, "bob"), CoroutineScope(Job()), open)

    @Test
    fun aButtonWithALabelAndA44dpTarget() {
        var clicks = 0
        rule.setContent { GiftButton(onClick = { clicks++ }) }
        rule.onNodeWithContentDescription("Send a gift").assertHasClickAction().assertWidthIsAtLeast(44.dp).assertHeightIsAtLeast(44.dp).performClick()
        assertEquals(1, clicks)
    }

    @Test
    fun largeSizeKeepsA44dpTarget() {
        rule.setContent { GiftButton(size = GiftButtonSize.Large) }
        rule.onNodeWithTag("gift-button").assertWidthIsEqualTo(44.dp).assertHeightIsEqualTo(44.dp)
    }

    @Test
    fun anOversizedIconCannotEnlargeTheButton() {
        var seen: Color? = null
        rule.setContent {
            GiftButton(icon = { c ->
                seen = c
                Box(Modifier.size(500.dp).background(c))
            })
        }
        rule.onNodeWithTag("gift-button").assertWidthIsEqualTo(44.dp).assertHeightIsEqualTo(44.dp)
        assertEquals(GiftingTheme().accent, seen)
    }

    @Test
    fun aFilledButtonGivesTheIconAccentText() {
        var seen: Color? = null
        rule.setContent { GiftButton(filled = true, icon = { c -> seen = c; Box(Modifier.size(10.dp)) }) }
        assertEquals(GiftingTheme().accentText, seen)
    }

    @Test
    fun disabledTakesNoPresses() {
        var clicks = 0
        rule.setContent { GiftButton(onClick = { clicks++ }, enabled = false) }
        rule.onNodeWithTag("gift-button").performClick()
        assertEquals(0, clicks)
    }

    @Test
    fun withATrayItTogglesAndSaysExpanded() {
        val h = holder(open = false)
        rule.setContent { GiftButton(tray = h, label = "Gift") }
        rule.onNodeWithContentDescription("Gift").assert(stateIs("collapsed")).performClick()
        assertTrue(h.isOpen)
        rule.onNodeWithContentDescription("Gift").assert(stateIs("expanded"))
    }

    @Test
    fun theKeyboardSwap() {
        val h = holder()
        rule.setContent {
            var text by remember { mutableStateOf("") }
            Row {
                BasicTextField(text, { text = it }, Modifier.giftTrayInput(h).testTag("field"))
                GiftButton(tray = h)
            }
        }
        rule.waitForIdle()
        assertTrue(h.inputBound)
        assertFalse("a bound field starts the tray closed", h.isOpen)
        rule.onNodeWithTag("field").performClick()
        rule.onNodeWithTag("field").assertIsFocused()
        rule.onNodeWithTag("gift-button").performClick()
        assertTrue(h.isOpen)
        rule.onNodeWithTag("field").assertIsNotFocused()
        rule.onNodeWithTag("gift-button").performClick()
        assertFalse(h.isOpen)
        rule.onNodeWithTag("field").assertIsFocused()
        h.open()
        rule.onNodeWithTag("field").performClick()
        rule.waitForIdle()
        assertFalse("a tap on the field closes the tray", h.isOpen)
    }
}
