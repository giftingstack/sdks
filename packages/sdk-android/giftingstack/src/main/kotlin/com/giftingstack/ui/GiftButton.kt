package com.giftingstack.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.indication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** The touch target is at least this big; the circle keeps its `size` (SPEC 20.4). */
internal val GIFT_BUTTON_MIN_TOUCH = 44.dp

/** The three fixed circle diameters of a [GiftButton] (SPEC 20.4): small 32 dp, medium 36 dp (default), large 44 dp. */
enum class GiftButtonSize(internal val circleDp: Float) {
    Small(32f),
    Medium(36f),
    Large(44f),
}

/** The circle and the glyph box of a [GiftButtonSize], in dp (SPEC 20.4): the glyph box is `22 * circle / 36`. */
internal data class GiftButtonMetrics(val circle: Float, val glyph: Float)

internal fun giftButtonMetrics(size: GiftButtonSize): GiftButtonMetrics = GiftButtonMetrics(size.circleDp, 22f * size.circleDp / 36f)

/** The scale that fits a w x h icon into a box x box glyph box: down only, never up, aspect ratio kept (SPEC 20.4). */
internal fun giftIconFitScale(w: Float, h: Float, box: Float): Float =
    if (w <= 0f || h <= 0f) 1f else minOf(1f, box / w, box / h)

/** The colours of a [GiftButton] (SPEC 20.4): background and glyph. */
internal data class GiftButtonColors(val background: Color, val glyph: Color)

/** Plain: no background, accent glyph. Filled: accent background, accentText glyph. Active (tray open): selected + accent. */
internal fun giftButtonColors(theme: GiftingTheme, filled: Boolean, active: Boolean): GiftButtonColors =
    when {
        active -> GiftButtonColors(theme.selected, theme.accent)
        filled -> GiftButtonColors(theme.accent, theme.accentText)
        else -> GiftButtonColors(Color.Transparent, theme.accent)
    }

/** The accessibility state of a button bound to a tray: "expanded" or "collapsed"; null without a tray. */
internal fun giftButtonState(tray: GiftTrayHolder?): String? = tray?.let { if (it.isOpen) "expanded" else "collapsed" }

/**
 * A small round button with a gift glyph for the app's message bar, next to its text field or emoji button
 * (SPEC 20.4). With [tray] a press is `tray.toggle()` (the keyboard swap when a field is bound with
 * [giftTrayInput]) and the button shows the tray's open state.
 *
 * @param tray the tray holder to toggle; the button is active while it is open.
 * @param onClick called after the toggle; without [tray] it is the only action.
 * @param label the accessibility label.
 * @param filled an accent background with the glyph in `accentText`; default plain (no background, accent glyph).
 * @param size one of three fixed circle sizes (32, 36, 44 dp); the touch target is at least 44 dp.
 * @param icon replaces the gift glyph; it gets the glyph colour and is fitted into the glyph box (scaled down,
 *   never up, overflow clipped), so it can never change the button's size.
 * @param enabled false: half transparent, no presses.
 * @param theme the tray's theme.
 */
@Composable
fun GiftButton(
    tray: GiftTrayHolder? = null,
    onClick: (() -> Unit)? = null,
    label: String = "Send a gift",
    filled: Boolean = false,
    size: GiftButtonSize = GiftButtonSize.Medium,
    icon: (@Composable (color: Color) -> Unit)? = null,
    enabled: Boolean = true,
    theme: GiftingTheme = GiftingTheme(),
    modifier: Modifier = Modifier,
) {
    val metrics = giftButtonMetrics(size)
    val colors = giftButtonColors(theme, filled, active = tray?.isOpen == true)
    val state = giftButtonState(tray)
    val source = remember { MutableInteractionSource() }
    Box(
        modifier
            .sizeIn(minWidth = GIFT_BUTTON_MIN_TOUCH, minHeight = GIFT_BUTTON_MIN_TOUCH)
            .clickable(interactionSource = source, indication = null, enabled = enabled, role = Role.Button) {
                tray?.toggle()
                onClick?.invoke()
            }
            .semantics {
                contentDescription = label
                if (state != null) stateDescription = state
            }
            .testTag("gift-button"),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(metrics.circle.dp)
                .alpha(if (enabled) 1f else 0.5f)
                .clip(CircleShape)
                .background(colors.background)
                .indication(source, LocalIndication.current),
            contentAlignment = Alignment.Center,
        ) {
            if (icon == null) {
                Canvas(Modifier.size(metrics.glyph.dp)) { drawGiftGlyph(colors.glyph) }
            } else {
                FittedIcon(metrics.glyph.dp) { icon(colors.glyph) }
            }
        }
    }
}

/** Draws [content] centred in a fixed [box] x [box] area: scaled down to fit, never up, overflow clipped. */
@Composable
private fun FittedIcon(box: Dp, content: @Composable () -> Unit) {
    Layout(content = content, modifier = Modifier.size(box).clipToBounds()) { measurables, constraints ->
        val side = constraints.maxWidth
        // Measured without limits: the icon reports the size it really wants, then it is scaled down into the box
        // (measured with the box as its limit it could never report "too big" and would only be cut off).
        val p = measurables.firstOrNull()?.measure(Constraints())
        layout(side, side) {
            if (p != null) {
                val k = giftIconFitScale(p.width.toFloat(), p.height.toFloat(), side.toFloat())
                p.placeRelativeWithLayer((side - p.width) / 2, (side - p.height) / 2) {
                    scaleX = k
                    scaleY = k
                }
            }
        }
    }
}

/** The gift glyph of SPEC 20.4: strokes of 1.8 in a 24 x 24 box, round joins and caps, no fill. */
private fun DrawScope.drawGiftGlyph(color: Color) {
    val k = size.minDimension / 24f
    scale(k, k, pivot = Offset.Zero) {
        val stroke = Stroke(width = 1.8f, cap = StrokeCap.Round, join = StrokeJoin.Round)
        drawRect(color, Offset(4f, 11f), Size(16f, 10f), style = stroke)
        drawRect(color, Offset(3f, 7f), Size(18f, 4f), style = stroke)
        drawLine(color, Offset(12f, 7f), Offset(12f, 21f), strokeWidth = 1.8f, cap = StrokeCap.Round)
        val bows =
            Path().apply {
                moveTo(12f, 7f)
                cubicTo(10f, 7f, 8f, 6f, 8f, 4.5f)
                cubicTo(8f, 3f, 10f, 3f, 12f, 7f)
                moveTo(12f, 7f)
                cubicTo(14f, 7f, 16f, 6f, 16f, 4.5f)
                cubicTo(16f, 3f, 14f, 3f, 12f, 7f)
            }
        drawPath(bows, color, style = stroke)
    }
}
