package com.giftingstack.core

import java.io.IOException
import java.net.SocketTimeoutException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** SPEC 3.4 (audit R-18): `sendGift` repeats one lost connection; nothing else is repeated. */
class LostConnectionRepeatTest {
    private class Recorder(private val fail: (Int) -> Throwable?) {
        val keys = ArrayList<String?>()

        val transport =
            GiftingTransport { req ->
                keys.add(req.headers["Idempotency-Key"])
                fail(keys.size)?.let { throw it }
                TransportResponse(200, body = "{}")
            }
    }

    private suspend fun networkError(block: suspend () -> Unit) {
        try {
            block()
            fail("expected network_error")
        } catch (e: GiftingException) {
            assertEquals("network_error", e.type)
        }
    }

    @Test
    fun twoLostConnectionsInARowEndAfterTwoRequestsWithTheSameKey() = runBlocking {
        val r = Recorder { IOException("reset") }
        networkError { GiftingClient({ "t" }, transport = r.transport).sendGift(SendGiftInput(receiver = "bob", giftId = "rose")) }
        assertEquals(2, r.keys.size)
        assertTrue(r.keys[0]!!.isNotEmpty())
        assertEquals(r.keys[0], r.keys[1])
    }

    @Test
    fun aTimeoutIsNotRepeated() = runBlocking {
        val r = Recorder { SocketTimeoutException("slow") }
        networkError { GiftingClient({ "t" }, transport = r.transport).sendGift(SendGiftInput(receiver = "bob", giftId = "rose")) }
        assertEquals(1, r.keys.size)
    }

    @Test
    fun aGetIsNeverRepeated() = runBlocking {
        val r = Recorder { IOException("reset") }
        networkError { GiftingClient({ "t" }, transport = r.transport).getGifts() }
        assertEquals(1, r.keys.size)
    }

    @Test
    fun aSendWithAnEmptyKeyIsNeverRepeated() = runBlocking {
        val r = Recorder { IOException("reset") }
        networkError {
            GiftingClient({ "t" }, transport = r.transport).sendGift(SendGiftInput(receiver = "bob", giftId = "rose", idempotencyKey = ""))
        }
        assertEquals(1, r.keys.size)
    }
}
