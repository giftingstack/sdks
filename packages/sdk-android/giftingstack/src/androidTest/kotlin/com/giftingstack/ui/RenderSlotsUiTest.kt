package com.giftingstack.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.giftingstack.core.AwayAckOn
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

private object InstantImages : GiftImageLoader {
    private val bmp = ImageBitmap(8, 8)

    override fun peek(url: String) = bmp

    override suspend fun load(url: String) = bmp

    override fun prefetch(url: String) {}
}

private fun received(id: String, name: String, count: Int) = ReceivedGift(GiftRef(id, name, "https://t/$id"), count)

/**
 * Compose tests of the render slots (`renderChip`, `renderRow`, `renderSummary`): a custom body is
 * drawn, null falls back to the default, the actions still fire and the accessibility labels stay.
 * They need a device or an emulator (`connectedDebugAndroidTest`).
 */
class RenderSlotsUiTest {
    @get:Rule val rule = createComposeRule()

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().size

    // ------------------------------------------------------------ wall

    private val noWall =
        object : GiftWallApi {
            override suspend fun queryGiftWalls(items: List<GiftWallQueryItem>): List<GiftWall> = error("no request expected")
        }

    private val gifts = listOf(received("rose", "Rose", 12), received("star", "Star", 10), received("hat", "Hat", 9))

    @Test
    fun customChipIsDrawnAndTheOverflowChipStaysDefault() {
        val seen = ArrayList<String>()
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantImages) {
                GiftWall(
                    noWall,
                    user = "mateo",
                    data = gifts,
                    max = 3,
                    reducedMotion = true,
                    renderChip = { chip ->
                        seen.add("${chip.gift.id}:${chip.count}:${chip.countText}")
                        BasicText("mine ${chip.gift.id}")
                    },
                )
            }
        }
        rule.onNodeWithText("mine rose", useUnmergedTree = true).assertExists()
        assertEquals("the overflow chip is never passed", listOf("rose:12:12", "star:10:10"), seen.distinct())
        rule.onNodeWithTag("gift-wall-overflow", useUnmergedTree = true).assertExists()
    }

    @Test
    fun defaultChipWhenNoSlotAndDefaultInsideTheSlot() {
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantImages) {
                GiftWall(noWall, user = "a", data = listOf(received("rose", "Rose", 12)), reducedMotion = true)
                GiftWall(
                    noWall,
                    user = "b",
                    data = listOf(received("star", "Star", 7)),
                    reducedMotion = true,
                    renderChip = { chip -> chip.Default() },
                )
            }
        }
        rule.onNodeWithText("12", useUnmergedTree = true).assertExists()
        rule.onNodeWithText("7", useUnmergedTree = true).assertExists()
    }

    @Test
    fun customChipKeepsThePressAndTheSpokenLabel() {
        val pressed = ArrayList<String>()
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantImages) {
                GiftWall(
                    noWall,
                    user = "mateo",
                    data = listOf(received("rose", "Rose", 12)),
                    onPressChip = { pressed.add(it.id) },
                    reducedMotion = true,
                    renderChip = { BasicText("mine") },
                )
            }
        }
        rule.onNodeWithContentDescription("Rose, 12").performClick()
        assertEquals(listOf("rose"), pressed)
    }

    @Test
    fun readOnlyWallWithCustomChipsKeepsItsOneSummaryLabel() {
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantImages) {
                GiftWall(noWall, user = "mateo", data = gifts, reducedMotion = true, renderChip = { BasicText("mine ${it.gift.id}") })
            }
        }
        rule.onNodeWithContentDescription("Gifts: 12 Roses, 10 Stars, 9 Hats").assertExists()
    }

    // ------------------------------------------------------------ leaderboard

    private fun board(metric: LeaderboardMetric = LeaderboardMetric.Units) =
        Leaderboard(
            LeaderboardBoard.Senders, LeaderboardPeriod.Week, metric, "2026-W41", null, null, "t",
            listOf(LeaderboardEntry(1, "ava", 120, 54_000), LeaderboardEntry(2, "mateo", 300, 41_000)),
            false,
            LeaderboardMe("me", 417, 3, 120, false),
        )

    private class BoardClient(val board: Leaderboard) : LeaderboardApi {
        override suspend fun getLeaderboard(board: LeaderboardBoard, query: LeaderboardQuery): Leaderboard = this.board
    }

    @Test
    fun customRowIsDrawnWithComputedDataAndThePinnedRowStaysDefault() {
        val seen = ArrayList<LeaderboardRowContext>()
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantImages) {
                GiftLeaderboard(
                    BoardClient(board()),
                    limit = 3,
                    highlightUser = "mateo",
                    reducedMotion = true,
                    renderRow = { row ->
                        seen.add(row)
                        BasicText("mine #${row.rank} ${row.name} ${row.scoreText}")
                    },
                )
            }
        }
        rule.waitUntil(5_000) { count("gift-lb-list") == 1 }
        rule.onNodeWithText("mine #1 ava 54K", useUnmergedTree = true).assertExists()
        val ava = seen.last { it.entry.user == "ava" }
        assertEquals(54_000L, ava.score)
        assertEquals(LeaderboardMetric.Units, ava.metric)
        assertTrue(!ava.isMe)
        assertTrue(seen.last { it.entry.user == "mateo" }.isMe)
        rule.onNodeWithContentDescription("Your rank: 417, 120 coins").assertExists()
    }

    @Test
    fun defaultRowWhenNoSlotAndDefaultInsideTheSlot() {
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantImages) {
                GiftLeaderboard(BoardClient(board()), limit = 3, reducedMotion = true, renderRow = { it.Default() })
            }
        }
        rule.waitUntil(5_000) { count("gift-lb-list") == 1 }
        rule.onNodeWithText("ava", useUnmergedTree = true).assertExists()
        rule.onNodeWithTag("gift-lb-medal-1", useUnmergedTree = true).assertExists()
    }

    @Test
    fun customRowKeepsThePressAndTheSpokenLabel() {
        val pressed = ArrayList<String>()
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantImages) {
                GiftLeaderboard(
                    BoardClient(board()),
                    limit = 3,
                    reducedMotion = true,
                    onPressUser = { pressed.add(it) },
                    renderRow = { BasicText("mine ${it.name}") },
                )
            }
        }
        rule.waitUntil(5_000) { count("gift-lb-list") == 1 }
        rule.onNodeWithContentDescription("Rank 1, ava, 54,000 coins").performClick()
        assertEquals(listOf("ava"), pressed)
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
    fun customSummaryBodyReplacesTheDefaultAndKeepsTheAnnouncement() {
        val client = AwayClient(summary())
        var seen: AwaySummaryContext? = null
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantImages) {
                Box(Modifier.fillMaxSize()) {
                    GiftAwaySummary(
                        client,
                        reducedMotion = true,
                        renderSummary = { s ->
                            seen = s
                            BasicText("mine ${s.headline}")
                        },
                    )
                }
            }
        }
        rule.waitUntil(5_000) { count("gift-away-card") == 1 }
        rule.onNodeWithText("mine 3 gifts from 1 person", useUnmergedTree = true).assertExists()
        rule.onNodeWithContentDescription("You received 3 gifts from 1 person while you were away").assertExists()
        assertEquals(0, count("gift-away-dismiss"))
        assertEquals("3 gifts", seen!!.gifts)
        assertEquals("1 person", seen!!.people)
        assertEquals("ava", seen!!.senders.single().name)
    }

    @Test
    fun customSummaryTapDoesNotDismissButDismissAndAckDo() {
        val client = AwayClient(summary())
        var done = 0
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantImages) {
                Box(Modifier.fillMaxSize()) {
                    GiftAwaySummary(
                        client,
                        reducedMotion = true,
                        ackOn = AwayAckOn.Manual,
                        onDone = { done++ },
                        renderSummary = { s ->
                            Column {
                                BasicText("mine", Modifier.testTag("mine"))
                                BasicText("seen", Modifier.testTag("seen").clickable { s.ack() })
                                BasicText("close", Modifier.testTag("close").clickable { s.dismiss() })
                            }
                        },
                    )
                }
            }
        }
        rule.waitUntil(5_000) { count("gift-away-card") == 1 }
        rule.onNodeWithTag("mine").performClick()
        rule.waitForIdle()
        assertEquals("a tap on custom content does not dismiss", 1, count("gift-away-card"))
        rule.onNodeWithTag("seen").performClick()
        rule.waitUntil(5_000) { client.acks.size == 1 }
        rule.onNodeWithTag("close").performClick()
        rule.waitUntil(5_000) { count("gift-away-card") == 0 }
        assertEquals(1, done)
    }

    @Test
    fun defaultInsideTheSummarySlotDrawsTheDefaultBody() {
        val client = AwayClient(summary())
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides InstantImages) {
                Box(Modifier.fillMaxSize()) { GiftAwaySummary(client, reducedMotion = true, renderSummary = { it.Default() }) }
            }
        }
        rule.waitUntil(5_000) { count("gift-away-card") == 1 }
        rule.onNodeWithContentDescription("ava, 3 gifts").assertExists()
        rule.onNodeWithContentDescription("Dismiss").assertExists()
    }
}
