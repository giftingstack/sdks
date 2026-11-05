/// Injectable timers for the pure controllers (fixtures drive a fake clock).
library;

import 'dart:async';

/// Starts a timer: calls the function after the given milliseconds. Returns
/// anything; hand it to a [TimerCanceller] to stop the timer.
typedef TimerStarter = Object? Function(void Function() fn, int ms);

/// Cancels what a [TimerStarter] returned.
typedef TimerCanceller = void Function(Object? handle);

/// The default [TimerStarter]: a `dart:async` [Timer].
Object? startTimer(void Function() fn, int ms) =>
    Timer(Duration(milliseconds: ms), fn);

/// The default [TimerCanceller].
void cancelTimer(Object? handle) {
  if (handle is Timer) handle.cancel();
}

/// Wall clock in ms, the default `now` of the controllers.
int wallClockMs() => DateTime.now().millisecondsSinceEpoch;
