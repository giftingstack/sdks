package com.giftingstack.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.giftingstack.core.BattleBarLabels
import com.giftingstack.core.BattleBarSide
import com.giftingstack.core.BattleView
import com.giftingstack.core.battleBarModel
import com.giftingstack.core.battleGains
import com.giftingstack.core.battleReadableOn
import com.giftingstack.core.BATTLE_EXTRA_COLORS
import com.giftingstack.core.formatBattleScore
import com.giftingstack.core.initialOf
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToLong
import kotlinx.coroutines.delay

/** A person as the bar shows them. */
data class BattleBarUser(val name: String, val avatarUrl: String? = null)

private val AVATAR = 40.dp
private val GOLD = Color(0xFFFFC83D)
private const val SLIDE_MS = 800
private const val COUNT_MS = 650

/** `1 - (1 - t)^3`, the same ease as the web and React Native bars. */
private val EaseOutCubic = Easing { t -> 1f - (1f - t).pow(3) }

/**
 * The battle bar of a round (SPEC 18.7): the receivers with their scores, a countdown, and a split
 * bar whose boundary slides as gifts arrive. Two sides are the classic versus; three or more (up
 * to 8) are a free-for-all: the clock, a row of cells, a bar of proportional segments. It draws
 * [view] only; your server starts and ends rounds. Nothing is drawn while [view] is null or has
 * fewer than two sides. A screen reader gets one element: the scores and the result.
 *
 * @param view from [GiftRoom.battleView], or use the overload that takes the room.
 * @param users names and pictures of the receivers by id. Fallback: the id.
 * @param sideColors override the side colours, one per side in order (default: the theme's accent,
 *   its coin colour, then teal and pink, then the same again). A shorter list keeps the default for
 *   the sides it does not name. Give the room the same list (`rememberGiftRoom(sideColors = ...)`).
 * @param reducedMotion default: the system "Remove animations" setting. Reduced motion: no
 *   sliding, counting or pulse.
 */
@Composable
fun GiftBattleBar(
    view: BattleView?,
    modifier: Modifier = Modifier,
    users: Map<String, BattleBarUser> = emptyMap(),
    sideColors: List<Color>? = null,
    reducedMotion: Boolean? = null,
    theme: GiftingTheme = GiftingTheme(),
    labels: BattleBarLabels = BattleBarLabels(),
) {
    val still = reducedMotion ?: rememberSystemReducedMotion()
    val loader = currentGiftImageLoader()
    val model = battleBarModel(view, { id -> users[id]?.name ?: id }, labels)
    // Which sides gained since the last frame of this round: they pulse.
    val tracker = remember { PulseTracker() }
    val pulses = tracker.update(view)
    if (model == null) return

    val colors = sidePalette(theme, model.sides.size, sideColors)
    val multi = model.sides.size > 2
    val clockFill = if (model.isFinal) theme.accent else theme.background
    val clockBorder = if (model.isFinal) Color.Transparent else if (model.urgent) theme.danger else theme.border
    val clockText = if (model.isFinal) theme.accentText else if (model.urgent) theme.danger else theme.text
    val spoken = listOf(model.spoken, model.banner).filter { it.isNotEmpty() }.joinToString(". ")

    val clock: @Composable () -> Unit = {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            BasicText(
                labels.vs,
                style = TextStyle(color = theme.muted, fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.8.sp),
            )
            Box(
                Modifier.defaultMinSize(minWidth = 52.dp)
                    .clip(CircleShape)
                    .background(clockFill)
                    .border(1.dp, clockBorder, CircleShape)
                    .padding(horizontal = 10.dp, vertical = 4.dp)
                    .testTag("gift-battle-clock"),
                contentAlignment = Alignment.Center,
            ) {
                BasicText(
                    model.clock,
                    style = TextStyle(color = clockText, fontSize = 13.sp, fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TABULAR_NUMBERS),
                )
            }
        }
    }

    Column(
        modifier.clearAndSetSemantics {
            contentDescription = spoken
            liveRegion = LiveRegionMode.Polite
        }.testTag("gift-battle-bar"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (multi) {
            // Three or more sides (SPEC 18.7): the clock, a row of cells, a bar of proportional segments.
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { clock() }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Top) {
                model.sides.forEachIndexed { i, side ->
                    BattleSideView(
                        side = side,
                        index = i,
                        cell = if (model.sides.size > 4) 30.dp else 36.dp,
                        right = false,
                        color = colors[i].first,
                        textColor = colors[i].second,
                        user = users[side.id],
                        pulse = pulses.getOrElse(i) { 0 },
                        still = still,
                        theme = theme,
                        labels = labels,
                        loader = loader,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            MultiBar(model.pcts, colors.map { it.first }, theme, still)
        } else Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            BattleSideView(
                side = model.sides[0],
                index = 0,
                right = false,
                color = colors[0].first,
                textColor = colors[0].second,
                user = users[model.sides[0].id],
                pulse = pulses[0],
                still = still,
                theme = theme,
                labels = labels,
                loader = loader,
                modifier = Modifier.weight(1f),
            )
            clock()
            BattleSideView(
                side = model.sides[1],
                index = 1,
                right = true,
                color = colors[1].first,
                textColor = colors[1].second,
                user = users[model.sides[1].id],
                pulse = pulses[1],
                still = still,
                theme = theme,
                labels = labels,
                loader = loader,
                modifier = Modifier.weight(1f),
            )
        }
        if (!multi) SplitBar(model.pct, colors[0].first, colors[1].first, theme, model.isFinal, still)
        if (model.banner.isNotEmpty()) {
            BasicText(
                model.banner,
                modifier = Modifier.fillMaxWidth().testTag("gift-battle-banner"),
                style = TextStyle(color = theme.text, fontSize = 13.sp, fontWeight = FontWeight.ExtraBold, textAlign = TextAlign.Center),
            )
        }
    }
}

/**
 * The battle bar of [room]: follows its round ([GiftRoom.battle]) and refreshes the clock every
 * [tickMs] while the round is open (0 = never). Same drawing as the overload that takes a view.
 */
@Composable
fun GiftBattleBar(
    room: GiftRoom,
    modifier: Modifier = Modifier,
    users: Map<String, BattleBarUser> = emptyMap(),
    sideColors: List<Color>? = null,
    reducedMotion: Boolean? = null,
    theme: GiftingTheme = GiftingTheme(),
    labels: BattleBarLabels = BattleBarLabels(),
    tickMs: Long = 1_000,
) {
    val battle by room.battle.collectAsState()
    var view by remember { mutableStateOf<BattleView?>(null) }
    LaunchedEffect(battle, tickMs) {
        view = room.battleView()
        // The clock only needs a frame while a round is open.
        while (tickMs > 0 && view?.open == true) {
            delay(tickMs)
            view = room.battleView()
        }
    }
    GiftBattleBar(view, modifier, users, sideColors, reducedMotion, theme, labels)
}

/** The two-colour form of the bar of a view: `sideColors = a to b` keeps working. */
@Composable
fun GiftBattleBar(
    view: BattleView?,
    sideColors: Pair<Color, Color>,
    modifier: Modifier = Modifier,
    users: Map<String, BattleBarUser> = emptyMap(),
    reducedMotion: Boolean? = null,
    theme: GiftingTheme = GiftingTheme(),
    labels: BattleBarLabels = BattleBarLabels(),
) = GiftBattleBar(view, modifier, users, listOf(sideColors.first, sideColors.second), reducedMotion, theme, labels)

/** The two-colour form of the bar of a room: `sideColors = a to b` keeps working. */
@Composable
fun GiftBattleBar(
    room: GiftRoom,
    sideColors: Pair<Color, Color>,
    modifier: Modifier = Modifier,
    users: Map<String, BattleBarUser> = emptyMap(),
    reducedMotion: Boolean? = null,
    theme: GiftingTheme = GiftingTheme(),
    labels: BattleBarLabels = BattleBarLabels(),
    tickMs: Long = 1_000,
) = GiftBattleBar(room, modifier, users, listOf(sideColors.first, sideColors.second), reducedMotion, theme, labels, tickMs)

/**
 * The colour and its text colour of every side: the app's, else the default palette (SPEC 18.7):
 * the theme's accent, its coin colour, teal and pink, then the same four again.
 */
private fun sidePalette(theme: GiftingTheme, count: Int, over: List<Color>?): List<Pair<Color, Color>> {
    val defaults =
        listOf(theme.accent to theme.accentText, theme.coin to theme.coinText) +
            BATTLE_EXTRA_COLORS.map { hex -> tokenColor(hex) to (if (battleReadableOn(hex) == "#ffffff") Color.White else Color.Black) }
    return List(count) { i -> over?.getOrNull(i)?.let { it to hexText(it) } ?: defaults[i % defaults.size] }
}

/** `#rrggbb` text colour that reads on [c]: black or white, whichever contrasts more. */
private fun hexText(c: Color): Color {
    val hex = "#" + (c.toArgb() and 0xFFFFFF).toString(16).padStart(6, '0')
    return if (battleReadableOn(hex) == "#ffffff") Color.White else Color.Black
}

/** Counts, per side, how often its score rose within one round (the pulse trigger). */
private class PulseTracker {
    private var round: String? = null
    private var last: List<Long>? = null
    private var counts = IntArray(0)

    fun update(view: BattleView?): List<Int> {
        val units = view?.sides?.map { it.units } ?: emptyList()
        if (counts.size < units.size) counts = counts.copyOf(units.size)
        val before = if (view != null && view.round == round) last else null
        val gains = battleGains(before, units)
        for (i in gains.indices) if (gains[i]) counts[i]++
        round = view?.round
        last = if (view == null) null else units
        return counts.toList()
    }
}

/**
 * One receiver: avatar in a ring (gold with a crown for the winner), name over a score that counts
 * up, the loser at half opacity, a short pulse when [pulse] rises.
 */
@Composable
private fun BattleSideView(
    side: BattleBarSide,
    index: Int,
    /** Three or more sides: the avatar's size; the side is a centred cell (avatar over name over score). Null: the versus layout. */
    cell: Dp? = null,
    right: Boolean,
    color: Color,
    textColor: Color,
    user: BattleBarUser?,
    pulse: Int,
    still: Boolean,
    theme: GiftingTheme,
    labels: BattleBarLabels,
    loader: GiftImageLoader,
    modifier: Modifier,
) {
    val scale = remember { Animatable(1f) }
    LaunchedEffect(pulse) {
        if (pulse > 0 && !still) {
            scale.animateTo(1.07f, tween(200))
            scale.animateTo(1f, tween(300))
        }
    }
    val count by animateFloatAsState(side.units.toFloat(), if (still) snap() else tween(COUNT_MS, easing = EaseOutCubic), label = "gift-battle-count")
    // Exact once the count has arrived (a Float cannot hold every large score).
    val shown = if (abs(count - side.units) < 1f) side.units else count.roundToLong()
    val ring = if (side.won) GOLD else color
    val url = user?.avatarUrl
    val size = cell ?: AVATAR
    val crowded = cell != null && cell < 36.dp

    val avatar: @Composable () -> Unit = {
        Box {
            Box(Modifier.size(size + 8.dp).border(2.dp, ring, CircleShape).padding(4.dp).clearAndSetSemantics {}) {
                if (url != null) {
                    Box(Modifier.size(size).clip(CircleShape).background(theme.border)) { GiftPicture(url, Modifier.size(size), loader) }
                } else {
                    Box(Modifier.size(size).clip(CircleShape).background(color), contentAlignment = Alignment.Center) {
                        BasicText(
                            initialOf(side.name),
                            style = TextStyle(color = textColor, fontSize = if (cell == null) 18.sp else (size.value * 0.45f).sp, fontWeight = FontWeight.ExtraBold),
                        )
                    }
                }
            }
            if (side.won) {
                BasicText(
                    "♛",
                    modifier =
                        Modifier.align(if (cell != null) Alignment.TopCenter else if (right) Alignment.TopEnd else Alignment.TopStart)
                            .offset(x = if (cell != null) 0.dp else if (right) (-2).dp else 2.dp, y = (-14).dp)
                            .testTag("gift-battle-crown"),
                    style = TextStyle(color = GOLD, fontSize = 18.sp),
                )
            }
        }
    }
    val who: @Composable (Modifier) -> Unit = { m ->
        Column(m, horizontalAlignment = if (cell != null) Alignment.CenterHorizontally else if (right) Alignment.End else Alignment.Start) {
            BasicText(
                side.name,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = TextStyle(color = theme.text, fontSize = if (cell == null) 13.sp else if (crowded) 11.sp else 12.sp, fontWeight = FontWeight.Bold),
            )
            BasicText(
                formatBattleScore(shown, labels),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.testTag("gift-battle-score-$index"),
                style =
                    TextStyle(
                        color = theme.text,
                        fontSize = if (cell == null) 20.sp else if (crowded) 14.sp else 17.sp,
                        fontWeight = FontWeight.ExtraBold,
                        fontFeatureSettings = TABULAR_NUMBERS,
                    ),
            )
        }
    }
    if (cell != null) {
        Column(
            modifier.alpha(if (side.lost) 0.5f else 1f).graphicsLayer {
                scaleX = scale.value
                scaleY = scale.value
            },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            avatar()
            who(Modifier)
        }
        return
    }
    Row(
        modifier.alpha(if (side.lost) 0.5f else 1f).graphicsLayer {
            scaleX = scale.value
            scaleY = scale.value
        },
        horizontalArrangement = if (right) Arrangement.spacedBy(8.dp, Alignment.End) else Arrangement.spacedBy(8.dp, Alignment.Start),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (right) {
            who(Modifier.weight(1f, fill = false))
            avatar()
        } else {
            avatar()
            who(Modifier.weight(1f, fill = false))
        }
    }
}

/**
 * The 16 dp bar of three or more sides: one segment per side, side `i` in `colors[i]` with the
 * width `pcts[i]` percent, 2 dp white lines between them. Every width slides (800 ms, ease out
 * cubic) unless [still].
 */
@Composable
private fun MultiBar(pcts: List<Double>, colors: List<Color>, theme: GiftingTheme, still: Boolean) {
    val shape = RoundedCornerShape(8.dp)
    Row(
        Modifier.fillMaxWidth().height(16.dp).clip(shape).border(1.dp, theme.border, shape).testTag("gift-battle-track"),
    ) {
        pcts.forEachIndexed { i, pct ->
            val p by animateFloatAsState(pct.toFloat(), if (still) snap() else tween(SLIDE_MS, easing = EaseOutCubic), label = "gift-battle-segment-$i")
            if (i > 0) Box(Modifier.fillMaxHeight().width(2.dp).background(Color.White))
            Box(Modifier.fillMaxHeight().weight(maxOf(p, 0.0001f)).background(colors[i]).testTag("gift-battle-segment-$i"))
        }
    }
}

/**
 * The 16 dp bar: side B colour as the base, side A from the left up to [pct], and the spark on the
 * boundary. The boundary slides (800 ms, ease out cubic) unless [still].
 */
@Composable
private fun SplitBar(pct: Double, colorA: Color, colorB: Color, theme: GiftingTheme, final: Boolean, still: Boolean) {
    val p by animateFloatAsState(pct.toFloat(), if (still) snap() else tween(SLIDE_MS, easing = EaseOutCubic), label = "gift-battle-split")
    val shape = RoundedCornerShape(8.dp)
    Box(
        Modifier.fillMaxWidth()
            .height(16.dp)
            .background(colorB, shape)
            .border(1.dp, theme.border, shape)
            .padding(1.dp)
            .testTag("gift-battle-track"),
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val boundary: Dp = maxWidth * (p / 100f)
            Box(
                Modifier.fillMaxHeight()
                    .fillMaxWidth(p / 100f)
                    .background(colorA, RoundedCornerShape(topStart = 7.dp, bottomStart = 7.dp, topEnd = 0.dp, bottomEnd = 0.dp))
                    .testTag("gift-battle-fill"),
            )
            val spark = RoundedCornerShape(2.dp)
            Box(
                Modifier.align(Alignment.TopStart)
                    .offset(x = boundary - 2.dp, y = (-5).dp)
                    .requiredSize(width = 4.dp, height = 26.dp)
                    .alpha(if (final) 0.5f else 1f)
                    .shadow(6.dp, spark, ambientColor = theme.accent, spotColor = theme.accent)
                    .background(Color.White, spark)
                    .testTag("gift-battle-spark"),
            )
        }
    }
}
