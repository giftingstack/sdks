package com.giftingstack.core

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

/** Malformed 2xx (SPEC 3.5, audit R-05), 64-bit money (R-06) and app callbacks that throw (R-14). */
@OptIn(ExperimentalCoroutinesApi::class)
class RobustnessTest {
    private suspend fun failure(block: suspend () -> Unit): GiftingException {
        try {
            block()
        } catch (e: GiftingException) {
            return e
        }
        fail("expected a GiftingException")
        throw IllegalStateException()
    }

    @Test
    fun aTwoXxThatIsNotJsonIsInvalidResponseWithoutItsText() = runBlocking {
        val client =
            GiftingClient(
                { "t" },
                transport = { TransportResponse(200, mapOf("X-Request-Id" to "req_9"), "<html>Captive portal secret-text</html>") },
            )
        val e = failure { client.getMe() }
        assertEquals(200, e.status)
        assertEquals("invalid_response", e.type)
        assertEquals("Invalid response (200).", e.message)
        assertEquals("req_9", e.requestId)
        assertFalse(e.retryable)
        assertFalse(e.toString().contains("secret-text"))
    }

    @Test
    fun jsonOfTheWrongShapeIsInvalidResponseToo() = runBlocking {
        val client = GiftingClient({ "t" }, transport = { TransportResponse(200, body = "[1,2]") })
        val e = failure { client.getMe() }
        assertEquals("invalid_response", e.type)
        assertNull(e.requestId)
    }

    @Test
    fun anInvalidTwoXxIsNotRetried() = runBlocking {
        var calls = 0
        val client = GiftingClient({ "t" }, transport = { calls++; TransportResponse(200, body = "oops") })
        failure { client.getGifts() }
        assertEquals(1, calls)
    }

    @Test
    fun moneyAboveTwoBillionSurvives() = runBlocking {
        val big = 5_000_000_000L
        val me = """{"user":"ayla","balance":$big}"""
        val client = GiftingClient({ "t" }, transport = { TransportResponse(200, body = me) })
        assertEquals(big, client.getMe().balance)
        val gift = Gift.fromJson(kotlinx.serialization.json.Json.parseToJsonElement("""{"id":"g","name":"G","price":$big,"sort_order":0}"""))
        assertEquals(big, gift.price)
        assertEquals(big, gift.toJson()["price"]?.let { (it as kotlinx.serialization.json.JsonPrimitive).content.toLong() })
    }

    // --- tray callbacks ---

    private class Api : GiftingApi {
        var fail = false
        var balance = 1000L
        val gift = Gift("g", "G", null, 100, null, null, 0)

        override suspend fun getGifts() = listOf(gift)

        override suspend fun getMe() = Me("ayla", balance)

        override suspend fun getReceivedGifts(user: String): List<ReceivedGift> = emptyList()

        override suspend fun sendGift(input: SendGiftInput): GiftTransaction {
            if (fail) throw GiftingException(500, "internal_error", "boom")
            balance -= gift.price
            return GiftTransaction("t", "ayla", input.receiver, GiftRef("g", "G", null), 1, 100, 100, null, null, "completed", "2026-01-01T00:00:00Z", balance)
        }
    }

    @Test
    fun aThrowingOnSentKeepsTheBalanceChargedAndSetsNoError() = runTest {
        var errors = 0
        val api = Api()
        val c = GiftTrayController(GiftTrayOptions(api, "bob", onSent = { throw IllegalStateException("app bug") }, onError = { errors++ }))
        c.refresh()
        c.send(api.gift)
        assertEquals(900L, c.state.value.balance)
        assertNull(c.state.value.error)
        assertEquals(0, errors)
    }

    @Test
    fun aThrowingOnErrorIsIgnoredAndTheRefundStillHappens() = runTest {
        val api = Api().also { it.fail = true }
        val c = GiftTrayController(GiftTrayOptions(api, "bob", onError = { throw IllegalStateException("app bug") }))
        c.refresh()
        c.send(api.gift)
        assertEquals(1000L, c.state.value.balance)
        assertEquals("internal_error", c.state.value.error?.type)
    }
}
