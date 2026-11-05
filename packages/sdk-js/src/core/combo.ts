/**
 * Counts the same gift sent again and again by the same person ("x2, x3, x4"). A pause longer
 * than the window starts a new run. Every (sender, gift) pair keeps its own run, so several
 * people can combo at the same time.
 */
export interface ComboTracker {
  /** Register one more send and return how many in a row this is, starting at 1. */
  hit(sender: string, giftId: string, now?: number): number;
  reset(): void;
}

export const DEFAULT_COMBO_WINDOW_MS = 2500;
/** Runs remembered at once (the oldest is dropped beyond this). */
export const MAX_COMBO_RUNS = 64;

/** `windowMs` may be a function; it is then read at every hit (remote recipes, spec section 13). */
export function createComboTracker(
  windowMs: number | (() => number) = DEFAULT_COMBO_WINDOW_MS,
): ComboTracker {
  const runs = new Map<string, { count: number; at: number }>();
  return {
    hit(sender, giftId, now = Date.now()) {
      const window = typeof windowMs === "function" ? windowMs() : windowMs;
      // JSON keeps ids that contain separators from running together.
      const key = JSON.stringify([sender, giftId]);
      // A run that paused for the window or more is over.
      for (const [k, run] of runs) if (now - run.at >= window) runs.delete(k);
      const count = (runs.get(key)?.count ?? 0) + 1;
      runs.delete(key); // the newest run goes last
      runs.set(key, { count, at: now });
      if (runs.size > MAX_COMBO_RUNS) runs.delete(runs.keys().next().value as string);
      return count;
    },
    reset() {
      runs.clear();
    },
  };
}
