package com.giftingstack.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.Lifecycle
import com.giftingstack.core.RoomSocket
import com.giftingstack.core.RoomSocketHandlers
import com.giftingstack.core.RoomStatus
import com.giftingstack.core.javaRoomSocketFactory
import java.io.DataInputStream
import java.net.ServerSocket
import java.security.MessageDigest
import java.util.Base64
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

private object RoomInstant : GiftImageLoader {
    private val bmp = ImageBitmap(8, 8)

    override fun peek(url: String) = bmp

    override suspend fun load(url: String) = bmp

    override fun prefetch(url: String) {}
}

/**
 * `rememberGiftRoom` on a device: the app lifecycle pauses and resumes the room, and the real
 * `java.net` transport works on Android (no main-thread network, text frames, resume). The fake
 * socket tests run the logic; the loopback test runs the transport against a tiny server inside
 * the test process.
 */
class GiftRoomUiTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    private class FakeSocket(val url: String, val protocols: List<String>, val handlers: RoomSocketHandlers) : RoomSocket {
        val sent = CopyOnWriteArrayList<String>()

        @Volatile var closed: Pair<Int, String>? = null

        override fun send(data: String) {
            sent.add(data)
        }

        override fun close(code: Int, reason: String) {
            closed = code to reason
        }
    }

    private fun gift(id: Long, tx: String) =
        """{"t":"gift","id":$id,"at":1000,"tx":"$tx","gift":{"id":"rose","name":"Rose","price":50,"icon_url":"https://t/rose"},"quantity":2,"sender":{"id":"mateo","name":"Mateo"},"receiver":null}"""

    private val welcome = """{"t":"welcome","v":1,"viewers":9,"gap":false,"replay":[],"ttl":3600,"now":1000}"""

    @Test
    fun theRoomFollowsTheAppLifecycleAndPlaysGiftsOnTheLayer() {
        val sockets = CopyOnWriteArrayList<FakeSocket>()
        val effects = GiftEffectLayerState()
        val ended = java.util.concurrent.atomic.AtomicInteger()
        var room: GiftRoom? = null
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides RoomInstant) {
                room =
                    rememberGiftRoom(
                        room = "live_1",
                        getToken = { "gs_ct_e30.sig" },
                        effects = effects,
                        socket = { url, protocols, handlers -> FakeSocket(url, protocols, handlers).also { sockets.add(it) } },
                    )
                Box(Modifier.fillMaxSize()) { GiftEffectLayer(effects, onEffectEnd = { e, _ -> if (e.gift.id == "rose") ended.incrementAndGet() }) }
            }
        }
        rule.waitUntil(5_000) { sockets.size == 1 }
        val first = sockets[0]
        assertEquals(listOf("gs.v1", "gs_ct_e30.sig"), first.protocols)
        rule.runOnUiThread {
            first.handlers.onOpen()
            first.handlers.onMessage(welcome)
            first.handlers.onMessage(gift(7, "gtx_a"))
        }
        assertEquals("""{"t":"hello","v":1,"last":null}""", first.sent.single())
        rule.waitForIdle()
        assertEquals(RoomStatus.Open, room!!.state.value.status)
        assertEquals(9L, room!!.state.value.viewers)
        // The room gift played on the layer (the test clock runs the whole effect while we wait for idle).
        rule.waitUntil(5_000) { ended.get() == 1 }

        // The app goes to the background: the socket closes, nothing reconnects.
        rule.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
        rule.waitUntil(5_000) { room!!.state.value.status == RoomStatus.Paused }
        assertEquals(1000 to "client", first.closed)
        Thread.sleep(500)
        assertEquals(1, sockets.size)

        // Back in the foreground: a new socket, and `hello` resumes after the last gift.
        rule.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        rule.waitUntil(5_000) { sockets.size == 2 }
        rule.runOnUiThread { sockets[1].handlers.onOpen() }
        assertEquals("""{"t":"hello","v":1,"last":7}""", sockets[1].sent.single())
    }

    @Test
    fun theRealTransportRunsOnAndroidAgainstALoopbackServer() {
        val server = ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1"))
        val hello = LinkedBlockingQueue<String>()
        val serverThread =
            Thread {
                server.accept().use { s ->
                    val input = s.getInputStream()
                    val sb = StringBuilder()
                    while (!sb.endsWith("\r\n\r\n")) sb.append(input.read().toChar())
                    val key = Regex("""Sec-WebSocket-Key: (\S+)""", RegexOption.IGNORE_CASE).find(sb)!!.groupValues[1]
                    val accept = Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-1").digest((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").toByteArray()))
                    val out = s.getOutputStream()
                    out.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: $accept\r\nSec-WebSocket-Protocol: gs.v1\r\n\r\n".toByteArray())
                    val din = DataInputStream(input)
                    din.readUnsignedByte()
                    val len = din.readUnsignedByte() and 0x7f
                    val mask = ByteArray(4).also { din.readFully(it) }
                    val p = ByteArray(len).also { din.readFully(it) }
                    for (i in p.indices) p[i] = (p[i].toInt() xor mask[i and 3].toInt()).toByte()
                    hello.add(String(p))
                    for (text in listOf(welcome, gift(7, "gtx_a"))) {
                        val b = text.toByteArray()
                        // 126 = a 16-bit length follows (the gift frame is longer than 125 bytes).
                        out.write(byteArrayOf(0x81.toByte(), 126, (b.size shr 8).toByte(), b.size.toByte()) + b)
                    }
                    out.flush()
                    Thread.sleep(8_000)
                }
            }
        serverThread.isDaemon = true
        serverThread.start()

        val effects = GiftEffectLayerState()
        var room: GiftRoom? = null
        rule.setContent {
            CompositionLocalProvider(LocalGiftImageLoader provides RoomInstant) {
                room =
                    rememberGiftRoom(
                        room = "live_1",
                        getToken = { "gs_ct_e30.sig" },
                        effects = effects,
                        url = "ws://127.0.0.1:${server.localPort}",
                        socket = javaRoomSocketFactory(), // callbacks on the main looper
                    )
                Box(Modifier.fillMaxSize()) { GiftEffectLayer(effects) }
            }
        }
        assertEquals("""{"t":"hello","v":1,"last":null}""", hello.poll(10, TimeUnit.SECONDS))
        rule.waitUntil(10_000) { room!!.state.value.status == RoomStatus.Open }
        rule.waitUntil(10_000) { rule.runOnUiThread { effects.items.size } == 1 }
        assertEquals(9L, room!!.state.value.viewers)
        assertTrue(rule.runOnUiThread { effects.items.single().event.gift.id } == "rose")
        server.close()
    }
}
