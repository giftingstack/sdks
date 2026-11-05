package com.giftingstack.core

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Leaderboard logic (SPEC section 16): tabs, a per-tab cache that answers at once and revalidates
 * in the background, the pinned "your rank" row and rank labels. No drawing. Port of
 * `packages/sdk-js/src/core/leaderboard.ts`.
 */

/** Tabs in the default order. */
val LEADERBOARD_PERIODS: List<LeaderboardPeriod> =
    listOf(LeaderboardPeriod.Day, LeaderboardPeriod.Week, LeaderboardPeriod.Month, LeaderboardPeriod.All)

/** A cached tab older than this is shown and fetched again in the background. */
const val LEADERBOARD_STALE_MS = 30_000L
const val DEFAULT_LEADERBOARD_LIMIT = 10

/**
 * Medal colours for ranks 1 to 3 (new tokens, used only by the leaderboard), `#rrggbb`. The rank
 * number on them uses the theme's `noticeBigText`; the contract is >= 4.5:1 (fixture
 * `leaderboard.json#rankColors`).
 */
val RANK_COLORS: Map<String, String> = linkedMapOf("rank1" to "#e8a93a", "rank2" to "#b8bcc8", "rank3" to "#c07a45")

/** The medal colour of rank 1 to 3, else null. */
fun rankColor(rank: Int): String? = if (rank in 1..3) RANK_COLORS["rank$rank"] else null

/** `#1`, `#417`, `#1,000`; null (beyond the top 1,000) -> [overflow]. */
fun leaderboardRankLabel(rank: Int?, overflow: String = "1,000+"): String =
    if (rank == null) overflow else "#${groupThousands(rank)}"

/**
 * The viewer's own row, pinned under the list, or null. Pinned when the viewer has a `me` block,
 * is not hidden, has a score above 0 on the metric, and is not visible in the rows: `rank` is null
 * (beyond the top 1,000) or greater than [limit], or a tie at the cut put them outside the rows.
 */
fun pinnedMe(board: Leaderboard?, limit: Int): LeaderboardMe? {
    val me = board?.me ?: return null
    if (me.hidden) return null
    if ((if (board.metric == LeaderboardMetric.Gifts) me.gifts else me.units) <= 0) return null
    if (me.rank == null || me.rank > limit) return me
    return if (board.data.any { it.user == me.user }) null else me
}

enum class LeaderboardStatus { Loading, Ready, Empty, Error }

class LeaderboardControllerOptions(
    val client: LeaderboardApi,
    val board: LeaderboardBoard = LeaderboardBoard.Senders,
    /** Tabs, in this order. An empty list counts as the default (day, week, month, all). */
    val periods: List<LeaderboardPeriod> = LEADERBOARD_PERIODS,
    /** Default week, or the first of [periods] when week is not one of them. */
    val initialPeriod: LeaderboardPeriod = LeaderboardPeriod.Week,
    /** Default gifts for receivers, units for senders. */
    val metric: LeaderboardMetric? = null,
    /** Rows, 1 to 100. */
    val limit: Int = DEFAULT_LEADERBOARD_LIMIT,
    /** Default true: ask for the viewer's own `me` block. */
    val includeMe: Boolean = true,
    val staleMs: Long = LEADERBOARD_STALE_MS,
    val onError: ((GiftingException) -> Unit)? = null,
)

data class LeaderboardState(
    val periods: List<LeaderboardPeriod>,
    val period: LeaderboardPeriod,
    val metric: LeaderboardMetric,
    /**
     * Loading: nothing to show yet (skeleton rows). Ready / Empty: [data] is shown (empty = no
     * rows). Error: the first load of this tab failed (message + "Try again").
     */
    val status: LeaderboardStatus = LeaderboardStatus.Loading,
    /** The answer shown for the current tab (possibly stale), else null. */
    val data: Leaderboard? = null,
    /** A request for the current tab is in flight while [data] stays visible. */
    val refreshing: Boolean = false,
    /** The last failure for the current tab, cleared by its next success. */
    val error: GiftingException? = null,
    /** The viewer's row to pin under the list ([pinnedMe]). */
    val pinned: LeaderboardMe? = null,
)

/**
 * The state of a leaderboard: the current tab, a per-tab cache that answers at once and refetches
 * in the background when 30 s old or more, and the viewer's pinned row. There is no polling here:
 * an app that wants it calls [refresh] on its own timer. Call everything from the main thread
 * (pass `viewModelScope` or a Compose scope as [scope]).
 */
class LeaderboardController(
    options: LeaderboardControllerOptions,
    private val scope: CoroutineScope,
    private val now: () -> Long = ::monotonicNowMs,
) {
    @Volatile private var options: LeaderboardControllerOptions = options

    private class Cached(val value: Leaderboard, val at: Long)

    private val cache = HashMap<Pair<LeaderboardPeriod, LeaderboardMetric>, Cached>()
    private val errors = HashMap<Pair<LeaderboardPeriod, LeaderboardMetric>, GiftingException>()
    private val inFlight = HashSet<Pair<LeaderboardPeriod, LeaderboardMetric>>()

    @Volatile private var alive = true
    private val _state: MutableStateFlow<LeaderboardState>
    val state: StateFlow<LeaderboardState>

    init {
        val periods = options.periods.ifEmpty { LEADERBOARD_PERIODS }
        _state =
            MutableStateFlow(
                LeaderboardState(
                    periods = periods,
                    period = if (options.initialPeriod in periods) options.initialPeriod else periods[0],
                    metric = options.metric ?: if (options.board == LeaderboardBoard.Receivers) LeaderboardMetric.Gifts else LeaderboardMetric.Units,
                ),
            )
        state = _state.asStateFlow()
    }

    /** Callbacks are read when used. `board`, `limit` and `includeMe` changes apply to new requests. */
    fun setOptions(options: LeaderboardControllerOptions) {
        this.options = options
    }

    private fun key() = _state.value.period to _state.value.metric

    /** Recompute the visible state of the current tab from the cache and the requests. */
    private fun render() {
        val key = key()
        val data = cache[key]?.value
        val error = errors[key]
        _state.value =
            _state.value.copy(
                data = data,
                error = error,
                refreshing = data != null && key in inFlight,
                status =
                    when {
                        data != null -> if (data.data.isNotEmpty()) LeaderboardStatus.Ready else LeaderboardStatus.Empty
                        error != null && key !in inFlight -> LeaderboardStatus.Error
                        else -> LeaderboardStatus.Loading
                    },
                pinned = pinnedMe(data, options.limit),
            )
    }

    /** Show the current tab: cached answer at once, a request if none or if it is stale. */
    private fun show(force: Boolean) {
        val key = key()
        val hit = cache[key]
        val stale = hit == null || now() - hit.at >= options.staleMs
        if ((force || stale) && key !in inFlight) fetch(key)
        render()
    }

    private fun fetch(key: Pair<LeaderboardPeriod, LeaderboardMetric>) {
        inFlight.add(key)
        // UNDISPATCHED: the request starts now, like the reference.
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            val o = options
            try {
                val value =
                    o.client.getLeaderboard(
                        o.board,
                        LeaderboardQuery(period = key.first, metric = key.second, limit = o.limit, includeMe = if (o.includeMe) null else false),
                    )
                cache[key] = Cached(value, now())
                errors.remove(key)
            } catch (e: CancellationException) {
                inFlight.remove(key)
                throw e
            } catch (e: Exception) {
                val err = asGiftingError(e)
                errors[key] = err
                if (alive) options.onError?.invoke(err)
            }
            inFlight.remove(key)
            if (alive) render()
        }
    }

    /** The screen opened: load the first tab. */
    fun start() = show(false)

    fun setPeriod(period: LeaderboardPeriod) {
        if (period == _state.value.period) return
        _state.value = _state.value.copy(period = period)
        show(false)
    }

    fun setMetric(metric: LeaderboardMetric) {
        if (metric == _state.value.metric) return
        _state.value = _state.value.copy(metric = metric)
        show(false)
    }

    /** Fetch the current tab again now (pull to refresh, "Try again", a poll). */
    fun refresh() = show(true)

    /** The screen is gone: answers that arrive later change nothing. */
    fun dispose() {
        alive = false
    }
}
