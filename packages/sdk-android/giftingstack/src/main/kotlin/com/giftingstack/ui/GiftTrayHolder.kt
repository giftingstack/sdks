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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.giftingstack.core.Gift
import com.giftingstack.core.GiftTrayController
import com.giftingstack.core.GiftEffectReceiver
import com.giftingstack.core.GiftTrayOptions
import com.giftingstack.core.GiftTrayState
import com.giftingstack.core.GiftTransaction
import com.giftingstack.core.GiftingApi
import com.giftingstack.core.GiftingException
import com.giftingstack.core.PlayOn
import com.giftingstack.core.InputSwapEvent
import com.giftingstack.core.InputSwapInput
import com.giftingstack.core.InputSwapTray
import com.giftingstack.core.KEYBOARD_MIN_HEIGHT
import com.giftingstack.core.TrayOpenState
import com.giftingstack.core.TrayReceiver
import com.giftingstack.core.resolveReceiver
import com.giftingstack.core.inputSwapStep
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
    open: Boolean? = null,
    onOpenChange: ((Boolean) -> Unit)? = null,
    receivers: List<TrayReceiver> = emptyList(),
    onReceiverChange: ((String) -> Unit)? = null,
) {
    val controller = GiftTrayController(options)
    val state: StateFlow<GiftTrayState> get() = controller.state

    // ------------------------------------------------------------ the receiver picker (SPEC 21)

    private var fallbackReceiver by mutableStateOf(options.receiver)
    private var receiverList by mutableStateOf(receivers)
    private var selectedReceiver by mutableStateOf<String?>(null)
    private var lastReceiver by mutableStateOf<String?>(null)
    private var onReceiverChangeCb = onReceiverChange
    private var toldReceiver: String = resolveReceiver(receivers.map { it.id }, null, null, options.receiver) ?: options.receiver

    /**
     * The sides the viewer can send to (SPEC 21): with two or more the tray shows a "Send to" row. Empty (the
     * default): the tray sends to the plain `receiver`, as before. A new list keeps the pick when it is still in the
     * list, else the next gift goes to the side gifted last, else the first. Snapshot state.
     */
    var receivers: List<TrayReceiver>
        get() = receiverList
        set(value) {
            if (value == receiverList) return
            receiverList = value
            if (selectedReceiver != null && value.none { it.id == selectedReceiver }) selectedReceiver = null
            tellReceiver()
        }

    /**
     * Who the next gift goes to (SPEC 21.2): the pick, else the side this tray gifted last, else the plain
     * `receiver` when it is a side, else the first side. Without [receivers] it is the plain `receiver`. Snapshot state.
     */
    val receiver: String
        get() = resolveReceiver(receiverList.map { it.id }, selectedReceiver, lastReceiver, fallbackReceiver) ?: fallbackReceiver

    /**
     * Picks the side the next gift goes to (a tap on the "Send to" row does the same). An id that is not in
     * [receivers] is ignored. Returns whether [id] is now the receiver. `onReceiverChange` is told when it changed.
     */
    fun selectReceiver(id: String): Boolean {
        if (receiverList.none { it.id == id }) return false
        selectedReceiver = id
        tellReceiver()
        return true
    }

    private fun tellReceiver() {
        val now = receiver
        if (now == toldReceiver) return
        toldReceiver = now
        onReceiverChangeCb?.invoke(now)
    }

    /** The callback of [rememberGiftTrayHolder]'s `onReceiverChange`, kept current. */
    internal fun setOnReceiverChange(cb: ((String) -> Unit)?) {
        onReceiverChangeCb = cb
    }

    private var onOpenChangeCb = onOpenChange

    /** True while the default open state is settled without telling `onOpenChange` (a field was bound first). */
    private var settlingDefault = false

    private val openState = TrayOpenState(open ?: true) { if (!settlingDefault) onOpenChangeCb?.invoke(it) }
    private var openFlag by mutableStateOf(open ?: true)

    /** No explicit `open` was given and nothing opened or closed the tray yet: a bound field may still close it. */
    private var defaultOpenPending = open == null

    private var binding: GiftTrayInputBinding? = null
    private var bindingCount by mutableStateOf(0)
    private var lastKeyboard by mutableStateOf<Dp?>(null)

    init {
        openState.subscribe { openFlag = openState.isOpen }
    }

    /**
     * Whether the tray is open (snapshot state: a composable that reads it recomposes). Starts true unless `open = false`,
     * or unless an app text field is bound with [giftTrayInput] and `open` was not given (SPEC 20.3).
     */
    val isOpen: Boolean get() = openFlag

    /** An app text field is bound with [giftTrayInput] (SPEC 20). Snapshot state. */
    val inputBound: Boolean get() = bindingCount > 0

    /**
     * The last keyboard height seen while a field was bound (at least [KEYBOARD_MIN_HEIGHT] dp), or null when none was
     * seen yet. It is kept when the keyboard goes down: the tray takes the keyboard's place. Snapshot state.
     */
    val keyboardHeight: Dp? get() = lastKeyboard

    /**
     * Shows the tray (the sheet comes back at its `initialSnap`). With a bound field the field loses focus and the
     * keyboard goes down first, so the two are never up together. Returns the new state.
     */
    fun open(): Boolean {
        defaultOpenPending = false
        if (!openState.isOpen) binding?.blur()
        return openState.open()
    }

    /** Hides the tray. Focus does not move. Returns the new state. */
    fun close(): Boolean {
        defaultOpenPending = false
        return openState.close()
    }

    /**
     * Open if closed, close if open: the host's Gift button is `tray.toggle()` (or [GiftButton]). With a bound field it
     * is the keyboard swap (`inputSwapStep` with the button event, SPEC 20.2): the keyboard goes down before the tray
     * opens, and the tray closes before the field gets focus and the keyboard back. Returns the new state.
     */
    fun toggle(): Boolean {
        defaultOpenPending = false
        val b = binding ?: return openState.toggle()
        val step = inputSwapStep(openState.isOpen, InputSwapEvent.Button)
        if (step.input == InputSwapInput.Blur) b.blur()
        applyTray(step.tray)
        // The field may have gone while the tray closed: focus only a field that is still bound.
        if (step.input == InputSwapInput.Focus) binding?.focus()
        return openState.isOpen
    }

    /** The bound field got focus (a tap on it, or the app focused it): an open tray closes; focus does not move. */
    fun onInputFocus() {
        val step = inputSwapStep(openState.isOpen, InputSwapEvent.InputFocus)
        if (step.tray != InputSwapTray.Keep) defaultOpenPending = false
        applyTray(step.tray)
    }

    /** Records a keyboard height; a value below [KEYBOARD_MIN_HEIGHT] dp is not a keyboard and is ignored. */
    fun recordKeyboardHeight(height: Dp) {
        if (height.value.isFinite() && height.value >= KEYBOARD_MIN_HEIGHT) lastKeyboard = height
    }

    /** The tray's height in the keyboard's place for a container [containerHeight] tall (SPEC 20.2). */
    fun keyboardPlaceHeight(containerHeight: Dp?): Dp =
        com.giftingstack.core.keyboardPlaceHeight(lastKeyboard?.value?.toDouble(), containerHeight?.value?.toDouble()).dp

    /**
     * Binds an app text field (what [giftTrayInput] does; also a seam for tests and custom fields). While bound, the
     * tray starts closed when no `open` was given, and [toggle] is the keyboard swap. Returns the function that unbinds
     * it; an unbound field is never focused again. A newer binding replaces an older one.
     */
    fun bindInput(input: GiftTrayInputBinding): () -> Unit {
        binding = input
        bindingCount++
        if (defaultOpenPending && openState.isOpen) {
            // SPEC 20.3: with a bound field the default of `open` is false. Nothing was shown or told yet.
            settlingDefault = true
            try {
                openState.close()
            } finally {
                settlingDefault = false
            }
        }
        defaultOpenPending = false
        var done = false
        return {
            if (!done) {
                done = true
                bindingCount--
                if (binding === input) binding = null
            }
        }
    }

    private fun applyTray(tray: InputSwapTray) {
        when (tray) {
            InputSwapTray.Open -> openState.open()
            InputSwapTray.Close -> openState.close()
            InputSwapTray.Keep -> Unit
        }
    }

    /** The callback of [rememberGiftTrayHolder]'s `onOpenChange`, kept current. */
    internal fun setOnOpenChange(cb: ((Boolean) -> Unit)?) {
        onOpenChangeCb = cb
    }

    /** Reloads the catalog and the balance, for example after the person buys coins. */
    fun refresh(): Job = scope.launch { controller.refresh() }

    /**
     * Sends one gift (optimistic balance, effect at the tap, refund on failure) to [receiver], the side picked in
     * the "Send to" row (SPEC 21). A successful send makes that side the default of the next list.
     */
    fun send(gift: Gift): Job {
        val to = receiver
        return scope.launch {
            if (controller.send(gift, to)) {
                lastReceiver = to
                tellReceiver()
            }
        }
    }

    fun setOptions(options: GiftTrayOptions) {
        controller.setOptions(options)
        if (fallbackReceiver != options.receiver) {
            fallbackReceiver = options.receiver
            tellReceiver()
        }
    }

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
 * @param open the first open state. Default `null`: open (a tray that exists is shown), or closed once an app text
 *   field is bound with [giftTrayInput] (SPEC 20.3). `false` starts it closed; the host's Gift button then opens it
 *   with `holder.toggle()` (SPEC 9.4). Read once.
 * @param onOpenChange called after every change of the open state (never for a call that changes nothing).
 * @param receivers a battle's sides (SPEC 21): with two or more the tray shows a "Send to" row and every gift goes
 *   to the picked side ([GiftTrayHolder.receiver]); [receiver] is only the fallback. `null` (default): the holder's
 *   own [GiftTrayHolder.receivers] are left alone (empty unless you set them).
 * @param onReceiverChange called with the id when the side the next gift goes to changes.
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
    open: Boolean? = null,
    onOpenChange: ((Boolean) -> Unit)? = null,
    receivers: List<TrayReceiver>? = null,
    onReceiverChange: ((String) -> Unit)? = null,
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
    val holder = remember { GiftTrayHolder(options, scope, open, onOpenChange, receivers.orEmpty(), onReceiverChange) }
    SideEffect {
        holder.setOnReceiverChange(onReceiverChange)
        holder.setOptions(options)
        holder.setOnOpenChange(onOpenChange)
        if (receivers != null) holder.receivers = receivers
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
