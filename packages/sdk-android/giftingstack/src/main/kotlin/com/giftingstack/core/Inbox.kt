package com.giftingstack.core

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * The gift inbox (SPEC section 19): who sent the signed-in user which gift in the last 24 hours,
 * one row per gift, newest first. Models, the pure helpers (`inboxTimeLabel`, `inboxRows`,
 * `inboxUnread`) and the paging controller behind the `GiftInbox` composable. No drawing. Port of
 * `packages/sdk-js/src/core/inbox.ts`.
 */

// ---------------------------------------------------------------- the call (SPEC 19.1)

/** The gift inbox call. `me` is the signed-in user. Implemented by [GiftingClient] and by test doubles. */
interface InboxApi {
    /** One page of the last 24 hours, newest first. The next (older) page: pass `nextCursor`. */
    suspend fun getInbox(query: InboxQuery = InboxQuery()): Inbox
}

data class InboxQuery(
    /** The `nextCursor` of the previous page. */
    val cursor: String? = null,
    /** Rows per page, 1 to 100. Server default 20. */
    val limit: Int? = null,
)

/** The gift of an [InboxItem]. [price] is today's catalog price. */
data class InboxGift(
    val id: String,
    val name: String,
    val price: Long,
    val iconUrl: String?,
    val animationUrl: String?,
) {
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "id" to JsonPrimitive(id),
                "name" to JsonPrimitive(name),
                "price" to JsonPrimitive(price),
                "icon_url" to iconUrl.json(),
                "animation_url" to animationUrl.json(),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): InboxGift {
            val o = e.jsonObject
            return InboxGift(o.str("id"), o.str("name"), o.long("price"), o.strOrNull("icon_url"), o.strOrNull("animation_url"))
        }
    }
}

data class InboxItem(
    /** The gift transaction (`gtx_...`). */
    val id: String,
    /** ISO 8601 time. */
    val createdAt: String,
    /** External id of the sender; null = a deleted sender. */
    val sender: String?,
    val gift: InboxGift,
    val quantity: Int,
    /** Value of the gift (price x quantity) when it was sent. A display counter, never a balance. */
    val units: Long,
    /** `completed` or `reversed` (a reversed gift stays in the page; the UI hides it). */
    val status: String,
) {
    /** Whether the gift counts (not reversed). */
    val completed: Boolean get() = status == "completed"

    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "id" to JsonPrimitive(id),
                "created_at" to JsonPrimitive(createdAt),
                "sender" to sender.json(),
                "gift" to gift.toJson(),
                "quantity" to JsonPrimitive(quantity),
                "units" to JsonPrimitive(units),
                "status" to JsonPrimitive(status),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): InboxItem {
            val o = e.jsonObject
            return InboxItem(
                id = o.str("id"),
                createdAt = o.str("created_at"),
                sender = o.strOrNull("sender"),
                gift = InboxGift.fromJson(o.getValue("gift")),
                quantity = o.int("quantity"),
                units = o.long("units"),
                status = o.str("status"),
            )
        }
    }
}

/** What `GET /v1/client/me/inbox` returns. The body never carries the gift's message, metadata or reference. */
data class Inbox(
    val user: String,
    val since: String,
    val until: String,
    /** Newest first. */
    val data: List<InboxItem>,
    val hasMore: Boolean,
    /** Pass to the next `getInbox` for the older page; null on the last page. */
    val nextCursor: String?,
) {
    fun toJson(): JsonObject =
        JsonObject(
            mapOf(
                "user" to JsonPrimitive(user),
                "since" to JsonPrimitive(since),
                "until" to JsonPrimitive(until),
                "data" to JsonArray(data.map { it.toJson() }),
                "has_more" to JsonPrimitive(hasMore),
                "next_cursor" to nextCursor.json(),
            ),
        )

    companion object {
        fun fromJson(e: JsonElement): Inbox {
            val o = e.jsonObject
            return Inbox(
                user = o.str("user"),
                since = o.str("since"),
                until = o.str("until"),
                data = o.getValue("data").jsonArray.map { InboxItem.fromJson(it) },
                hasMore = o.getValue("has_more").jsonPrimitive.boolean,
                nextCursor = o.strOrNull("next_cursor"),
            )
        }
    }
}

// ---------------------------------------------------------------- pure helpers (SPEC 19.2)

private val ISO_TIME = Regex("^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})(?:\\.(\\d+))?(Z|[+-]\\d{2}:?\\d{2})$")

/** Days since 1970-01-01 of a proleptic Gregorian date. */
private fun daysFromCivil(y: Int, m: Int, d: Int): Long {
    val yy = if (m <= 2) y - 1 else y
    val era = (if (yy >= 0) yy else yy - 399) / 400
    val yoe = yy - era * 400
    val doy = (153 * (m + (if (m > 2) -3 else 9)) + 2) / 5 + d - 1
    val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era.toLong() * 146_097L + doe - 719_468L
}

/**
 * An ISO 8601 time as `yyyy-MM-ddTHH:mm:ss[.fff](Z|+hh:mm)` in epoch milliseconds, or null when it
 * does not look like one. (`java.time` is not available below API 26 without desugaring.)
 */
fun parseIsoTimeMs(iso: String): Long? {
    val m = ISO_TIME.matchEntire(iso) ?: return null
    val g = m.groupValues
    val millis = if (g[7].isEmpty()) 0 else (g[7] + "00").take(3).toInt()
    var ms =
        (daysFromCivil(g[1].toInt(), g[2].toInt(), g[3].toInt()) * 86_400L + g[4].toInt() * 3_600L + g[5].toInt() * 60L + g[6].toInt()) * 1_000L +
            millis
    val zone = g[8]
    if (zone != "Z") {
        val digits = zone.substring(1).replace(":", "")
        val offset = (digits.substring(0, 2).toInt() * 60L + digits.substring(2, 4).toInt()) * 60_000L
        ms -= if (zone[0] == '+') offset else -offset
    }
    return ms
}

/**
 * `"now"` under a minute (also for a clock that went back), then `"5m"`, `"3h"`, `"1d"`: whole
 * units rounded down.
 */
fun inboxTimeLabel(createdAtMs: Long, nowMs: Long): String {
    val d = nowMs - createdAtMs
    return when {
        d < 60_000L -> "now"
        d < 3_600_000L -> "${d / 60_000L}m"
        d < 86_400_000L -> "${d / 3_600_000L}h"
        else -> "${d / 86_400_000L}d"
    }
}

/** What a screen reader says for a label of [inboxTimeLabel]: `"just now"`, `"5 minutes ago"`, `"1 hour ago"`. */
fun inboxTimeSpoken(label: String): String {
    if (label == "now") return "just now"
    val n = label.dropLast(1).toIntOrNull() ?: return label
    val unit =
        when (label.last()) {
            'm' -> "minute"
            'h' -> "hour"
            'd' -> "day"
            else -> return label
        }
    return "$n $unit${if (n == 1) "" else "s"} ago"
}

/** One visible row of the inbox. */
data class InboxRow(
    val id: String,
    /** `"Someone"` for a deleted sender, else the name from the map, else the sender id. */
    val senderName: String,
    val giftName: String,
    val quantity: Int,
    /** [inboxTimeLabel]. */
    val time: String,
    val iconUrl: String?,
    /** The sender id; null = deleted. */
    val sender: String?,
)

/**
 * The rows to draw: reversed gifts are dropped, the order is kept. [names] maps sender ids to
 * display names. A `created_at` that cannot be read counts as `now`.
 */
fun inboxRows(items: List<InboxItem>, nowMs: Long, names: Map<String, String> = emptyMap()): List<InboxRow> =
    items.filter { it.completed }.map {
        InboxRow(
            id = it.id,
            senderName = if (it.sender == null) "Someone" else names[it.sender] ?: it.sender,
            giftName = it.gift.name,
            quantity = it.quantity,
            time = inboxTimeLabel(parseIsoTimeMs(it.createdAt) ?: nowMs, nowMs),
            iconUrl = it.gift.iconUrl,
            sender = it.sender,
        )
    }

/**
 * How many completed gifts arrived strictly after [lastSeenMs] (all completed ones when it is
 * null). Reversed gifts never count.
 */
fun inboxUnread(items: List<InboxItem>, lastSeenMs: Long? = null): Int =
    items.count {
        if (!it.completed) return@count false
        if (lastSeenMs == null) return@count true
        val at = parseIsoTimeMs(it.createdAt) ?: return@count false
        at > lastSeenMs
    }

/** The sentence of a row: `"Ayla sent you Rose x3"` (the `x3` only above 1). */
fun inboxRowText(row: InboxRow, sentYou: String = "sent you"): String =
    "${row.senderName} $sentYou ${row.giftName}" + if (row.quantity > 1) " x${row.quantity}" else ""

// ---------------------------------------------------------------- paging controller

enum class InboxStatus { Loading, Ready, Empty, Error }

data class InboxState(
    val status: InboxStatus = InboxStatus.Loading,
    /** Every page loaded so far, newest first (reversed gifts included; [inboxRows] drops them). */
    val items: List<InboxItem> = emptyList(),
    /** An older page exists: show "Show more". */
    val hasMore: Boolean = false,
    /** The next page is being fetched. */
    val loadingMore: Boolean = false,
)

/**
 * The state of one inbox: the first page, then older pages appended on [loadMore]. [refresh] reloads
 * from the first page (rows stay visible meanwhile). A failed refresh with rows on screen keeps
 * them; a failed [loadMore] keeps them and leaves "Show more" to try again. Call everything from
 * the main thread (pass `viewModelScope` or a Compose scope as [scope]).
 */
class InboxController(
    private val client: InboxApi,
    private val scope: CoroutineScope,
    /** Rows per page, 1 to 100. */
    private val pageSize: Int = DEFAULT_INBOX_PAGE_SIZE,
) {
    /** Called with every loaded item after each successful page (for the app's own badge). */
    @Volatile var onLoaded: ((List<InboxItem>) -> Unit)? = null

    /** Failures never show a toast; they come here (the first load failing also shows the error state). */
    @Volatile var onError: ((GiftingException) -> Unit)? = null

    private val _state = MutableStateFlow(InboxState())
    val state: StateFlow<InboxState> = _state.asStateFlow()

    @Volatile private var alive = true
    private var generation = 0
    private var nextCursor: String? = null

    /** Loads the first page. */
    fun start(): Job = refresh()

    /** Reload from the first page. A newer refresh makes older answers count for nothing. */
    fun refresh(): Job {
        val gen = ++generation
        if (_state.value.items.isEmpty()) _state.value = InboxState(InboxStatus.Loading)
        else _state.value = _state.value.copy(loadingMore = false)
        return scope.launch(start = CoroutineStart.UNDISPATCHED) {
            try {
                val page = client.getInbox(InboxQuery(limit = pageSize))
                if (!alive || gen != generation) return@launch
                nextCursor = page.nextCursor
                publish(page.data, page.hasMore)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!alive || gen != generation) return@launch
                val cur = _state.value
                if (cur.items.isEmpty()) _state.value = InboxState(InboxStatus.Error)
                onError?.invoke(asGiftingError(e))
            }
        }
    }

    /** Appends the next older page. Ignored without more rows, while loading, or before the first page. */
    fun loadMore(): Job {
        val cur = _state.value
        val cursor = nextCursor
        if (cur.status != InboxStatus.Ready || !cur.hasMore || cur.loadingMore || cursor == null) return Job().also { it.complete() }
        val gen = generation
        _state.value = cur.copy(loadingMore = true)
        return scope.launch(start = CoroutineStart.UNDISPATCHED) {
            try {
                val page = client.getInbox(InboxQuery(cursor = cursor, limit = pageSize))
                if (!alive || gen != generation) return@launch
                nextCursor = page.nextCursor
                val have = _state.value.items.map { it.id }.toHashSet()
                publish(_state.value.items + page.data.filter { it.id !in have }, page.hasMore)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!alive || gen != generation) return@launch
                _state.value = _state.value.copy(loadingMore = false)
                onError?.invoke(asGiftingError(e))
            }
        }
    }

    private fun publish(items: List<InboxItem>, hasMore: Boolean) {
        // Nothing to draw and nothing older to ask for: the empty message. Rows that are all
        // reversed with an older page waiting stay "ready": "Show more" fetches the rest.
        val empty = !hasMore && items.none { it.completed }
        _state.value = InboxState(if (empty) InboxStatus.Empty else InboxStatus.Ready, items, hasMore, loadingMore = false)
        onLoaded?.invoke(items)
    }

    /** The screen is gone: answers that arrive later change nothing. */
    fun dispose() {
        alive = false
    }
}

const val DEFAULT_INBOX_PAGE_SIZE = 20
