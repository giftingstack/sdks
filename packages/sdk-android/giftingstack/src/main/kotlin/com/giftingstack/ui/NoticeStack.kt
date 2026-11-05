package com.giftingstack.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.giftingstack.core.NoticeData
import com.giftingstack.core.Timers

/** The most notice lines on screen at once; the oldest one goes when a new one would be the 4th. */
internal const val MAX_NOTICE_LINES = 3

/** How long a line slides out before it is removed (matches the 260 ms slide-out). */
internal const val NOTICE_EXIT_MS = 260L

/** One line of the notice stack. [data] and [visible] are Compose state; the rest is bookkeeping. */
internal class NoticeLine(val uid: Int, data: NoticeData, var durationMs: Int) {
    /** Identifies the line: a notice call with the same id updates it. */
    val id: Int = data.id
    var data: NoticeData by mutableStateOf(data)

    /** False while the line slides out, until it is removed. */
    var visible: Boolean by mutableStateOf(true)
    var expiry: Any? = null
    var removal: Any? = null
}

/**
 * The stack of notice lines, newest last (drawn at the bottom). Pure bookkeeping: timers come from
 * [attach], so it runs on a fake clock in tests. Every call comes on the main thread.
 *
 * - [show]: same id as a visible line = update it in place and restart its own timer; otherwise a
 *   new line at the bottom, and the oldest goes at once if there would be more than [maxLines].
 * - A line's own timer slides only that line out ([NOTICE_EXIT_MS] later it is removed).
 * - [hideNewest]: the core's hide (cancel of the notice owner). [clear]: everything at once.
 */
internal class NoticeStack(
    private val maxLines: Int = MAX_NOTICE_LINES,
    private val exitMs: Long = NOTICE_EXIT_MS,
) {
    val lines = mutableStateListOf<NoticeLine>()
    private var timers: Timers? = null
    private var nextUid = 1

    /** Starts the timers (also for lines that were added before the layer was on screen). */
    fun attach(t: Timers) {
        timers = t
        for (line in lines.toList()) {
            if (line.visible) {
                if (line.expiry == null) armExpiry(line)
            } else if (line.removal == null) {
                armRemoval(line)
            }
        }
    }

    /** Cancels every timer (the layer left the screen). Lines stay and are re-armed by [attach]. */
    fun detach() {
        for (line in lines) cancelTimers(line)
        timers = null
    }

    fun show(data: NoticeData, durationMs: Int) {
        val existing = lines.firstOrNull { it.id == data.id && it.visible }
        if (existing != null) {
            existing.data = data
            existing.durationMs = durationMs
            cancelExpiry(existing)
            armExpiry(existing)
            return
        }
        // A line with this id that is still sliding out is replaced by the new one.
        lines.firstOrNull { it.id == data.id }?.let { drop(it) }
        val line = NoticeLine(nextUid++, data, durationMs)
        lines.add(line)
        armExpiry(line)
        while (lines.size > maxLines) drop(lines[0])
    }

    /** Slides the newest visible line out. */
    fun hideNewest() {
        lines.lastOrNull { it.visible }?.let { dismiss(it) }
    }

    /** Removes every line and timer at once. */
    fun clear() {
        for (line in lines) cancelTimers(line)
        lines.clear()
    }

    private fun dismiss(line: NoticeLine) {
        if (!line.visible) return
        cancelExpiry(line)
        line.visible = false
        armRemoval(line)
    }

    private fun drop(line: NoticeLine) {
        cancelTimers(line)
        lines.remove(line)
    }

    private fun armExpiry(line: NoticeLine) {
        val t = timers ?: return
        line.expiry =
            t.set(line.durationMs.toLong()) {
                line.expiry = null
                dismiss(line)
            }
    }

    private fun armRemoval(line: NoticeLine) {
        val t = timers ?: return
        line.removal =
            t.set(exitMs) {
                line.removal = null
                lines.remove(line)
            }
    }

    private fun cancelExpiry(line: NoticeLine) {
        val handle = line.expiry ?: return
        line.expiry = null
        timers?.let { it.clear(handle) }
    }

    private fun cancelTimers(line: NoticeLine) {
        cancelExpiry(line)
        val handle = line.removal ?: return
        line.removal = null
        timers?.let { it.clear(handle) }
    }
}
