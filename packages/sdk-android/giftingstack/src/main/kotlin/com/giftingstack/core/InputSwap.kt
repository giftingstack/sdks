package com.giftingstack.core

import kotlin.math.floor
import kotlin.math.roundToInt

/**
 * The gift button in the app's message bar (spec section 20): the button closes the keyboard and
 * opens the tray in its place; a tap on the text field closes the tray and the keyboard comes
 * back. Pure: no UI, no clock; the platform layers blur, focus, open and close. Port of
 * `packages/sdk-js/src/core/inputSwap.ts`.
 */

/** What happened: the gift button (or `toggle()`), or the bound text field got focus. */
enum class InputSwapEvent { Button, InputFocus }

/** What to do with the tray. */
enum class InputSwapTray { Open, Close, Keep }

/** What to do with the text field (and the keyboard). */
enum class InputSwapInput { Blur, Focus, Keep }

/** What to do. Run [InputSwapInput.Blur] before [InputSwapTray.Open], and [InputSwapTray.Close] before [InputSwapInput.Focus]. */
data class InputSwapStep(val tray: InputSwapTray, val input: InputSwapInput)

/** The tray's height in the keyboard's place before any keyboard was seen. */
const val KEYBOARD_PLACE_FALLBACK = 300

/** A smaller inset is not a keyboard (an accessory bar, a hardware keyboard). */
const val KEYBOARD_MIN_HEIGHT = 120

/** The keyboard's place never takes more than this share of the container. */
const val KEYBOARD_PLACE_MAX_FRACTION = 0.6

/** One step of the keyboard swap (spec 20.2). */
fun inputSwapStep(open: Boolean, event: InputSwapEvent): InputSwapStep =
    when (event) {
        InputSwapEvent.Button ->
            if (open) InputSwapStep(InputSwapTray.Close, InputSwapInput.Focus) else InputSwapStep(InputSwapTray.Open, InputSwapInput.Blur)
        InputSwapEvent.InputFocus ->
            if (open) InputSwapStep(InputSwapTray.Close, InputSwapInput.Keep) else InputSwapStep(InputSwapTray.Keep, InputSwapInput.Keep)
    }

private fun Double?.finite(): Double? = this?.takeIf { it.isFinite() }

/**
 * How tall the tray is in the keyboard's place (spec 20.2), in dp.
 *
 * @param keyboardHeight the last keyboard height seen, or null/0 when none was seen yet.
 * @param containerHeight the height of the box the tray fills, or null/0 when unknown.
 */
fun keyboardPlaceHeight(keyboardHeight: Double?, containerHeight: Double?): Int {
    val kb = keyboardHeight.finite()
    var k = if (kb != null && kb >= KEYBOARD_MIN_HEIGHT) kb else KEYBOARD_PLACE_FALLBACK.toDouble()
    val c = containerHeight.finite()
    if (c != null && c > 0) k = minOf(k, floor(c * KEYBOARD_PLACE_MAX_FRACTION))
    // Math.round, like the reference (half up).
    return k.roundToInt()
}

/**
 * The sheet's `default` snap as a fraction of the container for the keyboard's place, or null
 * when the container is not measured yet.
 */
fun keyboardPlaceSnap(keyboardHeight: Double?, containerHeight: Double?): Double? {
    val h = containerHeight.finite() ?: return null
    if (h <= 0) return null
    return keyboardPlaceHeight(keyboardHeight, h) / h
}
