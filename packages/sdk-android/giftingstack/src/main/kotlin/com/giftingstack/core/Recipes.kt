package com.giftingstack.core

enum class EffectTier(val wire: String) {
    Small("small"),
    Medium("medium"),
    Large("large");

    companion object {
        fun fromWire(s: String): EffectTier = entries.first { it.wire == s }
    }
}

enum class EffectQuality(val wire: String) {
    High("high"),
    Low("low");

    companion object {
        fun fromWire(s: String): EffectQuality = entries.first { it.wire == s }
    }
}

enum class EffectStage(val wire: String) {
    FloatUp("float-up"),
    Center("center"),
}

/** From which price (in your own coin units) a gift is medium or large. */
data class TierThresholds(val mediumFrom: Int = 100, val largeFrom: Int = 10_000)

val DEFAULT_THRESHOLDS = TierThresholds()

/** `price >= largeFrom` is large (checked first), else `price >= mediumFrom` is medium. */
fun tierFor(price: Double, thresholds: TierThresholds = DEFAULT_THRESHOLDS): EffectTier =
    when {
        price >= thresholds.largeFrom -> EffectTier.Large
        price >= thresholds.mediumFrom -> EffectTier.Medium
        else -> EffectTier.Small
    }

fun tierFor(price: Int, thresholds: TierThresholds = DEFAULT_THRESHOLDS): EffectTier =
    tierFor(price.toDouble(), thresholds)

fun tierFor(price: Long, thresholds: TierThresholds = DEFAULT_THRESHOLDS): EffectTier =
    tierFor(price.toDouble(), thresholds)

/**
 * What each size of gift does, as plain data (spec 4.2). Lengths in dp, times in ms. The numbers
 * equal `packages/sdk-spec/recipes.json`; a unit test fails when they drift.
 */
data class EffectRecipe(
    val tier: EffectTier,
    /** Picture size at its biggest, relative to a 100 dp box. */
    val peakScale: Double,
    val flyInMs: Int,
    val holdMs: Int,
    val flyOutMs: Int,
    val stage: EffectStage,
    val sparks: Int,
    val sparkSpread: Int,
    val coins: Int,
    val dim: Boolean,
    val rays: Boolean,
    val noticeMs: Int,
    val noticeBig: Boolean,
)

private val BASE_RECIPES: Map<EffectTier, EffectRecipe> =
    mapOf(
        EffectTier.Small to
            EffectRecipe(
                tier = EffectTier.Small,
                peakScale = 0.9,
                flyInMs = 700,
                holdMs = 0,
                flyOutMs = 600,
                stage = EffectStage.FloatUp,
                sparks = 0,
                sparkSpread = 0,
                coins = 0,
                dim = false,
                rays = false,
                noticeMs = 2400,
                noticeBig = false,
            ),
        EffectTier.Medium to
            EffectRecipe(
                tier = EffectTier.Medium,
                peakScale = 1.5,
                flyInMs = 800,
                holdMs = 700,
                flyOutMs = 600,
                stage = EffectStage.Center,
                sparks = 24,
                sparkSpread = 130,
                coins = 0,
                dim = false,
                rays = false,
                noticeMs = 2400,
                noticeBig = false,
            ),
        EffectTier.Large to
            EffectRecipe(
                tier = EffectTier.Large,
                peakScale = 2.8,
                flyInMs = 900,
                holdMs = 1600,
                flyOutMs = 550,
                stage = EffectStage.Center,
                sparks = 50,
                sparkSpread = 230,
                coins = 34,
                dim = true,
                rays = true,
                noticeMs = 2800,
                noticeBig = true,
            ),
    )

/**
 * The recipe of a tier. `Low` quality (old or slow phones) has `sparks / 3` (rounded down), no
 * coins and no rays; everything else is unchanged.
 */
fun recipeFor(tier: EffectTier, quality: EffectQuality = EffectQuality.High, set: RecipeSet? = null): EffectRecipe {
    if (set != null) return set.recipes.getValue(quality).getValue(tier).copy()
    val base = BASE_RECIPES.getValue(tier)
    return if (quality == EffectQuality.High) {
        base.copy()
    } else {
        base.copy(sparks = base.sparks / 3, coins = 0, rays = false)
    }
}

fun allRecipes(quality: EffectQuality = EffectQuality.High): Map<EffectTier, EffectRecipe> =
    EffectTier.entries.associateWith { recipeFor(it, quality) }
