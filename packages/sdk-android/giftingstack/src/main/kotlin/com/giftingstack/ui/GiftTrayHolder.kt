package com.giftingstack.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import com.giftingstack.core.Gift
import com.giftingstack.core.GiftTrayController
import com.giftingstack.core.GiftEffectReceiver
import com.giftingstack.core.GiftTrayOptions
import com.giftingstack.core.GiftTrayState
import com.giftingstack.core.GiftTransaction
import com.giftingstack.core.GiftingApi
import com.giftingstack.core.GiftingException
import com.giftingstack.core.PlayOn
import com.giftingstack.core.TrayOpenState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * The state holder of a tray: a thin, ViewModel-friendly wrapper around [GiftTrayController]
 * that runs `refresh` and `send` in a scope you give it. In a ViewModel pass `viewModelScope`
 * (which runs on the main thread) and call [dispose] from `onCleared`; in Compose use
 * [rememberGiftTrayHolder].
 *
 * Pass the holder to the tray: `GiftTray(tray = holder)` takes the gifts, the balance, Send and the "Test mode"
 * badge ([GiftTrayState.testMode]) from [state]. (Or collect [state] with `collectAsState` and pass the fields
 * yourself; the badge then follows any holder made by [rememberGiftTrayHolder], or your `testMode`.)
 */
class GiftTrayHolder(
    options: GiftTrayOptions,
    private val scope: CoroutineScope,
    open: Boolean = true,
    onOpenChange: ((Boolean) -> Unit)? = null,
) {
    val controller = GiftTrayController(options)
    val state: StateFlow<GiftTrayState> get() = controller.state

    private val openState = TrayOpenState(open, onOpenChange)
    private var openFlag by mutableStateOf(open)

    init {
        openState.subscribe { openFlag = openState.isOpen }
    }

    /** Whether the tray is open (snapshot state: a composable that reads it recomposes). Starts true unless `open = false`. */
    val isOpen: Boolean get() = openFlag

    /** Shows the tray (the sheet comes back at its `initialSnap`). Returns the new state. */
    fun open(): Boolean = openState.open()

    /** Hides the tray. Returns the new state. */
    fun close(): Boolean = openState.close()

    /** Open if closed, close if open: the host's Gift button is `tray.toggle()`. Returns the new state. */
    fun toggle(): Boolean = openState.toggle()

    /** The callback of [rememberGiftTrayHolder]'s `onOpenChange`, kept current. */
    internal fun setOnOpenChange(cb: ((Boolean) -> Unit)?) {
        openState.onChange = cb
    }

    /** Reloads the catalog and the balance, for example after the person buys coins. */
    fun refresh(): Job = scope.launch { controller.refresh() }

    /** Sends one gift (optimistic balance, effect at the tap, refund on failure). */
    fun send(gift: Gift): Job = scope.launch { controller.send(gift) }

    fun setOptions(options: GiftTrayOptions) = controller.setOptions(options)

    fun attach() = controller.attach()

    /** The screen is gone: answers that arrive later change nothing. */
    fun dispose() = controller.dispose()
}

/**
 * Whether the app runs on a test key, as reported by the holders that [rememberGiftTrayHolder]
 * made (`me.livemode == false`). [GiftTray] shows its "Test mode" badge from this when its
 * `testMode` parameter is null. A key belongs to the whole app, so one report is enough; the
 * entry goes away with its holder. Snapshot state: a change recomposes the trays that read it.
 */
internal object GiftTrayTestMode {
    private val reports = mutableStateMapOf<Any, Boolean>()

    /** True while any live holder has reported a test token. */
    val active: Boolean get() = reports.values.any { it }

    fun report(owner: Any, testMode: Boolean) {
        if (testMode) reports[owner] = true else reports.remove(owner)
    }

    fun forget(owner: Any) {
        reports.remove(owner)
    }
}

/**
 * A [GiftTrayHolder] for this composition: loads the catalog when it is created (and again when
 * [client] changes), warms the picture cache, plays every sent gift on [effects] and stops
 * listening when it leaves the composition.
 *
 * @param effects the layer state shown by your `GiftEffectLayer`.
 * @param playOn `Tap` plays the effect at the tap and takes it back on failure; `Success`
 *   waits for the server.
 * @param roomId send every gift into this room (SPEC 17.1); pair it with [rememberGiftRoom].
 * @param receiverOf in a battle, `room::receiverFor`: your own gift then says who got it too (SPEC 18.4).
 * @param open the first open state (default true: a tray that exists is shown). `false` starts it closed; the
 *   host's Gift button then opens it with `holder.toggle()` (SPEC 9.4). Read once.
 * @param onOpenChange called after every change of the open state (never for a call that changes nothing).
 *
 * While the token is a test token (`me.livemode == false`) every `GiftTray` below that does not pass
 * `testMode` shows the "Test mode" badge.
 */
@Composable
fun rememberGiftTrayHolder(
    client: GiftingApi,
    receiver: String,
    effects: GiftEffectLayerState? = null,
    playOn: PlayOn = PlayOn.Tap,
    reference: String? = null,
    roomId: String? = null,
    receiverOf: ((String) -> GiftEffectReceiver?)? = null,
    onSent: ((GiftTransaction) -> Unit)? = null,
    onError: ((GiftingException) -> Unit)? = null,
    open: Boolean = true,
    onOpenChange: ((Boolean) -> Unit)? = null,
): GiftTrayHolder {
    val scope = rememberCoroutineScope()
    val loader = currentGiftImageLoader()
    val options =
        GiftTrayOptions(
            client = client,
            receiver = receiver,
            effects = effects?.let { e -> { e } },
            playOn = playOn,
            reference = reference,
            roomId = roomId,
            receiverOf = receiverOf,
            onSent = onSent,
            onError = onError,
            prefetch = { loader.prefetch(it) },
        )
    val holder = remember { GiftTrayHolder(options, scope, open, onOpenChange) }
    SideEffect {
        holder.setOptions(options)
        holder.setOnOpenChange(onOpenChange)
    }
    DisposableEffect(holder) {
        holder.attach()
        onDispose {
            holder.dispose()
            GiftTrayTestMode.forget(holder)
        }
    }
    // `GiftTray(testMode = null)` follows this (the token is a test token: show "Test mode").
    LaunchedEffect(holder) {
        holder.state.map { it.testMode }.distinctUntilChanged().collect { GiftTrayTestMode.report(holder, it) }
    }
    LaunchedEffect(holder, client) { holder.refresh() }
    return holder
}
