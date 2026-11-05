package com.giftingstack.core

import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

const val DEFAULT_BASE_URL = "https://api.giftingstack.com"

/** Any error from the API, or a network failure (`status` 0). */
class GiftingException(
    val status: Int,
    val type: String,
    message: String,
    val requestId: String? = null,
) : Exception(message) {
    /** Worth showing as "try again" rather than as a hard failure. */
    val retryable: Boolean get() = status == 0 || status == 429 || status >= 500

    /** `insufficient_balance`: show your coin store. */
    val insufficientBalance: Boolean get() = type == "insufficient_balance"
}

/** The name the task and the TypeScript reference use for [GiftingException]. */
typealias GiftingError = GiftingException

/** One HTTP request, as the client hands it to the transport. */
class TransportRequest(
    val method: String,
    /** The full URL, percent-encoded. */
    val url: String,
    val headers: Map<String, String>,
    /** The body as text (UTF-8), or null for none. */
    val body: String?,
)

class TransportResponse(
    val status: Int,
    val headers: Map<String, String> = emptyMap(),
    val body: String = "",
)

/**
 * Sends a request and returns the answer, whatever the status. Throw any exception when there is
 * no answer (DNS, offline, TLS, reset): the client turns it into a `network_error`.
 */
fun interface GiftingTransport {
    suspend fun send(request: TransportRequest): TransportResponse
}

/** What the tray and your own code call; implemented by [GiftingClient] and by test doubles. */
interface GiftingApi {
    suspend fun getGifts(): List<Gift>

    suspend fun getMe(): Me

    suspend fun getReceivedGifts(user: String): List<ReceivedGift>

    suspend fun sendGift(input: SendGiftInput): GiftTransaction
}

/** The batch call of the gift wall (SPEC section 14). Implemented by [GiftingClient] and by test doubles. */
interface GiftWallApi {
    /** Up to 25 walls in one call, answered in the same order. An empty list makes no request. */
    suspend fun queryGiftWalls(items: List<GiftWallQueryItem>): List<GiftWall>
}

/** The "while you were away" calls (SPEC section 15). */
interface AwayApi {
    /** Gifts the signed-in user received since they last looked. */
    suspend fun getAway(query: AwayQuery = AwayQuery()): AwaySummary

    /** Marks a summary as seen: send its cursor once it was shown. The server never moves back. */
    suspend fun ackAway(cursor: String)
}

/** The leaderboard call (SPEC section 16). `me` is the signed-in user. */
interface LeaderboardApi {
    suspend fun getLeaderboard(board: LeaderboardBoard, query: LeaderboardQuery = LeaderboardQuery()): Leaderboard
}

/** The default transport: `HttpURLConnection` on `Dispatchers.IO`. No extra dependency. */
class HttpUrlConnectionTransport(
    private val connectTimeoutMs: Int = 15_000,
    private val readTimeoutMs: Int = 30_000,
) : GiftingTransport {
    override suspend fun send(request: TransportRequest): TransportResponse =
        withContext(Dispatchers.IO) {
            val conn = URL(request.url).openConnection() as HttpURLConnection
            try {
                conn.requestMethod = request.method
                conn.connectTimeout = connectTimeoutMs
                conn.readTimeout = readTimeoutMs
                conn.instanceFollowRedirects = false
                for ((k, v) in request.headers) conn.setRequestProperty(k, v)
                if (request.body != null) {
                    conn.doOutput = true
                    conn.outputStream.use { it.write(request.body.toByteArray(Charsets.UTF_8)) }
                }
                val status = conn.responseCode
                val stream = if (status >= 400) conn.errorStream else conn.inputStream
                val text =
                    stream?.use { s ->
                        val out = ByteArrayOutputStream()
                        s.copyTo(out)
                        out.toString("UTF-8")
                    } ?: ""
                val headers = HashMap<String, String>()
                for ((k, v) in conn.headerFields) {
                    if (k != null && v.isNotEmpty()) headers[k.lowercase(Locale.ROOT)] = v.first()
                }
                TransportResponse(status, headers, text)
            } finally {
                conn.disconnect()
            }
        }
}

/** The header the app-facing API reads where the app runs from (information only). */
const val PLATFORM_HEADER = "X-GiftingStack-Platform"

/** The header with the phone's operating system, `ios` or `android` (information only). */
const val OS_HEADER = "X-GiftingStack-OS"

/** A new idempotency key (UUID v4), made once per `sendGift` call. */
fun newIdempotencyKey(): String = UUID.randomUUID().toString()

private const val UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"

/**
 * Exactly JavaScript's `encodeURIComponent`: UTF-8 percent-encoding of every byte except
 * `A-Z a-z 0-9 - _ . ! ~ * ' ( )`. Space is `%20` (not `+`). Do not replace it with
 * `URLEncoder`.
 */
fun encodeURIComponent(s: String): String {
    val sb = StringBuilder(s.length + 8)
    for (b in s.toByteArray(Charsets.UTF_8)) {
        val c = (b.toInt() and 0xFF)
        if (c < 0x80 && UNRESERVED.indexOf(c.toChar()) >= 0) {
            sb.append(c.toChar())
        } else {
            sb.append('%')
            sb.append("0123456789ABCDEF"[c shr 4])
            sb.append("0123456789ABCDEF"[c and 0x0F])
        }
    }
    return sb.toString()
}

/**
 * `?a=1&b=2` from the pairs whose value is not null, in the order given, values encoded like
 * `encodeURIComponent`. Empty when nothing is given.
 */
internal fun queryString(vararg pairs: Pair<String, String?>): String {
    val parts = pairs.filter { it.second != null }.map { (k, v) -> "$k=${encodeURIComponent(v!!)}" }
    return if (parts.isEmpty()) "" else "?" + parts.joinToString("&")
}

/**
 * The GiftingStack client API (spec section 3).
 *
 * @param getToken returns a client token for the signed-in user. Your own server creates it
 *   with `POST /v1/client-tokens`. Called again with `forceRefresh = true` after a 401.
 * @param baseUrl default `https://api.giftingstack.com`; trailing slashes are removed. `http://` is
 *   refused unless the host is `localhost`, `127.0.0.1`, `::1` or `10.0.2.2` (the emulator's dev
 *   machine) or [allowInsecure] is true: the bearer token would travel in clear text.
 * @param transport replace it in tests; the default uses `HttpURLConnection`.
 * @param platform where the app runs, sent as `X-GiftingStack-Platform` so the dashboard shows which
 *   platforms gifts are sent from (information only). Default `android`.
 * @param os the phone's operating system, sent as `X-GiftingStack-OS` (information only). Default
 *   `android`; null sends none.
 * @param allowInsecure lets a non-loopback `http://` [baseUrl] through (a staging proxy on your LAN).
 *   Never for a production app. Without it such a URL throws `IllegalArgumentException` here.
 */
class GiftingClient(
    private val getToken: suspend (forceRefresh: Boolean) -> String,
    baseUrl: String = DEFAULT_BASE_URL,
    private val transport: GiftingTransport = HttpUrlConnectionTransport(),
    private val platform: String = "android",
    private val os: String? = "android",
    allowInsecure: Boolean = false,
) : GiftingApi, GiftWallApi, AwayApi, LeaderboardApi, InboxApi {
    private val base = baseUrl.replace(Regex("/+$"), "")

    init {
        requireSecureUrl(base, allowInsecure, "baseUrl")
    }

    /** One lost-connection repeat per call (SPEC 3.4, audit R-18): shared by the attempts of a call. */
    private class Repeat {
        var used = false
    }

    private suspend fun once(
        method: String,
        path: String,
        token: String,
        body: JsonObject?,
        idempotencyKey: String?,
        repeat: Repeat,
    ): TransportResponse {
        val headers = LinkedHashMap<String, String>()
        headers["Authorization"] = "Bearer $token"
        headers[PLATFORM_HEADER] = platform
        if (os != null) headers[OS_HEADER] = os
        if (body != null) headers["Content-Type"] = "application/json"
        if (!idempotencyKey.isNullOrEmpty()) headers["Idempotency-Key"] = idempotencyKey
        try {
            return transport.send(TransportRequest(method, base + path, headers, body?.toString()))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // sendGift repeats ONE lost connection at once, same token, same key (the server replays it if the
            // first request arrived). Not our own timeout, not a GET, not a POST without a key (SPEC 3.4, R-18).
            if (!idempotencyKey.isNullOrEmpty() && !repeat.used && e !is java.net.SocketTimeoutException) {
                repeat.used = true
                return once(method, path, token, body, idempotencyKey, repeat)
            }
            throw GiftingException(
                0,
                "network_error",
                "Could not reach GiftingStack. Check your connection.",
            )
        }
    }

    /**
     * One call (SPEC 3.4). [decode] turns the parsed 2xx body into the typed answer; a body that is not
     * JSON, or that [decode] cannot read, is `invalid_response` (SPEC 3.5) and carries none of the body.
     * Timeouts: `HttpUrlConnectionTransport` has 15 s to connect and 30 s per read (SPEC 3.4 platform
     * note); a timeout is a transport failure, so `network_error`.
     */
    private suspend fun <T> request(
        method: String,
        path: String,
        body: JsonObject? = null,
        idempotencyKey: String? = null,
        decode: (JsonElement) -> T,
    ): T {
        val repeat = Repeat()
        var token = getToken(false)
        var res = once(method, path, token, body, idempotencyKey, repeat)
        // A rejected token is usually just an expired one: get a fresh one and try once more.
        if (res.status == 401) {
            token = getToken(true)
            res = once(method, path, token, body, idempotencyKey, repeat)
        }
        // One quiet retry for a server hiccup, with the same token and the same key.
        if (res.status >= 500) {
            res = once(method, path, token, body, idempotencyKey, repeat)
        }
        if (res.status !in 200..299) throw errorFrom(res)
        // 204 No Content (the away cursor PUT): there is nothing to parse.
        if (res.status == 204) return decode(JsonNull)
        try {
            return decode(JSON.parseToJsonElement(res.body))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Not JSON (a proxy's HTML page, a cut-off body) or not the shape of the model: never show its text.
            throw GiftingException(
                res.status,
                "invalid_response",
                "Invalid response (${res.status}).",
                requestIdOf(res),
            )
        }
    }

    override suspend fun getGifts(): List<Gift> =
        request("GET", "/v1/client/gifts") { json -> json.data().map { Gift.fromJson(it) } }

    override suspend fun getMe(): Me = request("GET", "/v1/client/me") { Me.fromJson(it) }

    override suspend fun getReceivedGifts(user: String): List<ReceivedGift> = getReceivedGifts(user, null)

    /**
     * The gift counters of a user; with [reference] only the gifts sent with that `reference`
     * (one post's wall). No query string without it.
     */
    suspend fun getReceivedGifts(user: String, reference: String?): List<ReceivedGift> =
        request("GET", "/v1/client/users/${encodeURIComponent(user)}/received-gifts" + queryString("reference" to reference)) { json ->
            json.data().map { ReceivedGift.fromJson(it) }
        }

    override suspend fun queryGiftWalls(items: List<GiftWallQueryItem>): List<GiftWall> {
        if (items.isEmpty()) return emptyList()
        val body =
            JsonObject(
                mapOf(
                    "items" to
                        JsonArray(
                            items.map { i ->
                                val o = HashMap<String, JsonElement>()
                                o["receiver"] = JsonPrimitive(i.receiver)
                                i.reference?.let { o["reference"] = JsonPrimitive(it) }
                                JsonObject(o)
                            },
                        ),
                ),
            )
        return request("POST", "/v1/client/gift-walls/query", body) { json -> json.data().map { GiftWall.fromJson(it) } }
    }

    override suspend fun getAway(query: AwayQuery): AwaySummary =
        request(
            "GET",
            "/v1/client/me/away" + queryString("since" to query.since, "max_groups" to query.maxGroups?.toString()),
        ) { AwaySummary.fromJson(it) }

    override suspend fun ackAway(cursor: String) {
        request("PUT", "/v1/client/me/away/cursor", JsonObject(mapOf("cursor" to JsonPrimitive(cursor)))) { }
    }

    override suspend fun getInbox(query: InboxQuery): Inbox =
        request(
            "GET",
            "/v1/client/me/inbox" + queryString("cursor" to query.cursor, "limit" to query.limit?.toString()),
        ) { Inbox.fromJson(it) }

    override suspend fun getLeaderboard(board: LeaderboardBoard, query: LeaderboardQuery): Leaderboard =
        request(
            "GET",
            "/v1/client/leaderboards/${encodeURIComponent(board.wire)}" +
                queryString(
                    "period" to query.period?.wire,
                    "metric" to query.metric?.wire,
                    "at" to query.at,
                    "limit" to query.limit?.toString(),
                    "include_me" to if (query.includeMe == false) "false" else null,
                ),
        ) { Leaderboard.fromJson(it) }

    override suspend fun sendGift(input: SendGiftInput): GiftTransaction {
        val body = HashMap<String, JsonElement>()
        body["receiver"] = JsonPrimitive(input.receiver)
        body["gift_id"] = JsonPrimitive(input.giftId)
        input.quantity?.let { body["quantity"] = JsonPrimitive(it) }
        input.message?.let { body["message"] = JsonPrimitive(it) }
        input.reference?.let { body["reference"] = JsonPrimitive(it) }
        input.roomId?.let { body["room_id"] = JsonPrimitive(it) }
        return request(
            "POST",
            "/v1/client/gift-transactions",
            JsonObject(body),
            input.idempotencyKey ?: newIdempotencyKey(),
        ) { GiftTransaction.fromJson(it) }
    }

    private fun JsonElement.data(): JsonArray = jsonObject.getValue("data").jsonArray

    private fun requestIdOf(res: TransportResponse): String? =
        res.headers.entries.firstOrNull { it.key.equals("X-Request-Id", ignoreCase = true) }?.value

    private fun errorFrom(res: TransportResponse): GiftingException {
        val parsed: JsonObject? =
            try {
                JSON.parseToJsonElement(res.body) as? JsonObject
            } catch (e: Exception) {
                null
            }
        val err = parsed?.get("error") as? JsonObject
        fun field(name: String): String? {
            val v = err?.get(name)
            return if (v is JsonPrimitive && v !is JsonNull && v.isString) v.content else null
        }
        val header = requestIdOf(res)
        return GiftingException(
            res.status,
            field("type") ?: "unknown_error",
            field("message") ?: "Request failed (${res.status}).",
            field("request_id") ?: header,
        )
    }

    private companion object {
        val JSON = Json { ignoreUnknownKeys = true }
    }
}
