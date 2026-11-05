package com.giftingstack.core

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * One-shot timers for the controllers. Injected so tests can drive a fake clock; the default runs
 * on the controller's scope (the main thread when you pass `viewModelScope` or a Compose scope).
 */
class Timers(
    /** Runs [fn] once after [delayMs]; returns a handle for [clear]. */
    val set: (delayMs: Long, fn: () -> Unit) -> Any,
    val clear: (handle: Any) -> Unit,
) {
    companion object {
        /** `delay` + `launch` on [scope]; clearing cancels the job. */
        fun forScope(scope: CoroutineScope): Timers =
            Timers(
                set = { ms, fn -> scope.launch { delay(ms); fn() } },
                clear = { (it as Job).cancel() },
            )
    }
}
