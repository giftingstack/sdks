package com.giftingstack.demo

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.giftingstack.ui.DefaultGiftImageLoader
import com.giftingstack.ui.GiftingTheme

/** The four tabs of the bottom bar. */
enum class PixelTab(val label: String) { Feed("Feed"), Live("Live"), Top("Top"), Inbox("Inbox"), Me("Me") }

/** Height of the tab bar without the system navigation bar. */
internal val TAB_BAR_HEIGHT = 56.dp

@Composable
internal fun Txt(text: String, color: Color, size: Float = 14f, bold: Boolean = false, modifier: Modifier = Modifier, align: TextAlign? = null, maxLines: Int = Int.MAX_VALUE) {
    BasicText(
        text,
        modifier,
        style = TextStyle(color = color, fontSize = size.sp, fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal, textAlign = align ?: TextAlign.Unspecified),
        maxLines = maxLines,
    )
}

/** A gift picture from the live library, loaded by the SDK's own image loader. */
@Composable
internal fun UrlImage(url: String?, size: Dp, modifier: Modifier = Modifier) {
    val bitmap by produceState<ImageBitmap?>(url?.let { DefaultGiftImageLoader.peek(it) }, url) {
        if (url != null && value == null) value = DefaultGiftImageLoader.load(url)
    }
    val b = bitmap
    if (b != null) Image(b, contentDescription = null, modifier = modifier.size(size), contentScale = ContentScale.Fit) else Box(modifier.size(size))
}

/** A round avatar with the person's initial (the demo has no image host for faces). */
@Composable
internal fun Avatar(id: String, size: Dp, modifier: Modifier = Modifier) {
    Box(modifier.size(size).clip(CircleShape).background(Color(userColor(id))), contentAlignment = Alignment.Center) {
        Txt(initialOf(id), Color.White, size.value * 0.42f, bold = true)
    }
}

@Composable
internal fun Card(theme: GiftingTheme, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(theme.surface).border(1.dp, theme.border, RoundedCornerShape(16.dp))) { content() }
}

/** A pill button; [filled] uses the accent colour. */
@Composable
internal fun Pill(label: String, theme: GiftingTheme, filled: Boolean = false, modifier: Modifier = Modifier, icon: (@Composable (Color) -> Unit)? = null, onClick: () -> Unit) {
    val fg = if (filled) theme.accentText else theme.text
    Row(
        modifier.heightIn(min = 44.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(if (filled) theme.accent else Color.Transparent)
            .then(if (filled) Modifier else Modifier.border(1.dp, theme.border, RoundedCornerShape(22.dp)))
            .clickable(onClick = onClick)
            .semantics { role = Role.Button }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
    ) {
        icon?.invoke(fg)
        Txt(label, fg, 14f, bold = true, maxLines = 1)
    }
}

/** A switch (the demo uses only foundation, so it draws its own). */
@Composable
internal fun PixelSwitch(on: Boolean, theme: GiftingTheme, label: String, onChange: (Boolean) -> Unit) {
    Box(
        Modifier.size(width = 52.dp, height = 44.dp)
            .semantics { role = Role.Switch; contentDescription = label }
            .clickable { onChange(!on) },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(width = 44.dp, height = 26.dp).clip(RoundedCornerShape(13.dp)).background(if (on) theme.accent else theme.border)) {
            Box(Modifier.padding(3.dp).size(20.dp).align(if (on) Alignment.CenterEnd else Alignment.CenterStart).clip(CircleShape).background(Color.White))
        }
    }
}

// ---- small drawn icons

@Composable
internal fun GiftIcon(color: Color, size: Dp = 18.dp) {
    Canvas(Modifier.size(size)) {
        val s = this.size.width
        val st = Stroke(width = s * 0.09f, cap = StrokeCap.Round)
        drawRoundRect(color, Offset(s * 0.14f, s * 0.46f), androidx.compose.ui.geometry.Size(s * 0.72f, s * 0.4f), androidx.compose.ui.geometry.CornerRadius(s * 0.05f), style = st)
        drawRoundRect(color, Offset(s * 0.08f, s * 0.28f), androidx.compose.ui.geometry.Size(s * 0.84f, s * 0.18f), androidx.compose.ui.geometry.CornerRadius(s * 0.05f), style = st)
        drawLine(color, Offset(s * 0.5f, s * 0.28f), Offset(s * 0.5f, s * 0.86f), st.width, StrokeCap.Round)
        val bow = Path().apply {
            moveTo(s * 0.5f, s * 0.28f)
            cubicTo(s * 0.3f, s * 0.28f, s * 0.26f, s * 0.08f, s * 0.4f, s * 0.1f)
            cubicTo(s * 0.46f, s * 0.11f, s * 0.5f, s * 0.2f, s * 0.5f, s * 0.28f)
            cubicTo(s * 0.5f, s * 0.2f, s * 0.54f, s * 0.11f, s * 0.6f, s * 0.1f)
            cubicTo(s * 0.74f, s * 0.08f, s * 0.7f, s * 0.28f, s * 0.5f, s * 0.28f)
        }
        drawPath(bow, color, style = st)
    }
}

@Composable
internal fun HeartIcon(color: Color, filled: Boolean, size: Dp = 18.dp) {
    Canvas(Modifier.size(size)) {
        val s = this.size.width
        val p = Path().apply {
            moveTo(s * 0.5f, s * 0.88f)
            cubicTo(s * 0.1f, s * 0.6f, s * 0.08f, s * 0.3f, s * 0.28f, s * 0.2f)
            cubicTo(s * 0.4f, s * 0.15f, s * 0.5f, s * 0.24f, s * 0.5f, s * 0.3f)
            cubicTo(s * 0.5f, s * 0.24f, s * 0.6f, s * 0.15f, s * 0.72f, s * 0.2f)
            cubicTo(s * 0.92f, s * 0.3f, s * 0.9f, s * 0.6f, s * 0.5f, s * 0.88f)
            close()
        }
        if (filled) drawPath(p, color) else drawPath(p, color, style = Stroke(width = s * 0.09f))
    }
}

@Composable
private fun TabIcon(tab: PixelTab, color: Color) {
    Canvas(Modifier.size(24.dp)) {
        val s = size.width
        val st = Stroke(width = s * 0.085f, cap = StrokeCap.Round)
        when (tab) {
            PixelTab.Feed -> {
                val p = Path().apply {
                    moveTo(s * 0.12f, s * 0.48f)
                    lineTo(s * 0.5f, s * 0.14f)
                    lineTo(s * 0.88f, s * 0.48f)
                    moveTo(s * 0.22f, s * 0.42f)
                    lineTo(s * 0.22f, s * 0.86f)
                    lineTo(s * 0.78f, s * 0.86f)
                    lineTo(s * 0.78f, s * 0.42f)
                }
                drawPath(p, color, style = st)
            }
            PixelTab.Live -> {
                // A dot with two arcs: a broadcast sign.
                drawCircle(color, s * 0.09f, Offset(s * 0.5f, s * 0.5f))
                drawArc(color, 140f, 80f, false, Offset(s * 0.22f, s * 0.22f), androidx.compose.ui.geometry.Size(s * 0.56f, s * 0.56f), style = st)
                drawArc(color, -40f, 80f, false, Offset(s * 0.22f, s * 0.22f), androidx.compose.ui.geometry.Size(s * 0.56f, s * 0.56f), style = st)
                drawArc(color, 140f, 80f, false, Offset(s * 0.06f, s * 0.06f), androidx.compose.ui.geometry.Size(s * 0.88f, s * 0.88f), style = st)
                drawArc(color, -40f, 80f, false, Offset(s * 0.06f, s * 0.06f), androidx.compose.ui.geometry.Size(s * 0.88f, s * 0.88f), style = st)
            }
            PixelTab.Top -> {
                val p = Path().apply {
                    moveTo(s * 0.5f, s * 0.1f)
                    lineTo(s * 0.62f, s * 0.38f)
                    lineTo(s * 0.92f, s * 0.4f)
                    lineTo(s * 0.68f, s * 0.6f)
                    lineTo(s * 0.77f, s * 0.9f)
                    lineTo(s * 0.5f, s * 0.72f)
                    lineTo(s * 0.23f, s * 0.9f)
                    lineTo(s * 0.32f, s * 0.6f)
                    lineTo(s * 0.08f, s * 0.4f)
                    lineTo(s * 0.38f, s * 0.38f)
                    close()
                }
                drawPath(p, color, style = st)
            }
            PixelTab.Inbox -> {
                drawRoundRect(color, Offset(s * 0.1f, s * 0.2f), androidx.compose.ui.geometry.Size(s * 0.8f, s * 0.6f), androidx.compose.ui.geometry.CornerRadius(s * 0.08f), style = st)
                val p = Path().apply {
                    moveTo(s * 0.1f, s * 0.28f)
                    lineTo(s * 0.5f, s * 0.58f)
                    lineTo(s * 0.9f, s * 0.28f)
                }
                drawPath(p, color, style = st)
            }
            PixelTab.Me -> {
                drawCircle(color, s * 0.2f, Offset(s * 0.5f, s * 0.32f), style = st)
                val p = Path().apply {
                    moveTo(s * 0.14f, s * 0.9f)
                    cubicTo(s * 0.14f, s * 0.58f, s * 0.86f, s * 0.58f, s * 0.86f, s * 0.9f)
                }
                drawPath(p, color, style = st)
            }
        }
    }
}

/** The bottom bar: five tabs, a count badge on the Inbox. No system bar padding here: the caller adds it. */
@Composable
internal fun PixelTabBar(current: PixelTab, unread: Int, theme: GiftingTheme, onSelect: (PixelTab) -> Unit) {
    Row(Modifier.fillMaxWidth().height(TAB_BAR_HEIGHT).background(theme.surface)) {
        for (tab in PixelTab.entries) {
            val on = tab == current
            val color = if (on) theme.accent else theme.muted
            Column(
                Modifier.weight(1f).height(TAB_BAR_HEIGHT).clickable { onSelect(tab) }.semantics { role = Role.Tab; contentDescription = tab.label + if (tab == PixelTab.Inbox && unread > 0) ", $unread new" else "" },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Box {
                    TabIcon(tab, color)
                    if (tab == PixelTab.Inbox && unread > 0) {
                        Box(Modifier.align(Alignment.TopEnd).padding(start = 18.dp).width(16.dp).height(16.dp).clip(CircleShape).background(theme.danger), contentAlignment = Alignment.Center) {
                            Txt(if (unread > 9) "9+" else unread.toString(), Color(0xFF2A0010), 9f, bold = true)
                        }
                    }
                }
                Txt(tab.label, color, 11f, bold = on)
            }
        }
    }
}

