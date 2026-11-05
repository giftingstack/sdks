/// How big a gift is, from its price.
enum EffectTier { small, medium, large }

/// `low` is for old or slow phones.
enum EffectQuality { high, low }

/// Where the picture ends up.
enum EffectStage {
  /// Floats up from the start point (small gifts).
  floatUp,

  /// Flies to the middle of the layer.
  center,
}

/// What one tier of gift does, as plain data (see `recipes.json`).
class EffectRecipe {
  /// Creates a recipe.
  const EffectRecipe({
    required this.tier,
    required this.peakScale,
    required this.flyInMs,
    required this.holdMs,
    required this.flyOutMs,
    required this.stage,
    required this.sparks,
    required this.sparkSpread,
    required this.coins,
    required this.dim,
    required this.rays,
    required this.noticeMs,
    required this.noticeBig,
  });

  /// The tier.
  final EffectTier tier;

  /// Picture scale at its biggest (picture is 100 dp at scale 1).
  final double peakScale;

  /// Time to fly in, ms.
  final int flyInMs;

  /// Time to hold, ms.
  final int holdMs;

  /// Time to leave, ms.
  final int flyOutMs;

  /// Where the picture ends up.
  final EffectStage stage;

  /// Number of sparks.
  final int sparks;

  /// Distance of the farthest sparks, dp.
  final int sparkSpread;

  /// Number of falling coins.
  final int coins;

  /// The screen darkens behind the gift.
  final bool dim;

  /// Light rays and a glow behind the gift.
  final bool rays;

  /// How long the notice stays, ms.
  final int noticeMs;

  /// Larger, golden notice.
  final bool noticeBig;

  /// A copy with some fields replaced.
  EffectRecipe copyWith({
    double? peakScale,
    int? flyInMs,
    int? holdMs,
    int? flyOutMs,
    EffectStage? stage,
    int? sparks,
    int? sparkSpread,
    int? coins,
    bool? dim,
    bool? rays,
    int? noticeMs,
    bool? noticeBig,
  }) =>
      EffectRecipe(
        tier: tier,
        peakScale: peakScale ?? this.peakScale,
        flyInMs: flyInMs ?? this.flyInMs,
        holdMs: holdMs ?? this.holdMs,
        flyOutMs: flyOutMs ?? this.flyOutMs,
        stage: stage ?? this.stage,
        sparks: sparks ?? this.sparks,
        sparkSpread: sparkSpread ?? this.sparkSpread,
        coins: coins ?? this.coins,
        dim: dim ?? this.dim,
        rays: rays ?? this.rays,
        noticeMs: noticeMs ?? this.noticeMs,
        noticeBig: noticeBig ?? this.noticeBig,
      );

  /// The recipe as JSON, with the keys of `recipes.json`.
  Map<String, Object?> toJson() => <String, Object?>{
        'tier': tier.name,
        'peakScale': peakScale,
        'flyInMs': flyInMs,
        'holdMs': holdMs,
        'flyOutMs': flyOutMs,
        'stage': stage == EffectStage.floatUp ? 'float-up' : 'center',
        'sparks': sparks,
        'sparkSpread': sparkSpread,
        'coins': coins,
        'dim': dim,
        'rays': rays,
        'noticeMs': noticeMs,
        'noticeBig': noticeBig,
      };
}
