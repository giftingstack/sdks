package com.giftingstack.core

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch

/**
 * Gift wall logic (SPEC section 14): which chips a wall shows, how counts are written, and a
 * loader that batches the walls of a feed into few requests. No drawing. Port of
 * `packages/sdk-js/src/core/wall.ts`.
 */

/** Chips a wall shows by default, the overflow chip included. */
const val DEFAULT_WALL_MAX = 6

/** [Count]: most received first (ties keep the catalog order). [Catalog]: the server's order. */
enum class WallOrder { Count, Catalog }

sealed interface WallChip {
    data class Gift(val gift: GiftRef, val count: Int) : WallChip

    /** [count] = the SUM of the hidden gifts' counts; [hidden] = how many gift kinds it stands for. */
    data class Overflow(val count: Long, val hidden: Int) : WallChip
}

/**
 * The chips of a wall. [items] come in catalog order (as the API sends them). Counts of 0 or less
 * are dropped. With more gifts than [max] (values below 1 count as 1), the first `max - 1` are
 * shown and one overflow chip carries the sum of the rest.
 */
fun wallChips(items: List<ReceivedGift>, max: Int = DEFAULT_WALL_MAX, order: WallOrder = WallOrder.Count): List<WallChip> {
    val limit = maxOf(1, max)
    val positive = items.filter { it.count > 0 }
    // `sortedByDescending` is stable: equal counts keep the catalog order.
    val kept = if (order == WallOrder.Count) positive.sortedByDescending { it.count } else positive
    fun chip(i: ReceivedGift): WallChip = WallChip.Gift(i.gift, i.count)
    if (kept.size <= limit) return kept.map(::chip)
    val shown = kept.subList(0, limit - 1)
    val hidden = kept.subList(limit - 1, kept.size)
    return shown.map(::chip) + WallChip.Overflow(hidden.sumOf { it.count.toLong() }, hidden.size)
}

/** Count suffixes of [formatCount]. */
data class CountLabels(val thousand: String = "K", val million: String = "M", val decimal: String = ".")

/**
 * A short count that never overstates: `999`, `1K`, `1.9K` (1,999), `12K`, `999K`, `1M`, `1.2M`,
 * `12M`. Always rounded DOWN, in integer arithmetic; a `.0` is left out. Below 1,000 (also
 * negative) the number is written as is.
 */
fun formatCount(n: Long, labels: CountLabels = CountLabels()): String {
    fun tenths(unit: Long, suffix: String): String {
        val t = n / (unit / 10)
        val whole = t / 10
        val dec = t % 10
        return if (dec == 0L) "$whole$suffix" else "$whole${labels.decimal}$dec$suffix"
    }
    return when {
        n < 1_000 -> n.toString()
        n < 10_000 -> tenths(1_000, labels.thousand)
        n < 1_000_000 -> "${n / 1_000}${labels.thousand}"
        n < 10_000_000 -> tenths(1_000_000, labels.million)
        else -> "${n / 1_000_000}${labels.million}"
    }
}

fun formatCount(n: Int, labels: CountLabels = CountLabels()): String = formatCount(n.toLong(), labels)

/** Requests made within this many ms of the first one share one batch call. */
const val WALL_BATCH_WINDOW_MS = 50L

/** The API answers at most this many walls per call; more make several calls. */
const val WALL_BATCH_SIZE = 25

/** A wall's answer is reused for this long. */
const val WALL_CACHE_TTL_MS = 60_000L

private fun wallKey(user: String, reference: String?) = "$user\u0000${reference.orEmpty()}"

/**
 * Shares wall requests across every `GiftWall` on a screen. [load] calls made within [windowMs]
 * (50) of the first queued one go out together when that window closes, in batches of at most
 * [batchSize] (25) walls, in the order first asked. A wall that is queued or in flight is not asked
 * again (same answer). An answer is cached per `(user, reference)` for [ttlMs] (60,000) from the
 * moment it arrived; a failure is not cached. Call it from one thread, the main thread.
 *
 * @param query the batch call, usually `client::queryGiftWalls`.
 * @param scope runs the batch calls and, by default, the window timer.
 * @param timers replace in tests; default: `delay` on [scope].
 */
class GiftWallLoader(
    private val query: suspend (List<GiftWallQueryItem>) -> List<GiftWall>,
    private val scope: CoroutineScope,
    private val now: () -> Long = ::monotonicNowMs,
    private val timers: Timers = Timers.forScope(scope),
    private val windowMs: Long = WALL_BATCH_WINDOW_MS,
    private val batchSize: Int = WALL_BATCH_SIZE,
    private val ttlMs: Long = WALL_CACHE_TTL_MS,
) {
    private class Waiter(val item: GiftWallQueryItem, var generation: Int) {
        val answer = CompletableDeferred<List<ReceivedGift>>()
    }

    private class Cached(val gifts: List<ReceivedGift>, val at: Long)

    private val cache = HashMap<String, Cached>()

    /** Queued (window open) or in flight, by key. */
    private val waiting = HashMap<String, Waiter>()

    /** Keys queued in the open window, in the order first asked. */
    private var queue = ArrayList<String>()
    private var windowOpen = false
    private val generations = HashMap<String, Int>()

    /** The cached wall if it is still fresh, else null. Lets a wall draw at once. */
    fun peek(user: String, reference: String? = null): List<ReceivedGift>? {
        val hit = cache[wallKey(user, reference)] ?: return null
        return if (now() - hit.at < ttlMs) hit.gifts else null
    }

    /** The counters of one wall; throws what the batch call threw. */
    suspend fun load(user: String, reference: String? = null): List<ReceivedGift> {
        peek(user, reference)?.let { return it }
        val key = wallKey(user, reference)
        waiting[key]?.let { return it.answer.await() }
        val waiter = Waiter(GiftWallQueryItem(user, reference), generations[key] ?: 0)
        waiting[key] = waiter
        queue.add(key)
        if (!windowOpen) {
            windowOpen = true
            timers.set(windowMs) { flush() }
        }
        return waiter.answer.await()
    }

    /**
     * Forget a wall (for example after the person sent a gift to it): the next [load] asks the
     * server again, even if an older request is still in flight (its answer is then not cached).
     */
    fun invalidate(user: String, reference: String? = null) {
        val key = wallKey(user, reference)
        cache.remove(key)
        val generation = (generations[key] ?: 0) + 1
        generations[key] = generation
        val w = waiting[key] ?: return
        // A queued wall has not been asked yet: it goes out with its window and its answer counts.
        // One in flight is let go: its answer reaches its callers but is not cached.
        if (queue.contains(key)) w.generation = generation else waiting.remove(key)
    }

    /** Forget every cached wall (requests already queued or in flight are kept). */
    fun clear() {
        cache.clear()
    }

    private fun flush() {
        windowOpen = false
        val keys = queue
        queue = ArrayList()
        for (chunk in keys.chunked(maxOf(1, batchSize))) {
            val waiters = chunk.map { waiting.getValue(it) }
            // UNDISPATCHED: the batch call starts now, like the reference.
            scope.launch(start = CoroutineStart.UNDISPATCHED) { send(chunk, waiters) }
        }
    }

    private suspend fun send(keys: List<String>, waiters: List<Waiter>) {
        try {
            val walls = query(waiters.map { it.item })
            val at = now()
            waiters.forEachIndexed { i, w ->
                val key = keys[i]
                val gifts = walls.getOrNull(i)?.gifts ?: emptyList()
                if (waiting[key] === w) waiting.remove(key)
                if ((generations[key] ?: 0) == w.generation) cache[key] = Cached(gifts, at)
                w.answer.complete(gifts)
            }
        } catch (e: Exception) {
            waiters.forEachIndexed { i, w ->
                val key = keys[i]
                if (waiting[key] === w) waiting.remove(key)
                w.answer.completeExceptionally(e)
            }
            if (e is CancellationException) throw e
        }
    }
}
