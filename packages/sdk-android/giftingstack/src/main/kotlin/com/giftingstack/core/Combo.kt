package com.giftingstack.core

/** Runs remembered at once (the oldest is dropped beyond this). */
const val MAX_COMBO_RUNS = 64

/** Default window of a combo run, in ms. */
const val DEFAULT_COMBO_WINDOW_MS: Long = 2500

/**
 * Counts the same gift sent again and again by the same person ("x2, x3, x4"). A pause of
 * the window (a fixed number or a function read at every hit, for remote recipes) or more since the previous hit starts a new run. Every (sender, gift) pair keeps its
 * own run, so several people can combo at the same time. Not thread-safe: use it from the UI thread (spec section 10).
 */
class ComboTracker(private val windowOf: () -> Long) {
    /** A fixed window. */
    constructor(windowMs: Long = DEFAULT_COMBO_WINDOW_MS) : this({ windowMs })

    private class Run(val count: Int, val at: Long)

    private val runs = LinkedHashMap<Pair<String, String>, Run>()

    /** Registers one more send and returns how many in a row this is, starting at 1. */
    fun hit(sender: String, giftId: String, now: Long = monotonicNowMs()): Int {
        // A Pair compares both strings exactly, so ids with separators never run together.
        val key = sender to giftId
        val window = windowOf()
        // A run that paused for the window or more is over.
        runs.entries.removeAll { now - it.value.at >= window }
        val count = (runs.remove(key)?.count ?: 0) + 1
        runs[key] = Run(count, now)
        if (runs.size > MAX_COMBO_RUNS) runs.remove(runs.keys.first())
        return count
    }

    fun reset() {
        runs.clear()
    }
}

/** Milliseconds from a monotonic clock (spec 4.3: native platforms should not use wall time). */
fun monotonicNowMs(): Long = System.nanoTime() / 1_000_000L
