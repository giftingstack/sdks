package com.giftingstack.ui

import com.giftingstack.core.EffectGift
import com.giftingstack.core.EffectQuality
import com.giftingstack.core.EffectTier
import com.giftingstack.core.Gift
import com.giftingstack.core.GiftEffectEvent
import com.giftingstack.core.GiftTransaction
import com.giftingstack.core.GiftRef
import com.giftingstack.core.GiftTrayOptions
import com.giftingstack.core.GiftingApi
import com.giftingstack.core.Me
import com.giftingstack.core.ReceivedGift
import com.giftingstack.core.SendGiftInput
import com.giftingstack.core.recipeFor
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Logic of the UI state holders that needs no device (the rest is in the instrumented tests). */
@OptIn(ExperimentalCoroutinesApi::class)
class UiLogicTest {
    private fun ev(price: Int) = GiftEffectEvent(EffectGift("g", "G", price.toLong(), null), "ayla")

    @Test
    fun timelineEndsMatchSpec() {
        // spec 7.3: small 1600, medium 2100, large 3850 (high) or 3050 (low: no coins)
        assertEquals(1600, EffectTimeline(recipeFor(EffectTier.Small)).totalMs)
        assertEquals(2100, EffectTimeline(recipeFor(EffectTier.Medium)).totalMs)
        assertEquals(3850, EffectTimeline(recipeFor(EffectTier.Large)).totalMs)
        assertEquals(3050, EffectTimeline(recipeFor(EffectTier.Large, EffectQuality.Low)).totalMs)
    }

    @Test
    fun timelinePhasesFollowTheTable() {
        val t = EffectTimeline(recipeFor(EffectTier.Large))
        assertEquals(0f, t.fly(0f), 1e-6f)
        assertEquals(1f, t.fly(900f), 1e-6f)
        assertTrue("fly overshoots", (0..900 step 10).any { t.fly(it.toFloat()) > 1.01f })
        assertEquals(1f, t.dim(300f), 1e-6f)
        assertEquals(1f, t.dim(900f + 1600f), 1e-6f)
        assertEquals(0f, t.dim(3050f), 1e-6f)
        assertEquals(0f, t.burst(900f), 1e-6f)
        assertEquals(1f, t.burst(1800f), 1e-6f)
        assertEquals(0f, t.leave(2500f), 1e-6f)
        assertEquals(1f, t.leave(3050f), 1e-6f)
        assertEquals(0f, t.raysFade(0f), 1e-6f)
        assertEquals(1f, t.raysFade(0.5f * 3050f), 1e-6f)
        assertEquals(0f, t.raysFade(3050f), 1e-6f)
    }

    @Test
    fun layerStateIdsStartAtOneAndSurviveClear() {
        val s = GiftEffectLayerState()
        assertEquals(1, s.play(ev(10)))
        assertEquals(2, s.play(ev(10)))
        s.clear()
        assertEquals(3, s.play(ev(10)))
        assertEquals(1, s.items.size)
    }

    @Test
    fun layerStateMirrorsTheScheduler() {
        val s = GiftEffectLayerState()
        val a = s.play(ev(10))
        assertEquals(listOf(a), s.items.map { it.id })
        assertTrue("notice waits for started()", s.noticeStack.lines.isEmpty())
        s.scheduler.started(a)
        assertEquals(listOf("G"), s.noticeStack.lines.map { it.data.giftName })
        assertTrue(s.noticeStack.lines.single().visible)
        s.cancel(a)
        assertTrue(s.items.isEmpty())
        assertTrue(s.noticeStack.lines.none { it.visible })
    }

    @Test
    fun layerStateCallsOnEffectEndOnlyForFinishedEffects() {
        val s = GiftEffectLayerState()
        val ended = ArrayList<EffectTier>()
        s.onEffectEnd = { _, tier -> ended.add(tier) }
        val a = s.play(ev(10))
        val b = s.play(ev(10))
        s.cancel(b)
        s.scheduler.finished(a)
        s.scheduler.finished(b)
        assertEquals(listOf(EffectTier.Small), ended)
    }

    private class Api : GiftingApi {
        var balance = 100L
        val gift = Gift("g", "G", null, 30, "i", "b", 0)

        override suspend fun getGifts() = listOf(gift)

        override suspend fun getMe() = Me("ayla", balance)

        override suspend fun getReceivedGifts(user: String): List<ReceivedGift> = emptyList()

        override suspend fun sendGift(input: SendGiftInput): GiftTransaction {
            balance -= gift.price
            return GiftTransaction("t", "ayla", input.receiver, GiftRef("g", "G", "i"), 1, 30, 30, null, null, "completed", "2026-01-01T00:00:00Z", balance)
        }
    }

    @Test
    fun trayHolderLoadsPlaysAndReconciles() = runTest {
        val api = Api()
        val layer = GiftEffectLayerState()
        val prefetched = ArrayList<String>()
        val scope = backgroundScope
        val holder =
            com.giftingstack.ui.GiftTrayHolder(
                GiftTrayOptions(api, "mert", effects = { layer }, prefetch = { prefetched.add(it) }),
                scope,
            )
        holder.refresh()
        testScheduler.runCurrent()
        assertEquals(100, holder.state.value.balance)
        assertEquals("icons only: the big pictures load when they play (SPEC 8 step 2)", listOf("i"), prefetched)
        holder.send(api.gift)
        testScheduler.runCurrent()
        assertEquals("optimistic balance and an effect at the tap", 70, holder.state.value.balance)
        assertEquals(1, layer.items.size)
        testScheduler.runCurrent()
        assertEquals(70, holder.state.value.balance)
        assertEquals("ayla", layer.items.first().event.sender)
    }
}
