package com.giftingstack.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import com.giftingstack.core.AwayApi
import com.giftingstack.core.AwayGift
import com.giftingstack.core.AwayGroup
import com.giftingstack.core.AwayQuery
import com.giftingstack.core.AwaySender
import com.giftingstack.core.AwaySummary
import com.giftingstack.core.AwayTopSender
import com.giftingstack.core.GiftRef
import com.giftingstack.core.GiftWall
import com.giftingstack.core.GiftWallApi
import com.giftingstack.core.GiftWallQueryItem
import com.giftingstack.core.GiftingException
import com.giftingstack.core.Leaderboard
import com.giftingstack.core.LeaderboardApi
import com.giftingstack.core.LeaderboardBoard
import com.giftingstack.core.LeaderboardEntry
import com.giftingstack.core.LeaderboardMe
import com.giftingstack.core.LeaderboardMetric
import com.giftingstack.core.LeaderboardPeriod
import com.giftingstack.core.LeaderboardQuery
import com.giftingstack.core.ReceivedGift
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Everything is already "loaded": no network in UI tests. */
private object Instant : GiftImageLoader {
    private val bmp = ImageBitmap(8, 8)

    override fun peek(url: String) = bmp

    override suspend fun load(url: String) = bmp

    override fun prefetch(url: String) {}
}

private fun rec(id: String, name: String, count: Int) = ReceivedGift(GiftRef(id, name, "https://t/$id"), count)

/**
 * Compose tests of the gift wall, the away card and the leaderboard. They need a device or an
 * emulator (`connectedDebugAndroidTest`); the pure rules behind them run on the JVM.
 */
class ComponentsUiTest {
    @get:Rule val rule = createComposeRule()

    // ------------------------------------------------------------ wall

    private class WallClient(val answer: (List<GiftWallQueryItem>) -> List<GiftWall>) : GiftWallApi {
        val asked = ArrayList<List<GiftWallQueryItem>>()

        override suspend fun queryGiftWalls(items: List<GiftWallQueryItem>): List<GiftWall> {
            asked.add(items)
            return answer(items)
        }
    }

    private val noWall = WallClient { error("no request expected") }

    @Test
    fun wallWithDataIsOneLabelledElement() {
        val data = listOf(rec("rose", "Rose", 40), rec("hat", "Hat", 20), rec("a", "A", 12), rec("b", "B", 10), rec("c", "C", 7))
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides Instant) {
                GiftWall(noWall, user = "mateo", data = data, max = 3, reducedMotion = true)
            }
        }
        rule.onNodeWithContentDescription("Gifts: 40 Roses, 20 Hats, and 29 more").assertExists()
        rule.onNodeWithTag("gift-wall-overflow", useUnmergedTree = true).assertExists()
        assertTrue("data given: no request", noWall.asked.isEmpty())
    }

    @Test
    fun tappableChipsAreButtonsWithTheirOwnLabel() {
        val pressed = ArrayList<String>()
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides Instant) {
                GiftWall(noWall, user = "mateo", data = listOf(rec("rose", "Rose", 12)), onPressChip = { pressed.add(it.id) }, reducedMotion = true)
            }
        }
        rule.onNodeWithContentDescription("Rose, 12").performClick()
        assertEquals(listOf("rose"), pressed)
    }

    @Test
    fun wallLoadsThroughTheSharedLoader() {
        val ok = WallClient { items -> items.map { GiftWall(it.receiver, it.reference, listOf(rec("rose", "Rose", 3))) } }
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides Instant) {
                GiftWall(ok, user = "mateo", reference = "post_1", reducedMotion = true)
            }
        }
        rule.waitUntil(5_000) { rule.onAllNodesCount("gift-wall") == 1 }
        rule.onNodeWithContentDescription("Gifts: 3 Roses").assertExists()
        assertEquals(listOf(listOf(GiftWallQueryItem("mateo", "post_1"))), ok.asked)
    }

    @Test
    fun aFailedWallDrawsNothingAndOnlyReportsTheError() {
        val errors = ArrayList<String>()
        val failing = WallClient { throw GiftingException(0, "network_error", "x") }
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides Instant) {
                GiftWall(failing, user = "ava", onError = { errors.add(it.type) }, reducedMotion = true)
            }
        }
        rule.waitUntil(5_000) { errors.isNotEmpty() }
        assertEquals(listOf("network_error"), errors)
        assertEquals(0, rule.onAllNodesCount("gift-wall"))
        assertEquals(0, rule.onAllNodesCount("gift-wall-skeleton"))
    }

    // ------------------------------------------------------------ away

    private fun summary() =
        AwaySummary(
            "me", "s", "e", "cur1", false, 3, 30, 1,
            listOf(AwayGroup(AwayGift("rose", "Rose", 10, "https://t/r", null), 3, 30, 1, listOf(AwaySender("ava", 3)))),
            listOf(AwayTopSender("ava", 3, 30)),
        )

    private class AwayClient(val summary: AwaySummary) : AwayApi {
        val acks = ArrayList<String>()

        override suspend fun getAway(query: AwayQuery) = summary

        override suspend fun ackAway(cursor: String) {
            acks.add(cursor)
        }
    }

    @Test
    fun awayCardAnnouncesAcknowledgesOnceAndDismisses() {
        val client = AwayClient(summary())
        var done = 0
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides Instant) {
                Box(Modifier.fillMaxSize()) { GiftAwaySummary(client, reducedMotion = true, onDone = { done++ }) }
            }
        }
        rule.waitUntil(5_000) { rule.onAllNodesCount("gift-away-card") == 1 }
        rule.onNodeWithContentDescription("You received 3 gifts from 1 person while you were away").assertExists()
        rule.onNodeWithContentDescription("ava, 3 gifts").assertExists()
        rule.waitUntil(5_000) { client.acks.size == 1 }
        rule.onNodeWithContentDescription("Dismiss").performClick()
        rule.waitUntil(5_000) { rule.onAllNodesCount("gift-away-card") == 0 }
        assertEquals(1, done)
        assertEquals("acknowledged once, with the cursor that was shown", listOf("cur1"), client.acks)
    }

    @Test
    fun awayReplayPlaysThroughTheLayerButNotUnderReducedMotion() {
        val reducedState = GiftEffectLayerState()
        val client = AwayClient(summary())
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides Instant) {
                Box(Modifier.fillMaxSize()) {
                    GiftAwaySummary(client, effects = reducedState, reducedMotion = true)
                    GiftEffectLayer(reducedState, reducedMotion = true)
                }
            }
        }
        rule.waitUntil(5_000) { rule.onAllNodesCount("gift-away-card") == 1 }
        rule.waitForIdle()
        assertTrue("reduced motion: the card only", reducedState.scheduler.notice().data == null)
    }

    @Test
    fun awayReplayPlaysThroughTheLayer() {
        val state = GiftEffectLayerState()
        val client = AwayClient(summary())
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides Instant) {
                Box(Modifier.fillMaxSize()) {
                    GiftAwaySummary(client, effects = state, reducedMotion = false)
                    GiftEffectLayer(state, reducedMotion = false)
                }
            }
        }
        rule.waitUntil(5_000) { state.scheduler.notice().data != null }
        assertEquals("the notice names the sender", "ava", state.scheduler.notice().data!!.senderName)
    }

    // ------------------------------------------------------------ leaderboard

    private fun board(metric: LeaderboardMetric = LeaderboardMetric.Units) =
        Leaderboard(
            LeaderboardBoard.Senders, LeaderboardPeriod.Week, metric, "2026-W41", null, null, "t",
            listOf(LeaderboardEntry(1, "ava", 120, 54_000), LeaderboardEntry(2, "mateo", 300, 41_000), LeaderboardEntry(2, "emma", 80, 41_000)),
            false,
            LeaderboardMe("me", 417, 3, 120, false),
        )

    private class BoardClient(val fail: Int, val board: Leaderboard) : LeaderboardApi {
        var calls = 0

        override suspend fun getLeaderboard(board: LeaderboardBoard, query: LeaderboardQuery): Leaderboard {
            calls++
            if (calls <= fail) throw GiftingException(503, "leaderboard_building", "x")
            return this.board
        }
    }

    @Test
    fun leaderboardRowsTabsAndPinnedRowAreLabelled() {
        val client = BoardClient(0, board())
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides Instant) {
                GiftLeaderboard(client, limit = 3, reducedMotion = true)
            }
        }
        rule.waitUntil(5_000) { rule.onAllNodesCount("gift-lb-list") == 1 }
        rule.onNodeWithContentDescription("Rank 1, ava, 54,000 coins").assertExists()
        rule.onNodeWithContentDescription("Rank 2, emma, 41,000 coins").assertExists()
        rule.onNodeWithContentDescription("Your rank: 417, 120 coins").assertExists()
        rule.onNodeWithTag("gift-lb-tab-week").assertIsSelected()
        rule.onNodeWithTag("gift-lb-medal-1", useUnmergedTree = true).assertExists()
    }

    @Test
    fun leaderboardErrorOffersTryAgain() {
        val client = BoardClient(1, board())
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides Instant) {
                GiftLeaderboard(client, limit = 3, reducedMotion = true)
            }
        }
        rule.waitUntil(5_000) { rule.onAllNodesCount("gift-lb-error") == 1 }
        rule.onNodeWithTag("gift-lb-retry").performClick()
        rule.waitUntil(5_000) { rule.onAllNodesCount("gift-lb-list") == 1 }
        assertEquals(2, client.calls)
    }

    private fun androidx.compose.ui.test.junit4.ComposeContentTestRule.onAllNodesCount(tag: String) =
        onAllNodes(androidx.compose.ui.test.hasTestTag(tag)).fetchSemanticsNodes().size
}
