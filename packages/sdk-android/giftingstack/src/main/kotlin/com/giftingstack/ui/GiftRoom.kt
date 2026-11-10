package com.giftingstack.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.giftingstack.core.DEFAULT_MAX_REPLAY_AGE_MS
import com.giftingstack.core.DEFAULT_ROOMS_URL
import com.giftingstack.core.DEFAULT_THRESHOLDS
import com.giftingstack.core.BattleView
import com.giftingstack.core.EffectPlayer
import com.giftingstack.core.EffectTier
import com.giftingstack.core.GiftingApi
import com.giftingstack.core.RoomBattle
import com.giftingstack.core.RoomClient
import com.giftingstack.core.RoomClientOptions
import com.giftingstack.core.RoomGiftEvent
import com.giftingstack.core.RoomSocketFactory
import com.giftingstack.core.RoomState
import com.giftingstack.core.RoomStatus
import com.giftingstack.core.ROOM_HEARTBEAT_MS
import com.giftingstack.core.ROOM_REFRESH_JITTER_MS
import com.giftingstack.core.TierThresholds
import com.giftingstack.core.Timers
import com.giftingstack.core.Gift
import com.giftingstack.core.javaRoomSocketFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Settings of a [GiftRoom] (the same names as `UseGiftRoomOptions` in the React Native SDK). */
class GiftRoomOptions(
    /** Room id, `^[A-Za-z0-9_.:-]{1,64}$`. */
    val room: String,
    /**
     * The same token function you give `GiftingClient`. Your server mints the token with `rooms`
     * and `name` (SPEC 17.2).
     */
    val getToken: suspend (forceRefresh: Boolean) -> String,
    /** Loads the catalog once so room gifts show the big picture. */
    val client: GiftingApi? = null,
    /** Room gifts play here automatically. */
    val effects: (() -> EffectPlayer?)? = null,
    val onEvent: ((RoomGiftEvent) -> Unit)? = null,
    val onGap: (() -> Unit)? = null,
    /** Battle scores changed (SPEC 18.6): a new snapshot, or null when the round was removed. */
    val onBattle: ((RoomBattle?) -> Unit)? = null,
    /** Default true: your own gifts already played on tap. */
    val skipOwn: Boolean = true,
    val maxReplayAgeMs: Long = DEFAULT_MAX_REPLAY_AGE_MS,
    val minTier: EffectTier = EffectTier.Small,
    val thresholds: TierThresholds = DEFAULT_THRESHOLDS,
    val resolveName: ((String) -> String?)? = null,
    /**
     * The border colours of the two battle sides in the gift notice (SPEC 7.4): pass the same pair
     * as `GiftBattleBar(sideColors = ...)`. Null: the theme's accent and coin colour.
     */
    val sideColors: List<Color>? = null,
    /** Default `wss://rt.giftingstack.com`. */
    val url: String = DEFAULT_ROOMS_URL,
    /** The WebSocket transport. Default [javaRoomSocketFactory] (main-thread callbacks). */
    val socket: RoomSocketFactory? = null,
    val heartbeatMs: Long = ROOM_HEARTBEAT_MS,
    val now: () -> Long = System::currentTimeMillis,
    val random: () -> Double = Math::random,
    /** Lets a plain `ws://` url to a host that is not on this device through (default false: `wss://` and loopback only; SPEC 3.1). */
    val allowInsecure: Boolean = false,
)

/**
 * One gift room membership with the app lifecycle: a [RoomClient] plus catalog loading and
 * playing room gifts on the effect layer. Call everything from the main thread (a ViewModel's
 * `viewModelScope`, or [rememberGiftRoom]). [foreground] connects (or reconnects with resume),
 * [background] closes the socket without leaving; [leave] ends it for good.
 */
class GiftRoom(options: GiftRoomOptions, private val scope: CoroutineScope, timers: Timers = Timers.forScope(scope)) {
    @Volatile private var options: GiftRoomOptions = options
    private val timers = timers

    @Volatile private var catalog: List<Gift>? = null

    val controller = RoomClient(clientOptions())

    val state: StateFlow<RoomState> get() = controller.state

    /**
     * The battle side [user] is on now (SPEC 18.4): pass it to the tray as `receiverOf = room::receiverFor` so your own
     * gift says who got it too. Null outside a round.
     */
    fun receiverFor(user: String): com.giftingstack.core.GiftEffectReceiver? = controller.receiverFor(user)

    /** The room's battle round (SPEC 18.6), null when there is none. Headless: draw your own bar. */
    val battle: StateFlow<RoomBattle?> get() = controller.battle

    /**
     * [com.giftingstack.core.battleView] of the current round at the server's time now, null without a
     * round. Call it again on a timer while the round is open to count down.
     */
    fun battleView(): BattleView? = controller.getBattleView()

    private fun clientOptions(): RoomClientOptions {
        val o = options
        return RoomClientOptions(
            room = o.room,
            getToken = { refresh -> options.getToken(refresh) },
            socket = o.socket ?: javaRoomSocketFactory(allowInsecure = o.allowInsecure),
            scope = scope,
            timers = timers,
            url = o.url,
            skipOwn = o.skipOwn,
            maxReplayAgeMs = o.maxReplayAgeMs,
            minTier = o.minTier,
            thresholds = o.thresholds,
            getCatalog = { catalog },
            resolveName = { u -> options.resolveName?.invoke(u) },
            sideColors = o.sideColors?.map(::colorCss),
            onEvent = { e ->
                options.effects?.invoke()?.play(e.toEffect())
                options.onEvent?.invoke(e)
            },
            onGap = { options.onGap?.invoke() },
            onBattle = { b -> options.onBattle?.invoke(b) },
            heartbeatMs = o.heartbeatMs,
            now = o.now,
            random = o.random,
            refreshJitterMs = ROOM_REFRESH_JITTER_MS,
            allowInsecure = o.allowInsecure,
        )
    }

    /** Callbacks and filter settings are read when used, so they can change between calls. */
    fun setOptions(options: GiftRoomOptions) {
        this.options = options
        controller.setOptions(clientOptions())
    }

    /** Loads the catalog once (for the big picture); a failure just leaves the small icon. */
    fun loadCatalog() {
        val client = options.client ?: return
        scope.launch {
            try {
                catalog = client.getGifts()
            } catch (e: kotlin.coroutines.cancellation.CancellationException) {
                throw e
            } catch (e: Exception) {
                // The event's own icon is used instead.
            }
        }
    }

    /** The app is in the foreground: connect, or reconnect with `last` after a pause. */
    fun foreground() {
        if (controller.getState().status == RoomStatus.Idle) controller.start()
        controller.resume()
        // Like the web page becoming visible: skip a pending wait, or start again after a stop that the app can retry.
        controller.reconnectNow()
    }

    /**
     * Skips a pending reconnect wait (the network is back), or starts again after the room stopped with the
     * reason `retries_exhausted` or the code 4011 (SPEC 18.3).
     */
    fun reconnectNow() = controller.reconnectNow()

    /** The app went to the background: close the socket, keep the resume point, no retry. */
    fun background() = controller.pause()

    /** Leave the room for good (unmounting leaves too). */
    fun leave() = controller.leave()
}

/**
 * Keeps the screen in a gift room while it is composed (SPEC 18): room gifts play in [effects].
 * The socket closes when the screen goes to the background (the lifecycle drops below STARTED)
 * and reconnects, with resume, when it comes back. Another [room] leaves the old one; a null
 * [room] means "not in a room" (nothing connects). Send with `rememberGiftTrayHolder(roomId = ...)`.
 *
 * Collect `room.state` for the status and the viewer count.
 *
 * @param getToken the same function as your client's; the token needs `rooms` and `name`.
 * @param client optional: loads the catalog once so room gifts show the big picture.
 * @param socket the WebSocket transport; the default is [javaRoomSocketFactory].
 * @param allowInsecure lets a non-loopback `ws://` [url] through (default false: `wss://`, or `ws://` to
 *   localhost, 127.0.0.1, ::1 and 10.0.2.2 only). Throws `IllegalArgumentException` for a refused [url].
 */
@Composable
fun rememberGiftRoom(
    room: String?,
    getToken: suspend (forceRefresh: Boolean) -> String,
    client: GiftingApi? = null,
    effects: GiftEffectLayerState? = null,
    onEvent: ((RoomGiftEvent) -> Unit)? = null,
    onGap: (() -> Unit)? = null,
    onBattle: ((RoomBattle?) -> Unit)? = null,
    skipOwn: Boolean = true,
    maxReplayAgeMs: Long = DEFAULT_MAX_REPLAY_AGE_MS,
    minTier: EffectTier = EffectTier.Small,
    thresholds: TierThresholds = DEFAULT_THRESHOLDS,
    resolveName: ((String) -> String?)? = null,
    sideColors: List<Color>? = null,
    url: String = DEFAULT_ROOMS_URL,
    socket: RoomSocketFactory? = null,
    allowInsecure: Boolean = false,
): GiftRoom {
    val scope = rememberCoroutineScope()
    val inRoom = room != null
    val options =
        GiftRoomOptions(
            room = room ?: "",
            getToken = getToken,
            client = client,
            effects = effects?.let { e -> { e } },
            onEvent = onEvent,
            onGap = onGap,
            onBattle = onBattle,
            skipOwn = skipOwn,
            maxReplayAgeMs = maxReplayAgeMs,
            minTier = minTier,
            thresholds = thresholds,
            resolveName = resolveName,
            sideColors = sideColors,
            url = url,
            socket = socket,
            allowInsecure = allowInsecure,
        )
    // A new room (or none) is a new membership; the old one leaves in onDispose below.
    val holder = remember(room) { GiftRoom(options, scope) }
    SideEffect { holder.setOptions(options) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(holder, lifecycle) {
        val observer =
            LifecycleEventObserver { _, event ->
                if (!inRoom) return@LifecycleEventObserver
                when (event) {
                    Lifecycle.Event.ON_START -> holder.foreground()
                    Lifecycle.Event.ON_STOP -> holder.background()
                    else -> Unit
                }
            }
        // Replays the events up to the current state: a screen that is already started connects now,
        // one composed in the background waits for ON_START.
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            holder.leave()
        }
    }
    LaunchedEffect(holder, client) { if (inRoom) holder.loadCatalog() }
    return holder
}

