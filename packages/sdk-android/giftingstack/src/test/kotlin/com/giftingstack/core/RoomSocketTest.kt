package com.giftingstack.core

import java.io.DataInputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.util.Base64
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** The real transport (`JavaRoomSocket`) against a tiny RFC 6455 server on a local socket. */
class RoomSocketTest {
    private lateinit var server: ServerSocket
    private val events = LinkedBlockingQueue<String>()

    private val handlers =
        object : RoomSocketHandlers {
            override fun onOpen() {
                events.add("open")
            }

            override fun onMessage(data: String) {
                events.add("message:$data")
            }

            override fun onClose(code: Int, reason: String) {
                events.add("close:$code:$reason")
            }
        }

    @Before
    fun setUp() {
        server = ServerSocket(0)
    }

    @After
    fun tearDown() {
        server.close()
    }

    private fun <T : Any> LinkedBlockingQueue<T>.take5(): T = poll(5, TimeUnit.SECONDS) ?: error("nothing within 5 s")

    private fun next(): String = events.take5()

    private fun open(path: String = "live_1", token: String = "tok.en"): RoomSocket =
        javaRoomSocketFactory(post = { it.run() }).open("ws://127.0.0.1:${server.localPort}/v1/rooms/$path", listOf(ROOM_SUBPROTOCOL, token), handlers)

    /** Reads the request, answers 101 (or [status]) and returns the request headers. */
    private fun accept(s: Socket, status: String = "101 Switching Protocols", badAccept: Boolean = false): Map<String, String> {
        val input = s.getInputStream()
        val sb = StringBuilder()
        while (!sb.endsWith("\r\n\r\n")) sb.append(input.read().toChar())
        val lines = sb.toString().trimEnd().split("\r\n")
        val headers = lines.drop(1).associate { l -> l.substringBefore(':').lowercase() to l.substringAfter(':').trim() } + ("request-line" to lines[0])
        val key = headers.getValue("sec-websocket-key")
        val accept = Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-1").digest((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").toByteArray()))
        val resp =
            if (status.startsWith("101")) {
                "HTTP/1.1 $status\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${if (badAccept) "AAAA" else accept}\r\nSec-WebSocket-Protocol: gs.v1\r\n\r\n"
            } else {
                "HTTP/1.1 $status\r\nContent-Length: 0\r\n\r\n"
            }
        s.getOutputStream().write(resp.toByteArray())
        s.getOutputStream().flush()
        return headers
    }

    private fun serverFrame(out: OutputStream, opcode: Int, payload: ByteArray, fin: Boolean = true) {
        val head = ArrayList<Byte>()
        head.add(((if (fin) 0x80 else 0) or opcode).toByte())
        when {
            payload.size < 126 -> head.add(payload.size.toByte())
            payload.size <= 0xffff -> {
                head.add(126)
                head.add((payload.size shr 8).toByte())
                head.add(payload.size.toByte())
            }
            else -> {
                head.add(127)
                for (i in 7 downTo 0) head.add(((payload.size.toLong() shr (8 * i)) and 0xff).toByte())
            }
        }
        out.write(head.toByteArray() + payload)
        out.flush()
    }

    private class ClientFrame(val opcode: Int, val payload: ByteArray, val masked: Boolean) {
        val text get() = String(payload, Charsets.UTF_8)
    }

    private fun readClientFrame(input: DataInputStream): ClientFrame {
        val b0 = input.readUnsignedByte()
        val b1 = input.readUnsignedByte()
        var len = (b1 and 0x7f).toLong()
        if (len == 126L) len = input.readUnsignedShort().toLong() else if (len == 127L) len = input.readLong()
        val mask = ByteArray(4).also { input.readFully(it) }
        val p = ByteArray(len.toInt()).also { input.readFully(it) }
        for (i in p.indices) p[i] = (p[i].toInt() xor mask[i and 3].toInt()).toByte()
        return ClientFrame(b0 and 0x0f, p, b1 and 0x80 != 0)
    }

    private fun serve(body: (Socket, DataInputStream) -> Unit): Thread {
        val t =
            Thread {
                server.accept().use { s ->
                    body(s, DataInputStream(s.getInputStream()))
                }
            }
        t.isDaemon = true
        t.start()
        return t
    }

    @Test
    fun handshakeSubprotocolsHelloMessagesPingAndServerClose() {
        var request: Map<String, String> = emptyMap()
        val frames = LinkedBlockingQueue<ClientFrame>()
        val done = LinkedBlockingQueue<Boolean>()
        serve { s, input ->
            request = accept(s)
            val out = s.getOutputStream()
            frames.add(readClientFrame(input))
            serverFrame(out, 1, """{"t":"viewers","n":3}""".toByteArray())
            // A text message split into three fragments with a ping in between.
            val big = "x".repeat(70_000)
            serverFrame(out, 1, big.substring(0, 30_000).toByteArray(), fin = false)
            serverFrame(out, 9, "hi".toByteArray())
            serverFrame(out, 0, big.substring(30_000, 60_000).toByteArray(), fin = false)
            serverFrame(out, 0, big.substring(60_000).toByteArray(), fin = true)
            // Binary frames are dropped; multi-byte text survives.
            serverFrame(out, 2, byteArrayOf(1, 2, 3))
            serverFrame(out, 1, "Mé ✓".toByteArray())
            frames.add(readClientFrame(input)) // the pong
            serverFrame(out, 8, byteArrayOf((4003 shr 8).toByte(), 4003.toByte()) + """{"x":1}""".toByteArray())
            frames.add(readClientFrame(input)) // the close echo
            done.add(true)
        }
        val sock = open()
        assertEquals("open", next())
        sock.send("""{"t":"hello","v":1,"last":null}""")
        val hello = frames.take5()
        assertEquals(1, hello.opcode)
        assertTrue("client frames are masked", hello.masked)
        assertEquals("""{"t":"hello","v":1,"last":null}""", hello.text)
        assertEquals("message:" + """{"t":"viewers","n":3}""", next())
        assertEquals("message:" + "x".repeat(70_000), next())
        assertEquals("message:Mé ✓", next())
        val pong = frames.take5()
        assertEquals(0xA, pong.opcode)
        assertEquals("hi", pong.text)
        assertEquals("close:4003:" + """{"x":1}""", next())
        val echo = frames.take5()
        assertEquals(8, echo.opcode)
        assertTrue(done.poll(5, TimeUnit.SECONDS) == true)

        assertTrue(request.getValue("request-line").startsWith("GET /v1/rooms/live_1 HTTP/1.1"))
        assertEquals("gs.v1, tok.en", request.getValue("sec-websocket-protocol"))
        assertEquals("13", request.getValue("sec-websocket-version"))
        assertEquals("websocket", request.getValue("upgrade").lowercase())
        assertEquals(0, events.size)
    }

    private fun closeCodeOf(f: ClientFrame): Int = ((f.payload[0].toInt() and 0xff) shl 8) or (f.payload[1].toInt() and 0xff)

    /** The server sends [bytes] raw; the client must close with [code] and report it. */
    private fun expectProtocolFailure(code: Int, reason: String, bytes: ByteArray) {
        val frames = LinkedBlockingQueue<ClientFrame>()
        serve { s, input ->
            accept(s)
            s.getOutputStream().write(bytes)
            s.getOutputStream().flush()
            frames.add(readClientFrame(input))
        }
        open()
        assertEquals("open", next())
        assertEquals("close:$code:$reason", next())
        val f = frames.take5()
        assertEquals(8, f.opcode)
        assertEquals(code, closeCodeOf(f))
    }

    @Test
    fun aMaskedServerFrameIsA1002() {
        // FIN + text, MASK bit set, length 1, a 4 byte mask and one payload byte.
        expectProtocolFailure(1002, "masked_frame", byteArrayOf(0x81.toByte(), 0x81.toByte(), 1, 2, 3, 4, 0x55))
    }

    @Test
    fun aContinuationFrameWithNothingToContinueIsA1002() {
        expectProtocolFailure(1002, "protocol", byteArrayOf(0x80.toByte(), 1, 'x'.code.toByte()))
    }

    @Test
    fun aNewDataFrameInsideAFragmentedMessageIsA1002() {
        // text, not final, then a second text frame instead of a continuation.
        expectProtocolFailure(1002, "protocol", byteArrayOf(0x01, 1, 'a'.code.toByte(), 0x81.toByte(), 1, 'b'.code.toByte()))
    }

    @Test
    fun aFragmentedOrOversizedControlFrameIsA1002() {
        // ping without FIN
        expectProtocolFailure(1002, "protocol", byteArrayOf(0x09, 0))
    }

    @Test
    fun aControlFrameLongerThan125BytesIsA1002() {
        expectProtocolFailure(1002, "protocol", byteArrayOf(0x89.toByte(), 126, 0, 126) + ByteArray(126))
    }

    @Test
    fun aMessageThatIsNotUtf8IsA1007() {
        expectProtocolFailure(1007, "bad_utf8", byteArrayOf(0x81.toByte(), 2, 0xC3.toByte(), 0x28))
    }

    @Test
    fun aMessageOverTheLimitIsA1009() {
        // A frame header that announces 2 MiB (16 bit and 64 bit forms are both refused before any allocation).
        expectProtocolFailure(1009, "too_big", byteArrayOf(0x82.toByte(), 127, 0, 0, 0, 0, 0, 0x20, 0, 0))
    }

    @Test
    fun aCloseFrameWithNoStatusIsReportedAs1006() {
        val frames = LinkedBlockingQueue<ClientFrame>()
        serve { s, input ->
            accept(s)
            serverFrame(s.getOutputStream(), 8, ByteArray(0))
            frames.add(readClientFrame(input))
        }
        open()
        assertEquals("open", next())
        assertEquals("close:1006:", next())
        assertEquals(8, frames.take5().opcode)
    }

    @Test
    fun aPongEchoesTheWholePingPayload() {
        val frames = LinkedBlockingQueue<ClientFrame>()
        serve { s, input ->
            accept(s)
            serverFrame(s.getOutputStream(), 9, ByteArray(125) { it.toByte() })
            frames.add(readClientFrame(input))
        }
        open()
        assertEquals("open", next())
        val pong = frames.take5()
        assertEquals(0xA, pong.opcode)
        assertTrue(pong.payload.contentEquals(ByteArray(125) { it.toByte() }))
    }

    @Test
    fun clientCloseSendsACloseFrameAndReportsNothing() {
        val frames = LinkedBlockingQueue<ClientFrame>()
        serve { s, input ->
            accept(s)
            frames.add(readClientFrame(input))
        }
        val sock = open()
        assertEquals("open", next())
        sock.close(1000, "client")
        val f = frames.take5()
        assertEquals(8, f.opcode)
        assertEquals(1000, ((f.payload[0].toInt() and 0xff) shl 8) or (f.payload[1].toInt() and 0xff))
        assertEquals("client", String(f.payload, 2, f.payload.size - 2))
        Thread.sleep(200)
        assertEquals("no callbacks after the client closed", 0, events.size)
    }

    @Test
    fun refusedUpgradeIsA1006() {
        serve { s, _ -> accept(s, status = "401 Unauthorized") }
        open()
        assertEquals("close:1006:http_401", next())
    }

    @Test
    fun wrongAcceptKeyIsA1006() {
        serve { s, _ -> accept(s, badAccept = true) }
        open()
        assertEquals("close:1006:bad_handshake", next())
    }

    @Test
    fun droppedConnectionIsA1006() {
        serve { s, _ ->
            accept(s)
            s.close()
        }
        open()
        assertEquals("open", next())
        assertEquals("close:1006:", next())
    }

    @Test
    fun nothingListeningIsA1006() {
        val port = server.localPort
        server.close()
        javaRoomSocketFactory(post = { it.run() }, connectTimeoutMs = 2000)
            .open("ws://127.0.0.1:$port/v1/rooms/a", listOf(ROOM_SUBPROTOCOL, "t"), handlers)
        assertEquals("close:1006:", next())
    }

    @Test
    fun plainWsToAnotherHostIsRefusedUnlessAllowed() {
        // R-07: the token is a subprotocol, so a clear-text connection to a remote host never opens.
        javaRoomSocketFactory(post = { it.run() }).open("ws://rooms.example.test/v1/rooms/a", listOf(ROOM_SUBPROTOCOL, "t"), handlers)
        assertEquals("close:1006:insecure_url", next())
        javaRoomSocketFactory(post = { it.run() }).open("http://10.1.2.3/v1/rooms/a", listOf(ROOM_SUBPROTOCOL, "t"), handlers)
        assertEquals("close:1006:insecure_url", next())
        // The loopback names pass the check (nothing listens on port 1: a connect failure, not insecure_url).
        for (host in listOf("localhost", "127.0.0.1", "[::1]", "10.0.2.2")) {
            javaRoomSocketFactory(post = { it.run() }, connectTimeoutMs = 300).open("ws://$host:1/v1/rooms/a", listOf(ROOM_SUBPROTOCOL, "t"), handlers)
            assertEquals("close:1006:", next())
        }
    }

    @Test
    fun aBadUrlIsA1006() {
        javaRoomSocketFactory(post = { it.run() }).open("not a url", listOf(ROOM_SUBPROTOCOL, "t"), handlers)
        assertEquals("close:1006:", next())
    }

    @Test
    fun theWholeRoomClientOverTheRealTransport() {
        // RoomClient + the real socket against the fake server: hello, welcome, a gift.
        val gift = """{"t":"gift","id":7,"at":1000,"tx":"gtx_1","gift":{"id":"rose","name":"Rose","price":5,"icon_url":null},"quantity":2,"sender":{"id":"u1","name":"Ayla"},"receiver":null}"""
        val hello = LinkedBlockingQueue<String>()
        serve { s, input ->
            accept(s)
            val out = s.getOutputStream()
            hello.add(readClientFrame(input).text)
            serverFrame(out, 1, """{"t":"welcome","v":1,"viewers":4,"gap":false,"replay":[],"ttl":3600,"now":1000}""".toByteArray())
            serverFrame(out, 1, gift.toByteArray())
            Thread.sleep(300)
        }
        val got = LinkedBlockingQueue<RoomGiftEvent>()
        val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Unconfined)
        // Everything on one thread, as on Android: a single-threaded executor stands in for the main looper.
        val main = java.util.concurrent.Executors.newSingleThreadExecutor()
        val clientOptions =
            RoomClientOptions(
                room = "live_1",
                getToken = { "gs_tok" },
                socket = javaRoomSocketFactory(post = { main.execute(it) }),
                scope = scope,
                timers = Timers.forScope(scope),
                url = "ws://127.0.0.1:${server.localPort}",
                now = { 1000 },
                onEvent = { got.add(it) },
            )
        lateinit var client: RoomClient
        main.submit { client = RoomClient(clientOptions) }.get()
        main.submit { client.start() }.get()
        assertEquals("""{"t":"hello","v":1,"last":null}""", hello.poll(5, TimeUnit.SECONDS))
        val e = got.take5()
        assertEquals("gtx_1", e.tx)
        assertEquals("Ayla", e.sender)
        assertEquals(2L, e.quantity)
        main.submit {
            assertEquals(RoomStatus.Open, client.getState().status)
            assertEquals(4L, client.getState().viewers)
            client.leave()
        }.get()
        main.shutdown()
    }
}
