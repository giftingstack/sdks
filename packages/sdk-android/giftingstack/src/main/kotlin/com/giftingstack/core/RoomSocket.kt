package com.giftingstack.core

import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * The room WebSocket transport (RFC 6455 client) on `java.net.Socket`: the SDK has no OkHttp, and
 * `HttpURLConnection` cannot upgrade. Text frames only, subprotocols `gs.v1` + the token
 * (SPEC 17.3), `wss` with the platform trust store and host name check, no extensions.
 *
 * Each socket owns one daemon thread (connect, handshake, read loop). Callbacks to
 * [RoomSocketHandlers] are handed to [post], which MUST run them one after the other on the thread
 * that owns the [RoomClient] (the main thread: see [mainThreadPost]); order is kept.
 *
 * @param post runs a callback on the client's thread. Default: the main looper.
 * @param connectTimeoutMs TCP connect and TLS/upgrade handshake limit.
 * @param allowInsecure lets a `ws://` URL to a non-loopback host through. Without it only `wss://`
 *   and `ws://` to `localhost`, `127.0.0.1`, `::1` or `10.0.2.2` open: the room token is sent as a
 *   subprotocol, so a plain connection would show it to the network.
 */
fun javaRoomSocketFactory(
    post: ((Runnable) -> Unit)? = null,
    connectTimeoutMs: Int = 10_000,
    allowInsecure: Boolean = false,
): RoomSocketFactory =
    RoomSocketFactory { url, protocols, handlers ->
        JavaRoomSocket(url, protocols, handlers, post ?: mainThreadPost(), connectTimeoutMs, allowInsecure)
    }

/** Posts to the Android main looper. Only valid on Android; JVM tests pass their own `post`. */
fun mainThreadPost(): (Runnable) -> Unit {
    val handler = android.os.Handler(android.os.Looper.getMainLooper())
    return { r -> handler.post(r) }
}

/** Largest message accepted from the server (events are small; a batch is far below this). */
internal const val ROOM_MAX_MESSAGE_BYTES = 1 shl 20

internal class JavaRoomSocket(
    private val url: String,
    private val protocols: List<String>,
    private val handlers: RoomSocketHandlers,
    private val post: (Runnable) -> Unit,
    private val connectTimeoutMs: Int,
    private val allowInsecure: Boolean = false,
) : RoomSocket {
    private val finished = AtomicBoolean(false)

    @Volatile private var closedByClient = false

    @Volatile private var raw: Socket? = null

    @Volatile private var out: OutputStream? = null
    private val writeLock = Any()
    private val random = SecureRandom()

    /** All writes of the client's thread go through this one thread, in order. */
    private val writer =
        Executors.newSingleThreadExecutor { r -> Thread(r, "gs-room-writer").also { it.isDaemon = true } }

    init {
        val t = Thread({ run() }, "gs-room-socket")
        t.isDaemon = true
        t.start()
    }

    private fun deliver(fn: () -> Unit) {
        if (closedByClient) return
        post(Runnable { if (!closedByClient) fn() })
    }

    private fun finish(code: Int, reason: String) {
        if (!finished.compareAndSet(false, true)) return
        closeRaw()
        writer.shutdown()
        deliver { handlers.onClose(code, reason) }
    }

    private fun closeRaw() {
        try {
            raw?.close()
        } catch (e: IOException) {
            // Already gone.
        }
    }

    private fun run() {
        try {
            // Plain ws:// (or http://) to a host that is not on this device: the token would go in clear text.
            val plain = url.substringBefore("://", "").lowercase().let { it == "ws" || it == "http" }
            if (plain && !allowInsecure && !isLoopbackUrl(url)) {
                finish(1006, "insecure_url")
                return
            }
            val uri = URI(url)
            val secure = uri.scheme.equals("wss", true) || uri.scheme.equals("https", true)
            require(secure || uri.scheme.equals("ws", true) || uri.scheme.equals("http", true)) { "not a ws url" }
            val host = uri.host ?: throw IOException("no host")
            val port = if (uri.port >= 0) uri.port else if (secure) 443 else 80
            var s = Socket()
            raw = s
            s.tcpNoDelay = true
            s.connect(InetSocketAddress(host, port), connectTimeoutMs)
            s.soTimeout = connectTimeoutMs
            if (secure) {
                val ssl = (SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(s, host, port, true) as SSLSocket
                val params = ssl.sslParameters
                // The host name check: without this the platform only checks the chain.
                params.endpointIdentificationAlgorithm = "HTTPS"
                ssl.sslParameters = params
                ssl.startHandshake()
                s = ssl
                raw = ssl
            }
            if (closedByClient) return closeRaw()
            val input = s.getInputStream()
            val output = s.getOutputStream()
            out = output
            val key = ByteArray(16).also { random.nextBytes(it) }.let(::base64)
            val path = (uri.rawPath?.ifEmpty { "/" } ?: "/") + (uri.rawQuery?.let { "?$it" } ?: "")
            val hostHeader = if (uri.port >= 0) "$host:$port" else host
            val request =
                "GET $path HTTP/1.1\r\nHost: $hostHeader\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
                    "Sec-WebSocket-Key: $key\r\nSec-WebSocket-Version: 13\r\n" +
                    "Sec-WebSocket-Protocol: ${protocols.joinToString(", ")}\r\n\r\n"
            output.write(request.toByteArray(Charsets.US_ASCII))
            output.flush()
            val head = readHead(input)
            val lines = head.split("\r\n")
            val status = lines.firstOrNull()?.split(" ")?.getOrNull(1)?.toIntOrNull() ?: 0
            if (status != 101) {
                finish(1006, "http_$status")
                return
            }
            val headers = HashMap<String, String>()
            for (l in lines.drop(1)) {
                val i = l.indexOf(':')
                if (i > 0) headers[l.substring(0, i).trim().lowercase()] = l.substring(i + 1).trim()
            }
            val accept = base64(MessageDigest.getInstance("SHA-1").digest((key + WS_GUID).toByteArray(Charsets.US_ASCII)))
            if (headers["sec-websocket-accept"] != accept || !headers["upgrade"].equals("websocket", true) ||
                headers["sec-websocket-protocol"] != ROOM_SUBPROTOCOL
            ) {
                finish(1006, "bad_handshake")
                return
            }
            s.soTimeout = 0
            deliver { handlers.onOpen() }
            readLoop(DataInputStream(input))
        } catch (e: Exception) {
            finish(1006, "")
        }
    }

    /** Headers up to the blank line, byte by byte so no frame byte is consumed. */
    private fun readHead(input: InputStream): String {
        val sb = ByteArrayOutputStream()
        var tail = 0
        while (true) {
            val b = input.read()
            if (b < 0) throw EOFException()
            sb.write(b)
            tail = (tail shl 8) or b
            if (tail == 0x0d0a0d0a) break
            if (sb.size() > 16 * 1024) throw IOException("headers too long")
        }
        return String(sb.toByteArray(), Charsets.ISO_8859_1).trimEnd()
    }

    private fun readLoop(input: DataInputStream) {
        val message = ByteArrayOutputStream()
        var textMessage = false
        var inMessage = false
        while (true) {
            val b0 = input.readUnsignedByte()
            val b1 = input.readUnsignedByte()
            val fin = b0 and 0x80 != 0
            val opcode = b0 and 0x0f
            if (b0 and 0x70 != 0) {
                fail(1002, "protocol")
                return
            }
            // RFC 6455 5.1: a server MUST NOT mask its frames; a client that gets one closes with 1002.
            if (b1 and 0x80 != 0) {
                fail(1002, "masked_frame")
                return
            }
            var len = (b1 and 0x7f).toLong()
            if (len == 126L) len = input.readUnsignedShort().toLong() else if (len == 127L) len = input.readLong()
            if (len < 0 || len > ROOM_MAX_MESSAGE_BYTES) {
                fail(1009, "too_big")
                return
            }
            // Control frames (close, ping, pong) are never fragmented and carry at most 125 bytes (5.5).
            if (opcode and 0x8 != 0 && (!fin || len > 125)) {
                fail(1002, "protocol")
                return
            }
            val payload = ByteArray(len.toInt())
            input.readFully(payload)
            when (opcode) {
                0x1, 0x2, 0x0 -> {
                    if (opcode != 0x0) {
                        // A new data frame while a fragmented message is still open.
                        if (inMessage) {
                            fail(1002, "protocol")
                            return
                        }
                        textMessage = opcode == 0x1
                        inMessage = true
                    } else if (!inMessage) {
                        // A continuation frame with nothing to continue.
                        fail(1002, "protocol")
                        return
                    }
                    if (message.size() + payload.size > ROOM_MAX_MESSAGE_BYTES) {
                        fail(1009, "too_big")
                        return
                    }
                    message.write(payload)
                    if (fin) {
                        val bytes = message.toByteArray()
                        message.reset()
                        inMessage = false
                        // Binary frames are dropped (SPEC 17.4: text only).
                        if (textMessage) {
                            val text = decodeUtf8(bytes)
                            if (text == null) {
                                fail(1007, "bad_utf8")
                                return
                            }
                            deliver { handlers.onMessage(text) }
                        }
                    }
                }
                0x8 -> {
                    // One byte cannot hold a status code (5.5.1).
                    if (payload.size == 1) {
                        fail(1002, "protocol")
                        return
                    }
                    // No status code at all is 1005; like Flutter and the web client, report it as 1006
                    // ("the connection went away") so the reconnect policy sees one value.
                    val code = if (payload.size >= 2) ((payload[0].toInt() and 0xff) shl 8) or (payload[1].toInt() and 0xff) else 1006
                    val reason = if (payload.size > 2) String(payload, 2, payload.size - 2, Charsets.UTF_8) else ""
                    writeFrame(0x8, if (payload.size >= 2) payload.copyOfRange(0, 2) else ByteArray(0))
                    finish(code, reason)
                    return
                }
                // The pong echoes the ping's payload (5.5.3).
                0x9 -> writeFrame(0xA, payload)
                0xA -> Unit
                else -> {
                    fail(1002, "protocol")
                    return
                }
            }
        }
    }

    /** Strict UTF-8: null when the bytes are not valid text (the message is a protocol error, 1007). */
    private fun decodeUtf8(bytes: ByteArray): String? =
        try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
                .decode(java.nio.ByteBuffer.wrap(bytes))
                .toString()
        } catch (e: java.nio.charset.CharacterCodingException) {
            null
        }

    /** We found a protocol error: tell the server, then report the close. */
    private fun fail(code: Int, reason: String) {
        writeFrame(0x8, closePayload(code, reason))
        finish(code, reason)
    }

    private fun closePayload(code: Int, reason: String): ByteArray {
        val r = reason.toByteArray(Charsets.UTF_8).let { if (it.size > 123) it.copyOf(123) else it }
        return byteArrayOf((code shr 8).toByte(), code.toByte()) + r
    }

    /** One masked, unfragmented client frame. Never throws; a broken pipe shows up in the read loop. */
    private fun writeFrame(opcode: Int, payload: ByteArray) {
        val o = out ?: return
        val mask = ByteArray(4).also { random.nextBytes(it) }
        val head = ByteArrayOutputStream()
        head.write(0x80 or opcode)
        when {
            payload.size < 126 -> head.write(0x80 or payload.size)
            payload.size <= 0xffff -> {
                head.write(0x80 or 126)
                head.write(payload.size shr 8)
                head.write(payload.size and 0xff)
            }
            else -> {
                head.write(0x80 or 127)
                for (i in 7 downTo 0) head.write(((payload.size.toLong() shr (8 * i)) and 0xff).toInt())
            }
        }
        head.write(mask)
        val body = ByteArray(payload.size) { (payload[it].toInt() xor mask[it and 3].toInt()).toByte() }
        synchronized(writeLock) {
            try {
                o.write(head.toByteArray())
                o.write(body)
                o.flush()
            } catch (e: IOException) {
                closeRaw()
            }
        }
    }

    override fun send(data: String) {
        if (finished.get() || closedByClient) return
        // Android refuses socket writes on the main thread, which is where the client runs.
        try {
            writer.execute { writeFrame(0x1, data.toByteArray(Charsets.UTF_8)) }
        } catch (e: RejectedExecutionException) {
            // Closed meanwhile.
        }
    }

    override fun close(code: Int, reason: String) {
        if (closedByClient) return
        closedByClient = true
        finished.set(true)
        try {
            writer.execute {
                writeFrame(0x8, closePayload(code, reason))
                closeRaw()
            }
        } catch (e: RejectedExecutionException) {
            closeRaw()
        }
        writer.shutdown()
    }

    private companion object {
        const val WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

        const val ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

        /** Standard base64 with padding (no `java.util.Base64` before API 26). */
        fun base64(bytes: ByteArray): String {
            val sb = StringBuilder()
            var i = 0
            while (i < bytes.size) {
                val b0 = bytes[i].toInt() and 0xff
                val b1 = if (i + 1 < bytes.size) bytes[i + 1].toInt() and 0xff else -1
                val b2 = if (i + 2 < bytes.size) bytes[i + 2].toInt() and 0xff else -1
                sb.append(ALPHABET[b0 shr 2])
                sb.append(ALPHABET[((b0 and 3) shl 4) or (if (b1 < 0) 0 else b1 shr 4)])
                sb.append(if (b1 < 0) '=' else ALPHABET[((b1 and 15) shl 2) or (if (b2 < 0) 0 else b2 shr 6)])
                sb.append(if (b2 < 0) '=' else ALPHABET[b2 and 63])
                i += 3
            }
            return sb.toString()
        }
    }
}
