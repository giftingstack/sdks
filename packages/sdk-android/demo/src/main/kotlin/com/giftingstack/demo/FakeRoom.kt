package com.giftingstack.demo

import com.giftingstack.core.Gift
import com.giftingstack.core.RoomSocket
import com.giftingstack.core.RoomSocketFactory
import com.giftingstack.core.RoomSocketHandlers
import com.giftingstack.core.Timers
import kotlin.random.Random

/** The room of the demo's Live tab and its stream host. */
const val LIVE_ROOM = "pixel_live"

/** The room of the "Battle 4+" mode: four hosts in every round. */
const val LIVE_ROOM_4 = "pixel_live_4"
const val LIVE_HOST = "zoe"

/** The second host of the battle bar, and the length of a round and of the break after it. */
const val LIVE_RIVAL = "mateo"

/** The hosts of the battle: the first two play "Battle", all four play "Battle 4+" (a free-for-all, one bar cell and one Gift button each). */
val LIVE_HOSTS = listOf(LIVE_HOST, LIVE_RIVAL, "emma", "dana")
const val LIVE_ROUND_MS = 45_000L
const val LIVE_BREAK_MS = 5_000L

/** The "posts" the Live tab gifts go to: one per side of the battle, with the room id on every send. */
val LIVE_POST = Post("live_1", LIVE_HOST, "Live", ArtKind.Aurora, "now", 0)
val LIVE_RIVAL_POST = Post("live_1", LIVE_RIVAL, "Live", ArtKind.Aurora, "now", 0)
val LIVE_HOST_POSTS = LIVE_HOSTS.map { Post("live_1", it, "Live", ArtKind.Aurora, "now", 0) }

/** The line under the host name in the Live tab. */
fun liveStatusLine(state: com.giftingstack.core.RoomState): String =
    when (state.status) {
        com.giftingstack.core.RoomStatus.Open -> "Live · " + (state.viewers ?: 0) + " watching"
        com.giftingstack.core.RoomStatus.Connecting -> "Connecting..."
        com.giftingstack.core.RoomStatus.Reconnecting -> "Reconnecting..."
        com.giftingstack.core.RoomStatus.Paused -> "Paused (app in the background)"
        com.giftingstack.core.RoomStatus.Idle -> "Not connected"
        com.giftingstack.core.RoomStatus.Closed -> "Left the room"
    }

/** Who sends gifts into the pretend room (everyone but the host). */
val LIVE_SENDERS: List<String> = SENDERS.filter { it !in LIVE_HOSTS }

/**
 * A pretend rooms server for the demo: a [RoomSocketFactory] that speaks the real wire protocol
 * (SPEC 17: `hello` -> `welcome`, then `gift` and `viewers` frames) so the demo runs the SDK's
 * real [com.giftingstack.core.RoomClient] without a rooms Worker. Other people send gifts every
 * few seconds, now and then five in a row (a combo), into a battle round between two hosts that the
 * gifts score into (the SDK's battle bar draws it). Callbacks run on whatever thread [timers]
 * fires on (the main thread with `Timers.forScope`). Not part of the SDK. Mirrors
 * `packages/sdk-js/demo/fakeRoom.ts`.
 */
class FakeRoomServer(
    private val gifts: () -> List<Gift>,
    private val senders: List<String> = LIVE_SENDERS,
    private val nameOf: (String) -> String = ::displayName,
    private val timers: Timers,
    private val now: () -> Long = System::currentTimeMillis,
    private val random: Random = Random.Default,
    private val minDelayMs: Long = 8_000,
    private val maxDelayMs: Long = 16_000,
    /** How many hosts every round has: two, or four for the "Battle 4+" mode. */
    private val sides: Int = 2,
) {
    private var nextId = now() * 1000
    private var nextTx = 1
    private var viewers = 38 + random.nextInt(20)

    /** Every socket opened so far (a test or the screen can look at them). */
    val sockets = ArrayList<FakeRoomSocket>()

    val factory = RoomSocketFactory { url, protocols, handlers -> FakeRoomSocket(url, protocols, handlers).also { sockets.add(it) } }

    // The battle round: gifts to either host count while the round is open; a new one starts after a break.
    private var round = 1
    private var started = now()
    private val units = LongArray(4)
    private val counts = LongArray(4)

    /** The sides of every round: the first [sides] hosts. */
    private fun sidesNow(): List<String> = LIVE_HOSTS.take(sides)

    private fun battleJson(): String {
        val scores = sidesNow().mapIndexed { i, id -> """{"id":${q(id)},"units":${units[i]},"gifts":${counts[i]}}""" }.joinToString(",")
        return """{"round":"demo_r$round","started":$started,"ends":${started + LIVE_ROUND_MS},"scores":[$scores]}"""
    }

    private fun scoresFrame(): String = """{"t":"scores","battle":${battleJson()}}"""

    /**
     * What the real API does after a send with `room_id`: the gift reaches everyone in the room and
     * counts for the open round. The SDK leaves the sender's own gifts out of its effects.
     */
    fun publish(sender: String, gift: Gift, quantity: Int, receiver: String) {
        val side = sidesNow().indexOf(receiver)
        val open = sockets.filter { !it.closed }
        val text = frame(sender, gift, quantity, receiver)
        for (s in open) s.deliver(text)
        if (side < 0 || now() >= started + LIVE_ROUND_MS) return
        units[side] += gift.price * quantity
        counts[side] += quantity.toLong()
        val scores = scoresFrame()
        for (s in open) s.deliver(scores)
    }

    private fun frame(sender: String, gift: Gift, quantity: Int, receiver: String): String =
        """{"t":"gift","id":${++nextId},"at":${now()},"tx":"gtx_demo${nextTx++}","gift":{"id":${q(gift.id)},"name":${q(gift.name)},"price":${gift.price},"icon_url":${gift.iconUrl?.let { q(it) } ?: "null"}},"quantity":$quantity,"sender":{"id":${q(sender)},"name":${q(nameOf(sender))}},"receiver":{"id":${q(receiver)}}}"""

    inner class FakeRoomSocket(val url: String, val protocols: List<String>, private val handlers: RoomSocketHandlers) : RoomSocket {
        private val handles = HashSet<Any>()
        private var open = false
        var closed = false
            private set

        /** The frames the client sent, as text. */
        val sent = ArrayList<String>()

        init {
            later(150) {
                open = true
                handlers.onOpen()
            }
        }

        override fun send(data: String) {
            if (!open || closed) return
            sent.add(data)
            when {
                data == "ping" -> push("pong")
                data.contains("\"t\":\"hello\"") -> {
                    push("""{"t":"welcome","v":1,"viewers":$viewers,"gap":false,"replay":[],"ttl":3600,"now":${now()},"battle":${battleJson()}}""")
                    later((started + LIVE_ROUND_MS - now()).coerceAtLeast(0), ::endRound)
                    schedule()
                    drift()
                }
            }
        }

        override fun close(code: Int, reason: String) {
            if (closed) return
            closed = true
            for (h in handles.toList()) timers.clear(h)
            handles.clear()
        }

        private fun push(text: String) {
            if (!closed) handlers.onMessage(text)
        }

        /** A frame from [FakeRoomServer.publish], once the socket is open. */
        internal fun deliver(text: String) {
            if (open) push(text)
        }

        private fun later(ms: Long, fn: () -> Unit) {
            lateinit var h: Any
            h = timers.set(ms) {
                handles.remove(h)
                if (!closed) fn()
            }
            handles.add(h)
        }

        /** The round is over (the bar shows Final); a new one starts after the break. */
        private fun endRound() {
            push(scoresFrame())
            later(LIVE_BREAK_MS) {
                round++
                started = now()
                units.fill(0)
                counts.fill(0)
                push(scoresFrame())
                later(LIVE_ROUND_MS, ::endRound)
            }
        }

        /** Sends a gift to one of the hosts of this round and counts it into the round while it is open. */
        private fun giftTo(sender: String, gift: Gift, quantity: Int, side: Int) {
            push(frame(sender, gift, quantity, sidesNow()[side]))
            if (now() >= started + LIVE_ROUND_MS) return
            units[side] += gift.price * quantity
            counts[side] += quantity.toLong()
            push(scoresFrame())
        }

        /** Someone in the room sends a gift; 1 in 12 times it is a combo of five. */
        private fun schedule() {
            later(minDelayMs + random.nextLong(maxDelayMs - minDelayMs + 1)) {
                val sender = senders.randomOrNull(random)
                // Mostly everyday gifts (the cheaper 60%): luxury effects cover the stream, so they are rare.
                val all = gifts()
                val cheap = all.sortedBy { it.price }.take(maxOf(1, kotlin.math.ceil(all.size * 0.6).toInt()))
                val gift = (if (random.nextInt(10) == 0) all else cheap).randomOrNull(random)
                if (sender != null && gift != null) {
                    val side = random.nextInt(sidesNow().size)
                    if (random.nextInt(12) == 0) {
                        for (i in 0 until 5) later(i * 250L) { giftTo(sender, gift, 1, side) }
                    } else {
                        giftTo(sender, gift, 1 + random.nextInt(2), side)
                    }
                }
                schedule()
            }
        }

        /** The viewer count wanders a little, like a real room. */
        private fun drift() {
            later(5_000) {
                viewers = maxOf(1, viewers + random.nextInt(7) - 3)
                push("""{"t":"viewers","n":$viewers}""")
                drift()
            }
        }
    }
}

private fun q(s: String): String = kotlinx.serialization.json.JsonPrimitive(s).toString()

/**
 * A token shaped like the real one (`gs_ct_<claims>.<signature>`) so the SDK can read the user from
 * it (it never checks the signature: only the server does). Not a secret, not valid anywhere.
 */
fun demoRoomToken(user: String): String {
    val claims = """{"v":1,"u":${q(user)},"n":${q(displayName(user))}}""".toByteArray(Charsets.UTF_8)
    return "gs_ct_${base64Url(claims)}.${"A".repeat(43)}"
}

private const val B64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

/** base64url without padding (`java.util.Base64` needs API 26, the demo supports 24). */
internal fun base64Url(bytes: ByteArray): String {
    val sb = StringBuilder()
    var i = 0
    while (i < bytes.size) {
        val b0 = bytes[i].toInt() and 0xff
        val b1 = if (i + 1 < bytes.size) bytes[i + 1].toInt() and 0xff else -1
        val b2 = if (i + 2 < bytes.size) bytes[i + 2].toInt() and 0xff else -1
        sb.append(B64URL[b0 shr 2])
        sb.append(B64URL[((b0 and 3) shl 4) or (if (b1 < 0) 0 else b1 shr 4)])
        if (b1 >= 0) sb.append(B64URL[((b1 and 15) shl 2) or (if (b2 < 0) 0 else b2 shr 6)])
        if (b2 >= 0) sb.append(B64URL[b2 and 63])
        i += 3
    }
    return sb.toString()
}
