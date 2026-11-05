package com.giftingstack.core

import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.floor
import kotlin.math.pow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Gift rooms, client side (SPEC section 17 is the wire protocol, section 18 the client rules,
 * docs/design/gift-rooms.md the design). Everything here is pure: the socket, the clock, the
 * timers, the random source and the token are injected, so the fixtures `rooms-*.json` drive it.
 * Port of `packages/sdk-js/src/core/rooms.ts`. The real socket is in `RoomSocket.kt`
 * ([javaRoomSocketFactory]), the Compose side in `ui/GiftRoom.kt`.
 *
 * Pieces: [parseRoomFrame] / [roomHelloFrame] (protocol), [roomRetryDecision] (reconnect
 * policy), [RoomEventFilter] (resume point, dedup, staleness, own gifts, tier filter),
 * [roomGiftToEffect] (event to effect) and [RoomClient] (the session state machine).
 */

/** The only subprotocol; the client token rides as the second entry. */
const val ROOM_SUBPROTOCOL = "gs.v1"
const val DEFAULT_ROOMS_URL = "wss://rt.giftingstack.com"

/** Events older than this (server clock) are dropped instead of played. */
const val DEFAULT_MAX_REPLAY_AGE_MS = 10_000L

/** Recent `tx` ids remembered for dedup. */
const val ROOM_DEDUP_SIZE = 256

/** Full jitter: `random(0, min(30 s, 0.5 s x 2^attempt))`, never below [ROOM_RETRY_FLOOR_MS] (SPEC 18.3). */
const val ROOM_BACKOFF_BASE_MS = 500L
const val ROOM_BACKOFF_MAX_MS = 30_000L

/** First retry after a drop (1006) or a server restart (1012): `random(0, 5 s)`. */
const val ROOM_FIRST_DROP_MAX_MS = 5_000L

/** A jittered wait is never shorter than this, so a draw of 0 cannot start a tight loop. */
const val ROOM_RETRY_FLOOR_MS = 500L

/**
 * Reconnect attempts in a row (no socket that stayed open [ROOM_STABLE_MS] in between) before the
 * client gives up: the state becomes `Closed` with the reason [ROOM_REASON_EXHAUSTED] and
 * `reconnectNow()` starts again with a fresh budget. About 3.5 minutes at the longest.
 */
const val ROOM_MAX_ATTEMPTS = 12

/** `Closed` reason after [ROOM_MAX_ATTEMPTS] failed attempts in a row. */
const val ROOM_REASON_EXHAUSTED = "retries_exhausted"

/** `getToken` has this long, from the start of a connection, to answer (SPEC 18.5 step 1). */
const val ROOM_TOKEN_MS = 20_000L

/** A 4008 with `retry_after` never gives up; its wait grows up to this cap. */
const val ROOM_LIMITED_MAX_MS = 300_000L

/** Spread of the proactive token refresh (SPEC 18.5); the entry points set it. */
const val ROOM_REFRESH_JITTER_MS = 120_000L

/** Rate limited (4008) or room full (4009): wait at least this, at most 5 times in a row. */
const val ROOM_LIMITED_MIN_MS = 30_000L
const val ROOM_LIMITED_MAX_RETRIES = 5

/** The attempt counters reset after a socket stayed open this long. */
const val ROOM_STABLE_MS = 60_000L

/** App heartbeat: `ping` after this long without any frame. */
const val ROOM_HEARTBEAT_MS = 45_000L

/** No frame within this after `ping`, or no `welcome` this long after opening: the socket is dead. */
const val ROOM_DEAD_MS = 10_000L

/** A socket never lives longer than this (design D8); the server closes it with 4001 anyway. */
const val ROOM_MAX_LIFETIME_MS = 60L * 60 * 1000

/** Reconnect with a fresh token this long before the server would close the socket. */
const val ROOM_REFRESH_AHEAD_MS = 30_000L

/** Close codes (SPEC 17.6). */
object RoomClose {
    const val TOKEN_EXPIRED = 4001
    const val FORBIDDEN = 4003
    const val BAD_ROOM_ID = 4004
    const val RATE_LIMITED = 4008
    const val ROOM_FULL = 4009
    const val PLAN = 4010
    const val SUSPENDED = 4011
    const val PROTOCOL = 4400
}

/** Room id rule (SPEC 17.1): `^[A-Za-z0-9_.:-]{1,64}$`. Plain code, no regex engine. */
fun isValidRoomId(room: String): Boolean =
    room.length in 1..64 &&
        room.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '_' || it == '.' || it == ':' || it == '-' }

// ---------------------------------------------------------------- protocol

class RoomGiftInfo(val id: String, val name: String, val price: Long, val iconUrl: String?) {
    override fun equals(other: Any?) = other is RoomGiftInfo && id == other.id && name == other.name && price == other.price && iconUrl == other.iconUrl

    override fun hashCode() = listOf(id, name, price, iconUrl).hashCode()
}

class RoomSender(val id: String, val name: String? = null) {
    override fun equals(other: Any?) = other is RoomSender && id == other.id && name == other.name

    override fun hashCode() = listOf(id, name).hashCode()
}

/** A `gift` event as the server sends it, unknown fields dropped. */
class RoomGiftMessage(
    val id: Long,
    /** Commit time, epoch ms (server clock). */
    val at: Long,
    val tx: String,
    val gift: RoomGiftInfo,
    val quantity: Long,
    val sender: RoomSender,
    /** The receiver's external id, or null. */
    val receiver: String?,
) {
    override fun equals(other: Any?) =
        other is RoomGiftMessage && id == other.id && at == other.at && tx == other.tx && gift == other.gift &&
            quantity == other.quantity && sender == other.sender && receiver == other.receiver

    override fun hashCode() = listOf(id, at, tx, gift, quantity, sender, receiver).hashCode()

    override fun toString() = "RoomGiftMessage(id=$id, tx=$tx, gift=${gift.id}, quantity=$quantity, sender=${sender.id})"

    /** The wire form (SPEC 17.4 names), for the fixtures. */
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "t" to JsonPrimitive("gift"),
                "id" to JsonPrimitive(id),
                "at" to JsonPrimitive(at),
                "tx" to JsonPrimitive(tx),
                "gift" to
                    JsonObject(
                        mapOf(
                            "id" to JsonPrimitive(gift.id),
                            "name" to JsonPrimitive(gift.name),
                            "price" to JsonPrimitive(gift.price),
                            "icon_url" to gift.iconUrl.json(),
                        ),
                    ),
                "quantity" to JsonPrimitive(quantity),
                "sender" to
                    JsonObject(
                        buildMap {
                            put("id", JsonPrimitive(sender.id))
                            sender.name?.let { put("name", JsonPrimitive(it)) }
                        },
                    ),
                "receiver" to (receiver?.let { JsonObject(mapOf("id" to JsonPrimitive(it))) } ?: JsonNull),
            ),
        )
}

/** One receiver's running total in a battle round (SPEC 17.8). Display counters only. */
data class RoomScoreEntry(
    /** Receiver external id. */
    val id: String,
    /** Sum of unit price x quantity of the counted gifts. */
    val units: Long,
    /** Number of counted gifts. */
    val gifts: Long,
)

/** A battle round with its scores, in the server's fixed order (the round's receivers first). */
data class RoomBattle(
    val round: String,
    /** Epoch ms (server clock). */
    val started: Long,
    /** Epoch ms (server clock): gifts from then on no longer count. */
    val ends: Long,
    val scores: List<RoomScoreEntry>,
)

sealed interface RoomServerMessage {
    class Welcome(
        val viewers: Long,
        val gap: Boolean,
        val replay: List<RoomGiftMessage>,
        /** Seconds until the server closes the socket with 4001. */
        val ttl: Double,
        /** Server time, epoch ms. */
        val now: Long,
        /** The room's battle round; null when there is none (or it was malformed). */
        val battle: RoomBattle? = null,
    ) : RoomServerMessage

    class Gift(val gift: RoomGiftMessage) : RoomServerMessage

    class Viewers(val n: Long) : RoomServerMessage

    class Batch(val events: List<RoomGiftMessage>) : RoomServerMessage

    /** Battle scores changed (SPEC 17.8): a new snapshot of the round, or null when it was removed. */
    class Scores(val battle: RoomBattle?) : RoomServerMessage

    data object Pong : RoomServerMessage
}

private const val MAX_SAFE_INTEGER = 9007199254740991.0

/** A JSON number that is an integer in the safe range (JS `Number.isSafeInteger`), else null. */
private fun JsonElement?.safeInt(): Long? {
    if (this !is JsonPrimitive || isString) return null
    val d = content.toDoubleOrNull() ?: return null
    if (d.isNaN() || d.isInfinite() || d != floor(d) || d > MAX_SAFE_INTEGER || d < -MAX_SAFE_INTEGER) return null
    return d.toLong()
}

/** An integer >= 0. */
private fun JsonElement?.count(): Long? = safeInt()?.takeIf { it >= 0 }

private fun JsonElement?.text(): String? = if (this is JsonPrimitive && isString) content else null

private fun JsonElement?.obj(): JsonObject? = this as? JsonObject

private fun parseGift(v: JsonElement?): RoomGiftMessage? {
    val o = v.obj() ?: return null
    if (o["t"].text() != "gift") return null
    val gift = o["gift"].obj()
    val sender = o["sender"].obj()
    val id = o["id"].count()
    val at = o["at"].count()
    val tx = o["tx"].text()
    val gid = gift?.get("id").text()
    val gname = gift?.get("name").text()
    val price = gift?.get("price").count()
    val quantity = o["quantity"].safeInt()
    val sid = sender?.get("id").text()
    if (id == null || at == null || tx == null || tx == "" || gid == null || gname == null || price == null ||
        quantity == null || quantity < 1 || sid == null
    ) {
        return null
    }
    val name = sender?.get("name").text()
    return RoomGiftMessage(
        id = id,
        at = at,
        tx = tx,
        gift = RoomGiftInfo(gid, gname, price, gift?.get("icon_url").text()),
        quantity = quantity,
        sender = RoomSender(sid, if (name != null && name != "") name else null),
        receiver = o["receiver"].obj()?.get("id").text(),
    )
}

/** A battle object, or null when malformed. Invalid score entries are dropped alone. */
private fun parseBattle(v: JsonElement?): RoomBattle? {
    val o = v.obj() ?: return null
    val round = o["round"].text()
    val started = o["started"].count()
    val ends = o["ends"].count()
    val list = o["scores"] as? JsonArray
    if (round == null || round.isEmpty() || started == null || ends == null || list == null) return null
    val scores =
        list.mapNotNull { e ->
            val m = e.obj() ?: return@mapNotNull null
            val id = m["id"].text()
            val units = m["units"].count()
            val gifts = m["gifts"].count()
            if (id != null && units != null && gifts != null) RoomScoreEntry(id, units, gifts) else null
        }
    return RoomBattle(round, started, ends, scores)
}

private fun giftList(v: JsonElement?): List<RoomGiftMessage>? =
    (v as? JsonArray)?.mapNotNull { parseGift(it) }

private val frameJson = Json

/**
 * One server frame, or `null` for anything to ignore: not JSON, an unknown `t`, a known `t` with
 * a missing or mistyped required field. Unknown fields are dropped; inside `replay` and `events`
 * an invalid gift is dropped alone. The literal text `pong` is [RoomServerMessage.Pong].
 */
fun parseRoomFrame(data: String): RoomServerMessage? {
    if (data == "pong") return RoomServerMessage.Pong
    val v: JsonElement =
        try {
            frameJson.parseToJsonElement(data)
        } catch (e: Exception) {
            return null
        }
    val o = v.obj() ?: return null
    return when (o["t"].text()) {
        "gift" -> parseGift(o)?.let { RoomServerMessage.Gift(it) }
        "welcome" -> {
            val raw = o["replay"]
            val replay = if (raw == null || raw is JsonNull) emptyList() else giftList(raw)
            val viewers = o["viewers"].count()
            val gap = (o["gap"] as? JsonPrimitive)?.takeIf { !it.isString && (it.content == "true" || it.content == "false") }?.content?.toBoolean()
            val ttlEl = o["ttl"]
            val ttl = if (ttlEl is JsonPrimitive && !ttlEl.isString) ttlEl.content.toDoubleOrNull() else null
            val now = o["now"].count()
            if (viewers == null || gap == null || replay == null || ttl == null || !(ttl >= 0) || now == null) {
                null
            } else {
                RoomServerMessage.Welcome(viewers, gap, replay, ttl, now, parseBattle(o["battle"]))
            }
        }
        "scores" ->
            when (val b = o["battle"]) {
                // Only an explicit null removes the round; a missing key is junk.
                null -> null
                is JsonNull -> RoomServerMessage.Scores(null)
                else -> parseBattle(b)?.let { RoomServerMessage.Scores(it) }
            }
        "viewers" -> o["n"].count()?.let { RoomServerMessage.Viewers(it) }
        "batch" -> giftList(o["events"])?.let { RoomServerMessage.Batch(it) }
        else -> null
    }
}

/** One side of a battle bar. */
data class BattleSide(
    val id: String,
    val units: Long,
    val gifts: Long,
    /** `units / total`, 0..1; an equal split while nobody has scored. */
    val share: Double,
)

/** What a battle bar shows (SPEC 18.6). */
data class BattleView(
    val round: String,
    /** The round still counts: `started <= serverNow < ends`. */
    val open: Boolean,
    /** `max(0, ends - serverNow)`, ms. */
    val remainingMs: Long,
    /** Sum of every side's `units`. */
    val total: Long,
    /** The server's order (the round's receivers first): keep it for a stable left/right bar. */
    val sides: List<BattleSide>,
    /** The receiver with the most units; null while nobody has scored or the top is tied. */
    val leader: String?,
)

/**
 * What a battle bar shows (SPEC 18.6), pure. [serverNow] is the server clock ([RoomClient] keeps
 * the offset from the last welcome); null (no welcome yet) reads as the round's start.
 */
fun battleView(battle: RoomBattle, serverNow: Long?): BattleView {
    val now = serverNow ?: battle.started
    val total = battle.scores.sumOf { it.units }
    val n = battle.scores.size
    val sides = battle.scores.map { BattleSide(it.id, it.units, it.gifts, if (total > 0) it.units.toDouble() / total else 1.0 / n) }
    var leader: String? = null
    var best = 0L
    var tied = false
    for (e in battle.scores) {
        if (e.units > best) {
            best = e.units
            leader = e.id
            tied = false
        } else if (e.units == best && best > 0) {
            tied = true
        }
    }
    return BattleView(
        round = battle.round,
        open = now >= battle.started && now < battle.ends,
        remainingMs = maxOf(0L, battle.ends - now),
        total = total,
        sides = sides,
        leader = if (tied) null else leader,
    )
}

/** The first frame after open: `{"t":"hello","v":1,"last":<id|null>}`, keys in this order. */
fun roomHelloFrame(last: Long?): String = """{"t":"hello","v":1,"last":${last ?: "null"}}"""

/** `wss://rt.giftingstack.com/v1/rooms/<room>` (trailing slashes of [baseUrl] removed). */
fun roomUrl(room: String, baseUrl: String = DEFAULT_ROOMS_URL): String =
    "${baseUrl.trimEnd('/')}/v1/rooms/${encodeURIComponent(room)}"

/**
 * The user a client token was minted for (claim `u`), or `null` when the token is not a
 * GiftingStack client token. Used only to skip the user's own gifts; the token is not verified
 * here (the server does that).
 */
fun roomTokenUser(token: String): String? {
    val prefix = "gs_ct_"
    if (!token.startsWith(prefix)) return null
    val dot = token.indexOf('.')
    if (dot <= prefix.length) return null
    val body = token.substring(prefix.length, dot)
    if (!body.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '_' }) return null
    return try {
        val claims = frameJson.parseToJsonElement(base64UrlToText(body)).obj()
        claims?.get("u").text()
    } catch (e: Exception) {
        null
    }
}

private const val B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

/** No `java.util.Base64` (API 26) and no `android.util.Base64` (absent in unit tests). */
private fun base64UrlToText(s: String): String {
    val out = java.io.ByteArrayOutputStream()
    var bits = 0
    var acc = 0
    for (ch in s) {
        val v = B64.indexOf(ch)
        require(v >= 0) { "bad base64url" }
        acc = (acc shl 6) or v
        bits += 6
        if (bits >= 8) {
            bits -= 8
            out.write((acc shr bits) and 0xff)
        }
    }
    return String(out.toByteArray(), Charsets.UTF_8)
}

// ---------------------------------------------------------------- reconnect policy

class RoomRetryInput(
    val code: Int,
    val reason: String,
    /** Failed connections in a row before this one (0 = the first since a stable socket). */
    val attempt: Int,
    /** 4008/4009 waits in a row before this one. */
    val limited: Int,
)

sealed interface RoomRetryDecision {
    class Stop(
        /** The client stopped by its own rule, not because the server said it is final: `reconnectNow()` may start again. */
        val resumable: Boolean = false,
        /** [ROOM_MAX_ATTEMPTS] failed attempts in a row. */
        val exhausted: Boolean = false,
    ) : RoomRetryDecision

    class Retry(
        val delayMs: Long,
        /** Ask `getToken` with `forceRefresh = true` before reconnecting. */
        val refreshToken: Boolean,
        /** A rate-limit/room-full wait: counts against the 5 such waits. */
        val limited: Boolean,
    ) : RoomRetryDecision
}

/** `retry_after` of a JSON close reason, in whole seconds; 0 when absent or not a count. */
private fun retryAfterSeconds(reason: String): Long =
    try {
        frameJson.parseToJsonElement(reason).obj()?.get("retry_after").count() ?: 0
    } catch (e: Exception) {
        0
    }

/**
 * Wait after a 4008 that carried `retry_after` (seconds): `max(30 s, retry_after)` doubled per wait
 * already in a row ([limited]), plus up to 25 % jitter, never above 5 minutes. Calls [random] once.
 */
fun roomRateLimitedDelayMs(retryAfterS: Long, limited: Int, random: () -> Double): Long {
    // Clamping the base first changes nothing (the result is capped anyway) and keeps the product in 64 bits.
    val base = minOf(ROOM_LIMITED_MAX_MS, maxOf(ROOM_LIMITED_MIN_MS, retryAfterS * 1000))
    val grown = minOf(ROOM_LIMITED_MAX_MS, base * (1L shl minOf(maxOf(0, limited), 16)))
    return minOf(ROOM_LIMITED_MAX_MS, grown + floor(random() * (grown / 4)).toLong())
}

/**
 * What to do after a socket closed (SPEC 18.3). [random] returns [0, 1) and is called at most
 * once, only for a jittered delay: `ROOM_RETRY_FLOOR_MS + floor(random() * (cap - floor))`.
 */
fun roomRetryDecision(input: RoomRetryInput, random: () -> Double): RoomRetryDecision {
    val attempt = input.attempt
    val reason = input.reason
    fun jitter(cap: Long): Long = ROOM_RETRY_FLOOR_MS + floor(random() * maxOf(0L, cap - ROOM_RETRY_FLOOR_MS)).toLong()
    fun backoff(): Long =
        jitter(minOf(ROOM_BACKOFF_MAX_MS.toDouble(), ROOM_BACKOFF_BASE_MS * 2.0.pow(maxOf(0, attempt))).toLong())
    when (input.code) {
        RoomClose.FORBIDDEN, RoomClose.BAD_ROOM_ID, RoomClose.PLAN, RoomClose.PROTOCOL -> return RoomRetryDecision.Stop()
        RoomClose.SUSPENDED -> return RoomRetryDecision.Stop(resumable = true)
        RoomClose.ROOM_FULL, RoomClose.RATE_LIMITED -> {
            if (input.code == RoomClose.ROOM_FULL && reason == "replaced") return RoomRetryDecision.Stop()
            val retryAfter = retryAfterSeconds(reason)
            if (input.code == RoomClose.RATE_LIMITED && retryAfter > 0) {
                // A platform limit that lifts by itself: grows, never gives up (and is not counted against the attempt ceiling).
                return RoomRetryDecision.Retry(
                    roomRateLimitedDelayMs(retryAfter, input.limited, random),
                    refreshToken = false,
                    limited = true,
                )
            }
            if (input.limited >= ROOM_LIMITED_MAX_RETRIES) return RoomRetryDecision.Stop(resumable = true)
            return RoomRetryDecision.Retry(maxOf(ROOM_LIMITED_MIN_MS, retryAfter * 1000), refreshToken = false, limited = true)
        }
        else -> Unit
    }
    if (attempt >= ROOM_MAX_ATTEMPTS) return RoomRetryDecision.Stop(resumable = true, exhausted = true)
    return when (input.code) {
        RoomClose.TOKEN_EXPIRED ->
            RoomRetryDecision.Retry(if (attempt == 0) 0 else backoff(), refreshToken = true, limited = false)
        1006, 1012 ->
            RoomRetryDecision.Retry(if (attempt == 0) jitter(ROOM_FIRST_DROP_MAX_MS) else backoff(), refreshToken = false, limited = false)
        else -> RoomRetryDecision.Retry(backoff(), refreshToken = false, limited = false)
    }
}

// ---------------------------------------------------------------- filter

class RoomEventFilterOptions(
    /** The signed-in user (token claim `u`): with [skipOwn], their gifts are not played again. */
    val user: String? = null,
    /** Default true: the sender's own tray already played the effect on tap. */
    val skipOwn: Boolean = true,
    /** Default 10,000. Events at least this old (server clock) are dropped. */
    val maxReplayAgeMs: Long = DEFAULT_MAX_REPLAY_AGE_MS,
    /** Viewer-side filter: only gifts of this tier or bigger. Default small (all). */
    val minTier: EffectTier = EffectTier.Small,
    val thresholds: TierThresholds = DEFAULT_THRESHOLDS,
)

class RoomFilterResult(
    /** The gifts to play, in order. */
    val events: List<RoomGiftMessage>,
    /** `welcome.gap`: events may have been missed. Always false for live frames. */
    val gap: Boolean,
)

/**
 * Decides which received gifts reach the app (SPEC 18.2). Keeps the resume point [last] (id of
 * the last gift received, played or not) and the last 256 `tx` across reconnects. Each gift, in
 * order: `last = id`; a `tx` seen before is dropped; then (the `tx` is remembered) a gift whose
 * age `serverNow - at` is at least `maxReplayAgeMs` is dropped, then the user's own gift
 * (`skipOwn`), then a gift below `minTier`. `serverNow` is `welcome.now` for the replay and
 * `welcome.now + (localNow - local time of the welcome)` for live gifts.
 */
class RoomEventFilter(private var options: RoomEventFilterOptions = RoomEventFilterOptions()) {
    /** Resume point sent in `hello`. */
    var last: Long? = null
        private set

    private val seen = HashSet<String>()
    private val order = ArrayDeque<String>()

    /** `welcome.now - local time of the welcome`; null before the first welcome. */
    private var offset: Long? = null

    fun setOptions(options: RoomEventFilterOptions) {
        this.options = options
    }

    /** The `tx` ids remembered, oldest first. */
    fun seenTx(): List<String> = order.toList()

    /** Server time now, from the last welcome; null before the first one. */
    fun serverNow(localNow: Long): Long? = offset?.let { localNow + it }

    fun welcome(msg: RoomServerMessage.Welcome, localNow: Long): RoomFilterResult {
        offset = msg.now - localNow
        return RoomFilterResult(pass(msg.replay, msg.now), msg.gap)
    }

    /** A live `gift` or `batch`. Before any welcome nothing passes (the server never does that). */
    fun live(events: List<RoomGiftMessage>, localNow: Long): RoomFilterResult {
        val off = offset ?: return RoomFilterResult(emptyList(), false)
        return RoomFilterResult(pass(events, localNow + off), false)
    }

    private fun pass(events: List<RoomGiftMessage>, serverNow: Long): List<RoomGiftMessage> {
        val o = options
        val min = o.minTier.ordinal
        val out = ArrayList<RoomGiftMessage>()
        for (e in events) {
            last = e.id
            if (e.tx in seen) continue
            remember(e.tx)
            if (serverNow - e.at >= o.maxReplayAgeMs) continue
            if (o.skipOwn && o.user != null && e.sender.id == o.user) continue
            if (tierFor(e.gift.price.toDouble(), o.thresholds).ordinal < min) continue
            out.add(e)
        }
        return out
    }

    private fun remember(tx: String) {
        seen.add(tx)
        order.addLast(tx)
        while (order.size > ROOM_DEDUP_SIZE) seen.remove(order.removeFirst())
    }
}

// ---------------------------------------------------------------- mapping

/**
 * A room gift ready for the effect layer: [toEffect] is what `play` takes. (The TypeScript type
 * extends the effect event; a Kotlin data class cannot be extended, so it is a method here.)
 */
class RoomGiftEvent(
    val gift: EffectGift,
    /** Display name for the notice, or null (the layer shows "Someone"). */
    val sender: String?,
    val quantity: Long,
    /** Event id (the resume point). */
    val id: Long,
    /** Gift transaction id. */
    val tx: String,
    /** Commit time, epoch ms (server clock). */
    val at: Long,
    /** The sender's external id. */
    val senderId: String,
    /** The sender's display name from their token (claim `n`), else null. */
    val senderName: String?,
    val receiverId: String?,
    /** Came in the `welcome` replay after a (re)connect, not live. */
    val replayed: Boolean,
) {
    /** What to pass to the effect layer's `play`. */
    fun toEffect(): GiftEffectEvent = GiftEffectEvent(gift, sender, quantity.coerceIn(1, Int.MAX_VALUE.toLong()).toInt())
}

class RoomMappingOptions(
    /** The app's gift catalog (`GET /v1/client/gifts`): supplies the big picture. */
    val catalog: List<Gift>? = null,
    /** Display name of a sender without a name claim. Return null for the default. */
    val resolveName: ((String) -> String?)? = null,
    val replayed: Boolean = false,
)

/**
 * Turns a room gift into what the effect layer plays (SPEC 18.4): name and price from the event
 * (the price at send time drives the tier); `image` = the catalog gift's `animation_url`, else
 * its `icon_url`, else the event's `icon_url`; `icon` = the event's `icon_url`, else the
 * catalog's; `sender` = the name claim, else `resolveName(sender id)`, else absent.
 */
fun roomGiftToEffect(msg: RoomGiftMessage, options: RoomMappingOptions = RoomMappingOptions()): RoomGiftEvent {
    val known = options.catalog?.firstOrNull { it.id == msg.gift.id }
    val image = known?.animationUrl ?: known?.iconUrl ?: msg.gift.iconUrl
    val icon = msg.gift.iconUrl ?: known?.iconUrl
    val senderName = msg.sender.name
    var sender: String? = senderName
    if (sender == null && options.resolveName != null) {
        sender =
            try {
                options.resolveName.invoke(msg.sender.id)?.takeIf { it.isNotEmpty() }
            } catch (e: Exception) {
                null
            }
    }
    return RoomGiftEvent(
        gift = EffectGift(msg.gift.id, msg.gift.name, msg.gift.price, image, icon),
        sender = sender,
        quantity = msg.quantity,
        id = msg.id,
        tx = msg.tx,
        at = msg.at,
        senderId = msg.sender.id,
        senderName = senderName,
        receiverId = msg.receiver,
        replayed = options.replayed,
    )
}

// ---------------------------------------------------------------- session

/** What a platform transport implements: one WebSocket, text frames only. */
interface RoomSocket {
    fun send(data: String)

    /** Close the socket. After this the client ignores every callback of this socket. */
    fun close(code: Int, reason: String)
}

interface RoomSocketHandlers {
    fun onOpen()

    /** Text frames only; a transport drops binary frames. */
    fun onMessage(data: String)

    /** Exactly once per socket (an error before or after open is a close with 1006). */
    fun onClose(code: Int, reason: String)
}

/** Opens [url] with the WebSocket protocols `["gs.v1", token]`. */
fun interface RoomSocketFactory {
    fun open(url: String, protocols: List<String>, handlers: RoomSocketHandlers): RoomSocket
}

enum class RoomStatus(val wire: String) {
    Idle("idle"),
    Connecting("connecting"),
    Open("open"),
    Reconnecting("reconnecting"),
    Paused("paused"),
    Closed("closed"),
}

data class RoomState(
    val status: RoomStatus = RoomStatus.Idle,
    /** Failed connections in a row. */
    val attempt: Int = 0,
    /** `Reconnecting`: the wait before the next attempt, ms. Else null. */
    val retryInMs: Long? = null,
    /** `Closed`: the close code (1000 after `leave()`), else the last close code seen or null. */
    val code: Int? = null,
    val reason: String? = null,
    /** Approximate viewer count from the server; null before the first welcome. */
    val viewers: Long? = null,
)

class RoomClientOptions(
    val room: String,
    /** The same token function as the client's. Mint the token with `rooms` and `name` (SPEC 17.2). */
    val getToken: suspend (forceRefresh: Boolean) -> String,
    val socket: RoomSocketFactory,
    /** Runs `getToken`. Use the main-thread scope: the client is single-threaded. */
    val scope: CoroutineScope,
    val timers: Timers,
    /** Default `wss://rt.giftingstack.com`. */
    val url: String = DEFAULT_ROOMS_URL,
    // filter
    val user: String? = null,
    val skipOwn: Boolean = true,
    val maxReplayAgeMs: Long = DEFAULT_MAX_REPLAY_AGE_MS,
    val minTier: EffectTier = EffectTier.Small,
    val thresholds: TierThresholds = DEFAULT_THRESHOLDS,
    // mapping
    val catalog: List<Gift>? = null,
    /** The catalog, read at each event (wins over [catalog]). */
    val getCatalog: (() -> List<Gift>?)? = null,
    val resolveName: ((String) -> String?)? = null,
    val onEvent: ((RoomGiftEvent) -> Unit)? = null,
    val onViewers: ((Long) -> Unit)? = null,
    val onGap: (() -> Unit)? = null,
    val onState: ((RoomState) -> Unit)? = null,
    /** Battle scores changed (SPEC 18.6): a new snapshot, or null when the round was removed. */
    val onBattle: ((RoomBattle?) -> Unit)? = null,
    /** App heartbeat interval. 0 turns it off for transports with protocol pings. Default 45,000. */
    val heartbeatMs: Long = ROOM_HEARTBEAT_MS,
    val now: () -> Long = System::currentTimeMillis,
    /** [0, 1). */
    val random: () -> Double = Math::random,
    /**
     * The proactive token refresh happens `random(0, refreshJitterMs)` earlier than 30 s before the
     * socket's end, so viewers that joined together do not all reconnect in the same second.
     * Default 0 (exact timing, as in the fixtures); `rememberGiftRoom` sets [ROOM_REFRESH_JITTER_MS].
     */
    val refreshJitterMs: Long = 0L,
    /**
     * Lets a plain `ws://` [url] to a host that is not on this device through (SPEC 3.1, audit R-07).
     * Without it [RoomClient] throws `IllegalArgumentException` when it is created, or when options
     * with such a url replace its own.
     */
    val allowInsecure: Boolean = false,
)

private enum class RoomTimer { Retry, Dead, Beat, Refresh }

/**
 * One room membership (SPEC 18): connects, says hello, plays what the filter lets through,
 * reconnects with backoff and resume, refreshes the token, keeps a heartbeat. Never throws into
 * the app; app callbacks that throw are ignored. Port of `RoomClient` in the TypeScript core.
 *
 * NOT thread-safe: call it, and deliver the socket callbacks, from one thread (the main thread;
 * `rememberGiftRoom` does). `getToken` runs in `options.scope`.
 *
 * idle -start-> connecting -welcome-> open -drop-> reconnecting -> connecting ...;
 * `pause()` (app in background) -> paused -`resume()`-> connecting; `leave()` or a final close
 * code -> closed (terminal).
 */
class RoomClient(options: RoomClientOptions) {
    private var options: RoomClientOptions = options.also { requireSecureUrl(it.url, it.allowInsecure, "The rooms url") }
    private val _state = MutableStateFlow(RoomState())
    val state: StateFlow<RoomState> = _state.asStateFlow()
    private val eventListeners = LinkedHashSet<(RoomGiftEvent) -> Unit>()
    private val _battle = MutableStateFlow<RoomBattle?>(null)

    /**
     * The room's battle round as last received (SPEC 18.6): from `welcome`, then each `scores`
     * frame. Kept across reconnects until the next welcome; null when there is none.
     */
    val battle: StateFlow<RoomBattle?> = _battle.asStateFlow()
    val filter = RoomEventFilter(filterOptions(null))

    /** Bumped whenever the current socket or token request stops mattering. */
    private var gen = 0
    private var socket: RoomSocket? = null
    private var limited = 0

    /** The wait now running is a 4008/4009 one: the platform said when to come back (SPEC 18.5 step 6, R-15). */
    private var waitIsLimited = false

    /** The last close was a stop by the client's own rule (SPEC 18.3): `reconnectNow()` may restart. */
    private var resumable = false
    private var refreshNext = false
    private var tokenUser: String? = null
    private var openedAt: Long? = null
    private var lastFrameAt = 0L
    private val timers = HashMap<RoomTimer, Any>()

    fun getState(): RoomState = _state.value

    fun getBattle(): RoomBattle? = _battle.value

    /** Server time now (from the last welcome), null before the first welcome. */
    fun serverNow(): Long? = filter.serverNow(now())

    /** [battleView] of the current round at the server's time now, null without a round. */
    fun getBattleView(): BattleView? = _battle.value?.let { battleView(it, serverNow()) }

    /** Callbacks and filter settings are read when used, so they can change between calls. */
    fun setOptions(options: RoomClientOptions) {
        requireSecureUrl(options.url, options.allowInsecure, "The rooms url")
        this.options = options
        filter.setOptions(filterOptions(tokenUser))
    }

    /** `user` option, else the token's `u` claim. */
    private fun filterOptions(tokenUser: String?): RoomEventFilterOptions =
        RoomEventFilterOptions(
            user = options.user ?: tokenUser,
            skipOwn = options.skipOwn,
            maxReplayAgeMs = options.maxReplayAgeMs,
            minTier = options.minTier,
            thresholds = options.thresholds,
        )

    /** Every gift that passes the filter, after `onEvent`. Returns the remover. */
    fun addEventListener(listener: (RoomGiftEvent) -> Unit): () -> Unit {
        eventListeners.add(listener)
        return { eventListeners.remove(listener) }
    }

    /** Connect. Only from idle; a bad room id closes at once with 4004 and opens nothing. */
    fun start() {
        if (_state.value.status != RoomStatus.Idle) return
        if (!isValidRoomId(options.room)) {
            finish(RoomClose.BAD_ROOM_ID, "bad_room_id")
            return
        }
        connect()
    }

    /** Leave the room for good: closes with 1000, no callbacks after this. */
    fun leave() {
        if (_state.value.status == RoomStatus.Closed) return
        finish(1000, "left")
    }

    /** App went to the background: close (1000), keep `last` and the dedup set, no retry. */
    fun pause() {
        val s = _state.value.status
        if (s == RoomStatus.Idle || s == RoomStatus.Closed || s == RoomStatus.Paused) return
        drop()
        set { it.copy(status = RoomStatus.Paused, retryInMs = null) }
    }

    /** Back in the foreground: reconnect now with `last`. Only from paused. */
    fun resume() {
        if (_state.value.status != RoomStatus.Paused) return
        connect()
    }

    /**
     * The network is back (or the user asked): skip a pending backoff wait (never a 4008/4009 one: the platform
     * said when to come back, SPEC 18.5 step 6). After a stop by the client's
     * own rule (`retries_exhausted`, 4011, the 4008/4009 limit) it starts again with a fresh attempt
     * budget. Nothing else changes.
     */
    fun reconnectNow() {
        if (_state.value.status == RoomStatus.Closed && resumable) {
            resumable = false
            limited = 0
            set { it.copy(attempt = 0) }
            connect()
            return
        }
        if (_state.value.status != RoomStatus.Reconnecting) return
        // Never skip a 4008/4009 wait: skipping it would send every viewer back at once and defeat the limit.
        if (waitIsLimited) return
        clear(RoomTimer.Retry)
        connect()
    }

    fun dispose() = leave()

    // ---------------------------------------------------------------- internals

    private fun now(): Long = options.now()

    private fun set(patch: (RoomState) -> RoomState) {
        _state.value = patch(_state.value)
        val s = _state.value
        safe { options.onState?.invoke(s) }
    }

    private inline fun safe(fn: () -> Unit) {
        try {
            fn()
        } catch (e: Exception) {
            // App callbacks never break the room.
        }
    }

    private fun later(name: RoomTimer, ms: Long, fn: () -> Unit) {
        clear(name)
        timers[name] =
            options.timers.set(maxOf(0L, ms)) {
                timers.remove(name)
                fn()
            }
    }

    private fun clear(name: RoomTimer) {
        val h = timers.remove(name) ?: return
        options.timers.clear(h)
    }

    private fun clearAll() {
        for (name in timers.keys.toList()) clear(name)
    }

    /** Forget the current socket (closing it with 1000) and any token request in flight. */
    private fun drop() {
        gen += 1
        clearAll()
        val s = socket
        socket = null
        openedAt = null
        if (s != null) safe { s.close(1000, "client") }
    }

    private fun finish(code: Int, reason: String) {
        drop()
        resumable = false
        set { it.copy(status = RoomStatus.Closed, retryInMs = null, code = code, reason = reason) }
    }

    private fun connect() {
        drop()
        val gen = this.gen
        val refresh = refreshNext
        refreshNext = false
        set { it.copy(status = RoomStatus.Connecting, retryInMs = null) }
        // A `getToken` that never answers must not keep the room connecting forever.
        later(RoomTimer.Dead, ROOM_TOKEN_MS) { dead(gen) }
        val o = options
        o.scope.launch {
            val token: String? =
                try {
                    o.getToken(refresh)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    null
                }
            if (gen != this@RoomClient.gen) return@launch
            // No token (the app's server is down, the user signed out): retry like a network error.
            if (token == null) closed(gen, 1006, "token_failed") else open(token, gen)
        }
    }

    private fun open(token: String, gen: Int) {
        tokenUser = roomTokenUser(token)
        filter.setOptions(filterOptions(tokenUser))
        val url = roomUrl(options.room, options.url)
        val handlers =
            object : RoomSocketHandlers {
                override fun onOpen() {
                    if (gen != this@RoomClient.gen || socket == null) return
                    lastFrameAt = now()
                    sendFrame(roomHelloFrame(filter.last))
                }

                override fun onMessage(data: String) {
                    if (gen != this@RoomClient.gen) return
                    message(data, gen)
                }

                override fun onClose(code: Int, reason: String) {
                    if (gen != this@RoomClient.gen) return
                    socket = null
                    closed(gen, code, reason)
                }
            }
        try {
            socket = options.socket.open(url, listOf(ROOM_SUBPROTOCOL, token), handlers)
        } catch (e: Exception) {
            closed(gen, 1006, "socket_failed")
            return
        }
        // From creation to `welcome`: the same 10 s as a missing pong.
        later(RoomTimer.Dead, ROOM_DEAD_MS) { dead(gen) }
    }

    private fun sendFrame(data: String) {
        val s = socket ?: return
        safe { s.send(data) }
    }

    private fun message(data: String, gen: Int) {
        val now = now()
        lastFrameAt = now
        if (_state.value.status == RoomStatus.Open) clear(RoomTimer.Dead)
        val msg = parseRoomFrame(data) ?: return
        when (msg) {
            is RoomServerMessage.Welcome -> {
                clear(RoomTimer.Dead)
                openedAt = now
                val ttlMs = minOf(msg.ttl * 1000, ROOM_MAX_LIFETIME_MS.toDouble())
                if (ttlMs > ROOM_REFRESH_AHEAD_MS) {
                    val left = (ttlMs - ROOM_REFRESH_AHEAD_MS).toLong()
                    val spread = minOf(options.refreshJitterMs, left / 2)
                    val early = if (spread > 0) floor(options.random() * spread).toLong() else 0L
                    later(RoomTimer.Refresh, left - early) {
                        if (gen != this.gen) return@later
                        refreshNext = true
                        connect()
                    }
                }
                beat(gen)
                set { it.copy(status = RoomStatus.Open, viewers = msg.viewers, retryInMs = null) }
                safe { options.onViewers?.invoke(msg.viewers) }
                val r = filter.welcome(msg, now)
                setBattle(msg.battle)
                if (r.gap) safe { options.onGap?.invoke() }
                emit(r.events, true, gen)
            }
            is RoomServerMessage.Gift -> emit(filter.live(listOf(msg.gift), now).events, false, gen)
            is RoomServerMessage.Batch -> emit(filter.live(msg.events, now).events, false, gen)
            is RoomServerMessage.Viewers -> {
                set { it.copy(viewers = msg.n) }
                safe { options.onViewers?.invoke(msg.n) }
            }
            is RoomServerMessage.Scores -> if (_state.value.status == RoomStatus.Open) setBattle(msg.battle)
            RoomServerMessage.Pong -> Unit
        }
    }

    private fun setBattle(battle: RoomBattle?) {
        if (battle == null && _battle.value == null) return
        _battle.value = battle
        safe { options.onBattle?.invoke(battle) }
    }

    private fun emit(events: List<RoomGiftMessage>, replayed: Boolean, gen: Int) {
        for (e in events) {
            if (gen != this.gen) return
            val o = options
            val event = roomGiftToEffect(e, RoomMappingOptions(o.getCatalog?.invoke() ?: o.catalog, o.resolveName, replayed))
            safe { o.onEvent?.invoke(event) }
            for (l in eventListeners.toList()) safe { l(event) }
        }
    }

    /** Heartbeat: `ping` after `heartbeatMs` without frames; the next frame must come within 10 s. */
    private fun beat(gen: Int) {
        val every = options.heartbeatMs
        if (every <= 0) return
        val wait = maxOf(0L, lastFrameAt + every - now())
        later(RoomTimer.Beat, wait) {
            if (gen != this.gen) return@later
            if (now() - lastFrameAt >= every) {
                sendFrame("ping")
                later(RoomTimer.Dead, ROOM_DEAD_MS) { dead(gen) }
                lastFrameAt = now()
            }
            beat(gen)
        }
    }

    /**
     * No token, no welcome or no answer to `ping` in time: drop the socket and retry like a 1006
     * (reason `token_timeout` while no socket exists yet, else `timeout`).
     */
    private fun dead(gen: Int) {
        if (gen != this.gen) return
        val s = socket
        socket = null
        if (s != null) safe { s.close(1000, "timeout") }
        closed(gen, 1006, if (s != null) "timeout" else "token_timeout")
    }

    private fun closed(gen: Int, code: Int, reason: String) {
        if (gen != this.gen) return
        val stable = openedAt?.let { now() - it >= ROOM_STABLE_MS } ?: false
        drop()
        if (stable) limited = 0
        val attempt = if (stable) 0 else _state.value.attempt
        val d = roomRetryDecision(RoomRetryInput(code, reason, attempt, limited), options.random)
        if (d !is RoomRetryDecision.Retry) {
            val stop = d as RoomRetryDecision.Stop
            resumable = stop.resumable
            set {
                it.copy(
                    status = RoomStatus.Closed,
                    retryInMs = null,
                    code = code,
                    reason = if (stop.exhausted) ROOM_REASON_EXHAUSTED else reason,
                    attempt = attempt,
                )
            }
            return
        }
        limited = if (d.limited) limited + 1 else 0
        waitIsLimited = d.limited
        refreshNext = d.refreshToken
        set { it.copy(status = RoomStatus.Reconnecting, attempt = attempt + 1, retryInMs = d.delayMs, code = code, reason = reason) }
        val next = this.gen
        later(RoomTimer.Retry, d.delayMs) {
            if (next == this.gen) connect()
        }
    }
}
