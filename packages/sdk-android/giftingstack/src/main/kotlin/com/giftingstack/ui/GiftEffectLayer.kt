package com.giftingstack.ui

import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.giftingstack.core.EffectPlayer
import com.giftingstack.core.EffectQuality
import com.giftingstack.core.EffectScheduler
import com.giftingstack.core.EffectSchedulerListener
import com.giftingstack.core.EffectSchedulerOptions
import com.giftingstack.core.EffectTier
import com.giftingstack.core.GiftEffectEvent
import com.giftingstack.core.NoticeData
import com.giftingstack.core.RecipesLoaders
import com.giftingstack.core.ScheduledEffect
import com.giftingstack.core.TierThresholds
import com.giftingstack.core.Timers
import com.giftingstack.core.monotonicNowMs

/**
 * Controls a [GiftEffectLayer]: `play`, `cancel`, `clear` (spec section 7.1). Create it with
 * [rememberGiftEffectLayerState] (or hold it in a ViewModel) and call it from the main thread.
 *
 * The queue, the caps, the combo and the notice text live in the shared [EffectScheduler]; this
 * class only turns what the scheduler says into Compose state.
 */
@Stable
class GiftEffectLayerState(
    comboWindowMs: Long? = null,
    now: () -> Long = ::monotonicNowMs,
) : EffectPlayer {
    val scheduler = EffectScheduler(comboWindowMs, now)

    internal val items = mutableStateListOf<ScheduledEffect>()
    internal val noticeStack = NoticeStack()
    internal var onEffectEnd: ((GiftEffectEvent, EffectTier) -> Unit)? = null

    init {
        scheduler.listener =
            object : EffectSchedulerListener {
                override fun enter(effect: ScheduledEffect) {
                    items.add(effect)
                }

                override fun exit(effect: ScheduledEffect) {
                    items.removeAll { it.id == effect.id }
                }

                override fun end(effect: ScheduledEffect) {
                    onEffectEnd?.invoke(effect.event, effect.recipe.tier)
                }

                override fun notice(notice: NoticeData, durationMs: Int) {
                    noticeStack.show(notice, durationMs)
                }

                override fun noticeHide() {
                    noticeStack.hideNewest()
                }

                override fun clear() {
                    items.clear()
                    noticeStack.clear()
                }
            }
    }

    /**
     * Shows a gift. Large gifts wait their turn; small and medium ones play at once, or show only
     * the notice when too many are on screen. Returns an id (1, 2, 3, ...) for [cancel].
     */
    override fun play(event: GiftEffectEvent): Int = scheduler.play(event)

    /** Takes back a gift that was shown too early, for example because its send failed. */
    override fun cancel(id: Int) = scheduler.cancel(id)

    /** Stops everything and forgets the queue and the combo run. */
    fun clear() = scheduler.clear()
}

@Composable
fun rememberGiftEffectLayerState(comboWindowMs: Long? = null): GiftEffectLayerState =
    remember { GiftEffectLayerState(comboWindowMs) }

/**
 * Put one of these over your screen, once, and call `play` on its [state] whenever a gift is sent
 * or received. It draws the effect by the gift's price and the "ayla sent X" notice with a combo
 * counter. It never takes touches.
 *
 * @param thresholds from which price a gift is medium or large.
 * @param quality [EffectQuality.Low] for slow phones: fewer sparks, no coin rain, no rays.
 * @param reducedMotion default: follows the system "Remove animations" setting (animator
 *   duration scale 0), live. Reduced motion shows only the notice.
 * @param origin where gifts start, as fractions of the layer.
 * @param pictureWaitMs longest wait for a gift's picture before its effect starts anyway.
 * @param pictureScale multiplier for the gift picture and the burst. Default: automatic, 1 on a
 *   phone, up to 2 in a big layer (a tablet, a landscape screen), never past 90 % of the short side.
 * @param noticeBottom distance of the notice from the bottom edge (above a tray).
 * @param remoteRecipes fetch effect numbers from `recipesUrl` (cached, refreshed at most every 6 h,
 *   spec section 13); `false` = embedded numbers only and no request.
 * @param recipesVersion pin a document: fetches `recipes.<version>.json`.
 * @param recipesUrl default `https://assets.giftingstack.com/recipes.json`.
 * @param onEffectEnd called when an effect played to its end (not for cancelled ones).
 */
@Composable
fun GiftEffectLayer(
    state: GiftEffectLayerState,
    modifier: Modifier = Modifier,
    thresholds: TierThresholds? = null,
    quality: EffectQuality = EffectQuality.High,
    reducedMotion: Boolean? = null,
    origin: Offset = Offset(0.5f, 0.86f),
    pictureWaitMs: Int = 300,
    pictureScale: Float? = null,
    noticeBottom: Dp = 150.dp,
    theme: GiftingTheme = GiftingTheme(),
    remoteRecipes: Boolean = true,
    recipesVersion: String? = null,
    recipesUrl: String? = null,
    onEffectEnd: ((GiftEffectEvent, EffectTier) -> Unit)? = null,
) {
    val systemReduced = rememberSystemReducedMotion()
    val reduced = reducedMotion ?: systemReduced
    // Remote effect numbers (spec section 13): the cached copy is used at once, a refresh runs in
    // the background, and a failure leaves the embedded numbers. `remoteRecipes = false` = no request.
    val recipesLoader = remember(remoteRecipes, recipesUrl, recipesVersion) { RecipesLoaders.forOptions(remoteRecipes, recipesUrl, recipesVersion) }
    LaunchedEffect(recipesLoader) { recipesLoader?.refresh() }
    SideEffect {
        state.scheduler.options =
            EffectSchedulerOptions(thresholds, quality, reduced, recipes = recipesLoader?.let { l -> { l.current()?.set } })
        state.onEffectEnd = onEffectEnd
    }

    // Every notice line has its own timer (run on this scope); they all stop when the layer leaves.
    val scope = rememberCoroutineScope()
    DisposableEffect(state, scope) {
        state.noticeStack.attach(Timers.forScope(scope))
        onDispose { state.noticeStack.detach() }
    }

    var size by remember { mutableStateOf(IntSize.Zero) }
    val loader = currentGiftImageLoader()
    Box(modifier.fillMaxSize().onSizeChanged { size = it }.testTag("gift-effect-layer")) {
        // The reference draws effects only once the layer has a size; gifts played before count
        // against the caps and start when the layer is measured.
        if (size.width > 0 && size.height > 0) {
            for (item in state.items) {
                key(item.id) {
                    EffectItem(
                        recipe = item.recipe,
                        image = item.event.gift.image,
                        layerSize = size,
                        origin = Offset(origin.x * size.width, origin.y * size.height),
                        theme = theme,
                        pictureWaitMs = pictureWaitMs,
                        pictureScale = pictureScale,
                        loader = loader,
                        onStart = { state.scheduler.started(item.id) },
                        onDone = { state.scheduler.finished(item.id) },
                    )
                }
            }
        }
        NoticeStackView(
            stack = state.noticeStack,
            bottom = noticeBottom,
            theme = theme,
            layerWidthPx = size.width,
            loader = loader,
        )
    }
}

private fun readReducedMotion(context: Context): Boolean =
    try {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    } catch (e: Exception) {
        false
    }

/** The system "Remove animations" setting (animator duration scale 0), followed live. */
@Composable
fun rememberSystemReducedMotion(): Boolean {
    val context = LocalContext.current
    var reduced by remember { mutableStateOf(readReducedMotion(context)) }
    DisposableEffect(context) {
        val observer =
            object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean) {
                    reduced = readReducedMotion(context)
                }
            }
        try {
            context.contentResolver.registerContentObserver(
                Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),
                false,
                observer,
            )
        } catch (_: Exception) {
            // Not observable here: the value read at start is used.
        }
        reduced = readReducedMotion(context)
        onDispose { context.contentResolver.unregisterContentObserver(observer) }
    }
    return reduced
}
