package com.giftingstack.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.SideEffect
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.giftingstack.core.AwayAckOn
import com.giftingstack.core.AwayApi
import com.giftingstack.core.AwayController
import com.giftingstack.core.AwayControllerOptions
import com.giftingstack.core.AwayEffectPlayer
import com.giftingstack.core.AwayStatus
import com.giftingstack.core.AwaySummary
import com.giftingstack.core.DEFAULT_AWAY_BUDGET_MS
import com.giftingstack.core.DEFAULT_AWAY_MAX_EFFECTS
import com.giftingstack.core.EffectQuality
import com.giftingstack.core.GiftLabels
import com.giftingstack.core.GiftingException
import com.giftingstack.core.TierThresholds
import com.giftingstack.core.awayGroupSpoken
import com.giftingstack.core.awaySenderSpoken
import com.giftingstack.core.awayTexts
import com.giftingstack.core.formatCount
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.withTimeoutOrNull

/** A display name (and picture) for an external id, from `resolveUsers`. */
data class AwayUser(val name: String, val avatarUrl: String? = null)

/** One top sender in [AwaySummaryContext.senders]. */
class AwaySenderInfo(
    val user: String?,
    /** The display name (from `resolveUsers`), else the id. */
    val name: String,
    val avatarUrl: String?,
    val count: Int,
)

/**
 * What `renderSummary` receives: the data the card would show, already computed, and callbacks.
 * [Default] draws the default body (title, line, senders, gifts and the close button).
 */
class AwaySummaryContext(
    val summary: AwaySummary,
    /** The card title, from the labels. */
    val title: String,
    /** `"37 gifts from 12 people"`, as the default card shows it. */
    val headline: String,
    /** `"37 gifts"` (`2,000+ gifts` when the count was capped). */
    val gifts: String,
    /** `"12 people"`. */
    val people: String,
    /** Top senders (the default card shows three), names from `resolveUsers` or the id. */
    val senders: List<AwaySenderInfo>,
    /** Close the card. Your own buttons call this: a tap on custom content does not dismiss. */
    val dismiss: () -> Unit,
    /** `AwayAckOn.Manual`: mark the summary as seen. */
    val ack: () -> Unit,
    /** The resolved theme, so your card can match the rest. */
    val theme: GiftingTheme,
    internal val default: @Composable () -> Unit,
) {
    /** Draws the default body. */
    @Composable fun Default() = default()
}

/** The longest the card waits for `resolveUsers`; ids it does not answer in time keep the id. */
const val AWAY_RESOLVE_WAIT_MS = 1_500L

/** The card slides in over this long (not under reduced motion). */
internal const val AWAY_SLIDE_MS = 240

/** For `AwayAckOn.Manual` apps and for a "check now" button: reaches the controller of a card. */
@Stable
class GiftAwayHandle {
    internal var controller: AwayController? = null

    /** Ask the server now (ignored while a card is up). */
    fun check() {
        controller?.check()
    }

    /** `AwayAckOn.Manual`: mark the card as seen. */
    fun ack() {
        controller?.ack()
    }

    fun dismiss() {
        controller?.dismiss()
    }
}

@Composable
fun rememberGiftAwayHandle(): GiftAwayHandle = remember { GiftAwayHandle() }

/** The part of the layer the replay plays through. */
fun GiftEffectLayerState.asAwayPlayer(): AwayEffectPlayer = AwayEffectPlayer { play(it) }

private val EaseOutCubicAway = Easing { easeOutCubic(it) }

private fun userIds(s: AwaySummary): List<String> {
    val ids = LinkedHashSet<String>()
    for (t in s.topSenders) t.user?.let { ids.add(it) }
    for (g in s.groups) for (x in g.senders) x.user?.let { ids.add(it) }
    return ids.toList()
}

/**
 * "While you were away: 37 gifts from 12 people". Checks once when it enters the composition (and
 * when the app comes back to the foreground, at most once a minute), shows a card with the top
 * senders and the gifts, replays the biggest gift groups through your [GiftEffectLayer], then goes
 * away by itself or on a tap. Nothing new, or any failure: draws nothing (SPEC 15.5). Put it over
 * your screen, below the effect layer, in a `Box`.
 *
 * @param effects the layer state shown by your `GiftEffectLayer`. Null: card only.
 * @param resolveUsers external ids are often not display names: map them here. The card waits up to
 *   1.5 s for it; ids it does not answer keep the id itself.
 * @param autoCheck `true` (default): check on entering and on return to the foreground.
 * @param ackOn when the cursor moves on: shown (default), finished, or manual (use [handle]).
 * @param focusOnShow move input focus (and with it the screen reader) to the card when it appears.
 * @param reducedMotion default: the system "Remove animations" setting: no replay, no slide-in.
 * @param renderSummary draws the body of the card yourself. The card still checks, names the senders,
 *   keeps its container, the screen reader announcement, the slide-in, the effect replay and the
 *   acknowledgement. Null (default): the default body. With your body a tap does not dismiss and
 *   there is no close button: call [AwaySummaryContext.dismiss]. Call [AwaySummaryContext.Default]
 *   to draw the default body inside your own frame.
 * @param handle see [rememberGiftAwayHandle].
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun GiftAwaySummary(
    client: AwayApi,
    modifier: Modifier = Modifier,
    effects: GiftEffectLayerState? = null,
    resolveUsers: (suspend (List<String>) -> Map<String, AwayUser>)? = null,
    autoCheck: Boolean = true,
    ackOn: AwayAckOn = AwayAckOn.Shown,
    maxEffects: Int = DEFAULT_AWAY_MAX_EFFECTS,
    budgetMs: Long = DEFAULT_AWAY_BUDGET_MS,
    thresholds: TierThresholds? = null,
    quality: EffectQuality = EffectQuality.High,
    focusOnShow: Boolean = false,
    renderSummary: (@Composable (AwaySummaryContext) -> Unit)? = null,
    onShow: ((AwaySummary) -> Unit)? = null,
    onDone: (() -> Unit)? = null,
    onError: ((GiftingException) -> Unit)? = null,
    reducedMotion: Boolean? = null,
    theme: GiftingTheme = GiftingTheme(),
    labels: GiftLabels = GiftLabels(),
    handle: GiftAwayHandle? = null,
) {
    val reduced = reducedMotion ?: rememberSystemReducedMotion()
    val scope = rememberCoroutineScope()
    val imageLoader = currentGiftImageLoader()
    var users by remember { mutableStateOf<Map<String, AwayUser>>(emptyMap()) }
    val usersNow by rememberUpdatedState(users)
    val reducedNow by rememberUpdatedState(reduced)
    val effectsNow by rememberUpdatedState(effects)

    val options =
        AwayControllerOptions(
            client = client,
            effects = { effectsNow?.asAwayPlayer() },
            reducedMotion = { reducedNow },
            ackOn = ackOn,
            maxEffects = maxEffects,
            budgetMs = budgetMs,
            thresholds = thresholds,
            quality = quality,
            resolveName = { u -> usersNow[u]?.name ?: u },
            labels = labels.sender,
            onShow = onShow,
            onDone = onDone,
            onError = onError,
        )
    val controller = remember(client) { AwayController(options, scope) }
    SideEffect { controller.setOptions(options) }
    DisposableEffect(controller, handle) {
        handle?.controller = controller
        onDispose {
            if (handle?.controller === controller) handle.controller = null
            controller.dispose()
        }
    }
    LaunchedEffect(controller, autoCheck) { if (autoCheck) controller.check() }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(controller, lifecycle, autoCheck) {
        if (!autoCheck) return@DisposableEffect onDispose {}
        // The app came back to the foreground: check again, at most once a minute (the controller throttles).
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_START) controller.foreground() }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    val state by controller.state.collectAsState()

    // The card shows once the names are in (or 1.5 s passed), so it never redraws its senders.
    val summary = state.summary
    var shownFor by remember { mutableStateOf<AwaySummary?>(null) }
    val resolveNow by rememberUpdatedState(resolveUsers)
    LaunchedEffect(summary) {
        if (summary == null) return@LaunchedEffect
        val ids = userIds(summary)
        val resolve = resolveNow
        if (resolve != null && ids.isNotEmpty()) {
            val found =
                try {
                    withTimeoutOrNull(AWAY_RESOLVE_WAIT_MS) { resolve(ids) }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    null
                }
            if (found != null) users = users + found
        }
        shownFor = summary
    }

    val visible = summary != null && shownFor === summary && (state.status == AwayStatus.Ready || state.status == AwayStatus.Playing)
    // The card is on screen: start the replay and the countdown (once per summary).
    LaunchedEffect(visible, state.status) { if (visible && state.status == AwayStatus.Ready) controller.start() }

    val slide = remember { Animatable(if (reduced) 1f else 0f) }
    LaunchedEffect(visible, reduced) {
        if (!visible) return@LaunchedEffect
        if (reduced) {
            slide.snapTo(1f)
        } else {
            slide.snapTo(0f)
            slide.animateTo(1f, tween(AWAY_SLIDE_MS, easing = EaseOutCubicAway))
        }
    }
    val focus = remember { FocusRequester() }
    LaunchedEffect(visible, focusOnShow) {
        if (visible && focusOnShow) {
            try {
                focus.requestFocus()
            } catch (_: Exception) {
                // Not attached yet or no focus target: nothing to move.
            }
        }
    }

    if (!visible) return
    val texts = awayTexts(summary, labels)
    val nameOf = { u: String? -> if (u == null) labels.someone else users[u]?.name ?: u }
    val shape = RoundedCornerShape(20.dp)

    // A non-modal card: the backdrop takes no touches, only the card does.
    Box(modifier.fillMaxSize().padding(24.dp).testTag("gift-away"), contentAlignment = Alignment.Center) {
        Box(
            Modifier.widthIn(max = 360.dp)
                .fillMaxWidth()
                .graphicsLayer {
                    alpha = slide.value
                    translationY = 18.dp.toPx() * (1f - slide.value)
                }
                .shadow(12.dp, shape)
                .clip(shape)
                .background(theme.surface)
                .border(Dp.Hairline, theme.border, shape)
                .semantics { paneTitle = labels.awayTitle }
                .focusRequester(focus)
                .focusable()
                .testTag("gift-away-card"),
        ) {
            val defaultBody: @Composable () -> Unit = {
            Column(
                Modifier.fillMaxWidth()
                    // A tap anywhere on the body dismisses; it is not a separate screen-reader element.
                    .pointerInput(controller) { detectTapGestures { controller.dismiss() } }
                    .padding(start = 18.dp, top = 18.dp, bottom = 18.dp, end = 52.dp)
                    .testTag("gift-away-body"),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Column(
                    Modifier.clearAndSetSemantics {
                        contentDescription = texts.announce
                        liveRegion = LiveRegionMode.Polite
                    }.testTag("gift-away-head"),
                    verticalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    BasicText(labels.awayTitle, style = TextStyle(color = theme.text, fontSize = 17.sp, fontWeight = FontWeight.ExtraBold))
                    BasicText(texts.line, style = TextStyle(color = theme.muted, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold))
                }

                val senders = summary.topSenders.take(3)
                if (senders.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        for (s in senders) {
                            val name = nameOf(s.user)
                            val avatar = s.user?.let { users[it]?.avatarUrl }
                            Column(
                                Modifier.widthIn(min = 56.dp, max = 88.dp)
                                    .clearAndSetSemantics { contentDescription = awaySenderSpoken(name, s.count, labels) }
                                    .testTag("gift-away-sender"),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(3.dp),
                            ) {
                                Avatar(name, avatar, 36.dp, theme, imageLoader)
                                BasicText(
                                    name,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    style = TextStyle(color = theme.text, fontSize = 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center),
                                )
                                BasicText(
                                    formatCount(s.count, labels.count),
                                    style = TextStyle(color = theme.muted, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = TABULAR_NUMBERS),
                                )
                            }
                        }
                    }
                }

                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (g in summary.groups) {
                        Row(
                            Modifier.clip(CircleShape)
                                .background(theme.background)
                                .padding(start = 6.dp, end = 10.dp, top = 4.dp, bottom = 4.dp)
                                .clearAndSetSemantics { contentDescription = awayGroupSpoken(g) }
                                .testTag("gift-away-group"),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            GiftChipIcon(g.gift.iconUrl, 28.dp, theme, imageLoader)
                            BasicText(
                                formatCount(g.count, labels.count),
                                style = TextStyle(color = theme.text, fontSize = 13.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = TABULAR_NUMBERS),
                            )
                        }
                    }
                }
            }
            // The close button: 44 x 44 dp, top right.
            Box(
                Modifier.align(Alignment.TopEnd)
                    .size(44.dp)
                    .clearAndSetSemantics {
                        contentDescription = labels.dismiss
                        role = Role.Button
                        onClick { controller.dismiss(); true }
                    }
                    .clickable { controller.dismiss() }
                    .testTag("gift-away-dismiss"),
                contentAlignment = Alignment.Center,
            ) {
                BasicText("×", style = TextStyle(color = theme.muted, fontSize = 26.sp))
            }
            }
            if (renderSummary != null) {
                Box(
                    Modifier.fillMaxWidth()
                        // Your body replaces the labelled head, so the arrival is announced here.
                        .semantics {
                            contentDescription = texts.announce
                            liveRegion = LiveRegionMode.Polite
                        }
                        .testTag("gift-away-custom"),
                ) {
                    renderSummary(
                        AwaySummaryContext(
                            summary = summary,
                            title = labels.awayTitle,
                            headline = texts.line,
                            gifts = texts.gifts,
                            people = texts.people,
                            senders = summary.topSenders.map { AwaySenderInfo(it.user, nameOf(it.user), it.user?.let { u -> users[u]?.avatarUrl }, it.count) },
                            dismiss = { controller.dismiss() },
                            ack = { controller.ack() },
                            theme = theme,
                            default = defaultBody,
                        ),
                    )
                }
            } else {
                defaultBody()
            }
        }
    }
}
