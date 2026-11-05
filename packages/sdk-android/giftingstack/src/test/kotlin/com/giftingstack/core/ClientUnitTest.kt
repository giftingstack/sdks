package com.giftingstack.core

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Things the fixtures do not pin but the Android client promises. */
class ClientUnitTest {
    @Test
    fun encodeUriComponentMatchesJavaScript() {
        assertEquals("a%2Fb%20c%3Ad", encodeURIComponent("a/b c:d"))
        assertEquals("%C3%BC-_.!~*'()", encodeURIComponent("ü-_.!~*'()"))
        assertEquals("%F0%9F%8E%81", encodeURIComponent("🎁"))
        assertEquals("a%2Bb%26c%3Dd%3Fe%23f", encodeURIComponent("a+b&c=d?e#f"))
        assertEquals("%25%22%3C%3E", encodeURIComponent("%\"<>"))
        assertEquals("AZaz09", encodeURIComponent("AZaz09"))
    }

    @Test
    fun saysWhereItRunsWithThePlatformAndOsHeaders() = runBlocking {
        val seen = mutableListOf<Map<String, String>>()
        val transport = GiftingTransport { req ->
            seen.add(req.headers)
            TransportResponse(200, body = "{\"data\": []}")
        }
        GiftingClient({ "t" }, transport = transport).getGifts()
        assertEquals("android", seen.last()["X-GiftingStack-Platform"])
        assertEquals("android", seen.last()["X-GiftingStack-OS"])
        GiftingClient({ "t" }, transport = transport, platform = "web", os = null).getGifts()
        assertEquals("web", seen.last()["X-GiftingStack-Platform"])
        assertTrue(!seen.last().containsKey("X-GiftingStack-OS"))
    }

    @Test
    fun generatedIdempotencyKeysAreUuidV4() {
        val a = newIdempotencyKey()
        assertTrue(Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$").matches(a))
        assertTrue(a != newIdempotencyKey())
    }

    @Test
    fun anyTransportExceptionIsANetworkError() = runBlocking {
        for (boom in listOf<Throwable>(IOException("x"), IllegalStateException("y"), RuntimeException("z"))) {
            val client = GiftingClient({ "t" }, transport = { throw boom })
            try {
                client.getMe()
                fail("expected an error")
            } catch (e: GiftingException) {
                assertEquals(0, e.status)
                assertEquals("network_error", e.type)
                assertTrue(e.retryable)
            }
        }
    }

    @Test
    fun cancellationIsNotAnNetworkError() = runBlocking {
        val client = GiftingClient({ "t" }, transport = { throw CancellationException("stop") })
        try {
            client.getMe()
            fail("expected cancellation")
        } catch (e: CancellationException) {
            // expected: cancellation must propagate, not become a GiftingException
        }
    }

    @Test
    fun errorsFromGetTokenPropagateUnchanged() = runBlocking {
        val boom = IllegalStateException("no token")
        val client = GiftingClient({ throw boom }, transport = { TransportResponse(200, body = "{}") })
        try {
            client.getMe()
            fail("expected the token error")
        } catch (e: IllegalStateException) {
            assertEquals(boom, e)
        }
    }

    @Test
    fun unknownJsonFieldsAreIgnored() = runBlocking {
        val body = """{"user":"ayla","balance":5,"future_field":{"a":1}}"""
        val client = GiftingClient({ "t" }, transport = { TransportResponse(200, body = body) })
        assertEquals(Me("ayla", 5), client.getMe())
    }
}
