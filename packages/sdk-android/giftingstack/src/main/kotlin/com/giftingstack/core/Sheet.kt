package com.giftingstack.core

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.abs
import kotlin.math.floor

/** The tray as a draggable bottom sheet (spec section 9.1): the three snap states. */
enum class SheetSnap(val wire: String) {
    Peek("peek"),
    Default("default"),
    Expanded("expanded");

    companion object {
        fun fromWire(s: String): SheetSnap = entries.first { it.wire == s }
    }
}

/** The snap states from the most closed to the most open. */
val SHEET_SNAPS: List<SheetSnap> = listOf(SheetSnap.Peek, SheetSnap.Default, SheetSnap.Expanded)

/** A release at least this fast (units per second) moves one state in the direction of the flick. */
const val SHEET_FLICK_VELOCITY = 600.0

/** Default snap fractions of the container; 0 means "as tall as the content needs". */
val SHEET_DEFAULT_FRACTIONS: Map<SheetSnap, Double> =
    mapOf(SheetSnap.Peek to 0.0, SheetSnap.Default to 0.0, SheetSnap.Expanded to 0.9)

data class SheetHeights(val peek: Double, val default: Double, val expanded: Double) {
    operator fun get(snap: SheetSnap): Double =
        when (snap) {
            SheetSnap.Peek -> peek
            SheetSnap.Default -> default
            SheetSnap.Expanded -> expanded
        }
}

/** Snap heights as fractions of the container; null = not given (the default applies). */
data class SheetSnapFractions(val peek: Double? = null, val default: Double? = null, val expanded: Double? = null) {
    operator fun get(snap: SheetSnap): Double? =
        when (snap) {
            SheetSnap.Peek -> peek
            SheetSnap.Default -> default
            SheetSnap.Expanded -> expanded
        }
}

/**
 * What the UI measured. Lengths are in the platform's unit (dp here). A floor or content height
 * of 0 means "not given".
 */
data class SheetLayout(
    val containerHeight: Double,
    val snaps: SheetSnapFractions = SheetSnapFractions(),
    val peekMinHeight: Double = 0.0,
    val defaultMinHeight: Double = 0.0,
    val contentHeight: Double = 0.0,
)

private fun positive(v: Double): Double = if (v.isFinite() && v > 0) v else 0.0

/** JS `Math.round`: half up. */
private fun roundHalfUp(v: Double): Double = floor(v + 0.5)

/** The three snap heights for a layout. Always `0 <= peek <= default <= expanded <= container`. */
fun resolveSheetHeights(layout: SheetLayout): SheetHeights {
    val h = positive(layout.containerHeight)

    fun fraction(s: SheetSnap): Double {
        val f = layout.snaps[s]
        return if (f != null && f.isFinite()) f.coerceIn(0.0, 1.0) else SHEET_DEFAULT_FRACTIONS.getValue(s)
    }

    val peek = maxOf(roundHalfUp(fraction(SheetSnap.Peek) * h), positive(layout.peekMinHeight))
    val def = maxOf(roundHalfUp(fraction(SheetSnap.Default) * h), positive(layout.defaultMinHeight), peek)
    var expanded = roundHalfUp(fraction(SheetSnap.Expanded) * h)
    val content = positive(layout.contentHeight)
    if (content > 0) expanded = minOf(expanded, content)
    expanded = maxOf(expanded, def)
    return SheetHeights(minOf(peek, h), minOf(def, h), minOf(expanded, h))
}

data class TraySheetState(
    /** The settled state, or the one the sheet is moving to. Stays the old one during a drag. */
    val snap: SheetSnap,
    /** How far the sheet is moved down from fully open. 0 = expanded. */
    val offset: Double,
    /** `heights.expanded - offset`: the sheet's top edge, measured from the container's bottom. */
    val visibleHeight: Double,
    val dragging: Boolean,
    val heights: SheetHeights,
    /** The gift grid scrolls by itself only when the sheet is fully open and not being dragged. */
    val gridScrollable: Boolean,
)

enum class ScrollOwner { Sheet, Grid }

/**
 * The sheet without a UI (spec section 9.1). Port of `packages/sdk-js/src/core/sheet.ts`: snap
 * heights, drag, release with a velocity bias, tap and accessibility steps, and who owns a drag
 * that starts on the grid. Velocity is units per second, positive = finger moving down. Call it
 * from the UI thread.
 */
class TraySheetController(
    initialSnap: SheetSnap = SheetSnap.Default,
    layout: SheetLayout = SheetLayout(containerHeight = 0.0),
    private var onSnapChange: ((SheetSnap) -> Unit)? = null,
) {
    private var heights = resolveSheetHeights(layout)
    private var snap = initialSnap
    private var offset = offsetOf(initialSnap)
    private var dragging = false

    /** The unclamped drag position, so the sheet stays under the finger after an over-drag. */
    private var raw = 0.0

    private val flow = MutableStateFlow(build())
    val state: StateFlow<TraySheetState> get() = flow

    fun setOnSnapChange(cb: ((SheetSnap) -> Unit)?) {
        onSnapChange = cb
    }

    fun getState(): TraySheetState = flow.value

    /** The offset at which [snap] is fully shown. */
    fun offsetOf(snap: SheetSnap): Double = heights.expanded - heights[snap]

    /** New measurements. Keeps the state; during a drag the position is clamped again. */
    fun setLayout(layout: SheetLayout) {
        heights = resolveSheetHeights(layout)
        offset = if (dragging) clamp(raw) else offsetOf(snap)
        emit()
    }

    fun dragStart() {
        if (dragging) return
        dragging = true
        raw = offset
        emit()
    }

    /** The finger moved [dy] (positive = down). Starts a drag if none is running. */
    fun drag(dy: Double) {
        if (!dragging) dragStart()
        raw += dy
        offset = clamp(raw)
        emit()
    }

    /**
     * The finger lifted with [velocity] (units/s, positive = down). Picks the state and moves
     * there. Without a running drag nothing changes and the current state is returned.
     */
    fun release(velocity: Double = 0.0): SheetSnap {
        if (!dragging) return snap
        dragging = false
        val target = pick(velocity)
        settle(target)
        return target
    }

    /** The drag was interrupted: back to the state it started from. No `onSnapChange`. */
    fun cancel() {
        if (!dragging) return
        dragging = false
        offset = offsetOf(snap)
        emit()
    }

    fun snapTo(target: SheetSnap) {
        dragging = false
        settle(target)
    }

    /** Tap on the handle: peek opens to default, default closes to peek, expanded goes to default. */
    fun toggle(): SheetSnap {
        val next = if (snap == SheetSnap.Default) SheetSnap.Peek else SheetSnap.Default
        snapTo(next)
        return next
    }

    /** Accessibility step: +1 opens one state, -1 closes one, both stop at the ends. */
    fun step(direction: Int): SheetSnap {
        val at = SHEET_SNAPS.indexOf(snap)
        val next = SHEET_SNAPS[(at + direction).coerceIn(0, SHEET_SNAPS.size - 1)]
        snapTo(next)
        return next
    }

    /**
     * A drag that starts on the gift grid moved [dy] first (positive = down). Who takes it: the
     * sheet (it moves) or the grid (it scrolls)? Decide once per gesture.
     */
    fun scrollOwner(dy: Double, gridScrollTop: Double): ScrollOwner =
        when {
            dragging || offset > 0 -> ScrollOwner.Sheet
            dy > 0 && gridScrollTop <= 0 -> ScrollOwner.Sheet
            else -> ScrollOwner.Grid
        }

    private fun clamp(v: Double): Double = minOf(offsetOf(SheetSnap.Peek), maxOf(0.0, v))

    /**
     * Flick (|velocity| >= 600): the nearest state beyond the current position in the flick's
     * direction; if there is none, the nearest state. Otherwise the nearest state. Ties go to
     * the more open state.
     */
    private fun pick(velocity: Double): SheetSnap {
        val open = SHEET_SNAPS.reversed() // most open first: ties keep the more open one
        val o = offset
        if (abs(velocity) >= SHEET_FLICK_VELOCITY) {
            val up = velocity < 0
            var best: SheetSnap? = null
            for (s in open) {
                val so = offsetOf(s)
                if (if (up) so >= o else so <= o) continue
                val b = best
                if (b == null || (if (up) so > offsetOf(b) else so < offsetOf(b))) best = s
            }
            if (best != null) return best
        }
        var best = open[0]
        for (s in open) {
            if (abs(offsetOf(s) - o) < abs(offsetOf(best) - o)) best = s
        }
        return best
    }

    private fun settle(target: SheetSnap) {
        val changed = target != snap
        snap = target
        offset = offsetOf(target)
        emit()
        if (changed) onSnapChange?.invoke(target)
    }

    private fun build() =
        TraySheetState(
            snap = snap,
            offset = offset,
            visibleHeight = heights.expanded - offset,
            dragging = dragging,
            heights = heights,
            gridScrollable = offset == 0.0 && !dragging,
        )

    private fun emit() {
        flow.value = build()
    }
}

// --------------------------------------------------------------------------- first placement

/** How the sheet's drawn offset follows its target offset. */
enum class SheetMove { Jump, Spring }

/**
 * A move is a spring only for a sheet that is measured AND already shown (placed), not being
 * dragged and without reduced motion. Everything else jumps: before the first measurement the
 * heights are guesses, so the offset would otherwise slide from the guess to the real value (the
 * sheet "flies up and comes down").
 */
fun sheetMove(placed: Boolean, measured: Boolean, dragging: Boolean, reducedMotion: Boolean): SheetMove =
    if (!placed || !measured || dragging || reducedMotion) SheetMove.Jump else SheetMove.Spring

/** The soft entrance (as iOS and Flutter): the sheet starts this far lower and invisible. */
const val SHEET_ENTRANCE_RISE_DP = 24.0

/** Length of the soft entrance. */
const val SHEET_ENTRANCE_MS = 200

/** Opacity of the whole sheet (surface, grid and Send bar together): 0 until placed. */
fun sheetEntranceAlpha(placed: Boolean, progress: Double, reducedMotion: Boolean): Double =
    when {
        !placed -> 0.0
        reducedMotion -> 1.0
        else -> progress.coerceIn(0.0, 1.0)
    }

/** How far lower than its place the whole sheet is drawn during the entrance (dp). */
fun sheetEntranceRise(placed: Boolean, progress: Double, reducedMotion: Boolean): Double =
    if (!placed || reducedMotion) 0.0 else (1.0 - progress.coerceIn(0.0, 1.0)) * SHEET_ENTRANCE_RISE_DP
