package com.giftingstack.ui

import com.giftingstack.core.Gift
import com.giftingstack.core.GiftRef
import com.giftingstack.core.GiftTransaction
import com.giftingstack.core.GiftTrayOptions
import com.giftingstack.core.GiftingApi
import com.giftingstack.core.Me
import com.giftingstack.core.ReceivedGift
import com.giftingstack.core.SendGiftInput
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * "Test mode" (SPEC 9): `GET /v1/client/me` says `livemode: false` for a token made with a test
 * key, and the tray state says `testMode`. An older server without the field: no badge.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TestModeTest {
    private fun me(json: String) = Me.fromJson(Json.parseToJsonElement(json))

    @Test
    fun meReadsAndWritesLivemode() {
        assertEquals(false, me("""{"user":"a","balance":1,"livemode":false}""").livemode)
        assertEquals(true, me("""{"user":"a","balance":1,"livemode":true}""").livemode)
        assertNull(me("""{"user":"a","balance":1}""").livemode)
        assertNull("a string is not a boolean", me("""{"user":"a","balance":1,"livemode":"false"}""").livemode)
        assertEquals(JsonPrimitive(false), Me("a", 1, false).toJson()["livemode"])
        assertFalse(Me("a", 1).toJson().jsonObject.containsKey("livemode"))
    }

    private class Api(private val result: Me) : GiftingApi {
        override suspend fun getGifts() = listOf(Gift("g", "G", null, 30, "i", "b", 0))

        override suspend fun getMe() = result

        override suspend fun getReceivedGifts(user: String): List<ReceivedGift> = emptyList()

        override suspend fun sendGift(input: SendGiftInput): GiftTransaction =
            GiftTransaction("t", "a", input.receiver, GiftRef("g", "G", "i"), 1, 30, 30, null, null, "completed", "2026-01-01T00:00:00Z", 0)
    }

    @Test
    fun trayStateFollowsLivemode() = runTest {
        for ((livemode, expected) in listOf(false to true, true to false, null to false)) {
            val holder = GiftTrayHolder(GiftTrayOptions(Api(Me("a", 5, livemode)), "mert", prefetch = {}), backgroundScope)
            assertFalse(holder.state.value.testMode)
            holder.refresh()
            testScheduler.runCurrent()
            assertEquals("livemode: $livemode", expected, holder.state.value.testMode)
        }
    }

    @Test
    fun theBadgeFollowsTheHoldersThatReportATestToken() {
        // What `GiftTray(testMode = null)` reads: on while any live holder reported a test token.
        val a = Any()
        val b = Any()
        assertFalse(GiftTrayTestMode.active)
        GiftTrayTestMode.report(a, true)
        assertTrue(GiftTrayTestMode.active)
        GiftTrayTestMode.report(b, true)
        GiftTrayTestMode.report(a, false)
        assertTrue("b still reports", GiftTrayTestMode.active)
        GiftTrayTestMode.forget(b)
        assertFalse(GiftTrayTestMode.active)
        GiftTrayTestMode.report(a, true)
        GiftTrayTestMode.forget(a)
        assertFalse("a disposed holder takes its report with it", GiftTrayTestMode.active)
    }

    @Test
    fun theHoldersRefreshFlipsBackWhenTheTokenBecomesLive() = runTest {
        var livemode: Boolean? = false
        val api =
            object : GiftingApi {
                override suspend fun getGifts() = listOf(Gift("g", "G", null, 30, "i", "b", 0))

                override suspend fun getMe() = Me("a", 5, livemode)

                override suspend fun getReceivedGifts(user: String): List<ReceivedGift> = emptyList()

                override suspend fun sendGift(input: SendGiftInput): GiftTransaction = error("not used")
            }
        val holder = GiftTrayHolder(GiftTrayOptions(api, "mert", prefetch = {}), backgroundScope)
        holder.refresh()
        testScheduler.runCurrent()
        assertTrue(holder.state.value.testMode)
        livemode = true
        holder.refresh()
        testScheduler.runCurrent()
        assertFalse(holder.state.value.testMode)
    }
}
