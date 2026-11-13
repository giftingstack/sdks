package com.giftingstack.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController

/**
 * What a [GiftTrayHolder] does with a bound text field (SPEC 20.3). [giftTrayInput] makes one from the field's focus
 * and the keyboard controller; implement it yourself for a custom field or a test.
 */
interface GiftTrayInputBinding {
    /** Take the focus away from the field and hide the keyboard. */
    fun blur()

    /** Focus the field and show the keyboard. */
    fun focus()
}

/**
 * Binds this text field to the gift tray (SPEC 20): the field of the app's message bar, next to a [GiftButton].
 *
 * ```
 * TextField(value, onValueChange, modifier = Modifier.weight(1f).giftTrayInput(holder))
 * GiftButton(tray = holder)
 * ```
 *
 * The gift button closes the keyboard and opens the tray in its place; a tap on the field closes the tray and the
 * keyboard comes back. While bound, the holder starts closed (unless you gave it `open`), `toggle()` is that swap,
 * `open()` hides the keyboard first, and the sheet's default height is the last keyboard height seen. The binding ends
 * when the field leaves the composition; a field that is gone is never focused.
 */
@Composable
fun Modifier.giftTrayInput(holder: GiftTrayHolder): Modifier {
    val requester = remember { FocusRequester() }
    val keyboard by rememberUpdatedState(LocalSoftwareKeyboardController.current)
    val focusManager by rememberUpdatedState(LocalFocusManager.current)
    val focused = remember { booleanArrayOf(false) }
    DisposableEffect(holder, requester) {
        var alive = true
        val unbind =
            holder.bindInput(
                object : GiftTrayInputBinding {
                    override fun blur() {
                        if (focused[0]) focusManager.clearFocus()
                        keyboard?.hide()
                    }

                    override fun focus() {
                        if (!alive) return
                        // A requester whose field is not laid out (yet, or any more) throws: nothing to focus then.
                        val ok = runCatching { requester.requestFocus() }.isSuccess
                        if (ok) keyboard?.show()
                    }
                },
            )
        onDispose {
            alive = false
            unbind()
        }
    }
    return this.focusRequester(requester).onFocusChanged { state ->
        val was = focused[0]
        focused[0] = state.isFocused
        if (state.isFocused && !was) holder.onInputFocus()
    }
}
