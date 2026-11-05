/**
 * "While you were away" logic (SPEC section 15): the replay plan for the effect layer and the
 * controller behind the summary card. No drawing; the clock and timers are injected.
 */
import type { GiftingClient, GiftingError } from "./client";
import {
  type EffectQuality,
  type EffectRecipe,
  type EffectTier,
  type TierThresholds,
  recipeFor,
  tierFor,
} from "./recipes";
import { asGiftingError } from "./tray";
import type { AwayGroup, AwaySummary, GiftEffectEvent } from "./types";

/** Gift groups replayed at most. */
export const DEFAULT_AWAY_MAX_EFFECTS = 5;
/** The replay must have ended by then (ms after the card appears). */
export const DEFAULT_AWAY_BUDGET_MS = 8_000;
/** Start gap after a small effect, then after a medium one (keeps medium at <= 2 at once). */
export const AWAY_GAP_AFTER_MS: Readonly<Record<"small" | "medium", number>> = {
  small: 450,
  medium: 1_100,
};
/** The large effect starts this long after every earlier effect has ended. */
export const AWAY_LARGE_PAUSE_MS = 300;
/** The card stays at least this long, and this long after the last effect ends. */
export const AWAY_CARD_MIN_MS = 4_000;
export const AWAY_CARD_TAIL_MS = 1_500;
/** `foreground()` checks again at most this often. */
export const AWAY_FOREGROUND_THROTTLE_MS = 60_000;

/**
 * How long one effect runs, from SPEC 7.3: `flyInMs + max(900, tail, coins > 0 ? tail + 800 : 0)`
 * with `tail = holdMs + flyOutMs`. Small 1600, medium 2100, large 3850 (3050 at low quality).
 */
export function effectDurationMs(recipe: EffectRecipe): number {
  const tail = recipe.holdMs + recipe.flyOutMs;
  return recipe.flyInMs + Math.max(900, tail, recipe.coins > 0 ? tail + 800 : 0);
}

export interface AwaySenderLabels {
  /** A deleted sender. Default `"Someone"`. */
  someone?: string;
  /** Two people. Default `"{a} and {b}"`. */
  pair?: string;
  /** One named person and one more. Default `"{a} and 1 other"`. */
  oneOther?: string;
  /** One named person and `{n}` more. Default `"{a} and {n} others"`. */
  others?: string;
}

/**
 * Who sent a group, for the effect's notice. `names` are display names in the server's order
 * (a deleted sender already turned into `labels.someone`), `senderCount` the number of distinct
 * people. 1 -> `"ayla"`; 2 with two names -> `"ayla and mert"`; otherwise
 * `"ayla and {senderCount - 1} others"` (`"... and 1 other"` for one). No name -> `someone`.
 */
export function awaySenderLabel(
  names: readonly string[],
  senderCount: number,
  labels: AwaySenderLabels = {},
): string {
  const someone = labels.someone ?? "Someone";
  const a = names[0] ?? someone;
  if (senderCount <= 1) return a;
  if (senderCount === 2 && names.length >= 2) {
    return (labels.pair ?? "{a} and {b}").replace("{a}", a).replace("{b}", names[1]!);
  }
  const n = senderCount - 1;
  if (n === 1) return (labels.oneOther ?? "{a} and 1 other").replace("{a}", a);
  return (labels.others ?? "{a} and {n} others").replace("{a}", a).replace("{n}", String(n));
}

export interface AwayReplayOptions {
  maxEffects?: number;
  budgetMs?: number;
  thresholds?: Partial<TierThresholds>;
  quality?: EffectQuality;
  /** Or no effect layer: the plan is empty and only the card shows. */
  reducedMotion?: boolean;
  /** Display name of a sender id. Default: the id itself. Deleted senders are always `labels.someone`. */
  resolveName?: (user: string) => string;
  labels?: AwaySenderLabels;
}

export interface AwayReplayItem {
  /** Start, in ms after the card appeared. */
  atMs: number;
  durationMs: number;
  tier: EffectTier;
  group: AwayGroup;
  /** What to pass to the effect layer's `play`. */
  event: GiftEffectEvent;
}

export interface AwayReplayPlan {
  /** In start order. */
  items: AwayReplayItem[];
  /** When the last effect ends (0 for an empty plan). */
  endMs: number;
}

/**
 * Plans the replay of an away summary as one short sequence, biggest last (SPEC 15.3):
 * the first `maxEffects` groups; only the first large one; small and medium by units ascending
 * (ties: gift id), then the large one; gaps 450 after small, 1100 after medium, the large one
 * 300 ms after everything before it ended; while the end is past `budgetMs`, the non-large item
 * with the lowest units goes (a lone large item that does not fit goes too).
 */
export function planAwayReplay(
  groups: readonly AwayGroup[],
  options: AwayReplayOptions = {},
): AwayReplayPlan {
  if (options.reducedMotion) return { items: [], endMs: 0 };
  const quality = options.quality ?? "high";
  const budget = options.budgetMs ?? DEFAULT_AWAY_BUDGET_MS;
  const max = Math.max(0, Math.floor(options.maxEffects ?? DEFAULT_AWAY_MAX_EFFECTS));
  const someone = options.labels?.someone ?? "Someone";
  const resolveName = options.resolveName ?? ((u: string) => u);

  const tiered = groups.slice(0, max).map((group) => ({
    group,
    tier: tierFor(group.gift.price, options.thresholds),
  }));
  const large = tiered.find((t) => t.tier === "large");
  const rest = tiered
    .filter((t) => t.tier !== "large")
    .sort((a, b) =>
      a.group.units !== b.group.units
        ? a.group.units - b.group.units
        : a.group.gift.id < b.group.gift.id
          ? -1
          : a.group.gift.id > b.group.gift.id
            ? 1
            : 0,
    );

  const layout = (small: typeof rest, big: typeof large) => {
    const items: AwayReplayItem[] = [];
    let at = 0;
    let end = 0;
    for (const t of small) {
      const durationMs = effectDurationMs(recipeFor(t.tier, quality));
      items.push(makeItem(t.group, t.tier, at, durationMs));
      end = Math.max(end, at + durationMs);
      at += AWAY_GAP_AFTER_MS[t.tier as "small" | "medium"];
    }
    if (big) {
      const start = items.length ? end + AWAY_LARGE_PAUSE_MS : 0;
      const durationMs = effectDurationMs(recipeFor("large", quality));
      items.push(makeItem(big.group, "large", start, durationMs));
      end = start + durationMs;
    }
    return { items, endMs: end };
  };
  const makeItem = (
    group: AwayGroup,
    tier: EffectTier,
    atMs: number,
    durationMs: number,
  ): AwayReplayItem => ({
    atMs,
    durationMs,
    tier,
    group,
    event: {
      gift: {
        id: group.gift.id,
        name: group.gift.name,
        price: group.gift.price,
        image: group.gift.animation_url ?? group.gift.icon_url,
        icon: group.gift.icon_url,
      },
      quantity: group.count,
      sender: awaySenderLabel(
        group.senders.map((s) => (s.user === null ? someone : resolveName(s.user))),
        group.sender_count,
        options.labels,
      ),
    },
  });

  let small = rest;
  let big = large;
  let plan = layout(small, big);
  while (plan.endMs > budget && plan.items.length > 0) {
    if (small.length > 0) small = small.slice(1);
    else big = undefined;
    plan = layout(small, big);
  }
  return plan;
}

/** How long the card stays: `max(4000, plan end + 1500)` ms. */
export function awayCardDurationMs(plan: AwayReplayPlan): number {
  return Math.max(AWAY_CARD_MIN_MS, plan.endMs + AWAY_CARD_TAIL_MS);
}

// ---------------------------------------------------------------- controller

export type AwayStatus = "idle" | "loading" | "empty" | "ready" | "playing" | "done";
export type AwayAckOn = "shown" | "finished" | "manual";

/** The part of an effect layer the replay needs. */
export interface AwayEffectPlayer {
  play(event: GiftEffectEvent): number;
}

export interface AwayControllerOptions extends Omit<AwayReplayOptions, "reducedMotion"> {
  client: Pick<GiftingClient, "getAway" | "ackAway">;
  /** The effect layer, read at each play. None: card only. */
  effects?: () => AwayEffectPlayer | null | undefined;
  /** Read when the card appears. */
  reducedMotion?: () => boolean;
  /** When the summary counts as seen. Default `"shown"`. */
  ackOn?: AwayAckOn;
  /** Sent as `max_groups` when given. */
  maxGroups?: number;
  /** The card shows only with at least this many gifts (default 1). Fewer: `empty`, still acknowledged. */
  minGifts?: number;
  onShow?: (summary: AwaySummary) => void;
  onDone?: () => void;
  /** Failures never show; they come here. */
  onError?: (error: GiftingError) => void;
  /** Default `Date.now`. */
  now?: () => number;
  setTimeout?: (fn: () => void, ms: number) => unknown;
  clearTimeout?: (handle: unknown) => void;
  /** Default 60,000. */
  throttleMs?: number;
}

export interface AwayState {
  status: AwayStatus;
  /** The summary being shown (ready, playing, done), else null. */
  summary: AwaySummary | null;
  /** The replay, planned when the card appears (playing, done), else null. */
  plan: AwayReplayPlan | null;
}

/**
 * Drives one summary card: `check()` loads, the UI shows the card and calls `start()`, the
 * controller plays the replay and dismisses the card after `awayCardDurationMs`, or earlier on
 * `dismiss()`. idle -> loading -> empty | ready -> playing -> done; a failed load goes back to
 * idle silently. `check()` runs only from a resting state (idle, empty, done).
 */
export class AwayController {
  private options: AwayControllerOptions;
  private state: AwayState = { status: "idle", summary: null, plan: null };
  private readonly listeners = new Set<() => void>();
  private timers: unknown[] = [];
  private alive = true;
  /** Whether the summary on screen was acknowledged (or its one attempt was made). */
  private acked = false;
  /** A cursor whose acknowledgement failed: retried once, at the next check. */
  private retryCursor: string | null = null;
  private lastCheckAt: number | null = null;

  constructor(options: AwayControllerOptions) {
    this.options = options;
  }

  /** Callbacks and settings are read when used, so they can change between calls. */
  setOptions(options: AwayControllerOptions): void {
    this.options = options;
  }

  getState = (): AwayState => this.state;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  private set(patch: Partial<AwayState>): void {
    this.state = { ...this.state, ...patch };
    for (const l of this.listeners) l();
  }

  private now(): number {
    return (this.options.now ?? Date.now)();
  }

  private later(fn: () => void, ms: number): void {
    const schedule = this.options.setTimeout ?? ((f: () => void, t: number) => setTimeout(f, t));
    this.timers.push(schedule(fn, ms));
  }

  private stopTimers(): void {
    const cancel =
      this.options.clearTimeout ??
      ((h: unknown) => clearTimeout(h as ReturnType<typeof setTimeout>));
    for (const t of this.timers) cancel(t);
    this.timers = [];
  }

  /** Ask the server what arrived. Ignored while loading, ready or playing. */
  check = async (): Promise<void> => {
    const s = this.state.status;
    if (s !== "idle" && s !== "empty" && s !== "done") return;
    this.lastCheckAt = this.now();
    this.set({ status: "loading", summary: null, plan: null });
    const { client } = this.options;
    if (this.retryCursor !== null) {
      const cursor = this.retryCursor;
      this.retryCursor = null;
      try {
        await client.ackAway(cursor);
      } catch (err) {
        if (this.alive) this.options.onError?.(asGiftingError(err));
      }
      if (!this.alive) return;
    }
    let summary: AwaySummary;
    try {
      const max = this.options.maxGroups;
      summary = await client.getAway(max === undefined ? {} : { maxGroups: max });
    } catch (err) {
      if (!this.alive) return;
      this.set({ status: "idle" });
      this.options.onError?.(asGiftingError(err));
      return;
    }
    if (!this.alive) return;
    this.acked = false;
    if (summary.total_gifts <= 0) this.set({ status: "empty" });
    else if (summary.total_gifts < (this.options.minGifts ?? 1)) {
      this.set({ status: "empty" });
      await this.sendAck(summary.cursor);
    } else this.set({ status: "ready", summary });
  };

  /** The app came back to the foreground: `check()` unless one ran less than 60 s ago. */
  foreground = (): Promise<void> => {
    const last = this.lastCheckAt;
    const throttle = this.options.throttleMs ?? AWAY_FOREGROUND_THROTTLE_MS;
    if (last !== null && this.now() - last < throttle) return Promise.resolve();
    return this.check();
  };

  /** The card is on screen: plan and play the replay, schedule the dismissal. Only from ready. */
  start = (): void => {
    const summary = this.state.summary;
    if (this.state.status !== "ready" || !summary) return;
    const o = this.options;
    const player = o.effects?.();
    const plan = planAwayReplay(summary.groups, {
      maxEffects: o.maxEffects,
      budgetMs: o.budgetMs,
      thresholds: o.thresholds,
      quality: o.quality,
      resolveName: o.resolveName,
      labels: o.labels,
      reducedMotion: !player || (o.reducedMotion?.() ?? false),
    });
    this.set({ status: "playing", plan });
    for (const item of plan.items) {
      this.later(() => {
        if (this.alive && this.state.status === "playing")
          this.options.effects?.()?.play(item.event);
      }, item.atMs);
    }
    this.later(() => this.dismiss(), awayCardDurationMs(plan));
    o.onShow?.(summary);
    if ((o.ackOn ?? "shown") === "shown") void this.ack();
  };

  /** Tap or timeout: the card goes. Plays not started yet are dropped; running ones finish. */
  dismiss = (): void => {
    const s = this.state.status;
    if (s !== "ready" && s !== "playing") return;
    this.stopTimers();
    this.set({ status: "done" });
    if ((this.options.ackOn ?? "shown") !== "manual") void this.ack();
    this.options.onDone?.();
  };

  /**
   * Marks the summary on screen as seen (`ackAway(summary.cursor)`). At most once per summary; a
   * failure is retried once at the next `check()`. `ackOn: "manual"` apps call this themselves.
   */
  ack = async (): Promise<void> => {
    const cursor = this.state.summary?.cursor;
    if (this.acked || !cursor) return;
    this.acked = true;
    await this.sendAck(cursor);
  };

  private sendAck = async (cursor: string | null | undefined): Promise<void> => {
    if (!cursor) return;
    try {
      await this.options.client.ackAway(cursor);
    } catch (err) {
      this.retryCursor = cursor;
      if (this.alive) this.options.onError?.(asGiftingError(err));
    }
  };

  /** The screen is gone: timers stop, answers that arrive later change nothing. */
  dispose(): void {
    this.alive = false;
    this.stopTimers();
  }
}
