package com.giftingstack.ui

import com.giftingstack.core.EffectRecipe
import kotlin.math.max
import kotlin.math.min

/** Easing "back" of React Native's `Easing.out(Easing.back(s))`: overshoots past 1, then settles. */
fun easeOutBack(t: Float, s: Float = 1.3f): Float {
    val u = 1f - t
    return 1f - u * u * ((s + 1f) * u - s)
}

fun easeInQuad(t: Float): Float = t * t

fun easeOutCubic(t: Float): Float {
    val u = 1f - t
    return 1f - u * u * u
}

private fun clamp01(x: Float): Float = min(1f, max(0f, x))

/**
 * All phases of one effect as pure functions of the time `t` (ms since the effect started),
 * after spec section 7.3. The drawing code reads these in the draw phase; nothing here allocates.
 */
class EffectTimeline(private val recipe: EffectRecipe) {
    private val flyIn = recipe.flyInMs.toFloat()
    private val hold = recipe.holdMs.toFloat()
    private val flyOut = recipe.flyOutMs.toFloat()

    /** hold + leave. */
    val tailMs: Int = recipe.holdMs + recipe.flyOutMs

    /** The effect is finished when every phase has ended (spec 7.3). */
    val totalMs: Int =
        recipe.flyInMs + maxOf(900, tailMs, if (recipe.coins > 0) tailMs + 800 else 0)

    /** The picture's fly-in progress with overshoot, 0 to about 1.1 and back to 1. */
    fun fly(t: Float): Float = easeOutBack(clamp01(t / flyIn), 1.3f)

    /** Opacity of the picture from the fly-in: 0 to 1 over the first 6 % of the fly progress. */
    fun appear(t: Float): Float = clamp01(fly(t) / 0.06f)

    /** 0 to 1 as the picture leaves (ease-in quad), 0 before. */
    fun leave(t: Float): Float = easeInQuad(clamp01((t - flyIn - hold) / flyOut))

    /** Dim opacity factor 0 to 1 (multiply by 0.62): up over 300 ms, down while leaving. */
    fun dim(t: Float): Float {
        val leaveStart = flyIn + hold
        return when {
            t < leaveStart -> clamp01(t / 300f)
            else -> 1f - clamp01((t - leaveStart) / flyOut)
        }
    }

    /** Spark burst progress (ease-out cubic over 900 ms from the end of the fly-in). */
    fun burst(t: Float): Float = easeOutCubic(clamp01((t - flyIn) / 900f))

    /** Coin rain progress, linear over `tail + 800` from the end of the fly-in. */
    fun rain(t: Float): Float = clamp01((t - flyIn) / (tailMs + 800f))

    /** Rays progress, linear over the whole fly + hold + leave. */
    fun spin(t: Float): Float = clamp01(t / (flyIn + tailMs))

    /** Rays and glow fade: `[0, 0.1, 0.85, 1] -> [0, 1, 1, 0]` of [spin]. */
    fun raysFade(t: Float): Float {
        val p = spin(t)
        return when {
            p < 0.1f -> p / 0.1f
            p < 0.85f -> 1f
            else -> (1f - p) / 0.15f
        }
    }
}
