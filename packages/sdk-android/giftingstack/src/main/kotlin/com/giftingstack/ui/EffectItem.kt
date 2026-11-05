package com.giftingstack.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.giftingstack.core.EffectRecipe
import com.giftingstack.core.EffectStage
import com.giftingstack.core.pictureScale as autoPictureScale
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random
import kotlinx.coroutines.withTimeoutOrNull

/** Picture size at scale 1, in dp. The recipe's `peakScale` is relative to this. */
const val EFFECT_PICTURE_SIZE_DP = 100

/** The random layout of one effect: fixed when it is created, never changes while it runs. */
private class EffectLayout(
    val stage: Offset,
    // Sparks as parallel arrays: no object per spark and nothing to allocate per frame.
    val sparkDx: FloatArray,
    val sparkDy: FloatArray,
    val sparkSize: FloatArray,
    val sparkColor: Array<Color>,
    val coinX: FloatArray,
    val coinSize: FloatArray,
    val coinStart: FloatArray,
    val coinFall: FloatArray,
    val rayR: Float,
    val wideRay: Path?,
    val thinRay: Path?,
) {
    companion object {
        /** Built with pixel values; `d` is the screen density (dp to px). */
        fun create(recipe: EffectRecipe, w: Float, h: Float, origin: Offset, d: Float, theme: GiftingTheme, k: Float): EffectLayout {
            val stage =
                if (recipe.stage == EffectStage.Center) {
                    Offset(w / 2f, h * 0.38f)
                } else {
                    Offset(origin.x + (Random.nextFloat() - 0.5f) * 0.2f * w, origin.y - 0.32f * h)
                }
            val n = recipe.sparks
            val dx = FloatArray(n)
            val dy = FloatArray(n)
            val sz = FloatArray(n)
            val colors = Array(n) { theme.glow }
            for (i in 0 until n) {
                val angle = i.toFloat() / maxOf(1, n) * 2f * PI.toFloat() + Random.nextFloat() * 0.6f
                val dist = recipe.sparkSpread * k * (0.4f + Random.nextFloat() * 0.8f) * d
                dx[i] = cos(angle) * dist
                dy[i] = sin(angle) * dist
                sz[i] = (5f + Random.nextFloat() * 6f) * d
                colors[i] = if (i % 3 == 0) theme.accent else theme.glow
            }
            val c = recipe.coins
            val r = min(w, h) * 1.6f
            return EffectLayout(
                stage = stage,
                sparkDx = dx,
                sparkDy = dy,
                sparkSize = sz,
                sparkColor = colors,
                coinX = FloatArray(c) { Random.nextFloat() * w },
                coinSize = FloatArray(c) { (10f + Random.nextFloat() * 8f) * d },
                coinStart = FloatArray(c) { Random.nextFloat() * 0.35f },
                coinFall = FloatArray(c) { 0.45f + Random.nextFloat() * 0.2f },
                rayR = r,
                wideRay = if (recipe.rays) rayPath(stage, r, r * 0.075f) else null,
                thinRay = if (recipe.rays) rayPath(stage, r, r * 0.028f) else null,
            )
        }

        /** A thin triangle from the stage centre to radius R/2 (pointing up; rotated when drawn). */
        private fun rayPath(c: Offset, r: Float, halfWidth: Float): Path =
            Path().apply {
                moveTo(c.x - halfWidth, c.y - r / 2f)
                lineTo(c.x + halfWidth, c.y - r / 2f)
                lineTo(c.x, c.y)
                close()
            }
    }
}

private fun lerp(a: Float, b: Float, f: Float): Float = a + (b - a) * f

/**
 * Plays one gift from start to finish and calls [onDone]. Waits for its picture first (up to
 * [pictureWaitMs]), so the dimming, the notice and the gift start together (spec 7.2). One
 * timeline value drives everything; it is read only in the draw phase (a `Canvas` for dim, rays,
 * glow, sparks and coins, a `graphicsLayer` for the picture), so no frame recomposes anything.
 */
@Composable
internal fun EffectItem(
    recipe: EffectRecipe,
    image: String?,
    layerSize: IntSize,
    origin: Offset,
    theme: GiftingTheme,
    pictureWaitMs: Int,
    pictureScale: Float?,
    loader: GiftImageLoader,
    onStart: () -> Unit,
    onDone: () -> Unit,
) {
    val density = LocalDensity.current.density
    val timeline = remember { EffectTimeline(recipe) }
    val w = layerSize.width.toFloat()
    val h = layerSize.height.toFloat()
    // Fixed for the life of the effect, even if the layer is resized.
    // The picture and the burst grow in a wide or tall layer, as the web layer's pictureScale.
    val k = remember { autoPictureScale(w / density.toDouble(), h / density.toDouble(), recipe.peakScale, pictureScale?.toDouble()).toFloat() }
    val peak = recipe.peakScale.toFloat() * k
    val layout = remember { EffectLayout.create(recipe, w, h, origin, density, theme, k) }
    val start by rememberUpdatedState(onStart)
    val done by rememberUpdatedState(onDone)

    var bitmap by remember { mutableStateOf(image?.let { loader.peek(it) }) }
    if (image != null) {
        // Shows the picture whenever it arrives, even after the wait ran out.
        LaunchedEffect(image) { loader.load(image)?.let { bitmap = it } }
    }

    val progress = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        // Picture gate (spec 7.2): start when the picture loaded or failed, or when the wait ran
        // out, whichever is first; at once without a picture or without a wait. The picture may
        // never report back (offline, bad URL). The timer cancels only this await, not the download.
        if (image != null && pictureWaitMs > 0 && bitmap == null) {
            withTimeoutOrNull(pictureWaitMs.toLong()) { loader.load(image) }
        }
        start()
        progress.animateTo(timeline.totalMs.toFloat(), tween(timeline.totalMs, easing = LinearEasing))
        done()
    }

    Box(Modifier.fillMaxSize().testTag("gift-effect-${recipe.tier.wire}")) {
        Canvas(Modifier.fillMaxSize()) {
            drawEffect(progress.value, recipe, timeline, layout, theme)
        }
        val pic = bitmap
        val box = EFFECT_PICTURE_SIZE_DP.dp
        val pictureModifier =
            Modifier.size(box).graphicsLayer {
                val t = progress.value
                val half = EFFECT_PICTURE_SIZE_DP * density / 2f
                val fly = timeline.fly(t)
                val leave = timeline.leave(t)
                translationX = lerp(origin.x, layout.stage.x, fly) - half
                translationY = lerp(origin.y, layout.stage.y, fly) - half - 0.07f * h * leave
                val scale = lerp(0.3f, peak, fly) * lerp(1f, 0.55f, leave)
                scaleX = scale
                scaleY = scale
                alpha = timeline.appear(t) * (1f - leave)
                // One picture: scale it with the draw, never through an offscreen buffer.
                compositingStrategy = CompositingStrategy.ModulateAlpha
            }
        if (image == null) {
            // No picture: the reference draws a coin-coloured disc.
            Canvas(pictureModifier) { drawCircle(theme.coin) }
        } else if (pic != null) {
            // Compose's Image has no fade-in of its own (spec 7.2: pictures MUST appear without one).
            Image(bitmap = pic, contentDescription = null, modifier = pictureModifier, contentScale = ContentScale.Fit)
        }
    }
}

private fun DrawScope.drawEffect(t: Float, recipe: EffectRecipe, tl: EffectTimeline, layout: EffectLayout, theme: GiftingTheme) {
    val d = density
    val stage = layout.stage

    if (recipe.dim) {
        val a = tl.dim(t) * 0.62f
        if (a > 0f) drawRect(Color.Black.copy(alpha = a))
    }

    if (recipe.rays) {
        val fade = tl.raysFade(t)
        val spin = tl.spin(t)
        if (fade > 0f) {
            // Two sets of rays turning in opposite directions, like a stage light.
            val wideTurn = lerp(0f, 60f, spin)
            val thinTurn = lerp(15f, -35f, spin)
            for (i in 0 until 12) {
                rotate(wideTurn + i * 30f, stage) { drawPath(layout.wideRay!!, theme.glow.copy(alpha = 0.34f * fade)) }
                rotate(thinTurn + i * 30f, stage) { drawPath(layout.thinRay!!, theme.glow.copy(alpha = 0.42f * fade)) }
            }
            // A soft round glow: circles that are brighter towards the middle.
            val grow = lerp(0.4f, 1f, tl.fly(t))
            val glow = theme.glow.copy(alpha = 0.16f * fade)
            for (k in GLOW_RINGS) drawCircle(glow, radius = EFFECT_PICTURE_SIZE_DP * 1.7f * k * d * grow, center = stage)
        }
    }

    val b = tl.burst(t)
    if (layout.sparkDx.isNotEmpty() && b > 0f) {
        val alpha = if (b < 0.12f) b / 0.12f else (1f - b) / 0.88f
        if (alpha > 0f) {
            val scale = 1f - 0.8f * b
            for (i in layout.sparkDx.indices) {
                drawCircle(
                    layout.sparkColor[i].copy(alpha = alpha),
                    radius = layout.sparkSize[i] / 2f * scale,
                    center = Offset(stage.x + layout.sparkDx[i] * b, stage.y + layout.sparkDy[i] * b),
                )
            }
        }
    }

    if (layout.coinX.isNotEmpty()) {
        val p = tl.rain(t)
        val travel = size.height + 48f * d
        for (i in layout.coinX.indices) {
            val start = layout.coinStart[i]
            if (p <= start) continue
            val alpha = if (p >= start + 0.02f) 1f else (p - start) / 0.02f
            val end = min(1f, start + layout.coinFall[i])
            val f = if (end > start) ((p - start) / (end - start)).coerceIn(0f, 1f) else 1f
            val r = layout.coinSize[i] / 2f
            drawCircle(theme.coin.copy(alpha = alpha), r, Offset(layout.coinX[i] + r, -24f * d + f * travel + r))
        }
    }
}

private val GLOW_RINGS = floatArrayOf(1f, 0.78f, 0.58f, 0.4f, 0.24f)
