/**
 * Leaderboard logic (SPEC section 16): tabs, a per-tab cache that answers at once and
 * revalidates in the background, the pinned "your rank" row and rank labels. No drawing; the
 * clock is injected.
 */
import type { GiftingClient, GiftingError } from "./client";
import { asGiftingError } from "./tray";
import type {
  Leaderboard,
  LeaderboardBoard,
  LeaderboardMe,
  LeaderboardMetric,
  LeaderboardPeriod,
} from "./types";

export const LEADERBOARD_PERIODS: readonly LeaderboardPeriod[] = ["day", "week", "month", "all"];
/** A cached tab older than this is shown and fetched again in the background. */
export const LEADERBOARD_STALE_MS = 30_000;
export const DEFAULT_LEADERBOARD_LIMIT = 10;

/**
 * Medal colours for ranks 1 to 3 (new tokens, used only by the leaderboard). The rank number on
 * them uses the theme's `noticeBigText`; the contract is >= 4.5:1 (fixture `leaderboard.json`).
 */
export const RANK_COLORS: Readonly<{ rank1: string; rank2: string; rank3: string }> = {
  rank1: "#e8a93a",
  rank2: "#b8bcc8",
  rank3: "#c07a45",
};

/** `1234567` -> `"1,234,567"`: whole numbers with a separator every three digits. */
export function groupThousands(n: number, separator = ","): string {
  const v = Math.trunc(n);
  const digits = String(Math.abs(v)).replace(/\B(?=(\d{3})+(?!\d))/g, separator);
  return v < 0 ? `-${digits}` : digits;
}

/** The shortest polling period a leaderboard accepts: 5 s (SPEC 16.4, audit R-17). */
export const LEADERBOARD_MIN_POLL_MS = 5_000;

/**
 * The polling period of a `refreshIntervalMs` option: 0 (or less, or not a number) is no polling,
 * anything else is at least `LEADERBOARD_MIN_POLL_MS`, so `refreshIntervalMs: 50` cannot turn a
 * screen into a request flood.
 */
export function leaderboardPollMs(refreshIntervalMs: number | null | undefined): number {
  const ms = refreshIntervalMs ?? 0;
  return Number.isFinite(ms) && ms > 0 ? Math.max(LEADERBOARD_MIN_POLL_MS, Math.floor(ms)) : 0;
}

/** `"#1"`, `"#417"`, `"#1,000"`; `null` (beyond the top 1,000) -> `"1,000+"`. */
export function leaderboardRankLabel(
  rank: number | null,
  labels: { overflow?: string } = {},
): string {
  return rank === null ? (labels.overflow ?? "1,000+") : `#${groupThousands(rank)}`;
}

/**
 * The viewer's own row, pinned under the list, or null. Pinned when the viewer has a `me` block,
 * is not hidden, has a score above 0 on the metric, and is not visible in the rows: `rank` is
 * null (beyond the top 1,000) or greater than `limit`, or a tie at the cut put them outside the
 * returned rows.
 */
export function pinnedMe(board: Leaderboard | null, limit: number): LeaderboardMe | null {
  const me = board?.me;
  if (!board || !me || me.hidden) return null;
  if ((board.metric === "gifts" ? me.gifts : me.units) <= 0) return null;
  if (me.rank === null || me.rank > limit) return me;
  return board.data.some((r) => r.user === me.user) ? null : me;
}

export type LeaderboardStatus = "loading" | "ready" | "empty" | "error";

export interface LeaderboardControllerOptions {
  client: Pick<GiftingClient, "getLeaderboard">;
  /** Default `"senders"`. */
  board?: LeaderboardBoard;
  /** Tabs, in this order. Default day, week, month, all. */
  periods?: readonly LeaderboardPeriod[];
  /** Default `"week"`, or the first of `periods` when week is not one of them. */
  initialPeriod?: LeaderboardPeriod;
  /** Default `"gifts"` for receivers, `"units"` for senders. */
  metric?: LeaderboardMetric;
  /** Rows, 1 to 100. Default 10. */
  limit?: number;
  /** Default true: ask for the viewer's own `me` block. */
  includeMe?: boolean;
  /** Default 30,000. */
  staleMs?: number;
  /** Default `Date.now`. */
  now?: () => number;
  onError?: (error: GiftingError) => void;
}

export interface LeaderboardState {
  periods: readonly LeaderboardPeriod[];
  period: LeaderboardPeriod;
  metric: LeaderboardMetric;
  /**
   * loading: nothing to show yet (skeleton rows); ready / empty: `data` is shown (empty = no
   * rows); error: the first load of this tab failed (message + "Try again").
   */
  status: LeaderboardStatus;
  /** The answer shown for the current tab (possibly stale), else null. */
  data: Leaderboard | null;
  /** A request for the current tab is in flight while `data` stays visible. */
  refreshing: boolean;
  /** The last failure for the current tab, cleared by its next success. */
  error: GiftingError | null;
  /** The viewer's row to pin under the list (`pinnedMe`). */
  pinned: LeaderboardMe | null;
}

type TabKey = `${LeaderboardPeriod}|${LeaderboardMetric}`;

export class LeaderboardController {
  private options: LeaderboardControllerOptions;
  private state: LeaderboardState;
  private readonly listeners = new Set<() => void>();
  private readonly cache = new Map<TabKey, { value: Leaderboard; at: number }>();
  private readonly errors = new Map<TabKey, GiftingError>();
  private readonly inFlight = new Set<TabKey>();
  /** Bumped when the cache is dropped: a request that began before it must not write its answer. */
  private epoch = 0;
  private started = false;
  private alive = true;

  constructor(options: LeaderboardControllerOptions) {
    this.options = options;
    const periods = options.periods?.length ? options.periods : LEADERBOARD_PERIODS;
    const wanted = options.initialPeriod ?? "week";
    this.state = {
      periods,
      period: periods.includes(wanted) ? wanted : periods[0]!,
      metric: options.metric ?? ((options.board ?? "senders") === "receivers" ? "gifts" : "units"),
      status: "loading",
      data: null,
      refreshing: false,
      error: null,
      pinned: null,
    };
  }

  /**
   * Callbacks are read when used. A change of `board`, `limit` or `includeMe` makes every cached
   * tab wrong, so the cache is dropped and the open tab is fetched again (answers still on their
   * way for the old setting are ignored). A new `board` also picks that board's default metric.
   */
  setOptions(options: LeaderboardControllerOptions): void {
    const before = this.options;
    this.options = options;
    const board = options.board ?? "senders";
    const boardChanged = board !== (before.board ?? "senders");
    const changed =
      boardChanged ||
      (options.limit ?? DEFAULT_LEADERBOARD_LIMIT) !==
        (before.limit ?? DEFAULT_LEADERBOARD_LIMIT) ||
      (options.includeMe ?? true) !== (before.includeMe ?? true);
    if (!changed) return;
    this.epoch++;
    this.cache.clear();
    this.errors.clear();
    this.inFlight.clear();
    if (boardChanged) {
      this.state = {
        ...this.state,
        metric: options.metric ?? (board === "receivers" ? "gifts" : "units"),
      };
    }
    if (this.started) this.show(true);
  }

  getState = (): LeaderboardState => this.state;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  private limit(): number {
    return this.options.limit ?? DEFAULT_LEADERBOARD_LIMIT;
  }

  private now(): number {
    return (this.options.now ?? Date.now)();
  }

  private key(): TabKey {
    return `${this.state.period}|${this.state.metric}`;
  }

  /** Recompute the visible state of the current tab from the cache and the requests. */
  private render(): void {
    const key = this.key();
    const hit = this.cache.get(key);
    const error = this.errors.get(key) ?? null;
    const data = hit?.value ?? null;
    this.state = {
      ...this.state,
      data,
      error,
      refreshing: data !== null && this.inFlight.has(key),
      status: data
        ? data.data.length
          ? "ready"
          : "empty"
        : error && !this.inFlight.has(key)
          ? "error"
          : "loading",
      pinned: pinnedMe(data, this.limit()),
    };
    for (const l of this.listeners) l();
  }

  /** Show the current tab: cached answer at once, a request if none or if it is stale. */
  private show(force: boolean): void {
    const key = this.key();
    const hit = this.cache.get(key);
    const stale = !hit || this.now() - hit.at >= (this.options.staleMs ?? LEADERBOARD_STALE_MS);
    if ((force || stale) && !this.inFlight.has(key)) void this.fetch(key);
    this.render();
  }

  private async fetch(key: TabKey): Promise<void> {
    const [period, metric] = key.split("|") as [LeaderboardPeriod, LeaderboardMetric];
    const epoch = this.epoch;
    this.inFlight.add(key);
    const includeMe = this.options.includeMe ?? true;
    try {
      const value = await this.options.client.getLeaderboard(this.options.board ?? "senders", {
        period,
        metric,
        limit: this.limit(),
        ...(includeMe ? {} : { includeMe: false }),
      });
      if (epoch === this.epoch) {
        this.cache.set(key, { value, at: this.now() });
        this.errors.delete(key);
      }
    } catch (err) {
      if (epoch === this.epoch) {
        const e = asGiftingError(err);
        this.errors.set(key, e);
        if (this.alive) this.options.onError?.(e);
      }
    } finally {
      if (epoch === this.epoch) this.inFlight.delete(key);
    }
    if (this.alive && epoch === this.epoch) this.render();
  }

  /** The screen opened: load the first tab. */
  start = (): void => {
    this.started = true;
    this.show(false);
  };

  setPeriod = (period: LeaderboardPeriod): void => {
    if (period === this.state.period) return;
    this.state = { ...this.state, period };
    this.show(false);
  };

  setMetric = (metric: LeaderboardMetric): void => {
    if (metric === this.state.metric) return;
    this.state = { ...this.state, metric };
    this.show(false);
  };

  /** Fetch the current tab again now (pull to refresh, "Try again", a poll). */
  refresh = (): void => this.show(true);

  /** The screen is gone: answers that arrive later change nothing. */
  dispose(): void {
    this.alive = false;
  }
}
