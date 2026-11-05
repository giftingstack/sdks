package com.giftingstack.demo

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import kotlin.math.PI
import kotlin.math.sin

/**
 * The pictures of the pretend posts, drawn with gradients and shapes: the demo needs no image
 * host and no stock photo. Demo only.
 */
@Composable
fun PostArt(kind: ArtKind, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxSize()) {
        when (kind) {
            ArtKind.Sunset -> sunset()
            ArtKind.City -> city()
            ArtKind.Ocean -> ocean()
            ArtKind.Aurora -> aurora()
        }
    }
}

private fun DrawScope.sunset() {
    val w = size.width
    val h = size.height
    val horizon = h * 0.62f
    drawRect(Brush.verticalGradient(listOf(Color(0xFF2B1055), Color(0xFFD4504C), Color(0xFFFFB347)), 0f, horizon), size = Size(w, horizon))
    drawCircle(Brush.radialGradient(listOf(Color(0xFFFFF3C4), Color(0xFFFFB347), Color(0x00FFB347)), Offset(w * 0.62f, horizon - h * 0.04f), h * 0.3f), h * 0.3f, Offset(w * 0.62f, horizon - h * 0.04f))
    drawCircle(Color(0xFFFFF3C4), h * 0.1f, Offset(w * 0.62f, horizon - h * 0.04f))
    drawRect(Brush.verticalGradient(listOf(Color(0xFF7A2F4A), Color(0xFF1B1038)), horizon, h), Offset(0f, horizon), Size(w, h - horizon))
    // The sun on the water.
    for (i in 0 until 6) {
        val y = horizon + h * (0.03f + i * 0.055f)
        val half = w * (0.12f - i * 0.012f)
        drawRect(Color(0x55FFD27A), Offset(w * 0.62f - half, y), Size(half * 2, h * 0.012f))
    }
    // The pier.
    drawRect(Color(0xFF1B1038), Offset(0f, horizon + h * 0.1f), Size(w * 0.55f, h * 0.025f))
    for (i in 0..5) drawRect(Color(0xFF1B1038), Offset(w * 0.04f + i * w * 0.1f, horizon + h * 0.1f), Size(w * 0.012f, h * 0.2f))
}

private fun DrawScope.city() {
    val w = size.width
    val h = size.height
    drawRect(Brush.verticalGradient(listOf(Color(0xFF0B1030), Color(0xFF3B2A7A), Color(0xFFE0457B))), size = size)
    val heights = listOf(0.45f, 0.62f, 0.38f, 0.7f, 0.5f, 0.58f, 0.34f, 0.66f, 0.48f, 0.55f)
    val bw = w / heights.size
    heights.forEachIndexed { i, f ->
        val top = h * (1f - f)
        drawRect(Color(0xFF12122B), Offset(i * bw, top), Size(bw - 2f, h - top))
        var y = top + bw * 0.25f
        var row = 0
        while (y < h - bw * 0.3f) {
            for (c in 0..2) {
                val lit = (i * 7 + row * 3 + c * 5) % 4 != 0
                drawRect(if (lit) Color(0xFFFFD27A) else Color(0xFF2A2A55), Offset(i * bw + bw * (0.18f + c * 0.25f), y), Size(bw * 0.14f, bw * 0.14f))
            }
            y += bw * 0.34f
            row++
        }
    }
}

private fun DrawScope.waves(baseline: Float, amp: Float, length: Float, phase: Float, color: Color) {
    val p = Path()
    p.moveTo(0f, size.height)
    var x = 0f
    while (x <= size.width + 4f) {
        p.lineTo(x, baseline + amp * sin((x / length * 2 * PI + phase).toFloat()))
        x += 4f
    }
    p.lineTo(size.width, size.height)
    p.close()
    drawPath(p, color)
}

private fun DrawScope.ocean() {
    val w = size.width
    val h = size.height
    drawRect(Brush.verticalGradient(listOf(Color(0xFF9AD8F5), Color(0xFFE8F7FF))), size = size)
    drawCircle(Color(0xFFFFF7D6), h * 0.09f, Offset(w * 0.2f, h * 0.2f))
    waves(h * 0.55f, h * 0.025f, w * 0.5f, 0f, Color(0xFF3BA7C9))
    waves(h * 0.65f, h * 0.03f, w * 0.42f, 1.6f, Color(0xFF1F86AD))
    waves(h * 0.78f, h * 0.035f, w * 0.36f, 3.1f, Color(0xFF0F5E86))
}

private fun DrawScope.aurora() {
    val w = size.width
    val h = size.height
    drawRect(Brush.verticalGradient(listOf(Color(0xFF050A22), Color(0xFF0E2A4A))), size = size)
    for (i in 0 until 24) drawCircle(Color(0xCCFFFFFF), 1.5f + (i % 3), Offset(w * ((i * 37 % 100) / 100f), h * (((i * 53) % 55) / 100f)))
    val bands = listOf(Color(0xFF3CF5A0) to 0.3f, Color(0xFF6B8CFF) to 0.38f, Color(0xFFB04FD0) to 0.24f)
    bands.forEachIndexed { i, (c, y) ->
        val p = Path()
        p.moveTo(0f, h * y)
        var x = 0f
        while (x <= w + 6f) {
            p.lineTo(x, h * y + h * 0.07f * sin((x / w * 2 * PI * 1.4 + i * 1.7).toFloat()))
            x += 6f
        }
        p.lineTo(w, h * (y + 0.35f))
        p.lineTo(0f, h * (y + 0.35f))
        p.close()
        drawPath(p, Brush.verticalGradient(listOf(c.copy(alpha = 0.75f), Color.Transparent), h * (y - 0.08f), h * (y + 0.35f)))
    }
    val m = Path()
    m.moveTo(0f, h)
    m.lineTo(0f, h * 0.82f)
    m.lineTo(w * 0.22f, h * 0.66f)
    m.lineTo(w * 0.4f, h * 0.82f)
    m.lineTo(w * 0.64f, h * 0.62f)
    m.lineTo(w * 0.85f, h * 0.8f)
    m.lineTo(w, h * 0.72f)
    m.lineTo(w, h)
    m.close()
    drawPath(m, Color(0xFF060914))
}
