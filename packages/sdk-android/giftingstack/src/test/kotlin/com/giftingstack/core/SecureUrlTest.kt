package com.giftingstack.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** R-07: `http://` and `ws://` only for loopback, unless `allowInsecure`. */
class SecureUrlTest {
    private fun refused(url: String, allow: Boolean = false): Boolean =
        try {
            requireSecureUrl(url, allow, "baseUrl")
            false
        } catch (e: IllegalArgumentException) {
            true
        }

    @Test
    fun httpsAndWssAlwaysPass() {
        assertFalse(refused("https://api.giftingstack.com"))
        assertFalse(refused("wss://rt.giftingstack.com"))
        assertFalse(refused("HTTPS://api.example.test///"))
    }

    @Test
    fun plainSchemesPassForLoopbackOnly() {
        for (host in listOf("localhost", "127.0.0.1", "[::1]", "10.0.2.2")) {
            assertFalse("http://$host", refused("http://$host:8787/proxy"))
            assertFalse("ws://$host", refused("ws://$host:8788"))
        }
        assertTrue(refused("http://api.example.test"))
        assertTrue(refused("ws://rt.example.test"))
        assertTrue(refused("http://192.168.1.10:8787"))
        assertTrue("userinfo does not make a host local", refused("http://localhost@evil.example/x"))
        assertTrue("a look-alike host", refused("http://localhost.evil.example/"))
    }

    @Test
    fun allowInsecureLetsAPlainUrlThrough() {
        assertFalse(refused("http://192.168.1.10:8787", allow = true))
        assertFalse(refused("ws://rt.example.test", allow = true))
    }

    @Test
    fun otherSchemesAndGarbagePassTheCheckAndFailInTheTransport() {
        // SPEC 3.1: only http:// (and ws:// for rooms) is refused here.
        assertFalse(refused("ftp://x.test"))
        assertFalse(refused("api.giftingstack.com"))
        assertFalse(refused(""))
        assertTrue("any case", refused("HTTP://api.example.test"))
        assertTrue(refused("WS://rt.example.test"))
    }

    @Test
    fun theMessageNamesTheOptionAndShowsOnlySchemeAndHost() {
        try {
            requireSecureUrl("http://user:secret@api.example.test:8080/path?token=abc", false, "baseUrl")
            fail("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            val m = e.message!!
            assertTrue(m, m.contains("allowInsecure"))
            assertTrue(m, m.contains("http://api.example.test"))
            assertFalse(m, m.contains("secret") || m.contains("token=abc") || m.contains("/path"))
        }
    }

    @Test
    fun theRoomClientRefusesAPlainWsUrlWhenCreatedAndWhenOptionsAreReplaced() {
        val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Job())
        fun opts(url: String, allow: Boolean = false) =
            RoomClientOptions(
                room = "live_1",
                getToken = { "t" },
                socket = RoomSocketFactory { _, _, _ -> error("unused") },
                scope = scope,
                timers = Timers.forScope(scope),
                url = url,
                allowInsecure = allow,
            )
        try {
            RoomClient(opts("ws://rt.example.test"))
            fail("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("allowInsecure"))
        }
        val client = RoomClient(opts("ws://127.0.0.1:8788"))
        RoomClient(opts("ws://rt.example.test", allow = true))
        RoomClient(opts("wss://rt.giftingstack.com"))
        try {
            client.setOptions(opts("ws://rt.example.test"))
            fail("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // The old options stay.
        }
        client.setOptions(opts("ws://rt.example.test", allow = true))
        scope.coroutineContext[kotlinx.coroutines.Job]!!.cancel()
    }

    @Test
    fun hostIsParsedWithoutThrowing() {
        assertEquals("localhost", urlHost("http://LocalHost:80/a?b#c"))
        assertEquals("::1", urlHost("ws://[::1]:8788//"))
        assertEquals("evil.example", urlHost("http://localhost@evil.example/"))
        assertNull(urlHost("not a url"))
        assertNull(urlHost("http://[::1"))
    }

    @Test
    fun theClientRefusesAPlainBaseUrlAtConstruction() {
        try {
            GiftingClient({ "t" }, baseUrl = "http://api.example.test", transport = { TransportResponse(200) })
            fail("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("baseUrl"))
        }
        // These construct: loopback, https, and the explicit opt-in.
        GiftingClient({ "t" }, baseUrl = "http://10.0.2.2:8787", transport = { TransportResponse(200) })
        GiftingClient({ "t" }, baseUrl = "https://api.example.test/", transport = { TransportResponse(200) })
        GiftingClient({ "t" }, baseUrl = "http://staging.lan", transport = { TransportResponse(200) }, allowInsecure = true)
    }
}
