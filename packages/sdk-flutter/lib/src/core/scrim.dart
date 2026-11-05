/// The tray's surroundings (SPEC section 9.4): the dim behind a bottom sheet
/// (`scrim`) and the open/closed state the host's Gift button toggles. Pure: no
/// UI, no clock. Port of `packages/sdk-js/src/core/scrim.ts`.
library;

import 'sheet.dart';

/// What a tap on the scrim does. [lower] lowers the sheet to peek first;
/// [dismiss] asks to close.
enum ScrimTap { lower, dismiss }

/// The scrim fades in and out over this long (ms); at once with reduced motion.
const int kScrimFadeMs = 200;

/// The scrim is black at this opacity.
const double kScrimOpacity = 0.4;

/// The dim is drawn: asked for, open, in place, and the sheet is above peek
/// (peek keeps the page in sight). [snap] is the sheet's settled state, or the
/// target of a running snap (`TraySheetState.snap`); [placed] is true once the
/// sheet is measured and drawn where it belongs.
bool scrimVisible({
  required bool scrim,
  required bool open,
  required SheetSnap snap,
  required bool placed,
}) =>
    scrim && open && placed && snap != SheetSnap.peek;

/// Fade duration in ms: [kScrimFadeMs], or 0 with reduced motion.
int scrimFadeMs(bool reducedMotion) => reducedMotion ? 0 : kScrimFadeMs;

/// What a tap on the scrim leads to.
enum ScrimTapOutcome {
  /// No scrim, or the tray is closed.
  ignored,

  /// Move the sheet to peek.
  lower,

  /// Close the tray (when it holds its own open state) and call `onDismiss`.
  dismiss,
}

/// A tap on the scrim. [ScrimTap.lower] (default) lowers any state above peek
/// and dismisses from peek; [ScrimTap.dismiss] dismisses from every state. A
/// hidden scrim takes no touches, so from peek this is only reached by calling
/// it directly.
ScrimTapOutcome scrimTapOutcome({
  required bool scrim,
  ScrimTap scrimTap = ScrimTap.lower,
  required bool open,
  required SheetSnap snap,
}) {
  if (!scrim || !open) return ScrimTapOutcome.ignored;
  if (scrimTap == ScrimTap.lower && snap != SheetSnap.peek) {
    return ScrimTapOutcome.lower;
  }
  return ScrimTapOutcome.dismiss;
}

/// The open/closed state behind `open()`, `close()` and `toggle()`: the host's
/// Gift button is `tray.toggle()`. Every method returns the new state.
class TrayOpenState {
  /// [open] is the initial state (default true: a tray that exists is shown).
  /// [onChange] runs after a change, never for a call that changes nothing.
  TrayOpenState({bool open = true, this.onChange}) : _open = open;

  /// Called after the state changed.
  void Function(bool open)? onChange;

  bool _open;
  final Set<void Function()> _listeners = <void Function()>{};

  /// Whether the tray is open.
  bool get isOpen => _open;

  /// Opens. Returns the new state.
  bool open() => _set(true);

  /// Closes. Returns the new state.
  bool close() => _set(false);

  /// Open if closed, close if open. Returns the new state.
  bool toggle() => _set(!_open);

  /// Runs [listener] after every change; returns the function that stops it.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  bool _set(bool next) {
    if (next == _open) return _open;
    _open = next;
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
    onChange?.call(next);
    return next;
  }
}
