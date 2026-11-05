/// Remote recipes (SPEC section 13): effect numbers fetched from a hosted copy
/// of `recipes.json`, so tuning ships without an app update. Pure: no network,
/// no storage, no timers. The loader (`recipes_loader.dart`) fetches and
/// caches; this file only parses, clamps and merges.
/// Port of `packages/sdk-js/src/core/remote-recipes.ts`.
library;

import 'recipes.dart';
import 'spec_data.g.dart';

/// The numbers a remote document may change. Caps, queue size and the sender
/// name are not here.
class RecipeSet {
  /// Creates a set.
  const RecipeSet({
    required this.thresholds,
    required this.comboWindowMs,
    required this.recipes,
  });

  /// The built-in values (`recipes.json`).
  factory RecipeSet.embedded() => RecipeSet(
        thresholds: const TierThresholds(
          mediumFrom: kMediumFrom,
          largeFrom: kLargeFrom,
        ),
        comboWindowMs: kComboWindowMs,
        recipes: <EffectQuality, Map<EffectTier, EffectRecipe>>{
          for (final q in EffectQuality.values) q: allRecipes(q),
        },
      );

  /// The tier thresholds (both given).
  final TierThresholds thresholds;

  /// Combo window, ms.
  final int comboWindowMs;

  /// The recipe of every quality and tier.
  final Map<EffectQuality, Map<EffectTier, EffectRecipe>> recipes;

  /// The set as JSON with the keys of `recipes.json` (for comparison in tests).
  Map<String, Object?> toJson() => <String, Object?>{
        'thresholds': <String, Object?>{
          'mediumFrom': thresholds.mediumFrom,
          'largeFrom': thresholds.largeFrom,
        },
        'comboWindowMs': comboWindowMs,
        'recipes': <String, Object?>{
          for (final q in EffectQuality.values)
            q.name: <String, Object?>{
              for (final t in EffectTier.values)
                t.name: recipes[q]![t]!.toJson(),
            },
        },
      };
}

/// A parsed remote document: a full set (missing or bad fields already hold
/// the embedded value).
class RemoteRecipeSet extends RecipeSet {
  /// Creates a remote set.
  const RemoteRecipeSet({
    required this.specVersion,
    required super.thresholds,
    required super.comboWindowMs,
    required super.recipes,
  });

  /// The document's own `specVersion` (same major as the SDK).
  final String specVersion;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'specVersion': specVersion, ...super.toJson()};
}

/// Allowed range of one number a remote document may set (SPEC 13.3).
class RemoteLimit {
  /// Creates a limit.
  const RemoteLimit(this.min, this.max, {required this.integer});

  /// Smallest allowed value.
  final double min;

  /// Largest allowed value.
  final double max;

  /// Rounded half up after clamping.
  final bool integer;
}

/// The limits of every number a remote document may set. A value outside is
/// clamped to the nearest end; integer values are then rounded half up.
const Map<String, RemoteLimit> remoteRecipeLimits = <String, RemoteLimit>{
  'peakScale': RemoteLimit(0.5, 4, integer: false),
  'flyInMs': RemoteLimit(0, 10000, integer: true),
  'holdMs': RemoteLimit(0, 10000, integer: true),
  'flyOutMs': RemoteLimit(0, 10000, integer: true),
  'sparks': RemoteLimit(0, 120, integer: true),
  'sparkSpread': RemoteLimit(0, 400, integer: true),
  'coins': RemoteLimit(0, 120, integer: true),
  'noticeMs': RemoteLimit(500, 8000, integer: true),
  'mediumFrom': RemoteLimit(1, 1000000, integer: true),
  'largeFrom': RemoteLimit(2, 10000000, integer: true),
  'comboWindowMs': RemoteLimit(500, 10000, integer: true),
};

bool _isObject(Object? v) => v is Map<Object?, Object?>;

Map<Object?, Object?> _obj(Object? v) =>
    _isObject(v) ? v! as Map<Object?, Object?> : const <Object?, Object?>{};

/// A finite number, clamped and (for integer fields) rounded half up;
/// otherwise null (the caller keeps the embedded value).
num? _clamped(String key, Object? value) {
  if (value is! num || !value.isFinite) return null;
  final limit = remoteRecipeLimits[key]!;
  final c = value.toDouble().clamp(limit.min, limit.max).toDouble();
  // Every range is >= 0, so floor(x + 0.5) is "half up", as in the spec.
  return limit.integer ? (c + 0.5).floor() : c;
}

int _int(String key, Object? value, int fallback) =>
    (_clamped(key, value) ?? fallback).toInt();

EffectRecipe _parseRecipe(EffectTier tier, Object? raw, EffectRecipe base) {
  if (!_isObject(raw)) return base;
  final m = _obj(raw);
  EffectStage? stage;
  if (m['stage'] == 'float-up') stage = EffectStage.floatUp;
  if (m['stage'] == 'center') stage = EffectStage.center;
  return base.copyWith(
    peakScale: _clamped('peakScale', m['peakScale'])?.toDouble(),
    flyInMs: _clamped('flyInMs', m['flyInMs'])?.toInt(),
    holdMs: _clamped('holdMs', m['holdMs'])?.toInt(),
    flyOutMs: _clamped('flyOutMs', m['flyOutMs'])?.toInt(),
    stage: stage,
    sparks: _clamped('sparks', m['sparks'])?.toInt(),
    sparkSpread: _clamped('sparkSpread', m['sparkSpread'])?.toInt(),
    coins: _clamped('coins', m['coins'])?.toInt(),
    dim: m['dim'] is bool ? m['dim']! as bool : null,
    rays: m['rays'] is bool ? m['rays']! as bool : null,
    noticeMs: _clamped('noticeMs', m['noticeMs'])?.toInt(),
    noticeBig: m['noticeBig'] is bool ? m['noticeBig']! as bool : null,
  );
}

TierThresholds _parseThresholds(Object? raw, TierThresholds base) {
  if (!_isObject(raw)) return base;
  final m = _obj(raw);
  final medium = _int('mediumFrom', m['mediumFrom'], base.mediumFrom);
  final large = _int('largeFrom', m['largeFrom'], base.largeFrom);
  // The pair must stay ordered; otherwise neither value is used.
  return large > medium
      ? TierThresholds(mediumFrom: medium, largeFrom: large)
      : base;
}

final RegExp _version = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

/// The major part of a `x.y.z` version, or null when the string is not one.
int? _major(Object? version) {
  if (version is! String) return null;
  final m = _version.firstMatch(version);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Reads a remote recipes document (already JSON-decoded). Returns null when
/// the whole document must be ignored: not an object, or a `specVersion` whose
/// major differs from the SDK's. Any single field of the wrong type falls back
/// to the embedded value for THAT field; numbers out of range are clamped
/// ([remoteRecipeLimits]). Caps, queue size, sender name, stage kinds and
/// unknown keys are never taken from the document.
RemoteRecipeSet? parseRemoteRecipes(Object? json, [RecipeSet? embedded]) {
  if (!_isObject(json)) return null;
  final doc = _obj(json);
  final docMajor = _major(doc['specVersion']);
  if (docMajor == null || docMajor != _major(kSpecVersion)) return null;
  final base = embedded ?? RecipeSet.embedded();
  final rawRecipes = _obj(doc['recipes']);
  final recipes = <EffectQuality, Map<EffectTier, EffectRecipe>>{
    for (final q in EffectQuality.values)
      q: <EffectTier, EffectRecipe>{
        for (final t in EffectTier.values)
          t: _parseRecipe(
            t,
            _obj(rawRecipes[q.name])[t.name],
            base.recipes[q]![t]!,
          ),
      },
  };
  return RemoteRecipeSet(
    specVersion: doc['specVersion']! as String,
    thresholds: _parseThresholds(doc['thresholds'], base.thresholds),
    comboWindowMs:
        _int('comboWindowMs', doc['comboWindowMs'], base.comboWindowMs),
    recipes: recipes,
  );
}

/// The set effects use. Merge order (SPEC 13.4): embedded < remote < app
/// options. [remote] is a parsed document (it already holds embedded values
/// where it had none) or null. [appThresholds] gives only the fields the app
/// set (see [TierThresholds.givenMediumFrom]); [appComboWindowMs] is the app's
/// own window, if any. The app's numbers are not clamped.
RecipeSet mergeRecipeSet(
  RecipeSet embedded,
  RecipeSet? remote, {
  TierThresholds? appThresholds,
  int? appComboWindowMs,
}) {
  final base = remote ?? embedded;
  return RecipeSet(
    thresholds: TierThresholds(
      mediumFrom: appThresholds?.givenMediumFrom ?? base.thresholds.mediumFrom,
      largeFrom: appThresholds?.givenLargeFrom ?? base.thresholds.largeFrom,
    ),
    comboWindowMs: appComboWindowMs ?? base.comboWindowMs,
    recipes: base.recipes,
  );
}

/// Default address of the hosted document. Hosting it is a separate deploy
/// step (not done yet: until then the request fails and the embedded values
/// stay).
const String defaultRecipesUrl = 'https://assets.giftingstack.com/recipes.json';

final RegExp _versionChars = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

/// The address to fetch. [version] pins a document: the last `.json` of the URL
/// becomes `.<version>.json` (`recipes.json` -> `recipes.1.0.0.json`). Returns
/// null (no network) when the version is not 1-64 characters of
/// `A-Z a-z 0-9 . _ -`, or the URL has no `.json` to pin.
String? remoteRecipesUrl([String? url, String? version]) {
  final base = url ?? defaultRecipesUrl;
  if (version == null) return base;
  if (!_versionChars.hasMatch(version)) return null;
  final at = base.lastIndexOf('.json');
  if (at < 0) return null;
  return '${base.substring(0, at)}.$version${base.substring(at)}';
}
