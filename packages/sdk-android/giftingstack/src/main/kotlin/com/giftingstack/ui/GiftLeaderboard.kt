package com.giftingstack.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CollectionInfo
import androidx.compose.ui.semantics.CollectionItemInfo
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.collectionInfo
import androidx.compose.ui.semantics.collectionItemInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.giftingstack.core.DEFAULT_LEADERBOARD_LIMIT
import com.giftingstack.core.GiftLabels
import com.giftingstack.core.GiftingException
import com.giftingstack.core.LEADERBOARD_PERIODS
import com.giftingstack.core.LeaderboardApi
import com.giftingstack.core.LeaderboardBoard
import com.giftingstack.core.LeaderboardController
import com.giftingstack.core.LeaderboardControllerOptions
import com.giftingstack.core.LeaderboardEntry
import com.giftingstack.core.LeaderboardMe
import com.giftingstack.core.LeaderboardMetric
import com.giftingstack.core.LeaderboardPeriod
import com.giftingstack.core.LeaderboardStatus
import com.giftingstack.core.groupThousands
import com.giftingstack.core.leaderboardPinnedSpoken
import com.giftingstack.core.leaderboardPinnedText
import com.giftingstack.core.leaderboardRowSpoken
import com.giftingstack.core.leaderboardScore
import com.giftingstack.core.leaderboardUnitsName
import com.giftingstack.core.rankColor
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay

/** A name (and picture) for an external id, from `resolveUsers`. */
data class LeaderboardUser(val name: String, val avatarUrl: String? = null)

/**
 * What `renderRow` receives for one ranked row. [Default] draws the default rank, avatar, name and
 * score, for a row you only want to wrap or to leave alone.
 */
class LeaderboardRowContext(
    val entry: LeaderboardEntry,
    val rank: Int,
    /** The display name (from `resolveUsers`), else the id. */
    val name: String,
    val avatarUrl: String?,
    val metric: LeaderboardMetric,
    /** The score for the shown metric: coins (`Units`) or gifts. */
    val score: Long,
    /** The score as the default row shows it (`54K`). */
    val scoreText: String,
    /** Whether this is the highlighted (signed-in) person. */
    val isMe: Boolean,
    /** The resolved theme, so your row can match the rest. */
    val theme: GiftingTheme,
    internal val default: @Composable () -> Unit,
) {
    /** Draws the default rank, avatar, name and score. */
    @Composable fun Default() = default()
}

/** Row height of the leaderboard, dp (SPEC 16.4). */
const val LEADERBOARD_ROW_DP = 52

/** For "pull to refresh" and for apps that poll: reaches the controller of a leaderboard. */
@Stable
class GiftLeaderboardHandle {
    internal var controller: LeaderboardController? = null

    /** Fetch the shown tab again now. */
    fun refresh() {
        controller?.refresh()
    }
}

@Composable
fun rememberGiftLeaderboardHandle(): GiftLeaderboardHandle = remember { GiftLeaderboardHandle() }

/**
 * Top senders or top receivers: tabs for today, this week, this month and all time, an optional
 * coins / gifts switch, up to 100 rows with medals for the first three, and the viewer's own
 * position pinned underneath when they are not in the rows (SPEC 16.4). Stale rows stay visible
 * while a tab refreshes in the background.
 *
 * @param periods tabs, in this order; one item: no tabs. An empty list = the four default tabs.
 * @param metric units (default for senders) or gifts (default for receivers).
 * @param metricToggle show a switch between coins and gifts.
 * @param limit rows, 1 to 100.
 * @param resolveUsers external ids are often not display names: map them here. Unknown ids keep
 *   the id itself.
 * @param highlightUser whose row is highlighted. Default: the signed-in user (`me`).
 * @param refreshIntervalMs 0 (default): no polling; otherwise the shown tab is fetched again this often.
 * @param renderRow draws the inside of each ranked row yourself. The board still loads, orders,
 *   names, highlights and pins; it keeps the row container, its spoken label and the press. A
 *   custom row may be taller than 52 dp. The pinned "You" row stays the default. Null (default):
 *   the default row. Call [LeaderboardRowContext.Default] to keep the default for some rows.
 * @param onPressUser makes the rows buttons; open a profile here.
 * @param reducedMotion default: the system "Remove animations" setting (no pulse, no spinner).
 * @param coinName the name of your currency, used in the coins tab and for screen readers.
 * @param handle see [rememberGiftLeaderboardHandle].
 */
@Composable
fun GiftLeaderboard(
    client: LeaderboardApi,
    modifier: Modifier = Modifier,
    board: LeaderboardBoard = LeaderboardBoard.Senders,
    periods: List<LeaderboardPeriod> = LEADERBOARD_PERIODS,
    initialPeriod: LeaderboardPeriod = LeaderboardPeriod.Week,
    metric: LeaderboardMetric? = null,
    metricToggle: Boolean = false,
    limit: Int = DEFAULT_LEADERBOARD_LIMIT,
    resolveUsers: (suspend (List<String>) -> Map<String, LeaderboardUser>)? = null,
    highlightUser: String? = null,
    refreshIntervalMs: Long = 0,
    renderRow: (@Composable (LeaderboardRowContext) -> Unit)? = null,
    onPressUser: ((String) -> Unit)? = null,
    onError: ((GiftingException) -> Unit)? = null,
    reducedMotion: Boolean? = null,
    theme: GiftingTheme = GiftingTheme(),
    labels: GiftLabels = GiftLabels(),
    coinName: String = "coins",
    handle: GiftLeaderboardHandle? = null,
) {
    val reduced = reducedMotion ?: rememberSystemReducedMotion()
    val scope = rememberCoroutineScope()
    val imageLoader = currentGiftImageLoader()
    val options =
        LeaderboardControllerOptions(
            client = client,
            board = board,
            periods = periods,
            initialPeriod = initialPeriod,
            metric = metric,
            limit = limit,
            onError = onError,
        )
    val controller = remember(client, board, limit, initialPeriod, metric, periods) { LeaderboardController(options, scope) }
    SideEffect { controller.setOptions(options) }
    DisposableEffect(controller, handle) {
        handle?.controller = controller
        controller.start()
        onDispose {
            if (handle?.controller === controller) handle.controller = null
            controller.dispose()
        }
    }
    LaunchedEffect(controller, refreshIntervalMs) {
        if (refreshIntervalMs > 0) {
            while (true) {
                delay(refreshIntervalMs)
                controller.refresh()
            }
        }
    }
    val state by controller.state.collectAsState()

    // Names for the rows on screen, asked once per id.
    var users by remember { mutableStateOf<Map<String, LeaderboardUser>>(emptyMap()) }
    val asked = remember { HashSet<String>() }
    val resolveNow by rememberUpdatedState(resolveUsers)
    val ids = (state.data?.data?.map { it.user } ?: emptyList()) + listOfNotNull(state.pinned?.user)
    val idsKey = ids.distinct().joinToString("\u0000")
    LaunchedEffect(idsKey) {
        val resolve = resolveNow ?: return@LaunchedEffect
        val fresh = ids.distinct().filter { it !in asked }
        if (fresh.isEmpty()) return@LaunchedEffect
        asked.addAll(fresh)
        try {
            users = users + resolve(fresh)
        } catch (e: CancellationException) {
            asked.removeAll(fresh.toSet())
            throw e
        } catch (e: Exception) {
            asked.removeAll(fresh.toSet())
        }
    }

    val highlight = highlightUser ?: state.data?.me?.user
    val metricNow = state.metric
    val nameOf = { id: String -> users[id]?.name ?: id }
    val shape = RoundedCornerShape(20.dp)

    Column(
        modifier.clip(shape).background(theme.surface).border(Dp.Hairline, theme.border, shape).padding(8.dp).testTag("gift-lb"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 32.dp).padding(horizontal = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (state.periods.size > 1) {
                Row(Modifier.selectableGroup().testTag("gift-lb-tabs"), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (p in state.periods) {
                        Tab(labels.tabs[p] ?: p.wire, state.period == p, Role.Tab, theme, "gift-lb-tab-${p.wire}") { controller.setPeriod(p) }
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            if (state.refreshing && !reduced) Spinner(theme.muted, labels.updating)
        }
        if (metricToggle) {
            Row(
                Modifier.selectableGroup()
                    .semantics { contentDescription = labels.metricSwitch }
                    .padding(horizontal = 4.dp)
                    .testTag("gift-lb-metric"),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Tab(leaderboardUnitsName(labels, coinName), metricNow == LeaderboardMetric.Units, Role.RadioButton, theme, "gift-lb-metric-units") {
                    controller.setMetric(LeaderboardMetric.Units)
                }
                Tab(labels.metricGifts, metricNow == LeaderboardMetric.Gifts, Role.RadioButton, theme, "gift-lb-metric-gifts") {
                    controller.setMetric(LeaderboardMetric.Gifts)
                }
            }
        }

        val data = state.data
        when {
            state.status == LeaderboardStatus.Loading -> SkeletonRows(limit.coerceAtLeast(1), reduced, theme, labels.loading)
            state.status == LeaderboardStatus.Error ->
                Column(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 28.dp).testTag("gift-lb-error"),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    BasicText(
                        labels.error,
                        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                        style = TextStyle(color = theme.danger, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center),
                    )
                    Box(
                        Modifier.heightIn(min = 44.dp)
                            .clip(CircleShape)
                            .background(theme.accent)
                            .semantics { role = Role.Button }
                            .clickable { controller.refresh() }
                            .padding(horizontal = 20.dp)
                            .testTag("gift-lb-retry"),
                        contentAlignment = Alignment.Center,
                    ) {
                        BasicText(labels.tryAgain, style = TextStyle(color = theme.accentText, fontSize = 14.sp, fontWeight = FontWeight.Bold))
                    }
                }
            state.status == LeaderboardStatus.Empty || data == null ->
                Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 28.dp).testTag("gift-lb-empty"), contentAlignment = Alignment.Center) {
                    BasicText(
                        labels.empty[state.period] ?: "",
                        style = TextStyle(color = theme.muted, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center),
                    )
                }
            else ->
                Column(Modifier.semantics { collectionInfo = CollectionInfo(rowCount = data.data.size, columnCount = 1) }.testTag("gift-lb-list")) {
                    for ((i, e) in data.data.withIndex()) {
                        EntryRow(e, i, nameOf(e.user), users[e.user]?.avatarUrl, e.user == highlight, metricNow, theme, labels, coinName, imageLoader, renderRow, onPressUser)
                    }
                }
        }

        state.pinned?.let { me ->
            if (state.status != LeaderboardStatus.Loading) {
                PinnedRow(me, nameOf(me.user), users[me.user]?.avatarUrl, metricNow, theme, labels, coinName, imageLoader, onPressUser)
            }
        }
    }
}

@Composable
private fun Tab(label: String, selected: Boolean, role: Role, theme: GiftingTheme, tag: String, onClick: () -> Unit) {
    Box(
        Modifier.heightIn(min = 32.dp)
            .clip(CircleShape)
            .background(if (selected) theme.accent else Color.Transparent)
            .selectable(selected = selected, role = role, onClick = onClick)
            .padding(horizontal = 12.dp)
            .testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(label, style = TextStyle(color = if (selected) theme.accentText else theme.muted, fontSize = 13.sp, fontWeight = FontWeight.Bold))
    }
}

@Composable
private fun Score(metric: LeaderboardMetric, gifts: Long, units: Long, theme: GiftingTheme, labels: GiftLabels, coinName: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        BasicText(
            leaderboardScore(metric, gifts, units, labels, coinName, spoken = false),
            style = TextStyle(color = theme.text, fontSize = 13.5.sp, fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TABULAR_NUMBERS),
        )
        if (metric == LeaderboardMetric.Units) {
            CoinDot(theme.coin, 11.dp)
        } else {
            BasicText(labels.giftsWord, style = TextStyle(color = theme.muted, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold))
        }
    }
}

@Composable
private fun EntryRow(
    e: LeaderboardEntry,
    index: Int,
    name: String,
    avatarUrl: String?,
    mine: Boolean,
    metric: LeaderboardMetric,
    theme: GiftingTheme,
    labels: GiftLabels,
    coinName: String,
    imageLoader: GiftImageLoader,
    renderRow: (@Composable (LeaderboardRowContext) -> Unit)?,
    onPressUser: ((String) -> Unit)?,
) {
    val medal = rankColor(e.rank)?.let { tokenColor(it) }
    val spoken = leaderboardRowSpoken(e, name, metric, labels, coinName)
    var m: Modifier =
        Modifier.fillMaxWidth()
            .then(if (renderRow != null) Modifier.heightIn(min = LEADERBOARD_ROW_DP.dp) else Modifier.height(LEADERBOARD_ROW_DP.dp))
            .clip(RoundedCornerShape(14.dp))
            .then(if (mine) Modifier.background(theme.selected) else Modifier)
            .clearAndSetSemantics {
                contentDescription = spoken
                collectionItemInfo = CollectionItemInfo(rowIndex = index, rowSpan = 1, columnIndex = 0, columnSpan = 1)
                if (onPressUser != null) {
                    role = Role.Button
                    onClick { onPressUser(e.user); true }
                }
            }
    if (onPressUser != null) m = m.clickable { onPressUser(e.user) }
    Row(
        m.padding(horizontal = 8.dp).testTag("gift-lb-row-${e.user}"),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val defaultContent: @Composable () -> Unit = {
        Box(
            Modifier.size(28.dp).clip(CircleShape).then(if (medal != null) Modifier.background(medal).testTag("gift-lb-medal-${e.rank}") else Modifier),
            contentAlignment = Alignment.Center,
        ) {
            BasicText(
                groupThousands(e.rank),
                style =
                    TextStyle(
                        color = if (medal != null) theme.noticeBigText else theme.muted,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.ExtraBold,
                        fontFeatureSettings = TABULAR_NUMBERS,
                    ),
            )
        }
        Avatar(name, avatarUrl, 32.dp, theme, imageLoader)
        BasicText(
            name,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            style = TextStyle(color = theme.text, fontSize = 14.sp, fontWeight = FontWeight.Bold),
        )
        Score(metric, e.gifts, e.units, theme, labels, coinName)
        }
        if (renderRow != null) {
            renderRow(
                LeaderboardRowContext(
                    entry = e,
                    rank = e.rank,
                    name = name,
                    avatarUrl = avatarUrl,
                    metric = metric,
                    score = if (metric == LeaderboardMetric.Units) e.units else e.gifts,
                    scoreText = leaderboardScore(metric, e.gifts, e.units, labels, coinName, spoken = false),
                    isMe = mine,
                    theme = theme,
                    default = defaultContent,
                ),
            )
        } else {
            defaultContent()
        }
    }
}

@Composable
private fun PinnedRow(
    me: LeaderboardMe,
    name: String,
    avatarUrl: String?,
    metric: LeaderboardMetric,
    theme: GiftingTheme,
    labels: GiftLabels,
    coinName: String,
    imageLoader: GiftImageLoader,
    onPressUser: ((String) -> Unit)?,
) {
    val spoken = leaderboardPinnedSpoken(me, metric, labels, coinName)
    var m: Modifier =
        Modifier.fillMaxWidth()
            .height(LEADERBOARD_ROW_DP.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(theme.selected)
            .border(Dp.Hairline, theme.border, RoundedCornerShape(14.dp))
            .clearAndSetSemantics {
                contentDescription = spoken
                if (onPressUser != null) {
                    role = Role.Button
                    onClick { onPressUser(me.user); true }
                }
            }
    if (onPressUser != null) m = m.clickable { onPressUser(me.user) }
    Row(
        m.padding(horizontal = 8.dp).testTag("gift-lb-pinned"),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Avatar(name, avatarUrl, 32.dp, theme, imageLoader)
        BasicText(
            leaderboardPinnedText(me, labels),
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            style = TextStyle(color = theme.text, fontSize = 14.sp, fontWeight = FontWeight.Bold),
        )
        Score(metric, me.gifts, me.units, theme, labels, coinName)
    }
}

@Composable
private fun SkeletonRows(count: Int, reduced: Boolean, theme: GiftingTheme, loadingLabel: String) {
    val alpha =
        if (reduced) {
            1f
        } else {
            val t = rememberInfiniteTransition(label = "gift-lb-pulse")
            t.animateFloat(0.45f, 1f, infiniteRepeatable(tween(800, easing = LinearEasing), RepeatMode.Reverse), label = "alpha").value
        }
    Column(
        Modifier.clearAndSetSemantics {
            contentDescription = loadingLabel
            progressBarRangeInfo = ProgressBarRangeInfo.Indeterminate
        }.testTag("gift-lb-skeleton"),
    ) {
        for (i in 0 until count) {
            Row(
                Modifier.fillMaxWidth().height(LEADERBOARD_ROW_DP.dp).padding(horizontal = 8.dp).testTag("gift-lb-skeleton-row"),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val c = theme.border.copy(alpha = theme.border.alpha * alpha)
                Box(Modifier.size(28.dp).clip(CircleShape).background(c))
                Box(Modifier.size(32.dp).clip(CircleShape).background(c))
                Box(Modifier.width((90 + (i * 37) % 60).dp).height(12.dp).clip(RoundedCornerShape(6.dp)).background(c))
            }
        }
    }
}

/** A small spinner for "refreshing, rows stay". Not drawn under reduced motion. */
@Composable
private fun Spinner(color: Color, label: String) {
    val t = rememberInfiniteTransition(label = "gift-lb-spin")
    val angle by t.animateFloat(0f, 360f, infiniteRepeatable(tween(900, easing = LinearEasing)), label = "angle")
    Canvas(
        Modifier.size(16.dp).rotate(angle).semantics { contentDescription = label }.testTag("gift-lb-spinner"),
    ) {
        val w = 2.dp.toPx()
        drawArc(
            color = color,
            startAngle = 0f,
            sweepAngle = 270f,
            useCenter = false,
            topLeft = Offset(w / 2, w / 2),
            size = Size(size.width - w, size.height - w),
            style = Stroke(width = w, cap = StrokeCap.Round),
        )
    }
}
