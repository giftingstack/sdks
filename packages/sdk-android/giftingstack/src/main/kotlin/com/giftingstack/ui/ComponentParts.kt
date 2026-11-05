package com.giftingstack.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import com.giftingstack.core.initialOf

/** Small pieces the wall, the away card and the leaderboard share. Not public API. */

/** A gift picture that never breaks the layout: a neutral disc while it is missing. Decorative. */
@Composable
internal fun GiftChipIcon(url: String?, size: Dp, theme: GiftingTheme, loader: GiftImageLoader) {
    if (url != null) {
        GiftPicture(url, Modifier.size(size).clearAndSetSemantics {}, loader)
    } else {
        Box(Modifier.size(size).clip(CircleShape).background(theme.border).clearAndSetSemantics {})
    }
}

/** A round avatar: the picture when there is one, else the initial on the accent colour. Decorative. */
@Composable
internal fun Avatar(name: String, url: String?, size: Dp, theme: GiftingTheme, loader: GiftImageLoader) {
    if (url != null) {
        Box(Modifier.size(size).clip(CircleShape).background(theme.border).clearAndSetSemantics {}) {
            GiftPicture(url, Modifier.size(size), loader)
        }
    } else {
        Box(Modifier.size(size).clip(CircleShape).background(theme.accent).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
            BasicText(
                initialOf(name),
                style = TextStyle(color = theme.accentText, fontSize = (size.value * 0.42f).sp, fontWeight = FontWeight.Bold),
            )
        }
    }
}

/** A small coin disc, like the tray's. Decorative. */
@Composable
internal fun CoinDot(color: androidx.compose.ui.graphics.Color, size: Dp) {
    Box(Modifier.size(size).clip(CircleShape).background(color).clearAndSetSemantics {})
}

/** Tabular figures, so counts do not jump while they change. */
internal const val TABULAR_NUMBERS = "tnum"
