/**
 * The numbers every platform shares, as one JSON object. `packages/sdk-spec/recipes.json` is
 * generated from this (`pnpm --filter @giftingstack/sdk-spec build:recipes`), and a test fails
 * when the file and this code disagree.
 */
import { DEFAULT_COMBO_WINDOW_MS } from "./combo";
import { DEFAULT_SENDER_NAME, MAX_CONCURRENT_EFFECTS, MAX_QUEUED_LARGE } from "./effects";
import { DEFAULT_THRESHOLDS, allRecipes } from "./recipes";
import { SPEC_VERSION } from "./version";

export { SPEC_VERSION };

export function specData() {
  return {
    specVersion: SPEC_VERSION,
    thresholds: { ...DEFAULT_THRESHOLDS },
    comboWindowMs: DEFAULT_COMBO_WINDOW_MS,
    maxConcurrentEffects: { ...MAX_CONCURRENT_EFFECTS },
    maxQueuedLarge: MAX_QUEUED_LARGE,
    defaultSenderName: DEFAULT_SENDER_NAME,
    recipes: { high: allRecipes("high"), low: allRecipes("low") },
  };
}
