import Foundation

// Effect recipes: what each size of gift does, as plain data (spec section 4). The numbers live
// in SpecData.generated.swift, generated from packages/sdk-spec/recipes.json.

public enum EffectTier: String, Codable, Sendable, CaseIterable, Hashable {
    case small
    case medium
    case large
}

public enum EffectQuality: String, Codable, Sendable, CaseIterable, Hashable {
    /// Every particle, coin rain and rays.
    case high
    /// For old or slow phones: a third of the sparks, no coins, no rays.
    case low
}

public enum EffectStage: String, Codable, Sendable, Hashable {
    /// The picture floats up from the start point.
    case floatUp = "float-up"
    /// The picture flies to the middle of the layer.
    case center
}

public struct EffectRecipe: Codable, Sendable, Equatable, Hashable {
    public var tier: EffectTier
    /// Picture size at its biggest, for a 100 pt picture at scale 1.
    public var peakScale: Double
    public var flyInMs: Int
    public var holdMs: Int
    public var flyOutMs: Int
    public var stage: EffectStage
    public var sparks: Int
    /// Distance the farthest sparks travel, in points.
    public var sparkSpread: Double
    public var coins: Int
    public var dim: Bool
    public var rays: Bool
    public var noticeMs: Int
    public var noticeBig: Bool

    public init(
        tier: EffectTier,
        peakScale: Double,
        flyInMs: Int,
        holdMs: Int,
        flyOutMs: Int,
        stage: EffectStage,
        sparks: Int,
        sparkSpread: Double,
        coins: Int,
        dim: Bool,
        rays: Bool,
        noticeMs: Int,
        noticeBig: Bool
    ) {
        self.tier = tier
        self.peakScale = peakScale
        self.flyInMs = flyInMs
        self.holdMs = holdMs
        self.flyOutMs = flyOutMs
        self.stage = stage
        self.sparks = sparks
        self.sparkSpread = sparkSpread
        self.coins = coins
        self.dim = dim
        self.rays = rays
        self.noticeMs = noticeMs
        self.noticeBig = noticeBig
    }
}

/// From which price a gift is medium or large. A missing field takes the default.
public struct TierThresholds: Sendable, Equatable, Hashable {
    /// Default 100.
    public var mediumFrom: Int
    /// Default 10,000.
    public var largeFrom: Int

    public init(
        mediumFrom: Int = GiftingSpec.defaultMediumFrom,
        largeFrom: Int = GiftingSpec.defaultLargeFrom
    ) {
        self.mediumFrom = mediumFrom
        self.largeFrom = largeFrom
    }
}

/// `price >= largeFrom` is large (checked first), else `price >= mediumFrom` is medium.
public func tierFor(_ price: Double, thresholds: TierThresholds = TierThresholds()) -> EffectTier {
    if price >= Double(thresholds.largeFrom) {
        return .large
    }
    if price >= Double(thresholds.mediumFrom) {
        return .medium
    }
    return .small
}

public func tierFor(_ price: Int, thresholds: TierThresholds = TierThresholds()) -> EffectTier {
    tierFor(Double(price), thresholds: thresholds)
}

/// A fresh copy of the tier's recipe. `low` quality: `sparks / 3` (rounded down), no coins,
/// no rays; everything else unchanged. With `set` (remote recipes, spec section 13) the recipe
/// comes from that table instead of the built-in one.
public func recipeFor(_ tier: EffectTier, quality: EffectQuality = .high, set: RecipeSet? = nil) -> EffectRecipe {
    if let set = set {
        return set.recipe(tier, quality: quality)
    }
    var recipe = GiftingSpec.specRecipe(tier, quality: .high)
    if quality == .low {
        recipe.sparks = recipe.sparks / 3
        recipe.coins = 0
        recipe.rays = false
    }
    return recipe
}

/// The three recipes for one quality.
public func allRecipes(_ quality: EffectQuality = .high) -> [EffectTier: EffectRecipe] {
    var out: [EffectTier: EffectRecipe] = [:]
    for tier in EffectTier.allCases {
        out[tier] = recipeFor(tier, quality: quality)
    }
    return out
}

extension GiftingSpec {
    /// At most this many effects of a tier on screen at once. Large ones queue instead.
    public static func maxConcurrentEffects(_ tier: EffectTier) -> Int {
        switch tier {
        case .small:
            return maxConcurrentSmall
        case .medium:
            return maxConcurrentMedium
        case .large:
            return maxConcurrentLarge
        }
    }
}
