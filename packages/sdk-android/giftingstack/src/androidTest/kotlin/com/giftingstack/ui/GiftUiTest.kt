package com.giftingstack.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.giftingstack.core.EffectGift
import com.giftingstack.core.EffectTier
import com.giftingstack.core.Gift
import com.giftingstack.core.GiftEffectEvent
import com.giftingstack.core.GiftTransaction
import com.giftingstack.core.GiftingApi
import com.giftingstack.core.Me
import com.giftingstack.core.ReceivedGift
import com.giftingstack.core.SendGiftInput
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Everything is already "loaded": no network in UI tests. */
private object InstantLoader : GiftImageLoader {
    private val bmp = ImageBitmap(8, 8)

    override fun peek(url: String) = bmp

    override suspend fun load(url: String) = bmp

    override fun prefetch(url: String) {}
}

private fun ev(price: Int, id: String = "rose", sender: String = "ava") =
    GiftEffectEvent(EffectGift(id, id.replaceFirstChar { it.uppercase() }, price.toLong(), "https://t/$id-512", "https://t/$id-256"), sender)

class GiftUiTest {
    @get:Rule val rule = createComposeRule()

    private fun layer(state: GiftEffectLayerState, reduced: Boolean = false, onEnd: ((GiftEffectEvent, EffectTier) -> Unit)? = null) {
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantLoader) {
                GiftEffectLayer(state, reducedMotion = reduced, onEffectEnd = onEnd)
            }
        }
    }

    private fun count(tag: String) = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().size

    @Test
    fun layerPassesTouchesThrough() {
        var clicks by mutableStateOf(0)
        val state = GiftEffectLayerState()
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantLoader) {
                Box(Modifier.fillMaxSize()) {
                    Box(Modifier.size(200.dp).testTag("under").clickable { clicks++ })
                    GiftEffectLayer(state, reducedMotion = false)
                }
            }
        }
        rule.mainClock.autoAdvance = false
        rule.mainClock.advanceTimeBy(100)
        rule.runOnIdle { state.play(ev(50_000)) } // a large effect covers the whole screen
        rule.mainClock.advanceTimeBy(500)
        assertEquals("the large effect is on screen", 1, count("gift-effect-large"))
        rule.onNodeWithTag("under").performClick()
        assertEquals("the click reached the content below the layer", 1, clicks)
    }

    @Test
    fun comboCounterAndNoticeText() {
        val state = GiftEffectLayerState()
        layer(state)
        rule.mainClock.autoAdvance = false
        rule.mainClock.advanceTimeBy(100)
        rule.runOnIdle { state.play(ev(10)) }
        rule.mainClock.advanceTimeBy(100)
        assertEquals("one gift: no counter", 0, count("gift-combo"))
        rule.runOnIdle { state.play(ev(10)) }
        rule.mainClock.advanceTimeBy(100)
        rule.onNodeWithTag("gift-combo").assertTextContains("x2")
        rule.runOnIdle { state.play(ev(10)) }
        rule.mainClock.advanceTimeBy(100)
        rule.onNodeWithTag("gift-combo").assertTextContains("x3")
        assertEquals(1, count("gift-notice"))
    }

    @Test
    fun twoSendersShowTwoNoticeLines() {
        val state = GiftEffectLayerState()
        layer(state)
        rule.mainClock.autoAdvance = false
        rule.mainClock.advanceTimeBy(100)
        rule.runOnIdle { state.play(ev(10, sender = "ava")) }
        rule.mainClock.advanceTimeBy(100)
        rule.runOnIdle { state.play(ev(10, sender = "bo")) }
        rule.mainClock.advanceTimeBy(100)
        assertEquals("the newest line keeps the tag", 1, count("gift-notice"))
        assertEquals("the older line", 1, count("gift-notice-line"))
        rule.runOnIdle { assertEquals(listOf("ava", "bo"), state.noticeStack.lines.map { it.data.senderName }) }
    }

    @Test
    fun reducedMotionShowsOnlyTheNotice() {
        val state = GiftEffectLayerState()
        layer(state, reduced = true)
        rule.mainClock.autoAdvance = false
        rule.mainClock.advanceTimeBy(100)
        rule.runOnIdle { state.play(ev(50_000)) }
        rule.mainClock.advanceTimeBy(50)
        assertEquals(0, count("gift-effect-large"))
        assertEquals(1, count("gift-notice"))
    }

    @Test
    fun effectEndsAfterItsTimelineAndNoticeExpires() {
        val state = GiftEffectLayerState()
        val ended = ArrayList<EffectTier>()
        layer(state) { _, tier -> ended.add(tier) }
        rule.mainClock.autoAdvance = false
        rule.mainClock.advanceTimeBy(100)
        rule.runOnIdle { state.play(ev(10)) } // small: 1600 ms, notice 2400 ms
        rule.mainClock.advanceTimeBy(1500)
        assertTrue("not ended at 1500 ms", ended.isEmpty())
        rule.mainClock.advanceTimeBy(200)
        assertEquals(listOf(EffectTier.Small), ended)
        assertEquals(0, count("gift-effect-small"))
        rule.mainClock.advanceTimeBy(1200)
        rule.mainClock.advanceTimeBy(300) // the line's own slide-out
        assertEquals("notice expired", 0, count("gift-notice"))
    }

    @Test
    fun cancelTakesTheEffectAndItsNoticeBack() {
        val state = GiftEffectLayerState()
        layer(state)
        rule.mainClock.autoAdvance = false
        rule.mainClock.advanceTimeBy(100)
        var id = 0
        rule.runOnIdle { id = state.play(ev(350)) }
        rule.mainClock.advanceTimeBy(100)
        assertEquals(1, count("gift-effect-medium"))
        rule.runOnIdle { state.cancel(id) }
        rule.mainClock.advanceTimeBy(50)
        assertEquals(0, count("gift-effect-medium"))
        rule.runOnIdle { assertTrue(state.noticeStack.lines.none { it.visible }) }
    }

    private fun gift(id: String, price: Int) = Gift(id, id.replaceFirstChar { it.uppercase() }, null, price.toLong(), "https://t/$id", null, 0)

    @Test
    fun trayShowsBalanceSelectsAndSends() {
        val sent = ArrayList<String>()
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantLoader) {
                GiftTray(listOf(gift("rose", 10), gift("crown", 5000)), balance = 1234, onSend = { sent.add(it.id) }, sheet = false)
            }
        }
        rule.onNodeWithContentDescription("Balance: 1,234 coins").assertExists()
        rule.onNodeWithContentDescription("Send: Rose").performClick()
        rule.onNodeWithContentDescription("Crown, 5,000 coins").performClick()
        rule.onNodeWithContentDescription("Not enough coins: Crown").assertIsNotEnabled()
        assertEquals(listOf("rose"), sent)
    }

    @Test
    fun trayShowsGetCoinsWhenTooPoorAndTopUpIsAvailable() {
        var topUps = 0
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantLoader) {
                GiftTray(listOf(gift("crown", 5000)), balance = 10, onSend = {}, onTopUp = { topUps++ }, sheet = false)
            }
        }
        rule.onNodeWithContentDescription("Get coins: Crown").assertIsEnabled().performClick()
        rule.onNodeWithContentDescription("Get more coins").performClick()
        assertEquals(2, topUps)
        rule.onNode(hasContentDescription("Crown, 5,000 coins")).assertExists()
    }

    /** A client whose `me` says whether the token is a test token. */
    private class MeApi(private val livemode: Boolean?) : GiftingApi {
        override suspend fun getGifts() = listOf(Gift("rose", "Rose", null, 10, "https://t/rose", null, 0))

        override suspend fun getMe() = Me("ava", 7, livemode)

        override suspend fun getReceivedGifts(user: String): List<ReceivedGift> = emptyList()

        override suspend fun sendGift(input: SendGiftInput): GiftTransaction = error("not used")
    }

    /**
     * A tray fed by a holder, `testMode` left to the default (null: follow the token). [viaTray]: the tray
     * takes everything from the holder (`GiftTray(tray = holder)`); else the host passes the fields itself.
     */
    private fun holderTray(livemode: Boolean?, testMode: Boolean? = null, viaTray: Boolean = false) {
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantLoader) {
                val holder = rememberGiftTrayHolder(MeApi(livemode), receiver = "mert")
                val state by holder.state.collectAsState()
                if (viaTray) {
                    GiftTray(tray = holder, sheet = false, testMode = testMode)
                } else {
                    GiftTray(state.gifts, state.balance, onSend = {}, sheet = false, testMode = testMode)
                }
            }
        }
        // The catalog and the balance have arrived.
        rule.waitUntil(5_000) { rule.onAllNodesWithContentDescription("Balance: 7 coins").fetchSemanticsNodes().isNotEmpty() }
        rule.waitForIdle()
    }

    @Test
    fun badgeShowsByItselfWithATestKeyAndWithoutTheHostPassingAnything() {
        holderTray(livemode = false)
        assertEquals(1, count("gift-test-mode"))
        rule.onNodeWithTag("gift-test-mode").assertTextContains("TEST MODE")
    }

    @Test
    fun badgeShowsWhenTheTrayTakesEverythingFromTheHolder() {
        holderTray(livemode = false, viaTray = true)
        assertEquals(1, count("gift-test-mode"))
    }

    @Test
    fun anExplicitFalseForcesTheBadgeOffEvenWithTheHolderPath() {
        holderTray(livemode = false, testMode = false, viaTray = true)
        assertEquals(0, count("gift-test-mode"))
    }

    @Test
    fun noBadgeWithALiveKeyOrAnOlderServer() {
        holderTray(livemode = true)
        assertEquals(0, count("gift-test-mode"))
    }

    @Test
    fun noBadgeWhenTheServerSaysNothingAboutLivemode() {
        holderTray(livemode = null)
        assertEquals(0, count("gift-test-mode"))
    }

    @Test
    fun anExplicitFalseForcesTheBadgeOff() {
        holderTray(livemode = false, testMode = false)
        assertEquals(0, count("gift-test-mode"))
    }

    @Test
    fun anExplicitTrueShowsTheBadgeWithoutAHolder() {
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantLoader) {
                GiftTray(listOf(gift("rose", 10)), balance = 5, onSend = {}, sheet = false, testMode = true, testModeLabel = "Sandbox")
            }
        }
        rule.onNodeWithTag("gift-test-mode").assertTextContains("SANDBOX")
    }

    @Test
    fun theBadgeAndTheBalanceFitANarrowHeaderWithoutOverlap() {
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantLoader) {
                Box(Modifier.width(300.dp)) {
                    GiftTray(
                        listOf(gift("rose", 10)),
                        balance = 1_234_567,
                        onSend = {},
                        onTopUp = {},
                        title = "Send a gift to Zeynep",
                        sheet = false,
                        testMode = true,
                    )
                }
            }
        }
        val badge = rule.onNodeWithTag("gift-test-mode").fetchSemanticsNode().boundsInRoot
        val balance = rule.onNodeWithTag("gift-balance").fetchSemanticsNode().boundsInRoot
        val topUp = rule.onNodeWithTag("gift-topup").fetchSemanticsNode().boundsInRoot
        assertTrue("badge ends before the balance starts: $badge $balance", badge.right <= balance.left + 0.5f)
        assertTrue("balance ends before + Coins starts: $balance $topUp", balance.right <= topUp.left + 0.5f)
        val tray = rule.onNodeWithTag("gift-tray").fetchSemanticsNode().boundsInRoot
        assertTrue("everything is inside the tray: $topUp $tray", topUp.right <= tray.right + 0.5f && badge.left >= tray.left)
    }

    /** Not run in CI (needs an emulator); written with the sheet and compiled with the library. */
    @Test
    fun sheetStartsAtDefaultAndTheHandleTogglesToPeek() {
        val insets = ArrayList<Float>()
        val gifts = (1..12).map { gift("g$it", 10 * it) }
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantLoader) {
                Box(Modifier.fillMaxSize()) {
                    GiftTray(gifts, balance = 1000, onSend = {}, onInsetChange = { insets.add(it.value) })
                }
            }
        }
        rule.waitForIdle()
        rule.onNodeWithTag("gift-handle").assertExists()
        val atDefault = insets.last()
        rule.onNodeWithTag("gift-handle").performClick()
        rule.waitForIdle()
        assertTrue("peek is lower than default", insets.last() < atDefault)
        rule.onNodeWithTag("gift-handle").performClick()
        rule.waitForIdle()
        assertEquals(atDefault, insets.last(), 0.5f)
    }

    /**
     * Not run in CI (needs an emulator). The first drawn frames of an opening sheet are never above
     * the Default snap (the old bug: one frame fully open, then a spring down), and the sheet is
     * invisible (alpha 0) or lower than its place, never higher, on the way in.
     */
    @Test
    fun sheetNeverRisesAboveItsDefaultSnapWhileItAppears() {
        val gifts = (1..12).map { gift("g$it", 10 * it) }
        rule.mainClock.autoAdvance = false
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantLoader) {
                Box(Modifier.fillMaxSize()) {
                    GiftTray(gifts, balance = 1000, onSend = {})
                }
            }
        }
        val tops = ArrayList<Float>()
        repeat(90) {
            rule.mainClock.advanceTimeByFrame()
            tops.add(rule.onNodeWithTag("gift-handle").fetchSemanticsNode().positionInRoot.y)
        }
        rule.mainClock.autoAdvance = true
        rule.waitForIdle()
        val settled = rule.onNodeWithTag("gift-handle").fetchSemanticsNode().positionInRoot.y
        assertTrue("the sheet was drawn above its Default snap: ${tops.min()} < $settled", tops.min() >= settled - 1f)
        assertEquals(settled, tops.last(), 1f)
    }
}
