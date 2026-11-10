package com.giftingstack.core

/** At most this many effects of a kind on screen at once. Large ones queue instead. */
val MAX_CONCURRENT_EFFECTS: Map<EffectTier, Int> =
    mapOf(EffectTier.Small to 6, EffectTier.Medium to 2, EffectTier.Large to 1)

/** Large gifts waiting their turn. A new one beyond this drops the oldest waiting one. */
const val MAX_QUEUED_LARGE = 5

/** Shown in the notice when an event has no sender. */
const val DEFAULT_SENDER_NAME = "Someone"

/** Notice ids remembered at once, one per (sender, gift) pair; the oldest is dropped beyond this. */
const val MAX_NOTICE_KEYS = 32

data class ScheduledEffect(
    val id: Int,
    val event: GiftEffectEvent,
    val recipe: EffectRecipe,
    /** Combo count for the notice, fixed when the gift was sent. */
    val count: Int,
)

/** What tells two receivers apart for the combo and the notice key: the side and the name. Null without a receiver. */
private fun receiverKey(r: GiftEffectReceiver?): String? = r?.let { "${it.side ?: ""}:${it.name}" }

data class NoticeData(
    /** Changes when a different gift or sender starts a new notice. */
    val id: Int,
    val senderName: String,
    val giftName: String,
    val image: String?,
    /** Gifts in a row, 1 for a single gift. */
    val count: Int,
    val big: Boolean,
    /** Only in a battle (SPEC 7.4): who got the gift and the side's colour. */
    val receiver: GiftEffectReceiver? = null,
)

/** What the UI implements. All calls come on the thread that called the scheduler. */
interface EffectSchedulerListener {
    /** An effect enters the screen. Draw it; call `started(id)` once its picture is ready. */
    fun enter(effect: ScheduledEffect) {}

    /** An effect leaves the screen (finished or cancelled). Remove it. */
    fun exit(effect: ScheduledEffect) {}

    /** An effect played to its end. Not called for cancelled or cleared effects. */
    fun end(effect: ScheduledEffect) {}

    /** Show this notice now and call `noticeExpired()` after [durationMs], replacing any timer. */
    fun notice(notice: NoticeData, durationMs: Int) {}

    /** Hide the notice and drop its timer. */
    fun noticeHide() {}

    /** Every effect is gone at once (`clear`). */
    fun clear() {}
}

data class EffectSchedulerOptions(
    /** Thresholds the app gave itself; they beat a remote set (spec 13.4). Null = not given. */
    val thresholds: TierThresholds? = null,
    val quality: EffectQuality = EffectQuality.High,
    /** Only the notice shows, no effect. */
    val reducedMotion: Boolean = false,
    /**
     * The remote recipe set (spec section 13), read at each `play`; null = the embedded one.
     * `thresholds` above and the constructor's `comboWindowMs` still win over it.
     */
    val recipes: (() -> RecipeSet?)? = null,
)

private val EMBEDDED_SET = embeddedRecipeSet()

data class NoticeState(val data: NoticeData?, val visible: Boolean, val owner: Int)

/**
 * Decides which gift effects are on screen, which wait and what the notice says. No drawing, no
 * timers (spec section 6). Port of `packages/sdk-js/src/core/effects.ts`. Call it from one
 * thread, the UI thread.
 */
class EffectScheduler(
    /** The combo window the app gave; null = the recipe set's window, read at each `play`. */
    comboWindowMs: Long? = null,
    private val now: () -> Long = ::monotonicNowMs,
) {
    var listener: EffectSchedulerListener = object : EffectSchedulerListener {}
    var options: EffectSchedulerOptions = EffectSchedulerOptions()

    private val appComboWindowMs = comboWindowMs
    private var currentComboWindowMs = appComboWindowMs ?: DEFAULT_COMBO_WINDOW_MS
    private val combo = ComboTracker { currentComboWindowMs }
    private var nextId = 1
    private val running = hashMapOf(EffectTier.Small to 0, EffectTier.Medium to 0, EffectTier.Large to 0)
    private var queue = ArrayList<ScheduledEffect>()
    private val onScreen = LinkedHashMap<Int, ScheduledEffect>()
    /** (sender, gift) pair -> notice id, oldest first. */
    private val noticeIds = LinkedHashMap<String, Int>()
    private var lastNoticeKey = ""
    private var noticeId = 0

    /** The play() id that wrote the notice now on screen. */
    private var noticeOwner = 0
    private var noticeData: NoticeData? = null
    private var noticeVisible = false

    /** Effects on screen, in the order they entered. */
    fun active(): List<ScheduledEffect> = onScreen.values.toList()

    /** Large effects waiting their turn, oldest first. */
    fun queued(): List<ScheduledEffect> = queue.toList()

    /** The last notice written (it stays after hiding) and whether it is showing. */
    fun notice(): NoticeState = NoticeState(noticeData, noticeVisible, noticeOwner)

    /**
     * Shows a gift. Large gifts wait their turn; small and medium ones play at once, or show only
     * the notice when too many are on screen. Returns an id for [cancel].
     */
    fun play(event: GiftEffectEvent): Int {
        val opts = options
        // Merge order: embedded < remote < app (spec 13.4). The recipe is fixed here, so effects
        // already playing or waiting keep it when a new remote set arrives.
        val set =
            mergeRecipeSet(
                EMBEDDED_SET,
                opts.recipes?.invoke(),
                AppRecipeOverrides(opts.thresholds?.let { PartialThresholds(it.mediumFrom, it.largeFrom) }, appComboWindowMs),
            )
        currentComboWindowMs = set.comboWindowMs
        val tier = tierFor(event.gift.price, set.thresholds)
        val recipe = recipeFor(tier, opts.quality, set)
        val sender = event.sender ?: DEFAULT_SENDER_NAME
        val quantity = event.quantity ?: 1
        val id = nextId++
        // A combo counts per receiver too: gifts to two hosts of a battle are two runs.
        val rkey = receiverKey(event.receiver)
        val run = combo.hit(sender, if (rkey == null) event.gift.id else "${event.gift.id}\u0000$rkey", now())
        val count = if (quantity > 1) quantity else run
        val item = ScheduledEffect(id, event, recipe, count)
        // Without an effect the notice shows now; with one, it shows when the effect starts.
        if (opts.reducedMotion) {
            showNotice(item)
            return id
        }
        if (tier == EffectTier.Large) {
            if (running.getValue(EffectTier.Large) >= MAX_CONCURRENT_EFFECTS.getValue(EffectTier.Large)) {
                if (queue.size >= MAX_QUEUED_LARGE) queue.removeAt(0)
                queue.add(item)
            } else {
                start(item)
            }
        } else if (running.getValue(tier) < MAX_CONCURRENT_EFFECTS.getValue(tier)) {
            start(item)
        } else {
            showNotice(item) // too many on screen: notice only
        }
        return id
    }

    /** The effect's picture is ready (or the wait ran out): it really starts, with its notice. */
    fun started(id: Int) {
        onScreen[id]?.let { showNotice(it) }
    }

    /** The effect's animation ran to its end. */
    fun finished(id: Int) {
        val item = onScreen[id] ?: return
        release(item)
        listener.end(item)
    }

    /** Takes back a gift that was shown too early, for example because its send failed. */
    fun cancel(id: Int) {
        queue = ArrayList(queue.filter { it.id != id })
        onScreen[id]?.let { release(it) }
        if (noticeOwner == id) hideNotice()
    }

    /** Stops everything, forgets the queue and the combo run. */
    fun clear() {
        queue = ArrayList()
        onScreen.clear()
        for (t in EffectTier.entries) running[t] = 0
        listener.clear()
        hideNotice()
        noticeIds.clear()
        combo.reset()
    }

    /** The notice's time is up. */
    fun noticeExpired() {
        noticeVisible = false
        noticeIds.clear()
        lastNoticeKey = ""
        listener.noticeHide()
    }

    private fun start(item: ScheduledEffect) {
        val tier = item.recipe.tier
        running[tier] = running.getValue(tier) + 1
        onScreen[item.id] = item
        listener.enter(item)
    }

    /** Takes an effect off the screen and lets the next large one in. */
    private fun release(item: ScheduledEffect) {
        val tier = item.recipe.tier
        onScreen.remove(item.id)
        running[tier] = maxOf(0, running.getValue(tier) - 1)
        listener.exit(item)
        if (tier == EffectTier.Large && queue.isNotEmpty()) start(queue.removeAt(0))
    }

    private fun showNotice(item: ScheduledEffect) {
        val event = item.event
        val sender = event.sender ?: DEFAULT_SENDER_NAME
        val receiver = event.receiver
        // The receiver is part of the key: a combo to one host and one to the other are two notices.
        val rkey = receiverKey(receiver)
        val key = if (rkey == null) "$sender|${event.gift.id}" else "$sender|${event.gift.id}|$rkey"
        noticeOwner = item.id
        // Every pair keeps its own id while it is remembered, so a combo returns to its own line
        // even when other people sent gifts in between.
        val id = noticeIds.remove(key) ?: ++noticeId
        noticeIds[key] = id
        if (noticeIds.size > MAX_NOTICE_KEYS) noticeIds.remove(noticeIds.keys.first())
        lastNoticeKey = key
        val data =
            NoticeData(
                id = id,
                senderName = sender,
                giftName = event.gift.name,
                image = event.gift.icon ?: event.gift.image,
                count = item.count,
                big = item.recipe.noticeBig,
                receiver = receiver?.let { GiftEffectReceiver(it.name, it.side, it.color) },
            )
        noticeData = data
        noticeVisible = true
        listener.notice(data, item.recipe.noticeMs)
    }

    private fun hideNotice() {
        noticeVisible = false
        noticeIds.remove(lastNoticeKey)
        lastNoticeKey = ""
        listener.noticeHide()
    }
}
