/**
 * Effect recipes: what each size of gift does, as plain data. Every player (React Native
 * today, web and others later) reads the same recipes, so a gift looks the same everywhere.
 * Nothing here knows about a screen or a framework.
 */

export type EffectTier = "small" | "medium" | "large";
export type EffectQuality = "high" | "low";

export interface TierThresholds {
  /** From this price (in your own coin units) a gift is at least medium. Default 100. */
  mediumFrom: number;
  /** From this price a gift is large. Default 10,000. */
  largeFrom: number;
}

export const DEFAULT_THRESHOLDS: TierThresholds = { mediumFrom: 100, largeFrom: 10_000 };

export function tierFor(price: number, thresholds: Partial<TierThresholds> = {}): EffectTier {
  const { mediumFrom, largeFrom } = { ...DEFAULT_THRESHOLDS, ...thresholds };
  if (price >= largeFrom) return "large";
  if (price >= mediumFrom) return "medium";
  return "small";
}

export interface EffectRecipe {
  tier: EffectTier;
  /** Gift picture size on screen at its biggest, in dp, for a 100 dp picture at scale 1. */
  peakScale: number;
  /** Time to fly in, then to hold, then to leave, in ms. */
  flyInMs: number;
  holdMs: number;
  flyOutMs: number;
  /** Where the picture ends up. */
  stage: "float-up" | "center";
  /** Sparks burst when the gift arrives. */
  sparks: number;
  /** Distance the farthest sparks travel, in dp. */
  sparkSpread: number;
  /** Gold coins falling over the whole screen. */
  coins: number;
  /** The screen darkens behind the gift. */
  dim: boolean;
  /** Light rays and a glow behind the gift. */
  rays: boolean;
  /** How long the notice (who sent what) stays, in ms. */
  noticeMs: number;
  /** Larger, golden notice. */
  noticeBig: boolean;
}

const RECIPES: Record<EffectTier, EffectRecipe> = {
  small: {
    tier: "small",
    peakScale: 0.9,
    flyInMs: 700,
    holdMs: 0,
    flyOutMs: 600,
    stage: "float-up",
    sparks: 0,
    sparkSpread: 0,
    coins: 0,
    dim: false,
    rays: false,
    noticeMs: 2400,
    noticeBig: false,
  },
  medium: {
    tier: "medium",
    peakScale: 1.5,
    flyInMs: 800,
    holdMs: 700,
    flyOutMs: 600,
    stage: "center",
    sparks: 24,
    sparkSpread: 130,
    coins: 0,
    dim: false,
    rays: false,
    noticeMs: 2400,
    noticeBig: false,
  },
  large: {
    tier: "large",
    peakScale: 2.8,
    flyInMs: 900,
    holdMs: 1600,
    flyOutMs: 550,
    stage: "center",
    sparks: 50,
    sparkSpread: 230,
    coins: 34,
    dim: true,
    rays: true,
    noticeMs: 2800,
    noticeBig: true,
  },
};

/**
 * `low` quality is for old or slow phones: far fewer particles, no coin rain and no rays.
 * The gift still flies in and the notice still shows. With `set` (a remote recipe set, spec
 * section 13) the recipe comes from that table instead of the built-in one; always a copy.
 */
export function recipeFor(
  tier: EffectTier,
  quality: EffectQuality = "high",
  set?: { recipes: Record<EffectQuality, Record<EffectTier, EffectRecipe>> },
): EffectRecipe {
  if (set) return { ...set.recipes[quality][tier] };
  const base = RECIPES[tier];
  if (quality === "high") return { ...base };
  return {
    ...base,
    sparks: Math.floor(base.sparks / 3),
    coins: 0,
    rays: false,
  };
}

/** The recipes as JSON, for apps that draw the effects themselves (Swift, Kotlin, Flutter...). */
export function allRecipes(quality: EffectQuality = "high"): Record<EffectTier, EffectRecipe> {
  return {
    small: recipeFor("small", quality),
    medium: recipeFor("medium", quality),
    large: recipeFor("large", quality),
  };
}
