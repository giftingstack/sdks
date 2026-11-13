package com.giftingstack.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import com.giftingstack.core.BattleSide
import com.giftingstack.core.BattleView
import com.giftingstack.core.Gift
import com.giftingstack.core.GiftTransaction
import com.giftingstack.core.GiftTrayOptions
import com.giftingstack.core.GiftingApi
import com.giftingstack.core.Me
import com.giftingstack.core.ReceivedGift
import com.giftingstack.core.SendGiftInput
import com.giftingstack.core.TrayReceiver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

private object PickerApi : GiftingApi {
    override suspend fun getGifts(): List<Gift> = emptyList()

    override suspend fun getMe(): Me = Me("viewer", 100)

    override suspend fun getReceivedGifts(user: String): List<ReceivedGift> = emptyList()

    override suspend fun sendGift(input: SendGiftInput): GiftTransaction = error("unused")
}

private val rose = Gift("rose", "Rose", null, 1, null, null, 0)

/**
 * Compose tests of the receiver picker (SPEC 21.3, 21.4). They need a device or an emulator
 * (`connectedDebugAndroidTest`); the holder logic runs on the JVM in `ReceiverPickerTest`.
 */
class ReceiverPickerUiTest {
    @get:Rule val rule = createComposeRule()

    private fun holder(receivers: List<TrayReceiver>) =
        GiftTrayHolder(GiftTrayOptions(PickerApi, "host"), CoroutineScope(Job()), receivers = receivers)

    private fun showTray(h: GiftTrayHolder) {
        rule.setContent {
            Box(Modifier.fillMaxSize()) { GiftTray(gifts = listOf(rose), balance = 100, onSend = {}, tray = h) }
        }
    }

    @Test
    fun twoSidesShowTheRowAndATapPicks() {
        val h = holder(listOf(TrayReceiver("mia", "Mia"), TrayReceiver("theo", "Theo", "#2ec4b6")))
        showTray(h)
        rule.onNodeWithContentDescription("Send to").assertExists()
        rule.onNodeWithTag("gift-receiver-mia").assertIsSelected()
        rule.onNodeWithTag("gift-receiver-theo")
            .assertIsNotSelected()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.RadioButton))
            .performClick()
        rule.onNodeWithTag("gift-receiver-theo").assertIsSelected()
        assertEquals("theo", h.receiver)
    }

    @Test
    fun onlyTheSelectedSideShowsItsName() {
        val h = holder(listOf(TrayReceiver("mia", "Mia"), TrayReceiver("theo", "Theo")))
        showTray(h)
        // Unselected: the avatar only (34 dp: 30 + the 2 dp ring), its name is its label.
        rule.onNodeWithTag("gift-receiver-theo").assertWidthIsEqualTo(34.dp).assertHeightIsAtLeast(44.dp)
        rule.onNodeWithText("Theo", useUnmergedTree = true).assertDoesNotExist()
        rule.onNodeWithContentDescription("Theo").assertExists()
        rule.onNodeWithText("Mia", useUnmergedTree = true).assertExists()
        rule.onNodeWithTag("gift-receiver-theo").performClick()
        rule.onNodeWithText("Theo", useUnmergedTree = true).assertExists()
        rule.onNodeWithText("Mia", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test
    fun fourSidesAndALongNameFitA347DpRow() {
        val sides = listOf("a" to "Amelia", "b" to "Bo", "c" to "Cy", "d" to "Delilah Longname-Smith").map { (id, n) -> TrayReceiver(id, n) }
        val h = holder(sides)
        h.selectReceiver("d")
        rule.setContent {
            Box(Modifier.width(375.dp)) { GiftTray(gifts = listOf(rose), balance = 100, onSend = {}, tray = h, sheet = false) }
        }
        val row = rule.onNodeWithTag("gift-send-to").getUnclippedBoundsInRoot()
        val last = rule.onNodeWithTag("gift-receiver-d").getUnclippedBoundsInRoot()
        assertTrue("the selected last side is in sight", last.right <= row.right && last.left >= row.left)
    }

    @Test
    fun theRowScrollsToShowTheSelectedSide() {
        val sides = (1..8).map { TrayReceiver("s$it", "Side number $it") }
        val h = holder(sides)
        rule.setContent {
            Box(Modifier.width(240.dp)) { GiftTray(gifts = listOf(rose), balance = 100, onSend = {}, tray = h, sheet = false) }
        }
        rule.runOnIdle { h.selectReceiver("s8") }
        rule.waitForIdle()
        val row = rule.onNodeWithTag("gift-send-to").getUnclippedBoundsInRoot()
        val chip = rule.onNodeWithTag("gift-receiver-s8").getUnclippedBoundsInRoot()
        assertTrue("the whole selected side is in the row", chip.left >= row.left && chip.right <= row.right)
        // And back to the first: the row scrolls left the least distance.
        rule.runOnIdle { h.selectReceiver("s1") }
        rule.waitForIdle()
        val first = rule.onNodeWithTag("gift-receiver-s1").getUnclippedBoundsInRoot()
        assertTrue(first.left >= row.left && first.right <= row.right)
    }

    @Test
    fun oneSideHasNoRow() {
        showTray(holder(listOf(TrayReceiver("mia", "Mia"))))
        rule.onNodeWithTag("gift-send-to").assertDoesNotExist()
    }

    @Test
    fun battleSidesAreButtonsWhenPressable() {
        val pressed = ArrayList<String>()
        val view =
            BattleView(
                round = "r1",
                open = true,
                remainingMs = 30_000,
                total = 0,
                sides = listOf(BattleSide("mia", 0, 0, 0.5), BattleSide("theo", 0, 0, 0.5)),
                leader = null,
            )
        rule.setContent {
            Box(Modifier.width(358.dp)) {
                GiftBattleBar(
                    view,
                    users = mapOf("mia" to BattleBarUser("Mia"), "theo" to BattleBarUser("Theo")),
                    reducedMotion = true,
                    onPressSide = { pressed.add(it) },
                )
            }
        }
        rule.onNodeWithContentDescription("Send Theo a gift")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assertWidthIsAtLeast(44.dp)
            .assertHeightIsAtLeast(44.dp)
            .performClick()
        assertEquals(listOf("theo"), pressed)
    }

    @Test
    fun battleSidesAreReadOnlyWithoutOnPressSide() {
        val view =
            BattleView(
                round = "r1",
                open = true,
                remainingMs = 30_000,
                total = 0,
                sides = listOf(BattleSide("mia", 0, 0, 0.5), BattleSide("theo", 0, 0, 0.5)),
                leader = null,
            )
        rule.setContent { GiftBattleBar(view, reducedMotion = true) }
        rule.onNodeWithContentDescription("Send mia a gift").assertDoesNotExist()
    }
}
