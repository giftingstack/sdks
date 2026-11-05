package com.giftingstack.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CollectionInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.collectionInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.giftingstack.core.DEFAULT_WALL_MAX
import com.giftingstack.core.GiftLabels
import com.giftingstack.core.GiftRef
import com.giftingstack.core.GiftWallApi
import com.giftingstack.core.GiftWallLoader
import com.giftingstack.core.GiftingException
import com.giftingstack.core.ReceivedGift
import com.giftingstack.core.WallChip
import com.giftingstack.core.WallOrder
import com.giftingstack.core.asGiftingError
import com.giftingstack.core.fill
import com.giftingstack.core.groupThousands
import com.giftingstack.core.wallChipLabel
import com.giftingstack.core.wallChipText
import com.giftingstack.core.wallChips
import com.giftingstack.core.wallSummaryText
import java.lang.ref.WeakReference
import java.util.WeakHashMap
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** `Sm`: icon 16, text 11, chip height 20. `Md` (default): icon 20, text 12.5, height 24 (SPEC 14.5). */
enum class GiftWallSize(val iconDp: Int, val textSp: Float, val heightDp: Int) {
    Sm(16, 11f, 20),
    Md(20, 12.5f, 24),
}

/** One loader per screen: every [GiftWall] below it shares its requests. Default: one per client. */
val LocalGiftWallLoader = compositionLocalOf<GiftWallLoader?> { null }

/**
 * The loader a [GiftWall] without an explicit one uses: one per client, shared by every wall of
 * the app, so a feed makes few requests. The client is held weakly.
 */
object GiftWallLoaders {
    private val scope by lazy { CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) }
    private val loaders = WeakHashMap<GiftWallApi, GiftWallLoader>()

    fun forClient(client: GiftWallApi): GiftWallLoader =
        synchronized(loaders) {
            loaders.getOrPut(client) {
                // The loader must not keep its own key alive, or the map entry would never go.
                val weak = WeakReference(client)
                GiftWallLoader(
                    query = { items -> weak.get()?.queryGiftWalls(items) ?: throw GiftingException(0, "client_gone", "The client is gone.") },
                    scope = scope,
                )
            }
        }
}

/**
 * What `renderChip` receives for one gift chip. [Default] draws the default icon and count, for a
 * chip you only want to wrap or to leave alone.
 */
class WallChipContext(
    val gift: GiftRef,
    /** The exact count. */
    val count: Int,
    /** The count as the default chip shows it (`1.2K`). */
    val countText: String,
    /** The resolved theme, so your chip can match the rest. */
    val theme: GiftingTheme,
    internal val default: @Composable () -> Unit,
) {
    /** Draws the default icon and count. */
    @Composable fun Default() = default()
}

private class WallResult(val id: String, val gifts: List<ReceivedGift>?, val arrived: Boolean)

private sealed interface WallShown {
    object Loading : WallShown

    object Failed : WallShown

    class Ready(val gifts: List<ReceivedGift>, val arrived: Boolean) : WallShown
}

/**
 * The gifts a post or a profile received, as a row of small chips: icon and count (SPEC 14.5).
 * Read-only unless you pass [onPressChip]. Nothing to show (no gifts, or the request failed) draws
 * nothing. Walls on one screen share their requests (see [GiftWallLoaders]).
 *
 * @param user the receiver's external id.
 * @param reference your content id, for example the post. Null: the profile wall.
 * @param max chips shown, the "+37" overflow chip included.
 * @param data counters you already have: no request is made.
 * @param refreshKey change it to fetch again, for example after the person sent a gift.
 * @param renderChip draws the inside of each gift chip yourself (the "+37" overflow chip is not
 *   passed). The wall still loads, orders and caps the chips and keeps the chip container, its
 *   spoken label and the press; a custom chip may be taller than the default. Null (default): the
 *   default icon and count. Call [WallChipContext.Default] to keep the default for some chips.
 * @param onPressChip makes the chips buttons (44 dp touch target); open your gift tray here.
 * @param onError failures only arrive here: a wall never shows an error.
 * @param reducedMotion default: the system "Remove animations" setting (no fade-in).
 * @param loader replace the shared loader (for example one per screen via [LocalGiftWallLoader]).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun GiftWall(
    client: GiftWallApi,
    user: String,
    modifier: Modifier = Modifier,
    reference: String? = null,
    max: Int = DEFAULT_WALL_MAX,
    order: WallOrder = WallOrder.Count,
    size: GiftWallSize = GiftWallSize.Md,
    data: List<ReceivedGift>? = null,
    refreshKey: Any? = null,
    renderChip: (@Composable (WallChipContext) -> Unit)? = null,
    onPressChip: ((GiftRef) -> Unit)? = null,
    onError: ((GiftingException) -> Unit)? = null,
    reducedMotion: Boolean? = null,
    theme: GiftingTheme = GiftingTheme(),
    labels: GiftLabels = GiftLabels(),
    loader: GiftWallLoader? = null,
) {
    val reduced = reducedMotion ?: rememberSystemReducedMotion()
    val sharedLoader = remember(client) { GiftWallLoaders.forClient(client) }
    val wallLoader = loader ?: LocalGiftWallLoader.current ?: sharedLoader
    val imageLoader = currentGiftImageLoader()
    val errorNow by rememberUpdatedState(onError)
    val id = "$user\u0000${reference.orEmpty()}"
    var result by remember { mutableStateOf<WallResult?>(null) }
    val lastKey = remember { arrayOf(refreshKey) }

    LaunchedEffect(wallLoader, user, reference, data, refreshKey) {
        if (data != null) return@LaunchedEffect
        val fresh = lastKey[0] != refreshKey
        lastKey[0] = refreshKey
        if (fresh) wallLoader.invalidate(user, reference)
        val cached = if (fresh) null else wallLoader.peek(user, reference)
        if (cached != null) {
            result = WallResult(id, cached, arrived = false)
            return@LaunchedEffect
        }
        try {
            result = WallResult(id, wallLoader.load(user, reference), arrived = true)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            result = WallResult(id, null, arrived = false)
            errorNow?.invoke(asGiftingError(e))
        }
    }

    val current = result
    val shown: WallShown =
        when {
            data != null -> WallShown.Ready(data, arrived = false)
            current != null && current.id == id ->
                if (current.gifts != null) WallShown.Ready(current.gifts, current.arrived) else WallShown.Failed
            else -> wallLoader.peek(user, reference)?.let { WallShown.Ready(it, arrived = false) } ?: WallShown.Loading
        }

    when (shown) {
        WallShown.Failed -> Unit
        WallShown.Loading -> {
            // Static skeleton chips, hidden from screen readers (no shimmer, so nothing to reduce).
            FlowRow(
                modifier.testTag("gift-wall-skeleton").clearAndSetSemantics {},
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                for (i in 0 until 3) {
                    androidx.compose.foundation.layout.Box(
                        Modifier.width((40 + i * 8).dp).height(size.heightDp.dp).clip(CircleShape).background(theme.border).testTag("gift-wall-skeleton-chip"),
                    )
                }
            }
        }
        is WallShown.Ready -> {
            val chips = wallChips(shown.gifts, max, order)
            if (chips.isEmpty()) {
                if (labels.emptyText.isNotEmpty()) {
                    BasicText(labels.emptyText, modifier, style = TextStyle(color = theme.muted, fontSize = size.textSp.sp, fontWeight = FontWeight.SemiBold))
                }
            } else {
                // A new answer fades in over 120 ms (not under reduced motion); one from the cache does not.
                val fade = remember(shown.gifts) { Animatable(if (shown.arrived && !reduced) 0f else 1f) }
                LaunchedEffect(fade) { if (fade.value < 1f) fade.animateTo(1f, tween(120)) }
                val tappable = onPressChip != null
                val rowSemantics =
                    if (tappable) {
                        Modifier.semantics { collectionInfo = CollectionInfo(rowCount = 1, columnCount = chips.size) }
                    } else {
                        // One element for a screen reader: "Gifts: 12 Roses, 3 Hearts, and 37 more".
                        val summary = wallSummaryText(chips, labels)
                        Modifier.clearAndSetSemantics { contentDescription = summary }
                    }
                FlowRow(
                    modifier.graphicsLayer { alpha = fade.value }.testTag("gift-wall").then(rowSemantics),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    for (chip in chips) {
                        WallChipView(chip, size, theme, labels, imageLoader, renderChip, onPressChip)
                    }
                }
            }
        }
    }
}

@Composable
private fun WallChipView(
    chip: WallChip,
    size: GiftWallSize,
    theme: GiftingTheme,
    labels: GiftLabels,
    imageLoader: GiftImageLoader,
    renderChip: (@Composable (WallChipContext) -> Unit)?,
    onPress: ((GiftRef) -> Unit)?,
) {
    val isGift = chip is WallChip.Gift
    val custom = chip is WallChip.Gift && renderChip != null
    val chipHeight = if (custom) Modifier.heightIn(min = size.heightDp.dp) else Modifier.height(size.heightDp.dp)
    var m: Modifier = chipHeight.clip(CircleShape).background(theme.surface).border(Dp.Hairline, theme.border, CircleShape)
    when {
        // A button of its own: "Rose, 12". The touch target grows to the platform minimum
        // (48 dp, at least the 44 dp of the document) without making the row taller.
        onPress != null && chip is WallChip.Gift -> {
            val label = wallChipLabel(chip, labels)
            m = m.clearAndSetSemantics {
                contentDescription = label
                role = Role.Button
                onClick { onPress(chip.gift); true }
            }.clickable { onPress(chip.gift) }
        }
        // The "+37" chip next to buttons is read, not pressed.
        onPress != null && chip is WallChip.Overflow -> {
            val label = fill(labels.wallMore, "n" to groupThousands(chip.count))
            m = m.clearAndSetSemantics { contentDescription = label }
        }
    }
    Row(
        m.padding(start = if (isGift) 4.dp else 8.dp, end = 8.dp)
            .testTag(if (chip is WallChip.Gift) "gift-wall-chip-${chip.gift.id}" else "gift-wall-overflow"),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val defaultContent: @Composable () -> Unit = {
            if (chip is WallChip.Gift) GiftChipIcon(chip.gift.iconUrl, size.iconDp.dp, theme, imageLoader)
            BasicText(
                wallChipText(chip, labels),
                style =
                    TextStyle(
                        color = if (isGift) theme.text else theme.muted,
                        fontSize = size.textSp.sp,
                        fontWeight = FontWeight.Bold,
                        fontFeatureSettings = TABULAR_NUMBERS,
                    ),
            )
        }
        if (chip is WallChip.Gift && renderChip != null) {
            renderChip(WallChipContext(chip.gift, chip.count, wallChipText(chip, labels), theme, defaultContent))
        } else {
            defaultContent()
        }
    }
}
