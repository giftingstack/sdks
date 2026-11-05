package com.giftingstack.core

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * "While you were away" logic (SPEC section 15): the replay plan for the effect layer and the
 * controller behind the summary card. No drawing. Port of `packages/sdk-js/src/core/away.ts`.
 */

/** Gift groups replayed at most. */
const val DEFAULT_AWAY_MAX_EFFECTS = 5

/** The replay must have ended by then (ms after the card appears). */
const val DEFAULT_AWAY_BUDGET_MS = 8_000L

/** Start gap after a small effect. */
const val AWAY_GAP_AFTER_SMALL_MS = 450L

/** Start gap after a medium effect (keeps medium at <= 2 at once). */
const val AWAY_GAP_AFTER_MEDIUM_MS = 1_100L

/** The large effect starts this long after every earlier effect has ended. */
const val AWAY_LARGE_PAUSE_MS = 300L

/** The card stays at least this long, and this long after the last effect ends. */
const val AWAY_CARD_MIN_MS = 4_000L
const val AWAY_CARD_TAIL_MS = 1_500L

/** `foreground()` checks again at most this often. */
const val AWAY_FOREGROUND_THROTTLE_MS = 60_000L

/**
 * How long one effect runs, from SPEC 7.3: `flyInMs + max(900, tail, coins > 0 ? tail + 800 : 0)`
 * with `tail = holdMs + flyOutMs`. Small 1600, medium 2100, large 3850 (3050 at low quality).
 */
fun effectDurationMs(recipe: EffectRecipe): Long {
    val tail = recipe.holdMs + recipe.flyOutMs
    return (recipe.flyInMs + maxOf(900, tail, if (recipe.coins > 0) tail + 800 else 0)).toLong()
}

data class AwaySenderLabels(
    /** A deleted sender. */
    val someone: String = "Someone",
    /** Two people. */
    val pair: String = "{a} and {b}",
    /** One named person and one more. */
    val oneOther: String = "{a} and 1 other",
    /** One named person and `{n}` more. */
    val others: String = "{a} and {n} others",
)

/**
 * Who sent a group, for the effect's notice. [names] are display names in the server's order (a
 * deleted sender already turned into `labels.someone`), [senderCount] the number of distinct
 * people. 1 -> `"ayla"`; 2 with two names -> `"ayla and mert"`; otherwise
 * `"ayla and {senderCount - 1} others"` (`"... and 1 other"` for one). No name -> `someone`.
 */
fun awaySenderLabel(names: List<String>, senderCount: Int, labels: AwaySenderLabels = AwaySenderLabels()): String {
    val a = names.firstOrNull() ?: labels.someone
    if (senderCount <= 1) return a
    if (senderCount == 2 && names.size >= 2) return labels.pair.replaceFirst("{a}", a).replaceFirst("{b}", names[1])
    val n = senderCount - 1
    if (n == 1) return labels.oneOther.replaceFirst("{a}", a)
    return labels.others.replaceFirst("{a}", a).replaceFirst("{n}", n.toString())
}

class AwayReplayOptions(
    val maxEffects: Int = DEFAULT_AWAY_MAX_EFFECTS,
    val budgetMs: Long = DEFAULT_AWAY_BUDGET_MS,
    /** Null: the defaults. */
    val thresholds: TierThresholds? = null,
    val quality: EffectQuality = EffectQuality.High,
    /** Or no effect layer: the plan is empty and only the card shows. */
    val reducedMotion: Boolean = false,
    /** Display name of a sender id. Default: the id itself. Deleted senders never reach it. */
    val resolveName: (String) -> String = { it },
    val labels: AwaySenderLabels = AwaySenderLabels(),
)

class AwayReplayItem(
    /** Start, in ms after the card appeared. */
    val atMs: Long,
    val durationMs: Long,
    val tier: EffectTier,
    val group: AwayGroup,
    /** What to pass to the effect layer's `play`. */
    val event: GiftEffectEvent,
)

class AwayReplayPlan(
    /** In start order. */
    val items: List<AwayReplayItem>,
    /** When the last effect ends (0 for an empty plan). */
    val endMs: Long,
)

private class Tiered(val group: AwayGroup, val tier: EffectTier)

/**
 * Plans the replay of an away summary as one short sequence, biggest last (SPEC 15.3): the first
 * `maxEffects` groups; only the first large one; small and medium by units ascending (ties: gift
 * id), then the large one; gaps 450 after small, 1100 after medium, the large one 300 ms after
 * everything before it ended; while the end is past `budgetMs`, the non-large item with the
 * lowest units goes (a lone large item that does not fit goes too).
 */
fun planAwayReplay(groups: List<AwayGroup>, options: AwayReplayOptions = AwayReplayOptions()): AwayReplayPlan {
    if (options.reducedMotion) return AwayReplayPlan(emptyList(), 0)
    val thresholds = options.thresholds ?: DEFAULT_THRESHOLDS
    val max = maxOf(0, options.maxEffects)

    val tiered = groups.take(max).map { Tiered(it, tierFor(it.gift.price, thresholds)) }
    val large = tiered.firstOrNull { it.tier == EffectTier.Large }
    // Plain code-unit string comparison of the ids, as the reference (`<` on strings).
    val rest =
        tiered.filter { it.tier != EffectTier.Large }
            .sortedWith { a, b ->
                if (a.group.units != b.group.units) a.group.units.compareTo(b.group.units) else a.group.gift.id.compareTo(b.group.gift.id)
            }

    fun makeItem(group: AwayGroup, tier: EffectTier, atMs: Long, durationMs: Long) =
        AwayReplayItem(
            atMs = atMs,
            durationMs = durationMs,
            tier = tier,
            group = group,
            event =
                GiftEffectEvent(
                    gift =
                        EffectGift(
                            id = group.gift.id,
                            name = group.gift.name,
                            price = group.gift.price,
                            image = group.gift.animationUrl ?: group.gift.iconUrl,
                            icon = group.gift.iconUrl,
                        ),
                    quantity = group.count,
                    sender =
                        awaySenderLabel(
                            group.senders.map { s -> if (s.user == null) options.labels.someone else options.resolveName(s.user) },
                            group.senderCount,
                            options.labels,
                        ),
                ),
        )

    fun layout(small: List<Tiered>, big: Tiered?): AwayReplayPlan {
        val items = ArrayList<AwayReplayItem>()
        var at = 0L
        var end = 0L
        for (t in small) {
            val durationMs = effectDurationMs(recipeFor(t.tier, options.quality))
            items.add(makeItem(t.group, t.tier, at, durationMs))
            end = maxOf(end, at + durationMs)
            at += if (t.tier == EffectTier.Small) AWAY_GAP_AFTER_SMALL_MS else AWAY_GAP_AFTER_MEDIUM_MS
        }
        if (big != null) {
            val start = if (items.isNotEmpty()) end + AWAY_LARGE_PAUSE_MS else 0L
            val durationMs = effectDurationMs(recipeFor(EffectTier.Large, options.quality))
            items.add(makeItem(big.group, EffectTier.Large, start, durationMs))
            end = start + durationMs
        }
        return AwayReplayPlan(items, end)
    }

    var small = rest
    var big = large
    var plan = layout(small, big)
    while (plan.endMs > options.budgetMs && plan.items.isNotEmpty()) {
        if (small.isNotEmpty()) small = small.drop(1) else big = null
        plan = layout(small, big)
    }
    return plan
}

/** How long the card stays: `max(4000, plan end + 1500)` ms. */
fun awayCardDurationMs(plan: AwayReplayPlan): Long = maxOf(AWAY_CARD_MIN_MS, plan.endMs + AWAY_CARD_TAIL_MS)

// ---------------------------------------------------------------- controller

enum class AwayStatus { Idle, Loading, Empty, Ready, Playing, Done }

/** When the summary counts as seen. */
enum class AwayAckOn { Shown, Finished, Manual }

/** The part of an effect layer the replay needs (`GiftEffectLayerState` has it; see `asAwayPlayer`). */
fun interface AwayEffectPlayer {
    fun play(event: GiftEffectEvent): Int
}

/** What the controller reads, as the options object of the reference. */
class AwayControllerOptions(
    val client: AwayApi,
    /** The effect layer, read at each play. None (or null): card only. */
    val effects: (() -> AwayEffectPlayer?)? = null,
    /** Read when the card appears. */
    val reducedMotion: (() -> Boolean)? = null,
    val ackOn: AwayAckOn = AwayAckOn.Shown,
    /** Sent as `max_groups` when given. */
    val maxGroups: Int? = null,
    val maxEffects: Int = DEFAULT_AWAY_MAX_EFFECTS,
    val budgetMs: Long = DEFAULT_AWAY_BUDGET_MS,
    val thresholds: TierThresholds? = null,
    val quality: EffectQuality = EffectQuality.High,
    val resolveName: (String) -> String = { it },
    val labels: AwaySenderLabels = AwaySenderLabels(),
    /** Default 60,000. */
    val throttleMs: Long = AWAY_FOREGROUND_THROTTLE_MS,
    val onShow: ((AwaySummary) -> Unit)? = null,
    val onDone: (() -> Unit)? = null,
    /** Failures never show; they come here. */
    val onError: ((GiftingException) -> Unit)? = null,
)

data class AwayState(
    val status: AwayStatus = AwayStatus.Idle,
    /** The summary being shown (ready, playing, done), else null. */
    val summary: AwaySummary? = null,
    /** The replay, planned when the card appears (playing, done), else null. */
    val plan: AwayReplayPlan? = null,
)

/**
 * Drives one summary card: [check] loads, the UI shows the card and calls [start], the controller
 * plays the replay and dismisses the card after [awayCardDurationMs], or earlier on [dismiss].
 * idle -> loading -> empty | ready -> playing -> done; a failed load goes back to idle silently.
 * [check] runs only from a resting state (idle, empty, done).
 *
 * Call everything from one thread, the main thread (pass `viewModelScope` or a Compose scope as
 * [scope]); client calls leave it by themselves. The functions that talk to the server return the
 * [Job] so a caller can wait for them; they start at once, on the calling thread.
 */
class AwayController(
    options: AwayControllerOptions,
    private val scope: CoroutineScope,
    private val now: () -> Long = ::monotonicNowMs,
    private val timers: Timers = Timers.forScope(scope),
) {
    @Volatile private var options: AwayControllerOptions = options
    private val _state = MutableStateFlow(AwayState())
    val state: StateFlow<AwayState> = _state.asStateFlow()

    private var handles = ArrayList<Any>()

    @Volatile private var alive = true

    /** Whether the summary on screen was acknowledged (or its one attempt was made). */
    private var acked = false

    /** A cursor whose acknowledgement failed: retried once, at the next check. */
    private var retryCursor: String? = null
    private var lastCheckAt: Long? = null

    /** Callbacks and settings are read when used, so they can change between calls. */
    fun setOptions(options: AwayControllerOptions) {
        this.options = options
    }

    private fun later(ms: Long, fn: () -> Unit) {
        handles.add(timers.set(ms, fn))
    }

    private fun stopTimers() {
        for (h in handles) timers.clear(h)
        handles = ArrayList()
    }

    /** Ask the server what arrived. Ignored while loading, ready or playing. */
    fun check(): Job = scope.launch(start = CoroutineStart.UNDISPATCHED) { runCheck() }

    private suspend fun runCheck() {
        val s = _state.value.status
        if (s != AwayStatus.Idle && s != AwayStatus.Empty && s != AwayStatus.Done) return
        lastCheckAt = now()
        _state.value = AwayState(AwayStatus.Loading)
        val client = options.client
        val retry = retryCursor
        if (retry != null) {
            retryCursor = null
            try {
                client.ackAway(retry)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (alive) options.onError?.invoke(asGiftingError(e))
            }
            if (!alive) return
        }
        val summary: AwaySummary
        try {
            val max = options.maxGroups
            summary = client.getAway(if (max == null) AwayQuery() else AwayQuery(maxGroups = max))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!alive) return
            _state.value = _state.value.copy(status = AwayStatus.Idle)
            options.onError?.invoke(asGiftingError(e))
            return
        }
        if (!alive) return
        acked = false
        _state.value =
            if (summary.totalGifts <= 0) _state.value.copy(status = AwayStatus.Empty)
            else _state.value.copy(status = AwayStatus.Ready, summary = summary)
    }

    /** The app came back to the foreground: [check] unless one ran less than 60 s ago. */
    fun foreground(): Job {
        val last = lastCheckAt
        if (last != null && now() - last < options.throttleMs) return Job().also { it.complete() }
        return check()
    }

    /** The card is on screen: plan and play the replay, schedule the dismissal. Only from ready. */
    fun start() {
        val st = _state.value
        val summary = st.summary
        if (st.status != AwayStatus.Ready || summary == null) return
        val o = options
        val player = o.effects?.invoke()
        val plan =
            planAwayReplay(
                summary.groups,
                AwayReplayOptions(
                    maxEffects = o.maxEffects,
                    budgetMs = o.budgetMs,
                    thresholds = o.thresholds,
                    quality = o.quality,
                    reducedMotion = player == null || (o.reducedMotion?.invoke() ?: false),
                    resolveName = o.resolveName,
                    labels = o.labels,
                ),
            )
        _state.value = st.copy(status = AwayStatus.Playing, plan = plan)
        for (item in plan.items) {
            later(item.atMs) {
                if (alive && _state.value.status == AwayStatus.Playing) options.effects?.invoke()?.play(item.event)
            }
        }
        later(awayCardDurationMs(plan)) { dismiss() }
        o.onShow?.invoke(summary)
        if (o.ackOn == AwayAckOn.Shown) ack()
    }

    /** Tap or timeout: the card goes. Plays not started yet are dropped; running ones finish. */
    fun dismiss() {
        val s = _state.value.status
        if (s != AwayStatus.Ready && s != AwayStatus.Playing) return
        stopTimers()
        _state.value = _state.value.copy(status = AwayStatus.Done)
        if (options.ackOn != AwayAckOn.Manual) ack()
        options.onDone?.invoke()
    }

    /**
     * Marks the summary on screen as seen (`ackAway(summary.cursor)`). At most once per summary; a
     * failure is retried once at the next [check]. `AwayAckOn.Manual` apps call this themselves.
     */
    fun ack(): Job = scope.launch(start = CoroutineStart.UNDISPATCHED) { runAck() }

    private suspend fun runAck() {
        val cursor = _state.value.summary?.cursor
        if (acked || cursor.isNullOrEmpty()) return
        acked = true
        try {
            options.client.ackAway(cursor)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            retryCursor = cursor
            if (alive) options.onError?.invoke(asGiftingError(e))
        }
    }

    /** The screen is gone: timers stop, answers that arrive later change nothing. */
    fun dispose() {
        alive = false
        stopTimers()
    }
}
