package com.giftingstack.core

import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** The part of an effect layer the tray needs. */
interface EffectPlayer {
    fun play(event: GiftEffectEvent): Int

    fun cancel(id: Int)
}

enum class PlayOn { Tap, Success }

class GiftTrayOptions(
    val client: GiftingApi,
    /** Who gets the gifts: the owner of the post or profile on screen. */
    val receiver: String,
    /** Returns the effect layer that shows each gift, if there is one right now. */
    val effects: (() -> EffectPlayer?)? = null,
    /** `Tap` (default): play at the tap, take back on failure. `Success`: play after the server. */
    val playOn: PlayOn = PlayOn.Tap,
    /** Your own context id, for example the post id. Saved with each gift. */
    val reference: String? = null,
    /** A room id (SPEC 17.1): every send goes into that room, everyone in it sees the effect. */
    val roomId: String? = null,
    /**
     * In a battle, the side a receiver is on (`room.controller.receiverFor`, SPEC 18.4): the user's own gift
     * then says who got it, like the room's gifts of the others. Null outside a battle.
     */
    val receiverOf: ((String) -> GiftEffectReceiver?)? = null,
    val onSent: ((GiftTransaction) -> Unit)? = null,
    val onError: ((GiftingException) -> Unit)? = null,
    /** Starts downloading a picture. Called for every `icon_url` once the catalog loads (not the big pictures, SPEC 8 step 2). */
    val prefetch: ((String) -> Unit)? = null,
)

data class GiftTrayState(
    val gifts: List<Gift> = emptyList(),
    val balance: Long = 0,
    /** The signed-in user, as named by the token. */
    val user: String? = null,
    val loading: Boolean = true,
    /** The last problem: loading failed, or the last send failed. Cleared by the next success. */
    val error: GiftingException? = null,
    /** The server said the token is a test token (`me.livemode == false`): show "Test mode". */
    val testMode: Boolean = false,
)

/** Any failure as a [GiftingException]. Anything else becomes status 0, `unknown_error`. */
fun asGiftingError(err: Throwable): GiftingException =
    err as? GiftingException
        ?: GiftingException(0, "unknown_error", err.message ?: "Something went wrong.")

/**
 * Everything a gift tray does besides drawing (spec section 8): loads the catalog and the
 * balance, sends gifts, keeps the balance right while the person taps fast (combos) and plays
 * the effect for each gift. Port of `packages/sdk-js/src/core/tray.ts`.
 *
 * Call `refresh` and `send` from the UI thread (for example `viewModelScope`, which is
 * `Dispatchers.Main.immediate`); client calls leave the main thread by themselves.
 */
class GiftTrayController(options: GiftTrayOptions) {
    @Volatile private var options: GiftTrayOptions = options
    private val _state = MutableStateFlow(GiftTrayState())
    val state: StateFlow<GiftTrayState> = _state.asStateFlow()

    /** Sends that have not finished yet. */
    private val pending = AtomicInteger(0)
    @Volatile private var alive = true

    /** Callbacks and settings are read when used, so they can change between calls. */
    fun setOptions(options: GiftTrayOptions) {
        this.options = options
    }

    /** The screen is (back) on. */
    fun attach() {
        alive = true
    }

    /** The screen is gone: answers that arrive later change nothing. */
    fun dispose() {
        alive = false
    }

    /** Reloads the catalog and the balance, for example after the person buys coins. */
    suspend fun refresh() {
        val o = options
        try {
            val (list, me) =
                coroutineScope {
                    val gifts = async { o.client.getGifts() }
                    val me = async { o.client.getMe() }
                    gifts.await() to me.await()
                }
            if (!alive) return
            // Download the small icons now (SPEC 8 step 2). The big picture of the selected gift is the tray's job; the others load when they first play.
            for (g in list) {
                g.iconUrl?.let { options.prefetch?.invoke(it) }
            }
            _state.update {
                it.copy(
                    gifts = list.sortedBy { g -> g.sortOrder },
                    balance = me.balance,
                    user = me.user,
                    error = null,
                    testMode = me.livemode == false,
                )
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (alive) _state.update { it.copy(error = asGiftingError(e)) }
        } finally {
            if (alive) _state.update { it.copy(loading = false) }
        }
    }

    /** After a burst of taps the server's number is the truth. */
    private suspend fun reconcile(client: GiftingApi) {
        try {
            val me = client.getMe()
            if (alive && pending.get() == 0) _state.update { it.copy(balance = me.balance) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // The optimistic number stays; the next send or refresh corrects it.
        }
    }

    /**
     * Sends one gift (optimistic): the coins are taken at once, the effect plays at the tap or
     * after the server, and a failure gives the coins back. Does not check affordability: the
     * Send button does (see [sendButtonState]).
     */
    suspend fun send(gift: Gift) {
        val o = options
        val client = o.client
        val user = _state.value.user
        pending.incrementAndGet()
        // Take the coins at once so the number moves with every tap.
        _state.update { it.copy(balance = it.balance - gift.price) }
        fun show(sender: String, quantity: Int): Int? {
            val battleReceiver =
                try {
                    o.receiverOf?.invoke(o.receiver)
                } catch (e: Exception) {
                    null // app code: never let it break a send
                }
            return o.effects?.invoke()?.play(
                GiftEffectEvent(
                    gift =
                        EffectGift(
                            id = gift.id,
                            name = gift.name,
                            price = gift.price,
                            image = gift.animationUrl ?: gift.iconUrl,
                            icon = gift.iconUrl,
                        ),
                    sender = sender,
                    quantity = quantity,
                    receiver = battleReceiver,
                ),
            )
        }
        val early = o.playOn == PlayOn.Tap
        val shownId: Int? = if (early) show(user ?: "You", 1) else null
        try {
            val tx = client.sendGift(SendGiftInput(receiver = o.receiver, giftId = gift.id, reference = o.reference, roomId = o.roomId))
            if (!alive) return
            _state.update { it.copy(error = null) }
            // App code from here on: a throwing callback must never look like a failed send (the coins are
            // spent), so it must not reach the catch below that refunds the optimistic balance.
            if (!early) safe { show(user ?: tx.sender, tx.quantity) }
            safe { options.onSent?.invoke(tx) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val err = asGiftingError(e)
            // The gift was shown before the server answered: take it back.
            if (shownId != null) o.effects?.invoke()?.cancel(shownId)
            if (alive) _state.update { it.copy(balance = it.balance + gift.price, error = err) }
            safe { options.onError?.invoke(err) }
        } finally {
            if (pending.decrementAndGet() == 0) reconcile(client)
        }
    }
}

/** Runs an app callback; whatever it throws is ignored (SPEC 8). */
private inline fun safe(fn: () -> Unit) {
    try {
        fn()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        // The app's problem, not the send's.
    }
}

enum class SendButtonLabel(val wire: String) {
    Send("send"),
    GetCoins("getCoins"),
    NotEnough("notEnough"),
}

enum class SendButtonAction(val wire: String) {
    Send("send"),
    TopUp("topUp"),
    None("none"),
}

data class SendButtonState(
    /** The gift the tray shows as selected, or null for an empty tray. */
    val selectedId: String?,
    /** The selected gift costs more than the balance. */
    val broke: Boolean,
    val label: SendButtonLabel,
    val pressable: Boolean,
    /** What a press does. */
    val action: SendButtonAction,
)

/**
 * The tray's Send button. The selected gift is the one with [selectedId], else the first one.
 * Too expensive: "Get coins" (opens the store) when [canTopUp], else "Not enough coins" (off).
 */
fun sendButtonState(
    gifts: List<Gift>,
    selectedId: String?,
    balance: Int,
    disabled: Boolean = false,
    canTopUp: Boolean = false,
): SendButtonState = sendButtonState(gifts, selectedId, balance.toLong(), disabled, canTopUp)

/** Same, with a 64-bit balance (what [GiftTrayState.balance] is). */
fun sendButtonState(
    gifts: List<Gift>,
    selectedId: String?,
    balance: Long,
    disabled: Boolean = false,
    canTopUp: Boolean = false,
): SendButtonState {
    val selected = gifts.firstOrNull { it.id == selectedId } ?: gifts.firstOrNull()
    val broke = selected != null && selected.price > balance
    val canSend = selected != null && !disabled && !broke
    val label =
        if (broke) {
            if (canTopUp) SendButtonLabel.GetCoins else SendButtonLabel.NotEnough
        } else {
            SendButtonLabel.Send
        }
    val pressable = canSend || (broke && canTopUp && !disabled)
    return SendButtonState(
        selectedId = selected?.id,
        broke = broke,
        label = label,
        pressable = pressable,
        action =
            when {
                !pressable -> SendButtonAction.None
                broke -> SendButtonAction.TopUp
                else -> SendButtonAction.Send
            },
    )
}
