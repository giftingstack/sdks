/**
 * Remote recipes (spec section 13): effect numbers fetched from a hosted copy of
 * `recipes.json`, so tuning ships without an app update. Pure: no network, no storage, no
 * timers. The platform's loader fetches and caches; this file only parses, clamps and merges.
 */
import { DEFAULT_COMBO_WINDOW_MS } from "./combo";
import {
  DEFAULT_THRESHOLDS,
  type EffectQuality,
  type EffectRecipe,
  type EffectTier,
  type TierThresholds,
  allRecipes,
} from "./recipes";
import { SPEC_VERSION } from "./version";

/** The numbers a remote document may change. Caps, queue size and sender name are not here. */
export interface RecipeSet {
  thresholds: TierThresholds;
  comboWindowMs: number;
  recipes: Record<EffectQuality, Record<EffectTier, EffectRecipe>>;
}

/** A parsed remote document: a full set (missing or bad fields already hold the embedded value). */
export interface RemoteRecipeSet extends RecipeSet {
  /** The document's own `specVersion` (same major as the SDK). */
  specVersion: string;
}

/** The values built into the SDK (`recipes.json`). Always a fresh copy. */
export function embeddedRecipeSet(): RecipeSet {
  return {
    thresholds: { ...DEFAULT_THRESHOLDS },
    comboWindowMs: DEFAULT_COMBO_WINDOW_MS,
    recipes: { high: allRecipes("high"), low: allRecipes("low") },
  };
}

/**
 * Allowed range of every number a remote document may set (spec section 13.3). A value outside
 * is clamped to the nearest end; `integer` values are then rounded half up.
 */
export const REMOTE_RECIPE_LIMITS = {
  peakScale: { min: 0.5, max: 4, integer: false },
  flyInMs: { min: 0, max: 10_000, integer: true },
  holdMs: { min: 0, max: 10_000, integer: true },
  flyOutMs: { min: 0, max: 10_000, integer: true },
  sparks: { min: 0, max: 120, integer: true },
  sparkSpread: { min: 0, max: 400, integer: true },
  coins: { min: 0, max: 120, integer: true },
  noticeMs: { min: 500, max: 8_000, integer: true },
  mediumFrom: { min: 1, max: 1_000_000, integer: true },
  largeFrom: { min: 2, max: 10_000_000, integer: true },
  comboWindowMs: { min: 500, max: 10_000, integer: true },
} as const;

export type RemoteRecipeLimitKey = keyof typeof REMOTE_RECIPE_LIMITS;

const NUMBER_FIELDS = [
  "peakScale",
  "flyInMs",
  "holdMs",
  "flyOutMs",
  "sparks",
  "sparkSpread",
  "coins",
  "noticeMs",
] as const;
const BOOLEAN_FIELDS = ["dim", "rays", "noticeBig"] as const;
const STAGES: readonly EffectRecipe["stage"][] = ["float-up", "center"];
const TIERS: readonly EffectTier[] = ["small", "medium", "large"];
const QUALITIES: readonly EffectQuality[] = ["high", "low"];

type Obj = Record<string, unknown>;
const isObject = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);

/** A finite number, clamped and (for integer fields) rounded half up; otherwise the fallback. */
function clampField(key: RemoteRecipeLimitKey, value: unknown, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  const { min, max, integer } = REMOTE_RECIPE_LIMITS[key];
  const clamped = Math.min(max, Math.max(min, value));
  // Every range is >= 0, so Math.round is "half up" here, as in the spec.
  return integer ? Math.round(clamped) : clamped;
}

function parseRecipe(tier: EffectTier, raw: unknown, base: EffectRecipe): EffectRecipe {
  const out: EffectRecipe = { ...base, tier };
  if (!isObject(raw)) return out;
  for (const f of NUMBER_FIELDS) out[f] = clampField(f, raw[f], base[f]);
  for (const f of BOOLEAN_FIELDS) if (typeof raw[f] === "boolean") out[f] = raw[f];
  const stage = raw.stage;
  if (typeof stage === "string" && (STAGES as readonly string[]).includes(stage)) {
    out.stage = stage as EffectRecipe["stage"];
  }
  return out;
}

function parseThresholds(raw: unknown, base: TierThresholds): TierThresholds {
  if (!isObject(raw)) return { ...base };
  const mediumFrom = clampField("mediumFrom", raw.mediumFrom, base.mediumFrom);
  const largeFrom = clampField("largeFrom", raw.largeFrom, base.largeFrom);
  // The pair must stay ordered; otherwise neither value is used.
  return largeFrom > mediumFrom ? { mediumFrom, largeFrom } : { ...base };
}

/** The major part of a `x.y.z` version, or null when the string is not one. */
function major(version: unknown): number | null {
  if (typeof version !== "string") return null;
  const m = /^(\d+)\.(\d+)\.(\d+)$/.exec(version);
  return m ? Number(m[1]) : null;
}

/**
 * Reads a remote recipes document (already JSON-decoded). Returns null when the whole document
 * must be ignored: not an object, or a `specVersion` whose major differs from the SDK's. Any
 * single field of the wrong type falls back to the embedded value for THAT field; numbers out
 * of range are clamped (`REMOTE_RECIPE_LIMITS`). Caps, queue size, sender name, stage kinds and
 * unknown keys are never taken from the document.
 */
export function parseRemoteRecipes(
  json: unknown,
  embedded: RecipeSet = embeddedRecipeSet(),
): RemoteRecipeSet | null {
  if (!isObject(json)) return null;
  const docMajor = major(json.specVersion);
  if (docMajor === null || docMajor !== major(SPEC_VERSION)) return null;
  const rawRecipes = isObject(json.recipes) ? json.recipes : {};
  const recipes = {} as RecipeSet["recipes"];
  for (const q of QUALITIES) {
    const rawQ = isObject(rawRecipes[q]) ? rawRecipes[q] : {};
    const tiers = {} as Record<EffectTier, EffectRecipe>;
    for (const t of TIERS) tiers[t] = parseRecipe(t, rawQ[t], embedded.recipes[q][t]);
    recipes[q] = tiers;
  }
  return {
    specVersion: json.specVersion as string,
    thresholds: parseThresholds(json.thresholds, embedded.thresholds),
    comboWindowMs: clampField("comboWindowMs", json.comboWindowMs, embedded.comboWindowMs),
    recipes,
  };
}

/** What the app itself passed (layer options). Not clamped: the app owns its own numbers. */
export interface AppRecipeOverrides {
  thresholds?: Partial<TierThresholds>;
  comboWindowMs?: number;
}

/**
 * The set effects use. Merge order (spec 13.4): embedded < remote < app options. `remote` is a
 * parsed document (it already holds embedded values where it had none) or null.
 */
export function mergeRecipeSet(
  embedded: RecipeSet,
  remote: RecipeSet | null,
  app: AppRecipeOverrides = {},
): RecipeSet {
  const base = remote ?? embedded;
  const thresholds = { ...base.thresholds };
  if (app.thresholds?.mediumFrom !== undefined) thresholds.mediumFrom = app.thresholds.mediumFrom;
  if (app.thresholds?.largeFrom !== undefined) thresholds.largeFrom = app.thresholds.largeFrom;
  return {
    thresholds,
    comboWindowMs: app.comboWindowMs ?? base.comboWindowMs,
    recipes: base.recipes,
  };
}

/** Default address of the hosted document. Hosting it is a separate deploy step. */
export const DEFAULT_RECIPES_URL = "https://assets.giftingstack.com/recipes.json";

/**
 * The address to fetch. `version` pins a document: the last `.json` of the URL becomes
 * `.<version>.json` (`recipes.json` -> `recipes.1.0.0.json`). Returns null (no network) when
 * the version is not 1-64 characters of `A-Z a-z 0-9 . _ -`, or the URL has no `.json` to pin.
 */
export function remoteRecipesUrl(url?: string, version?: string): string | null {
  const base = url ?? DEFAULT_RECIPES_URL;
  if (version === undefined) return base;
  if (!/^[A-Za-z0-9._-]{1,64}$/.test(version)) return null;
  const at = base.lastIndexOf(".json");
  if (at < 0) return null;
  return `${base.slice(0, at)}.${version}${base.slice(at)}`;
}
