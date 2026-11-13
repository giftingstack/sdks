package com.giftingstack.ui

import com.giftingstack.core.EffectPlayer
import com.giftingstack.core.Gift
import com.giftingstack.core.GiftEffectEvent
import com.giftingstack.core.GiftEffectReceiver
import com.giftingstack.core.GiftRef
import com.giftingstack.core.GiftTransaction
import com.giftingstack.core.GiftTrayOptions
import com.giftingstack.core.GiftingApi
import com.giftingstack.core.GiftingException
import com.giftingstack.core.Me
import com.giftingstack.core.ReceivedGift
import com.giftingstack.core.SendGiftInput
import com.giftingstack.core.TrayReceiver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The holder side of SPEC 21 (the receiver picker): who the next gift goes to, on the JVM. */
@OptIn(ExperimentalCoroutinesApi::class)
class ReceiverPickerTest {
    private class Api : GiftingApi {
        val sent = ArrayList<String>()
        var fail = false

        override suspend fun getGifts(): List<Gift> = emptyList()

        override suspend fun getMe(): Me = Me("viewer", 1_000)

        override suspend fun getReceivedGifts(user: String): List<ReceivedGift> = emptyList()

        override suspend fun sendGift(input: SendGiftInput): GiftTransaction {
            if (fail) throw GiftingException(500, "internal_error", "no")
            sent.add(input.receiver)
            return GiftTransaction("gtx_1", "viewer", input.receiver, GiftRef("rose", "Rose", null), 1, 1, 1, null, null, "completed", "2026-11-13T00:00:00Z", 999)
        }
    }

    private val rose = Gift("rose", "Rose", null, 1, null, null, 0)
    private val sides = listOf(TrayReceiver("mia", "Mia"), TrayReceiver("theo", "Theo", "#2ec4b6"))

    private fun holder(
        api: Api,
        receivers: List<TrayReceiver> = emptyList(),
        receiver: String = "host",
        changes: MutableList<String>? = null,
        receiverOf: ((String) -> GiftEffectReceiver?)? = null,
    ) = GiftTrayHolder(
        GiftTrayOptions(api, receiver, receiverOf = receiverOf),
        CoroutineScope(UnconfinedTestDispatcher()),
        receivers = receivers,
        onReceiverChange = changes?.let { c -> { id: String -> c.add(id) } },
    )

    @Test
    fun withoutReceiversNothingChanges() {
        val api = Api()
        val h = holder(api)
        assertEquals("host", h.receiver)
        assertFalse("no sides: nothing to pick", h.selectReceiver("mia"))
        h.send(rose)
        assertEquals(listOf("host"), api.sent)
        assertEquals("host", h.receiver)
    }

    @Test
    fun theFirstSideByDefaultAndThePickWins() {
        val api = Api()
        val changes = ArrayList<String>()
        val h = holder(api, sides, changes = changes)
        assertEquals("mia", h.receiver)
        assertTrue(h.selectReceiver("theo"))
        assertEquals("theo", h.receiver)
        assertEquals(listOf("theo"), changes)
        assertTrue("same pick again: no change told", h.selectReceiver("theo"))
        assertEquals(listOf("theo"), changes)
        h.send(rose)
        assertEquals(listOf("theo"), api.sent)
    }

    @Test
    fun anIdThatIsNotASideIsIgnored() {
        val h = holder(Api(), sides)
        assertFalse(h.selectReceiver("zoe"))
        assertEquals("mia", h.receiver)
    }

    @Test
    fun theFallbackReceiverWinsWhenItIsASide() {
        assertEquals("theo", holder(Api(), sides, receiver = "theo").receiver)
        assertEquals("mia", holder(Api(), sides, receiver = "zoe").receiver)
    }

    @Test
    fun aNewRoundStartsAtTheSideGiftedLast() {
        val api = Api()
        val h = holder(api, sides)
        h.selectReceiver("theo")
        h.send(rose)
        // Next round: new list, the pick is gone with it; theo was gifted last and is still a side.
        h.receivers = listOf(TrayReceiver("ava", "Ava"), TrayReceiver("theo", "Theo"))
        assertEquals("theo", h.receiver)
        // A round without theo: the first side.
        h.receivers = listOf(TrayReceiver("ava", "Ava"), TrayReceiver("zoe", "Zoe"))
        assertEquals("ava", h.receiver)
    }

    @Test
    fun aNewListKeepsThePickWhenItIsStillASide() {
        val changes = ArrayList<String>()
        val h = holder(Api(), sides, changes = changes)
        h.selectReceiver("theo")
        h.receivers = sides + TrayReceiver("ava", "Ava")
        assertEquals("theo", h.receiver)
        assertEquals(listOf("theo"), changes)
        // The pick left the list: it is forgotten (it does not come back with a later list).
        h.receivers = listOf(TrayReceiver("ava", "Ava"), TrayReceiver("mia", "Mia"))
        assertEquals("ava", h.receiver)
        h.receivers = sides
        assertEquals("mia", h.receiver)
        assertEquals(listOf("theo", "ava", "mia"), changes)
    }

    @Test
    fun aFailedSendDoesNotBecomeTheLastSide() {
        val api = Api()
        val h = holder(api, sides)
        h.selectReceiver("theo")
        api.fail = true
        h.send(rose)
        h.selectReceiver("mia")
        h.receivers = listOf(TrayReceiver("ava", "Ava"), TrayReceiver("theo", "Theo"))
        assertEquals("ava", h.receiver)
    }

    @Test
    fun theEffectSaysWhoGotIt() {
        val played = ArrayList<GiftEffectEvent>()
        val player =
            object : EffectPlayer {
                override fun play(event: GiftEffectEvent): Int {
                    played.add(event)
                    return played.size
                }

                override fun cancel(id: Int) = Unit
            }
        val h =
            GiftTrayHolder(
                GiftTrayOptions(Api(), "host", effects = { player }, receiverOf = { id -> GiftEffectReceiver(id.uppercase()) }),
                CoroutineScope(UnconfinedTestDispatcher()),
                receivers = sides,
            )
        h.selectReceiver("theo")
        h.send(rose)
        assertEquals("THEO", played.single().receiver?.name)
    }

    /** SPEC 21.3: the row scrolls the least distance that shows the whole selected side. */
    @Test
    fun revealScrollOffsetMovesTheLeastDistance() {
        // Row 300 px wide, content 500 px (max 200), at 0.
        // Already in sight: no move.
        assertEquals(0, revealScrollOffset(current = 0, viewport = 300, start = 100, end = 200, max = 200))
        assertEquals(50, revealScrollOffset(current = 50, viewport = 300, start = 50, end = 350, max = 200))
        // Cut off on the right: its end at the right edge.
        assertEquals(80, revealScrollOffset(current = 0, viewport = 300, start = 250, end = 380, max = 200))
        assertEquals(150, revealScrollOffset(current = 100, viewport = 300, start = 300, end = 450, max = 200))
        // Cut off on the left: its start at the left edge.
        assertEquals(40, revealScrollOffset(current = 150, viewport = 300, start = 40, end = 100, max = 200))
        assertEquals(140, revealScrollOffset(current = 150, viewport = 300, start = 140, end = 200, max = 200))
        // Wider than the row: its start at the left edge.
        assertEquals(60, revealScrollOffset(current = 0, viewport = 100, start = 60, end = 200, max = 400))
        // Clamped to the scroll range.
        assertEquals(200, revealScrollOffset(current = 0, viewport = 300, start = 420, end = 520, max = 200))
        assertEquals(0, revealScrollOffset(current = 10, viewport = 300, start = -5, end = 30, max = 200))
        // No overflow (max 0): never moves.
        assertEquals(0, revealScrollOffset(current = 0, viewport = 300, start = 250, end = 320, max = 0))
    }
}
