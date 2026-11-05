import 'effect_recipe.dart';
import 'spec_data.g.dart';

export 'effect_recipe.dart';

/// Price thresholds between the tiers.
///
/// A field the app does not give is "not given" ([givenMediumFrom] is null):
/// then a remote recipe set may supply it (SPEC 13.4); the getters always
/// answer with a number.
class TierThresholds {
  /// Creates thresholds; missing fields take the defaults (100 and 10 000).
  const TierThresholds({int? mediumFrom, int? largeFrom})
      : givenMediumFrom = mediumFrom,
        givenLargeFrom = largeFrom;

  /// What the app passed for `mediumFrom`, or null.
  final int? givenMediumFrom;

  /// What the app passed for `largeFrom`, or null.
  final int? givenLargeFrom;

  /// From this price a gift is at least medium.
  int get mediumFrom => givenMediumFrom ?? kMediumFrom;

  /// From this price a gift is large (checked first).
  int get largeFrom => givenLargeFrom ?? kLargeFrom;
}

/// The tier of a gift costing [price].
EffectTier tierFor(
  num price, [
  TierThresholds thresholds = const TierThresholds(),
]) {
  if (price >= thresholds.largeFrom) return EffectTier.large;
  if (price >= thresholds.mediumFrom) return EffectTier.medium;
  return EffectTier.small;
}

/// A fresh copy of the tier's recipe. `low` quality: a third of the sparks
/// (floor), no coins, no rays; everything else is unchanged.
EffectRecipe recipeFor(
  EffectTier tier, [
  EffectQuality quality = EffectQuality.high,
]) {
  final base = kHighRecipes[tier]!;
  if (quality == EffectQuality.high) return base.copyWith();
  return base.copyWith(sparks: base.sparks ~/ 3, coins: 0, rays: false);
}

/// The recipes of every tier, for apps that draw effects themselves.
Map<EffectTier, EffectRecipe> allRecipes([
  EffectQuality quality = EffectQuality.high,
]) =>
    <EffectTier, EffectRecipe>{
      for (final t in EffectTier.values) t: recipeFor(t, quality),
    };
