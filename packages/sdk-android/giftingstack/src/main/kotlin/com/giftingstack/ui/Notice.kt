package com.giftingstack.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.giftingstack.core.NoticeData

private val EaseOutBack12 = Easing { easeOutBack(it, 1.2f) }
private val EaseInQuad = Easing { easeInQuad(it) }

/**
 * The notice stack, bottom-left: up to [MAX_NOTICE_LINES] lines, the newest at the bottom (above
 * [bottom]), 6 dp apart. Takes no touches.
 */
@Composable
internal fun NoticeStackView(
    stack: NoticeStack,
    bottom: Dp,
    theme: GiftingTheme,
    layerWidthPx: Int,
    loader: GiftImageLoader,
) {
    val lines = stack.lines
    Box(Modifier.fillMaxSize()) {
        Column(
            Modifier.align(Alignment.BottomStart).padding(start = 12.dp, bottom = bottom),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            val newest = lines.lastOrNull()
            for (line in lines) {
                key(line.uid) {
                    Notice(
                        data = line.data,
                        visible = line.visible,
                        tag = if (line === newest) "gift-notice" else "gift-notice-line",
                        theme = theme,
                        layerWidthPx = layerWidthPx,
                        loader = loader,
                    )
                }
            }
        }
    }
}

/**
 * One line, "ayla sent Bear boba x3". Slides in from the left, stays, and slides out. The combo
 * number pops each time it grows (spec 7.4).
 */
@Composable
internal fun Notice(
    data: NoticeData,
    visible: Boolean,
    tag: String,
    theme: GiftingTheme,
    layerWidthPx: Int,
    loader: GiftImageLoader,
) {
    val slide = remember { Animatable(0f) }
    val pop = remember { Animatable(1f) }
    val lastCount = remember { intArrayOf(-1) }

    LaunchedEffect(visible) {
        if (visible) {
            slide.animateTo(1f, tween(380, easing = EaseOutBack12))
        } else {
            slide.animateTo(0f, tween(260, easing = EaseInQuad))
        }
    }

    LaunchedEffect(data) {
        val popNow = lastCount[0] >= 0 && data.count > lastCount[0] && data.count > 1
        lastCount[0] = data.count
        if (popNow) {
            pop.snapTo(1.9f)
            // React Native's spring(friction 4, tension 160) is stiffness ~665, damping ~13, mass 1.
            pop.animateTo(1f, spring(dampingRatio = 0.25f, stiffness = 665f))
        }
    }

    val big = data.big
    val textColor = if (big) theme.noticeBigText else theme.noticeText
    val maxWidth = with(LocalDensity.current) { (layerWidthPx * 0.92f).toDp() }
    Row(
        Modifier.widthIn(max = maxWidth)
            .graphicsLayer {
                val p = slide.value
                translationX = -260.dp.toPx() * (1f - p)
                alpha = p.coerceIn(0f, 1f)
            }
            .clip(CircleShape)
            .background(if (big) theme.noticeBigBackground else theme.noticeBackground)
            .padding(start = 5.dp, end = 16.dp, top = if (big) 7.dp else 5.dp, bottom = if (big) 7.dp else 5.dp)
            .semantics { liveRegion = LiveRegionMode.Polite }
            .testTag(tag),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(if (big) 34.dp else 28.dp).clip(CircleShape).background(theme.accent),
            contentAlignment = Alignment.Center,
        ) {
            BasicText(
                data.senderName.take(1).uppercase(),
                style = TextStyle(color = theme.accentText, fontSize = 12.sp, fontWeight = FontWeight.Bold),
            )
        }
        Column {
            BasicText(
                data.senderName,
                style = TextStyle(color = textColor, fontSize = 12.5.sp, lineHeight = 15.sp, fontWeight = FontWeight.Bold),
                maxLines = 1,
            )
            BasicText(
                "sent ${data.giftName}",
                style = TextStyle(color = textColor.copy(alpha = textColor.alpha * 0.92f), fontSize = 12.5.sp, lineHeight = 15.sp),
                maxLines = 1,
            )
        }
        data.image?.let { url ->
            // A fresh image element per picture: never show the previous gift while the next loads.
            key(url) { GiftPicture(url, Modifier.size(if (big) 46.dp else 36.dp), loader) }
        }
        if (data.count > 1) {
            BasicText(
                "x${data.count}",
                modifier =
                    Modifier.widthIn(min = 40.dp).graphicsLayer {
                        scaleX = pop.value
                        scaleY = pop.value
                    }.testTag("gift-combo"),
                style =
                    TextStyle(
                        color = if (big) theme.noticeBigText else theme.comboText,
                        fontSize = 28.sp,
                        fontWeight = FontWeight.ExtraBold,
                        fontStyle = FontStyle.Italic,
                        textAlign = TextAlign.Center,
                    ),
            )
        }
    }
}


/** A gift picture from the [GiftImageLoader], drawn at once when it is in memory, no fade-in. */
@Composable
internal fun GiftPicture(url: String, modifier: Modifier, loader: GiftImageLoader) {
    var bitmap by remember(url) { mutableStateOf(loader.peek(url)) }
    if (bitmap == null) {
        LaunchedEffect(url) { bitmap = loader.load(url) }
    }
    bitmap?.let { Image(bitmap = it, contentDescription = null, modifier = modifier, contentScale = ContentScale.Fit) }
        ?: Box(modifier)
}
