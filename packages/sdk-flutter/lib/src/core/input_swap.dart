/// The gift button in the app's message bar (SPEC section 20): the button
/// closes the keyboard and opens the tray in its place; a tap on the text field
/// closes the tray and the keyboard comes back. Pure: no UI, no clock; the
/// widgets blur, focus, open and close. Port of
/// `packages/sdk-js/src/core/inputSwap.ts`.
library;

import 'dart:math' as math;

/// What happened: the gift button (or `toggle()`), or the bound text field got
/// focus.
enum InputSwapEvent { button, inputFocus }

/// What to do with the tray.
enum InputSwapTray { open, close, keep }

/// What to do with the text field.
enum InputSwapInput { blur, focus, keep }

/// One step of the keyboard swap. Run `input: blur` before `tray: open`, and
/// `tray: close` before `input: focus`.
class InputSwapStep {
  /// Creates a step.
  const InputSwapStep({required this.tray, required this.input});

  /// What to do with the tray.
  final InputSwapTray tray;

  /// What to do with the text field.
  final InputSwapInput input;

  @override
  bool operator ==(Object other) =>
      other is InputSwapStep && other.tray == tray && other.input == input;

  @override
  int get hashCode => Object.hash(tray, input);

  @override
  String toString() => 'InputSwapStep(${tray.name}, ${input.name})';
}

/// The tray's height in the keyboard's place before any keyboard was seen.
const int kKeyboardPlaceFallback = 300;

/// A smaller inset is not a keyboard (an accessory bar, a desktop window).
const int kKeyboardMinHeight = 120;

/// The keyboard's place never takes more than this share of the container.
const double kKeyboardPlaceMaxFraction = 0.6;

/// One step of the keyboard swap (SPEC 20.2).
InputSwapStep inputSwapStep(bool open, InputSwapEvent event) {
  if (event == InputSwapEvent.button) {
    return open
        ? const InputSwapStep(
            tray: InputSwapTray.close, input: InputSwapInput.focus)
        : const InputSwapStep(
            tray: InputSwapTray.open, input: InputSwapInput.blur);
  }
  return open
      ? const InputSwapStep(
          tray: InputSwapTray.close, input: InputSwapInput.keep)
      : const InputSwapStep(
          tray: InputSwapTray.keep, input: InputSwapInput.keep);
}

bool _finite(double? v) => v != null && v.isFinite;

/// How tall the tray is in the keyboard's place (SPEC 20.2), in logical
/// pixels. [keyboardHeight] is the last keyboard height seen (null or 0: none
/// yet); [containerHeight] is the box the tray fills (null or 0: unknown).
int keyboardPlaceHeight({double? keyboardHeight, double? containerHeight}) {
  var k = _finite(keyboardHeight) && keyboardHeight! >= kKeyboardMinHeight
      ? keyboardHeight
      : kKeyboardPlaceFallback.toDouble();
  if (_finite(containerHeight) && containerHeight! > 0) {
    k = math.min(
      k,
      (containerHeight * kKeyboardPlaceMaxFraction).floorToDouble(),
    );
  }
  // Math.round: half up.
  return (k + 0.5).floor();
}

/// The sheet's `default` snap as a fraction of the container for the
/// keyboard's place, or null when the container is not measured yet.
double? keyboardPlaceSnap({double? keyboardHeight, double? containerHeight}) {
  if (!_finite(containerHeight) || containerHeight! <= 0) return null;
  return keyboardPlaceHeight(
        keyboardHeight: keyboardHeight,
        containerHeight: containerHeight,
      ) /
      containerHeight;
}
