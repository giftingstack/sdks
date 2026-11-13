package com.giftingstack.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.gestures.awaitVerticalTouchSlopOrCancellation
import androidx.compose.foundation.gestures.verticalDrag
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.imeAnimationTarget
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.horizontalScroll
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.input.pointer.util.addPointerInputChange
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.collapse
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.expand
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.giftingstack.core.Gift
import com.giftingstack.core.SEND_TO_LABEL
import com.giftingstack.core.TrayReceiver
import com.giftingstack.core.initialOf
import com.giftingstack.core.ScrollOwner
import com.giftingstack.core.SendButtonAction
import com.giftingstack.core.SCRIM_OPACITY
import com.giftingstack.core.ScrimTap
import com.giftingstack.core.ScrimTapOutcome
import com.giftingstack.core.SendButtonLabel
import com.giftingstack.core.SHEET_ENTRANCE_MS
import com.giftingstack.core.SendButtonState
import com.giftingstack.core.SheetLayout
import com.giftingstack.core.SheetMove
import com.giftingstack.core.SheetSnap
import com.giftingstack.core.SheetSnapFractions
import com.giftingstack.core.TraySheetController
import com.giftingstack.core.keyboardPlaceSnap
import com.giftingstack.core.sendButtonState
import com.giftingstack.core.sheetEntranceAlpha
import com.giftingstack.core.scrimFadeMs
import com.giftingstack.core.scrimTakesTouches
import com.giftingstack.core.scrimTapOutcome
import com.giftingstack.core.scrimVisible
import com.giftingstack.core.sheetEntranceRise
import com.giftingstack.core.sheetMove
import java.util.Locale
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlin.math.ceil
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlin.math.sign

/** Always en-US grouping (`1,234`), whatever the device locale (spec section 9). */
fun formatCoins(n: Int): String = formatCoins(n.toLong())
fun formatCoins(n: Long): String = String.format(Locale.US, "%,d", n)

private val EaseOutCubicEasing = Easing { easeOutCubic(it) }

/** Gap between the header and the grid, and between the rows of the body (spec 9). */
private const val BODY_GAP_DP = 12

/**
 * A tray of gifts with the balance and a Send button (spec section 9). Presentational: you pass
 * data and callbacks, usually from a [GiftTrayHolder].
 *
 * By default the tray is a draggable bottom sheet (spec 9.1): it fills the bottom of its parent
 * (put it in a `Box` over your screen, next to the [GiftEffectLayer]), pulls up to show more gifts
 * and down to show more of the screen. The body moves, the Send bar stays. `sheet = false` is the
 * fixed-height tray, sized by its content, as before.
 *
 * @param gifts the gifts to show. Default: `tray.state.gifts`.
 * @param balance the balance. Default: `tray.state.balance`.
 * @param onSend called when the person taps Send. Tap again for a combo. Default: `tray.send`.
 * @param tray your [GiftTrayHolder] (see [rememberGiftTrayHolder]): `GiftTray(tray = tray)` is all a screen needs.
 * @param onTopUp shows "+ Coins" and, when the balance is too low, a "Get coins" button.
 * @param coinName the name of your currency, used in accessibility labels.
 * @param gridMaxHeight (fixed tray only) rows scroll when taller than this.
 * @param defaultSelectedId id of the gift selected first. Default: the first gift.
 * @param disabled turn off sending, for example while a request is running.
 * @param onSelectedChange called with the gift shown as selected, when it changes.
 * @param sheet `true` (default) = bottom sheet, `false` = the fixed tray. Read once.
 * @param initialSnap the sheet's first state: peek, default (two rows) or expanded.
 * @param snaps snap heights as fractions of the container; null fields use the defaults
 *   (peek and default fit their content, expanded is 90 %, capped at the full content). When [tray] has a bound text
 *   field ([giftTrayInput], SPEC 20.3), a null `default` is the keyboard's place: the last keyboard height seen
 *   (300 dp before any), at most 60 % of the container.
 * @param onSnapChange called when the settled state changes.
 * @param onInsetChange the sheet's visible height: live during a drag, the target when a state is
 *   chosen. Pass it (plus a gap) as the effect layer's `noticeBottom` so the notice sits above the sheet.
 * @param bottomInset the safe area under the Send bar (for example the navigation bar height).
 * @param controller your own [TraySheetController] to drive the sheet (for example `snapTo`).
 * @param open (sheet) the tray is shown or hidden. Default `null`: `tray.isOpen` when you pass a [tray], else `true`.
 *   Closed, the sheet, the footer and the scrim are invisible, take no touches, are out of the accessibility tree and
 *   `onInsetChange` says 0; opening shows the sheet again at `initialSnap` (SPEC 9.4). When you pass it, the tray never
 *   closes itself: react in `onDismiss`.
 * @param scrim (sheet) a black dim (0.4) behind the sheet over the whole box the tray fills, above your screen. It
 *   fades in with the sheet (200 ms, at once with reduced motion), is hidden at peek and takes the touches above the
 *   sheet while it shows (accessibility button "Close gift tray"). Default `false`. Needs a bounded parent.
 * @param scrimTap what a tap on the dim does: [ScrimTap.Lower] (default) lowers the sheet to peek, and from peek
 *   dismisses; [ScrimTap.Dismiss] dismisses from every state. A dismissal closes [tray] (when [open] is not given)
 *   and then calls [onDismiss].
 * @param onDismiss a tap on the dim asked to close. With a [tray] it is already closed when this runs.
 */
@Composable
fun GiftTray(
    gifts: List<Gift>? = null,
    balance: Long? = null,
    onSend: ((Gift) -> Unit)? = null,
    modifier: Modifier = Modifier,
    onTopUp: (() -> Unit)? = null,
    title: String = "Send a gift",
    coinName: String = "coins",
    sendLabel: String = "Send",
    notEnoughLabel: String = "Not enough coins",
    getCoinsLabel: String = "Get coins",
    columns: Int = 4,
    gridMaxHeight: Dp = 230.dp,
    defaultSelectedId: String? = null,
    disabled: Boolean = false,
    theme: GiftingTheme = GiftingTheme(),
    onSelectedChange: ((Gift?) -> Unit)? = null,
    sheet: Boolean = true,
    initialSnap: SheetSnap = SheetSnap.Default,
    snaps: SheetSnapFractions = SheetSnapFractions(),
    onSnapChange: ((SheetSnap) -> Unit)? = null,
    onInsetChange: ((Dp) -> Unit)? = null,
    bottomInset: Dp = 0.dp,
    controller: TraySheetController? = null,
    /**
     * Picking a gift lowers the sheet to peek (the picked gift and Send), so what is behind it stays
     * in sight, for example a live stream. The handle (or a drag up) brings the grid back. Sheet only.
     */
    collapseOnSelect: Boolean = false,
    /**
     * The "Test mode" badge after the title. `null` (default) follows the token: it shows while a
     * [rememberGiftTrayHolder] reports `me.livemode == false` (a test key). `true` always shows it,
     * `false` never. With a holder of your own (a ViewModel) pass `GiftTrayState.testMode`.
     */
    testMode: Boolean? = null,
    testModeLabel: String = "Test mode",
    /**
     * Your [GiftTrayHolder]: the tray takes [gifts], [balance], [onSend] (`tray.send`) and the "Test mode"
     * badge from it, and recomposes when its state changes. Anything you pass yourself wins.
     */
    tray: GiftTrayHolder? = null,
    open: Boolean? = null,
    scrim: Boolean = false,
    scrimTap: ScrimTap = ScrimTap.Lower,
    onDismiss: (() -> Unit)? = null,
    /** The label of the "Send to" row (SPEC 21.3), shown when [tray] has two or more `receivers`. */
    sendToLabel: String = SEND_TO_LABEL,
) {
    val isOpen = open ?: tray?.isOpen ?: true
    // The receiver picker (SPEC 21): only with two or more sides; the holder keeps the pick.
    val receivers = tray?.receivers.orEmpty()
    val receiverRow: (@Composable () -> Unit)? =
        if (tray != null && receivers.size >= 2) {
            { ReceiverRow(receivers, tray.receiver, sendToLabel, isOpen, theme, currentGiftImageLoader()) { tray.selectReceiver(it) } }
        } else {
            null
        }
    // A bound app text field (SPEC 20.3): remember the keyboard height and take its place.
    val inputBound = tray?.inputBound == true
    if (tray != null && inputBound) RecordKeyboardHeight(tray)
    val keyboardPlace = inputBound && snaps.default == null
    // The open parameter, when given, is the host's to change; otherwise a dismissal closes the holder.
    val dismiss: () -> Unit = {
        if (open == null) tray?.close()
        onDismiss?.invoke()
    }
    val trayState = tray?.state?.collectAsState()?.value
    @Suppress("NAME_SHADOWING") val gifts: List<Gift> = gifts ?: trayState?.gifts ?: missingTrayData()
    @Suppress("NAME_SHADOWING") val balance: Long = balance ?: trayState?.balance ?: missingTrayData()
    @Suppress("NAME_SHADOWING")
    val onSend: (Gift) -> Unit = onSend ?: tray?.let { t -> fun(g: Gift) { t.send(g) } } ?: missingTrayData()
    val loader = currentGiftImageLoader()
    // An explicit testMode wins; else the tray state; else what a rememberGiftTrayHolder elsewhere reports.
    val badge = if (testMode ?: trayState?.testMode ?: GiftTrayTestMode.active) testModeLabel else null
    var selectedId by remember { mutableStateOf(defaultSelectedId ?: gifts.firstOrNull()?.id) }
    val selected = gifts.firstOrNull { it.id == selectedId } ?: gifts.firstOrNull()

    // The gift shown as selected (the person's choice, else the first one), for a debug "same as tray".
    LaunchedEffect(selected?.id) { onSelectedChange?.invoke(selected) }

    // Warm up the pictures: small icons for the whole tray, the big picture for the selected gift.
    LaunchedEffect(gifts) { for (g in gifts) g.iconUrl?.let { loader.prefetch(it) } }
    val bigPicture = selected?.animationUrl ?: selected?.iconUrl
    LaunchedEffect(bigPicture) { bigPicture?.let { loader.prefetch(it) } }

    val button = sendButtonState(gifts, selectedId, balance, disabled, canTopUp = onTopUp != null)
    val label =
        when (button.label) {
            SendButtonLabel.Send -> sendLabel
            SendButtonLabel.GetCoins -> getCoinsLabel
            SendButtonLabel.NotEnough -> notEnoughLabel
        }
    val columnCount = columns.coerceAtLeast(1)
    val press: () -> Unit = {
        if (selected != null) {
            when (button.action) {
                SendButtonAction.TopUp -> onTopUp?.invoke()
                SendButtonAction.Send -> onSend(selected)
                SendButtonAction.None -> Unit
            }
        }
    }

    // `sheet` is read once, like the other platforms.
    val asSheet = remember { sheet }
    if (!asSheet) {
        val shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
        Box(modifier.clip(shape).background(theme.surface).border(Dp.Hairline, theme.border, shape).testTag("gift-tray")) {
            if (bigPicture != null) Box(Modifier.align(Alignment.TopEnd)) { WarmUpPicture(bigPicture, loader) }
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(BODY_GAP_DP.dp)) {
                TrayHeader(title, badge, balance, coinName, onTopUp, theme)
                receiverRow?.invoke()
                Column(Modifier.heightIn(max = gridMaxHeight).verticalScroll(rememberScrollState())) {
                    GiftRows(gifts, columnCount, selected?.id, coinName, theme, loader, { selectedId = it }, null)
                }
                SendButton(button, label, selected, theme, press, Modifier.fillMaxWidth())
            }
        }
        return
    }

    SheetTray(
        gifts = gifts,
        balance = balance,
        selected = selected,
        onSelect = { selectedId = it },
        button = button,
        label = label,
        press = press,
        modifier = modifier,
        onTopUp = onTopUp,
        title = title,
        badge = badge,
        coinName = coinName,
        columns = columnCount,
        theme = theme,
        loader = loader,
        bigPicture = bigPicture,
        initialSnap = initialSnap,
        snaps = snaps,
        onSnapChange = onSnapChange,
        onInsetChange = onInsetChange,
        bottomInset = bottomInset,
        external = controller,
        collapseOnSelect = collapseOnSelect,
        open = isOpen,
        scrim = scrim,
        scrimTap = scrimTap,
        onDismiss = dismiss,
        keyboardPlace = keyboardPlace,
        keyboardHeight = tray?.keyboardHeight?.value?.toDouble(),
        receiverRow = receiverRow,
    )
}

/**
 * Records the keyboard's height on [tray] while an app text field is bound (SPEC 20.3): the IME inset's animation
 * target (the height the keyboard settles at, not the frames of its slide), kept by the holder when it is at least
 * [com.giftingstack.core.KEYBOARD_MIN_HEIGHT] dp. Needs an edge-to-edge window, where the IME inset reaches Compose.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RecordKeyboardHeight(tray: GiftTrayHolder) {
    val target = WindowInsets.imeAnimationTarget
    val density = LocalDensity.current
    LaunchedEffect(tray, target, density) {
        snapshotFlow { target.getBottom(density) }.collect { px -> tray.recordKeyboardHeight((px / density.density).dp) }
    }
}

private fun missingTrayData(): Nothing = throw IllegalArgumentException("GiftTray needs a tray, or gifts, balance and onSend.")

// --------------------------------------------------------------------------- the bottom sheet

@Composable
private fun SheetTray(
    gifts: List<Gift>,
    balance: Long,
    selected: Gift?,
    onSelect: (String) -> Unit,
    button: SendButtonState,
    label: String,
    press: () -> Unit,
    modifier: Modifier,
    onTopUp: (() -> Unit)?,
    title: String,
    badge: String?,
    coinName: String,
    columns: Int,
    theme: GiftingTheme,
    loader: GiftImageLoader,
    bigPicture: String?,
    initialSnap: SheetSnap,
    snaps: SheetSnapFractions,
    onSnapChange: ((SheetSnap) -> Unit)?,
    onInsetChange: ((Dp) -> Unit)?,
    bottomInset: Dp,
    external: TraySheetController?,
    collapseOnSelect: Boolean,
    open: Boolean,
    scrim: Boolean,
    scrimTap: ScrimTap,
    onDismiss: () -> Unit,
    keyboardPlace: Boolean,
    keyboardHeight: Double?,
    receiverRow: (@Composable () -> Unit)?,
) {
    val density = LocalDensity.current.density
    val controller = external ?: remember { TraySheetController(initialSnap) }
    // With collapseOnSelect a pick also lowers the sheet to peek.
    val pick: (String) -> Unit = { id ->
        onSelect(id)
        if (collapseOnSelect) controller.snapTo(SheetSnap.Peek)
    }
    SideEffect { if (external == null) controller.setOnSnapChange(onSnapChange) }
    val state by controller.state.collectAsState()
    val reduced = rememberSystemReducedMotion()

    // Closing puts the sheet back at its first state. It is invisible and `placed` is false by then,
    // so the move is a jump; the person's selected gift stays (SPEC 9.4).
    LaunchedEffect(open) { if (!open) controller.snapTo(initialSnap) }

    // Content floors, measured after layout and on every change (spec 9.1).
    var topPx by remember { mutableIntStateOf(0) }
    var footerPx by remember { mutableIntStateOf(0) }
    var rowPx by remember { mutableIntStateOf(0) }
    val topDp = topPx / density.toDouble()
    val footerDp = footerPx / density.toDouble()
    val rowDp = rowPx / density.toDouble()
    val rows = if (gifts.isEmpty()) 0 else ceil(gifts.size / columns.toDouble()).toInt()
    val gridTopDp = topDp + BODY_GAP_DP
    val peekMin = if (topPx > 0 && footerPx > 0) gridTopDp + footerDp else 0.0
    val defaultMin = peekMin + minOf(2, rows) * rowDp
    val contentHeight = peekMin + rows * rowDp

    val gridScroll = rememberScrollState()
    val screenHeightDp = LocalConfiguration.current.screenHeightDp

    BoxWithConstraints(modifier.fillMaxSize()) {
        val containerDp = (if (constraints.hasBoundedHeight) constraints.maxHeight / density else screenHeightDp * 1f).toDouble()
        // Until the header, the footer and a row are measured the container counts as 0, so the
        // sheet never shows heights computed from half a layout.
        val floorsReady = topPx > 0 && footerPx > 0 && (rows == 0 || rowPx > 0)
        // With a bound text field the default snap is the keyboard's place (SPEC 20.3); the floors still apply.
        val sheetSnaps = if (keyboardPlace) snaps.copy(default = keyboardPlaceSnap(keyboardHeight, containerDp)) else snaps
        LaunchedEffect(containerDp, sheetSnaps, peekMin, defaultMin, contentHeight, floorsReady) {
            controller.setLayout(SheetLayout(if (floorsReady) containerDp else 0.0, sheetSnaps, peekMin, defaultMin, contentHeight))
        }

        val measured = state.heights.expanded > 0.0
        // The displayed offset: it follows the finger while dragging and springs to the target
        // otherwise (critically damped, no overshoot; reduced motion jumps).
        val targetPx = (state.offset * density).toFloat()
        val shown = remember { Animatable(targetPx) }
        // The sheet is drawn only from `placed` on: a few frames after the first full measurement,
        // when the displayed offset has JUMPED to its target. Until then the heights are guesses
        // (the first frame after the measurement has the sheet fully open), and a spring from there
        // would show it flying up and coming down.
        var placed by remember { mutableStateOf(false) }
        val latestTarget by rememberUpdatedState(targetPx)
        LaunchedEffect(measured, open) {
            if (!measured || !open) {
                // The floors were lost (for example the first gifts arrived), or the tray is closed: settle again.
                placed = false
                return@LaunchedEffect
            }
            if (placed) return@LaunchedEffect
            // Two frames of rest so the measurements settle, then jump and show.
            withFrameNanos { }
            withFrameNanos { }
            shown.snapTo(latestTarget)
            placed = true
        }
        LaunchedEffect(targetPx, state.dragging, measured, placed, reduced) {
            when (sheetMove(placed, measured, state.dragging, reduced)) {
                SheetMove.Jump -> shown.snapTo(targetPx)
                SheetMove.Spring -> shown.animateTo(targetPx, spring(dampingRatio = 1f, stiffness = 320f))
            }
        }
        // One soft entrance for the whole sheet (surface, grid and Send bar together).
        val entrance = remember { Animatable(0f) }
        LaunchedEffect(placed, reduced) {
            when {
                !placed -> entrance.snapTo(0f)
                reduced -> entrance.snapTo(1f)
                else -> entrance.animateTo(1f, tween(SHEET_ENTRANCE_MS, easing = EaseOutCubicEasing))
            }
        }
        // Closed: the inset is 0, said once (also at the start when the tray starts closed).
        LaunchedEffect(open, if (open) state.visibleHeight else 0.0, open && measured) {
            if (!open) onInsetChange?.invoke(0.dp) else if (measured) onInsetChange?.invoke(state.visibleHeight.dp)
        }

        val expandedDp = state.heights.expanded.dp
        val hideGrid = state.snap == SheetSnap.Peek && !state.dragging
        val connection = remember(controller, gridScroll, density) { GridSheetConnection(controller, gridScroll, density) }
        val shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)

        // The dim: behind the sheet and the footer, above the screen content (SPEC 9.4).
        if (scrim) {
            TrayScrim(
                visible = scrimVisible(scrim, open, state.snap, placed),
                active = scrimTakesTouches(scrim, open, placed),
                reduced = reduced,
                onTap = {
                    when (scrimTapOutcome(scrim, scrimTap, open, controller.getState().snap)) {
                        ScrimTapOutcome.Lower -> controller.snapTo(SheetSnap.Peek)
                        ScrimTapOutcome.Dismiss -> onDismiss()
                        ScrimTapOutcome.Ignored -> Unit
                    }
                },
            )
        }
        // Closed: the sheet is not composed at all (invisible, no touches, out of the accessibility
        // tree). Its measurements, the selected gift and the grid scroll live above and are kept.
        if (!open) return@BoxWithConstraints
        // With a scrim the sheet and the footer take part in hit testing everywhere, so a tap on a
        // gap of the sheet does not fall through to the scrim.
        val blockTouches = if (scrim) Modifier.passiveTouchSink() else Modifier

        Box(
            Modifier.align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(if (measured) expandedDp else 0.dp)
                // Applied after the placement, to everything the sheet draws (the footer included).
                .graphicsLayer {
                    alpha = sheetEntranceAlpha(placed, entrance.value.toDouble(), reduced).toFloat()
                    translationY = (sheetEntranceRise(placed, entrance.value.toDouble(), reduced) * density).toFloat()
                }
                .clipToBounds()
                .testTag("gift-tray"),
        ) {
            if (bigPicture != null) Box(Modifier.align(Alignment.TopEnd)) { WarmUpPicture(bigPicture, loader) }
            // The body is laid out once at its tallest and only moved (translationY) afterwards.
            // While nothing is measured yet its children get unbounded height, so they report
            // their natural size.
            Column(
                Modifier.fillMaxWidth()
                    .wrapContentHeight(Alignment.Top, unbounded = true)
                    .graphicsLayer { translationY = shown.value }
                    .clip(shape)
                    .background(theme.surface)
                    .border(Dp.Hairline, theme.border, shape)
                    .then(blockTouches)
                    .padding(horizontal = 14.dp),
            ) {
                // The block above the grid: handle, header and the "Send to" row (SPEC 21.3). Its height is the
                // peek floor, so the row is in sight in every snap state. Only the handle and the header drag.
                Column(Modifier.onSizeChanged { topPx = it.height }) {
                    Column(Modifier.sheetDrag(controller, density)) {
                        SheetHandle(state.snap, controller, theme)
                        TrayHeader(title, badge, balance, coinName, onTopUp, theme)
                    }
                    if (receiverRow != null) {
                        Spacer(Modifier.height(RECEIVER_ROW_GAP_DP.dp))
                        receiverRow()
                    }
                }
                Spacer(Modifier.height(BODY_GAP_DP.dp))
                val gridHeight = if (measured) (state.heights.expanded - gridTopDp - footerDp).coerceAtLeast(0.0).dp else 0.dp
                Column(
                    Modifier.height(gridHeight)
                        .nestedScroll(connection)
                        .verticalScroll(gridScroll)
                        .then(if (hideGrid) Modifier.clearAndSetSemantics {} else Modifier),
                ) {
                    GiftRows(gifts, columns, selected?.id, coinName, theme, loader, pick) { rowPx = it }
                }
            }
            // The footer stays put at the bottom and is drawn above the body.
            SheetFooter(
                selected = selected,
                button = button,
                label = label,
                press = press,
                coinName = coinName,
                theme = theme,
                loader = loader,
                bottomInset = bottomInset,
                modifier = Modifier.align(Alignment.BottomCenter).wrapContentHeight(Alignment.Bottom, unbounded = true).onSizeChanged { footerPx = it.height }.then(blockTouches),
            )
        }
    }
}

/**
 * The dim behind the sheet (SPEC 9.4): black at [SCRIM_OPACITY], fades over [scrimFadeMs] (ease-out,
 * both directions). It takes touches and is the button "Close gift tray" only while [visible];
 * fading out or hidden it takes none and is out of the accessibility tree.
 */
@Composable
private fun TrayScrim(visible: Boolean, active: Boolean, reduced: Boolean, onTap: () -> Unit) {
    val alpha = remember { Animatable(0f) }
    LaunchedEffect(visible, reduced) {
        val target = if (visible) SCRIM_OPACITY.toFloat() else 0f
        val ms = scrimFadeMs(reduced)
        if (ms == 0) alpha.snapTo(target) else alpha.animateTo(target, tween(ms, easing = LinearOutSlowInEasing))
    }
    val source = remember { MutableInteractionSource() }
    Box(
        Modifier.fillMaxSize()
            .drawBehind { drawRect(Color.Black, alpha = alpha.value) }
            .then(
                if (active) {
                    Modifier.clickable(interactionSource = source, indication = null, role = Role.Button, onClick = onTap)
                        .semantics { contentDescription = "Close gift tray" }
                } else {
                    Modifier.clearAndSetSemantics {}
                },
            )
            .testTag("gift-scrim"),
    )
}

/** Takes part in hit testing without consuming anything, so touches do not fall through to the scrim below. */
private fun Modifier.passiveTouchSink(): Modifier =
    pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent() } }

/** The grid's nested-scroll rule (spec 9.1): decide once per gesture who takes the drag. */
private class GridSheetConnection(
    private val c: TraySheetController,
    private val scroll: ScrollState,
    private val density: Float,
) : NestedScrollConnection {
    private var owner: ScrollOwner? = null

    override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
        if (source != NestedScrollSource.UserInput) return Offset.Zero
        val dy = (available.y / density).toDouble()
        val o = owner ?: c.scrollOwner(dy, scroll.value.toDouble() / density).also { owner = it }
        if (o != ScrollOwner.Sheet) return Offset.Zero
        c.drag(dy)
        return Offset(0f, available.y)
    }

    override suspend fun onPreFling(available: Velocity): Velocity {
        val o = owner
        owner = null
        if (o != ScrollOwner.Sheet) return Velocity.Zero
        c.release((available.y / density).toDouble())
        return available
    }
}

/**
 * A press on the handle or the header that moves more than the touch slop is a drag of the sheet
 * (the slop already travelled is applied, so the sheet does not lag); a press below it stays a tap.
 * Mostly horizontal movement is not ours.
 */
private fun Modifier.sheetDrag(c: TraySheetController, density: Float): Modifier =
    pointerInput(c, density) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            val tracker = VelocityTracker()
            tracker.addPointerInputChange(down)
            val slop = viewConfiguration.touchSlop
            val first =
                awaitVerticalTouchSlopOrCancellation(down.id) { change, overSlop ->
                    tracker.addPointerInputChange(change)
                    c.dragStart()
                    c.drag(((overSlop + slop * sign(overSlop)) / density).toDouble())
                    change.consume()
                }
            if (first != null) {
                val finished =
                    verticalDrag(first.id) { change ->
                        tracker.addPointerInputChange(change)
                        c.drag((change.positionChange().y / density).toDouble())
                        change.consume()
                    }
                if (finished) c.release((tracker.calculateVelocity().y / density).toDouble()) else c.cancel()
            }
        }
    }

@Composable
private fun SheetHandle(snap: SheetSnap, c: TraySheetController, theme: GiftingTheme) {
    Box(
        Modifier.fillMaxWidth()
            .padding(top = 8.dp, bottom = 4.dp)
            .clickable(role = Role.Button) { c.toggle() }
            .semantics {
                contentDescription = "Gift tray"
                stateDescription = snap.wire
                expand("Show more gifts") { c.step(1); true }
                collapse("Show fewer gifts") { c.step(-1); true }
                customActions =
                    listOf(
                        CustomAccessibilityAction("Show more gifts") { c.step(1); true },
                        CustomAccessibilityAction("Show fewer gifts") { c.step(-1); true },
                    )
            }
            .testTag("gift-handle"),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(width = 36.dp, height = 5.dp).clip(RoundedCornerShape(3.dp)).background(theme.muted.copy(alpha = 0.7f)))
    }
}

@Composable
private fun SheetFooter(
    selected: Gift?,
    button: SendButtonState,
    label: String,
    press: () -> Unit,
    coinName: String,
    theme: GiftingTheme,
    loader: GiftImageLoader,
    bottomInset: Dp,
    modifier: Modifier,
) {
    val hairline = Dp.Hairline
    BoxWithConstraints(
        modifier.fillMaxWidth()
            .background(theme.surface)
            .drawBehind {
                val w = hairline.toPx().coerceAtLeast(1f)
                drawRect(theme.border, Offset.Zero, androidx.compose.ui.geometry.Size(w, size.height))
                drawRect(theme.border, Offset(size.width - w, 0f), androidx.compose.ui.geometry.Size(w, size.height))
            }
            .padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 14.dp + bottomInset),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (selected != null) {
                // Hidden from screen readers: the Send label already names the gift.
                Row(
                    Modifier.widthIn(max = this@BoxWithConstraints.maxWidth * 0.45f).clearAndSetSemantics {},
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    val icon = selected.iconUrl
                    if (icon != null) {
                        key(icon) { GiftPicture(icon, Modifier.size(36.dp), loader) }
                    } else {
                        Box(Modifier.size(36.dp).clip(RoundedCornerShape(10.dp)).background(theme.border))
                    }
                    Column(Modifier.weight(1f, fill = false)) {
                        BasicText(
                            selected.name,
                            style = TextStyle(color = theme.text, fontSize = 12.5.sp, fontWeight = FontWeight.Bold),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        PriceRow(selected.price, theme)
                    }
                }
            }
            SendButton(button, label, selected, theme, press, Modifier.weight(1f))
        }
    }
}

// ------------------------------------------------------------------ shared parts of both trays

/** The test mode badge (SPEC 9): the same colours on every platform, whatever the theme. */
private val TEST_BADGE_BACKGROUND = Color(0xFFF5A524)
private val TEST_BADGE_TEXT = Color(0xFF1A1300)

@Composable
private fun TrayHeader(
    title: String,
    badge: String?,
    balance: Long,
    coinName: String,
    onTopUp: (() -> Unit)?,
    theme: GiftingTheme,
) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        BasicText(
            title,
            modifier = Modifier.weight(1f),
            // One line, ends with "…" (SPEC 9): the badge and the balance never overlap it, and a long or
            // translated title never changes the peek height.
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            style = TextStyle(color = theme.text, fontSize = 15.sp, fontWeight = FontWeight.Bold),
        )
        if (badge != null) {
            BasicText(
                badge.uppercase(),
                maxLines = 1,
                softWrap = false,
                modifier =
                    Modifier.clip(RoundedCornerShape(6.dp))
                        .background(TEST_BADGE_BACKGROUND)
                        .padding(horizontal = 8.dp, vertical = 2.dp)
                        .testTag("gift-test-mode"),
                style =
                    TextStyle(
                        color = TEST_BADGE_TEXT,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.ExtraBold,
                        letterSpacing = 0.4.sp,
                    ),
            )
        }
        Row(
            Modifier.clip(CircleShape)
                .background(theme.background)
                .padding(horizontal = 10.dp, vertical = 4.dp)
                .semantics(mergeDescendants = true) { contentDescription = "Balance: ${formatCoins(balance)} $coinName" }
                .testTag("gift-balance"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            CoinDisc(theme.coin, 14.dp)
            CountUpText(balance, theme)
        }
        if (onTopUp != null) {
            BasicText(
                "+ Coins",
                modifier =
                    Modifier.clickable(role = Role.Button, onClick = onTopUp)
                        .semantics { contentDescription = "Get more $coinName" }
                        .testTag("gift-topup"),
                style = TextStyle(color = theme.coin, fontSize = 13.sp, fontWeight = FontWeight.Bold),
            )
        }
    }
}

/** Gap between the header and the "Send to" row of the sheet (in the fixed tray the body gap applies). */
private const val RECEIVER_ROW_GAP_DP = 10

/** The avatar of a side in the "Send to" row (SPEC 21.3). */
private val RECEIVER_AVATAR = 30.dp

/** Gap between the label and the first side and between sides (SPEC 21.3). */
private val RECEIVER_GAP = 8.dp

/**
 * The horizontal scroll offset that shows the whole chip [start]..[end] (content px) in a [viewport] px wide row
 * scrolled to [current], moving the least distance (SPEC 21.3): unchanged when the chip is already in sight; else its
 * start at the left edge when it is cut off on the left or wider than the row; else its end at the right edge.
 * Clamped to 0..[max].
 */
internal fun revealScrollOffset(current: Int, viewport: Int, start: Int, end: Int, max: Int): Int {
    val target =
        when {
            start < current || end - start > viewport -> start
            end > current + viewport -> end - viewport
            else -> current
        }
    return target.coerceIn(0, max.coerceAtLeast(0))
}

/** Where a side's chip was laid out in the row's content (px) and whether it was drawn as the selected one. */
private data class ChipBounds(val start: Int, val end: Int, val selected: Boolean)

/**
 * The "Send to" row (SPEC 21.3): the label, then every side, one line that scrolls sideways. A side is its 30 dp
 * avatar in a 2 dp ring of its colour; the [selectedId] side also has an outer ring in `text`, full opacity and its
 * name in `accent` after the avatar, the others are the avatar only at 0.55 (their name is their accessibility
 * label). Whenever the selection, the list or [open] changes, the row scrolls its own [ScrollState] the least
 * distance that shows the whole selected side (animated unless reduced motion); nothing else scrolls. A tap calls
 * [onSelect]. For screen readers a radio group labelled [label].
 */
@Composable
private fun ReceiverRow(
    receivers: List<TrayReceiver>,
    selectedId: String?,
    label: String,
    open: Boolean,
    theme: GiftingTheme,
    loader: GiftImageLoader,
    onSelect: (String) -> Unit,
) {
    val colors = sidePalette(theme, receivers.size, receivers.map { r -> r.color?.let { runCatching { tokenColor(it) }.getOrNull() } })
    val scroll = rememberScrollState()
    val reduced = rememberSystemReducedMotion()
    var viewport by remember { mutableIntStateOf(0) }
    // A new list starts with no bounds, so the reveal waits for the new layout.
    val bounds = remember(receivers) { mutableStateMapOf<String, ChipBounds>() }
    LaunchedEffect(selectedId, receivers, open) {
        if (!open || selectedId == null) return@LaunchedEffect
        // Wait for the layout that drew this side as the selected one (its name widens it).
        val chip = snapshotFlow { bounds[selectedId]?.takeIf { it.selected && viewport > 0 } }.filterNotNull().first()
        val target = revealScrollOffset(scroll.value, viewport, chip.start, chip.end, scroll.maxValue)
        if (target != scroll.value) {
            if (reduced) scroll.scrollTo(target) else scroll.animateScrollTo(target)
        }
    }
    Row(
        Modifier.fillMaxWidth()
            .onSizeChanged { viewport = it.width }
            .horizontalScroll(scroll)
            .semantics { contentDescription = label }
            .selectableGroup()
            .testTag("gift-send-to"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(RECEIVER_GAP),
    ) {
        BasicText(
            label,
            // The group carries the label for screen readers.
            modifier = Modifier.clearAndSetSemantics {},
            maxLines = 1,
            softWrap = false,
            style = TextStyle(color = theme.muted, fontSize = 12.sp, fontWeight = FontWeight.Bold),
        )
        receivers.forEachIndexed { i, r ->
            val selected = r.id == selectedId
            val (ring, ringText) = colors[i]
            Row(
                Modifier.heightIn(min = 44.dp)
                    // In the row's content coordinates (the scroll is applied outside its content).
                    .onPlaced { c ->
                        val x = c.positionInParent().x.roundToInt()
                        bounds[r.id] = ChipBounds(x, x + c.size.width, selected)
                    }
                    .alpha(if (selected) 1f else 0.55f)
                    .selectable(selected = selected, role = Role.RadioButton, onClick = { onSelect(r.id) })
                    .clearAndSetSemantics {
                        contentDescription = r.name
                        role = Role.RadioButton
                        this.selected = selected
                    }
                    .testTag("gift-receiver-${r.id}"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                // Selected: an outer ring in `text` (2 dp) around the side ring. The side ring (2 dp, side colour)
                // around the 30 dp avatar, so an unselected side is 34 dp wide.
                Box(
                    (if (selected) Modifier.border(2.dp, theme.text, CircleShape).padding(2.dp) else Modifier)
                        .border(2.dp, ring, CircleShape)
                        .padding(2.dp),
                ) {
                    val url = r.avatarUrl
                    if (url != null) {
                        Box(Modifier.size(RECEIVER_AVATAR).clip(CircleShape).background(ring)) {
                            key(url) { GiftPicture(url, Modifier.size(RECEIVER_AVATAR), loader) }
                        }
                    } else {
                        Box(Modifier.size(RECEIVER_AVATAR).clip(CircleShape).background(ring), contentAlignment = Alignment.Center) {
                            BasicText(initialOf(r.name), style = TextStyle(color = ringText, fontSize = 13.sp, fontWeight = FontWeight.Bold))
                        }
                    }
                }
                // Only the selected side shows its name, so four sides fit a 375 dp phone.
                if (selected) {
                    BasicText(
                        r.name,
                        modifier = Modifier.widthIn(max = 72.dp),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        style = TextStyle(color = theme.accent, fontSize = 12.sp, fontWeight = FontWeight.Bold),
                    )
                }
            }
        }
    }
}

/** The rows of cells; [onFirstRowHeight] reports the first row's height in px (for the sheet floors). */
@Composable
private fun GiftRows(
    gifts: List<Gift>,
    columns: Int,
    selectedId: String?,
    coinName: String,
    theme: GiftingTheme,
    loader: GiftImageLoader,
    onSelect: (String) -> Unit,
    onFirstRowHeight: ((Int) -> Unit)?,
) {
    gifts.chunked(columns).forEachIndexed { index, row ->
        Row(Modifier.fillMaxWidth().then(if (index == 0 && onFirstRowHeight != null) Modifier.onSizeChanged { onFirstRowHeight(it.height) } else Modifier)) {
            for (g in row) {
                GiftCell(
                    gift = g,
                    selected = g.id == selectedId,
                    coinName = coinName,
                    theme = theme,
                    loader = loader,
                    onSelect = { onSelect(g.id) },
                    modifier = Modifier.weight(1f),
                )
            }
            // Keep the cells of the last row as wide as the others.
            for (i in row.size until columns) Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun SendButton(
    button: SendButtonState,
    label: String,
    selected: Gift?,
    theme: GiftingTheme,
    press: () -> Unit,
    modifier: Modifier,
) {
    val pressable = button.pressable
    val bg = if (pressable) (if (button.broke) theme.coin else theme.accent) else theme.border
    Box(
        modifier.clip(CircleShape)
            .background(bg)
            .clickable(enabled = pressable, role = Role.Button, onClick = press)
            .padding(vertical = 13.dp)
            .clearAndSetSemantics {
                contentDescription = if (selected != null) "$label: ${selected.name}" else label
                role = Role.Button
                if (!pressable) disabled()
            }
            .testTag("gift-send"),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(
            label,
            style =
                TextStyle(
                    color = if (button.broke && pressable) theme.coinText else theme.accentText,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                ),
        )
    }
}

@Composable
private fun PriceRow(price: Long, theme: GiftingTheme) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        CoinDisc(theme.coin, 9.dp)
        BasicText(
            formatCoins(price),
            style = TextStyle(color = theme.text, fontSize = 11.5.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"),
        )
    }
}

@Composable
private fun CoinDisc(color: Color, size: Dp) {
    Box(Modifier.size(size).clip(CircleShape).background(color))
}

/** The balance counts up or down to its new value over 600 ms (ease-out cubic). */
@Composable
private fun CountUpText(value: Long, theme: GiftingTheme) {
    val anim = remember { Animatable(value.toFloat()) }
    LaunchedEffect(value) { anim.animateTo(value.toFloat(), tween(600, easing = EaseOutCubicEasing)) }
    BasicText(
        formatCoins(anim.value.roundToLong()),
        style = TextStyle(color = theme.text, fontSize = 13.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"),
    )
}

@Composable
private fun GiftCell(
    gift: Gift,
    selected: Boolean,
    coinName: String,
    theme: GiftingTheme,
    loader: GiftImageLoader,
    onSelect: () -> Unit,
    modifier: Modifier,
) {
    val description = "${gift.name}, ${formatCoins(gift.price)} $coinName"
    Box(
        modifier
            .padding(4.dp)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onSelect)
            .clearAndSetSemantics {
                contentDescription = description
                role = Role.RadioButton
                this.selected = selected
            }
            .testTag("gift-${gift.id}"),
    ) {
        Column(
            Modifier.fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .background(if (selected) theme.selected else theme.background)
                .border(1.5.dp, if (selected) theme.accent else Color.Transparent, RoundedCornerShape(14.dp))
                .padding(vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            // As the web tray: min(72 dp, 78 % of the cell), square.
            val iconModifier = Modifier.fillMaxWidth(ICON_CELL_FRACTION).widthIn(max = ICON_MAX_DP.dp).aspectRatio(1f)
            val icon = gift.iconUrl
            if (icon != null) {
                key(icon) { GiftPicture(icon, iconModifier, loader) }
            } else {
                Box(iconModifier.clip(RoundedCornerShape(12.dp)).background(theme.border))
            }
            PriceRow(gift.price, theme)
        }
    }
}

/** Tray icons are as wide as 78 % of the cell, at most 72 dp (the web tray's `min(72px, 78%)`). */
internal const val ICON_CELL_FRACTION = 0.78f
internal const val ICON_MAX_DP = 72

/**
 * Draws the selected gift's big picture where nobody can see it (1 % opacity, the size the effect
 * uses) so the first frame of the effect does not pay for uploading it to the GPU.
 */
@Composable
private fun WarmUpPicture(url: String, loader: GiftImageLoader) {
    key(url) {
        GiftPicture(
            url,
            Modifier.size(EFFECT_PICTURE_SIZE_DP.dp).graphicsLayer {
                alpha = 0.01f
                compositingStrategy = CompositingStrategy.ModulateAlpha
            }.semantics { contentDescription = "" }.testTag("gift-warmup"),
            loader,
        )
    }
}
