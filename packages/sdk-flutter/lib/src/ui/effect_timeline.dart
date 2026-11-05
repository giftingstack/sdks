/// The timeline of one effect (SPEC section 7.3) as pure math: given the time
/// since the effect started, what every phase's progress is. No Flutter code,
/// so it is unit-tested without a screen.
library;

import 'dart:math' as math;

import '../core/effect_recipe.dart';

/// Picture size at scale 1, in dp.
const double kEffectPictureSize = 100;

/// How much bigger than the phone layout the gift picture is drawn in a wide
/// layer (a tablet, a landscape phone). A phone layer (about 390 x 700) gives
/// 1; the picture grows with the layer's area up to 2, and never beyond 90
/// percent of the layer's short side at its biggest. [manual] replaces the
/// automatic value. Port of `pictureScale` in `packages/sdk-js/src/web/anim.ts`.
double pictureScale(
  double width,
  double height,
  double peakScale, [
  double? manual,
]) {
  final room =
      (0.9 * math.min(width, height)) / (kEffectPictureSize * peakScale);
  final wanted =
      manual ?? math.min(2.0, math.max(1.0, math.sqrt(width * height) / 530));
  return math.min(wanted, math.max(room, 0.5));
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// `Easing.out(Easing.back(s))`: ease-out with overshoot.
double backOut(double t, double s) {
  final x = 1 - t;
  return 1 - x * x * ((s + 1) * x - s);
}

/// Ease-out cubic.
double outCubic(double t) {
  final x = 1 - t;
  return 1 - x * x * x;
}

/// Ease-in quad.
double inQuad(double t) => t * t;

/// Piecewise-linear interpolation like React Native's `interpolate`.
/// With [clamp] false the first and last segments extend (the reference's
/// default); with true the output stays between the end values.
double interpolate(
  double x,
  List<double> input,
  List<double> output, {
  bool clamp = false,
}) {
  assert(input.length == output.length && input.length >= 2);
  final last = input.length - 1;
  if (clamp) {
    if (x <= input.first) return output.first;
    if (x >= input[last]) return output[last];
  }
  var i = 1;
  while (i < last && x > input[i]) {
    i++;
  }
  final a = input[i - 1];
  final b = input[i];
  if (b == a) return output[i];
  return output[i - 1] + (output[i] - output[i - 1]) * ((x - a) / (b - a));
}

/// Progress of every phase at one moment.
class EffectFrame {
  /// Creates a frame.
  const EffectFrame({
    required this.fly,
    required this.leave,
    required this.burst,
    required this.rain,
    required this.spin,
    required this.dim,
  });

  /// Eased fly-in progress (overshoots 1).
  final double fly;

  /// Eased leave progress, 0 to 1.
  final double leave;

  /// Eased burst progress, 0 to 1.
  final double burst;

  /// Linear coin-rain progress, 0 to 1.
  final double rain;

  /// Linear rays progress, 0 to 1.
  final double spin;

  /// Dim progress, 0 to 1 (opacity is 0.62 times this).
  final double dim;
}

/// Timing of one recipe.
class EffectTimeline {
  /// Creates the timeline of [recipe].
  EffectTimeline(this.recipe);

  /// The recipe.
  final EffectRecipe recipe;

  /// `holdMs + flyOutMs`.
  int get tail => recipe.holdMs + recipe.flyOutMs;

  /// When the leave phase starts, ms.
  int get leaveStartMs => recipe.flyInMs + recipe.holdMs;

  /// When the effect is finished:
  /// `flyInMs + max(900, tail, coins > 0 ? tail + 800 : 0)`.
  int get totalMs {
    var after = 900;
    if (tail > after) after = tail;
    if (recipe.coins > 0 && tail + 800 > after) after = tail + 800;
    return recipe.flyInMs + after;
  }

  /// The phases at [ms] after the start.
  EffectFrame at(double ms) {
    final flyP = _clamp01(ms / recipe.flyInMs);
    final dimIn = _clamp01(ms / 300);
    final leaveP = _clamp01((ms - leaveStartMs) / recipe.flyOutMs);
    final burstP = _clamp01((ms - recipe.flyInMs) / 900);
    final rainP = _clamp01((ms - recipe.flyInMs) / (tail + 800));
    final spinP = _clamp01(ms / (recipe.flyInMs + tail));
    return EffectFrame(
      fly: backOut(flyP, 1.3),
      leave: inQuad(leaveP),
      burst: outCubic(burstP),
      rain: rainP,
      spin: spinP,
      dim: recipe.dim ? dimIn * (1 - leaveP) : 0,
    );
  }
}
