package com.giftingstack.core

/**
 * The tray's surroundings (spec section 9.4): the dim behind a bottom sheet (`scrim`) and the
 * open/closed state the host's Gift button toggles. Pure: no UI, no clock. Port of
 * `packages/sdk-js/src/core/scrim.ts` and `packages/sdk-flutter/lib/src/core/scrim.dart`.
 */

/** What a tap on the scrim does. [Lower] lowers the sheet to peek first; [Dismiss] asks to close. */
enum class ScrimTap { Lower, Dismiss }

/** The scrim fades in and out over this long (ms); at once with reduced motion. */
const val SCRIM_FADE_MS = 200

/** The scrim is black at this opacity. */
const val SCRIM_OPACITY = 0.4

/**
 * The dim is drawn: asked for, open, in place, and the sheet is above peek (peek keeps the page in
 * sight). [snap] is the sheet's settled state, or the target of a running snap; [placed] is true
 * once the sheet is measured and drawn where it belongs.
 */
fun scrimVisible(scrim: Boolean, open: Boolean, snap: SheetSnap, placed: Boolean): Boolean =
    scrim && open && placed && snap != SheetSnap.Peek

/**
 * The scrim takes touches: asked for, open and in place, in EVERY state including peek (a tap on
 * the empty space closes a peeking tray, 2026-11-09). The dim stays hidden at peek
 * ([scrimVisible]); only its touches are taken.
 */
fun scrimTakesTouches(scrim: Boolean, open: Boolean, placed: Boolean): Boolean = scrim && open && placed

/** Fade duration in ms: [SCRIM_FADE_MS], or 0 with reduced motion. */
fun scrimFadeMs(reducedMotion: Boolean): Int = if (reducedMotion) 0 else SCRIM_FADE_MS

/** What a tap on the scrim leads to. */
enum class ScrimTapOutcome {
    /** No scrim, or the tray is closed. */
    Ignored,

    /** Move the sheet to peek. */
    Lower,

    /** Close the tray (when it holds its own open state) and call `onDismiss`. */
    Dismiss,
}

/**
 * A tap on the scrim. [ScrimTap.Lower] (default) lowers any state above peek and dismisses from
 * peek; [ScrimTap.Dismiss] dismisses from every state.
 */
fun scrimTapOutcome(
    scrim: Boolean,
    scrimTap: ScrimTap = ScrimTap.Lower,
    open: Boolean,
    snap: SheetSnap,
): ScrimTapOutcome {
    if (!scrim || !open) return ScrimTapOutcome.Ignored
    if (scrimTap == ScrimTap.Lower && snap != SheetSnap.Peek) return ScrimTapOutcome.Lower
    return ScrimTapOutcome.Dismiss
}

/**
 * The open/closed state behind `open()`, `close()` and `toggle()`: the host's Gift button is
 * `tray.toggle()`. Every method returns the new state. A call that changes nothing returns the
 * state and notifies nobody. A change updates the state, then notifies subscribers, then calls
 * [onChange]. Call it from the UI thread.
 *
 * @param open the initial state (default true: a tray that exists is shown).
 */
class TrayOpenState(open: Boolean = true, var onChange: ((Boolean) -> Unit)? = null) {
    private var current = open
    private val listeners = LinkedHashSet<() -> Unit>()

    val isOpen: Boolean get() = current

    fun open(): Boolean = set(true)

    fun close(): Boolean = set(false)

    /** Open if closed, close if open. */
    fun toggle(): Boolean = set(!current)

    /** Runs [listener] after every change; returns the function that stops it. */
    fun subscribe(listener: () -> Unit): () -> Unit {
        listeners.add(listener)
        return { listeners.remove(listener) }
    }

    private fun set(next: Boolean): Boolean {
        if (next == current) return current
        current = next
        for (l in listeners.toList()) l()
        onChange?.invoke(next)
        return next
    }
}
