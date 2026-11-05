/**
 * Gift wall logic (SPEC section 14): which chips a wall shows, how counts are written, and a
 * loader that batches the walls of a feed into few requests. No drawing, no timers of its own:
 * the clock and the timer are injected so the fixtures can drive it.
 */
import type { GiftWall, GiftWallQueryItem, ReceivedGift } from "./types";

/** Chips a wall shows by default, the overflow chip included. */
export const DEFAULT_WALL_MAX = 6;

/** `"count"`: most received first (ties keep the catalog order). `"catalog"`: the server's order. */
export type WallOrder = "count" | "catalog";

export type WallChip =
  | { type: "gift"; gift: ReceivedGift["gift"]; count: number }
  /** `count` = the SUM of the hidden gifts' counts; `hidden` = how many gift kinds it stands for. */
  | { type: "overflow"; count: number; hidden: number };

export interface WallChipsOptions {
  /** Chips shown including the overflow chip. Default 6; values below 1 count as 1. */
  max?: number;
  order?: WallOrder;
}

/**
 * The chips of a wall. `items` comes in catalog order (as the API sends it). Counts of 0 or less
 * are dropped. With more gifts than `max`, the first `max - 1` are shown and one overflow chip
 * carries the sum of the rest.
 */
export function wallChips(
  items: readonly ReceivedGift[],
  options: WallChipsOptions = {},
): WallChip[] {
  const max = Math.max(1, Math.floor(options.max ?? DEFAULT_WALL_MAX));
  const kept = items.filter((i) => i.count > 0);
  // Array.prototype.sort is stable, so equal counts keep the catalog order.
  if ((options.order ?? "count") === "count") kept.sort((a, b) => b.count - a.count);
  const chip = (i: ReceivedGift): WallChip => ({ type: "gift", gift: i.gift, count: i.count });
  if (kept.length <= max) return kept.map(chip);
  const shown = kept.slice(0, max - 1);
  const hidden = kept.slice(max - 1);
  return [
    ...shown.map(chip),
    { type: "overflow", count: hidden.reduce((sum, i) => sum + i.count, 0), hidden: hidden.length },
  ];
}

export interface CountLabels {
  /** Default `"K"`. */
  thousand?: string;
  /** Default `"M"`. */
  million?: string;
  /** Default `"."`. */
  decimal?: string;
}

/**
 * A short count that never overstates: `999`, `1K`, `1.9K` (1,999), `12K`, `999K`, `1M`, `1.2M`,
 * `12M`. Always rounded DOWN; a `.0` is left out. Negative or fractional input: truncated
 * towards zero first, and below 1,000 written as is.
 */
export function formatCount(n: number, labels: CountLabels = {}): string {
  const k = labels.thousand ?? "K";
  const m = labels.million ?? "M";
  const dot = labels.decimal ?? ".";
  const v = Number.isFinite(n) ? Math.trunc(n) : 0;
  const tenths = (unit: number, suffix: string) => {
    const t = Math.floor(v / (unit / 10));
    const whole = Math.floor(t / 10);
    const dec = t % 10;
    return dec === 0 ? `${whole}${suffix}` : `${whole}${dot}${dec}${suffix}`;
  };
  if (v < 1_000) return String(v);
  if (v < 10_000) return tenths(1_000, k);
  if (v < 1_000_000) return `${Math.floor(v / 1_000)}${k}`;
  if (v < 10_000_000) return tenths(1_000_000, m);
  return `${Math.floor(v / 1_000_000)}${m}`;
}

// ---------------------------------------------------------------- loader

/** Requests made within this many ms of the first one share one batch call. */
export const WALL_BATCH_WINDOW_MS = 50;
/** The API answers at most this many walls per call; more make several calls. */
export const WALL_BATCH_SIZE = 25;
/** A wall's answer is reused for this long. */
export const WALL_CACHE_TTL_MS = 60_000;

export interface GiftWallLoaderOptions {
  /** The batch call, usually `(items) => client.queryGiftWalls(items)`. */
  query: (items: GiftWallQueryItem[]) => Promise<GiftWall[]>;
  /** Default `Date.now`. */
  now?: () => number;
  /** Default the global `setTimeout`. */
  setTimeout?: (fn: () => void, ms: number) => unknown;
  windowMs?: number;
  batchSize?: number;
  ttlMs?: number;
}

interface Waiter {
  item: GiftWallQueryItem;
  promise: Promise<ReceivedGift[]>;
  resolve: (v: ReceivedGift[]) => void;
  reject: (e: unknown) => void;
  generation: number;
}

const keyOf = (user: string, reference?: string | null) => `${user}\u0000${reference ?? ""}`;

/**
 * Shares wall requests across every `GiftWall` on a screen. `load` calls made within
 * `windowMs` (50) of the first queued one go out together when that window closes, in batches
 * of at most 25 walls, in the order first asked. A wall that is queued or in flight is not asked
 * again (same promise). An answer is cached per `(user, reference)` for `ttlMs` (60,000) from
 * the moment it arrived; a failure is not cached.
 */
export class GiftWallLoader {
  private readonly opts: GiftWallLoaderOptions;
  private readonly cache = new Map<string, { gifts: ReceivedGift[]; at: number }>();
  /** Queued (window open) or in flight, by key. */
  private readonly waiting = new Map<string, Waiter>();
  /** Keys queued in the open window, in the order first asked. */
  private queue: string[] = [];
  private windowOpen = false;
  private readonly generations = new Map<string, number>();

  constructor(options: GiftWallLoaderOptions) {
    this.opts = options;
  }

  private now(): number {
    return (this.opts.now ?? Date.now)();
  }

  private ttl(): number {
    return this.opts.ttlMs ?? WALL_CACHE_TTL_MS;
  }

  /** The cached wall if it is still fresh, else `undefined`. Lets a wall draw at once. */
  peek(user: string, reference?: string | null): ReceivedGift[] | undefined {
    const hit = this.cache.get(keyOf(user, reference));
    return hit && this.now() - hit.at < this.ttl() ? hit.gifts : undefined;
  }

  load(user: string, reference?: string | null): Promise<ReceivedGift[]> {
    const fresh = this.peek(user, reference);
    if (fresh) return Promise.resolve(fresh);
    const key = keyOf(user, reference);
    const known = this.waiting.get(key);
    if (known) return known.promise;
    let resolve!: (v: ReceivedGift[]) => void;
    let reject!: (e: unknown) => void;
    const promise = new Promise<ReceivedGift[]>((res, rej) => {
      resolve = res;
      reject = rej;
    });
    const item: GiftWallQueryItem =
      reference === undefined || reference === null
        ? { receiver: user }
        : { receiver: user, reference };
    this.waiting.set(key, {
      item,
      promise,
      resolve,
      reject,
      generation: this.generations.get(key) ?? 0,
    });
    this.queue.push(key);
    if (!this.windowOpen) {
      this.windowOpen = true;
      const schedule = this.opts.setTimeout ?? ((fn: () => void, ms: number) => setTimeout(fn, ms));
      schedule(() => this.flush(), this.opts.windowMs ?? WALL_BATCH_WINDOW_MS);
    }
    return promise;
  }

  /**
   * Forget a wall (for example after the person sent a gift to it): the next `load` asks the
   * server again, even if an older request is still in flight (its answer is then not cached).
   */
  invalidate(user: string, reference?: string | null): void {
    const key = keyOf(user, reference);
    this.cache.delete(key);
    const generation = (this.generations.get(key) ?? 0) + 1;
    this.generations.set(key, generation);
    const w = this.waiting.get(key);
    if (!w) return;
    // A queued wall has not been asked yet: it goes out with its window and its answer counts.
    // One in flight is let go: its answer reaches its callers but is not cached.
    if (this.queue.includes(key)) w.generation = generation;
    else this.waiting.delete(key);
  }

  /** Forget every cached wall (requests already queued or in flight are kept). */
  clear(): void {
    this.cache.clear();
  }

  private flush(): void {
    this.windowOpen = false;
    const keys = this.queue;
    this.queue = [];
    const size = Math.max(1, this.opts.batchSize ?? WALL_BATCH_SIZE);
    for (let i = 0; i < keys.length; i += size) {
      const chunk = keys.slice(i, i + size);
      const waiters = chunk.map((k) => this.waiting.get(k)!);
      void this.send(chunk, waiters);
    }
  }

  private async send(keys: string[], waiters: Waiter[]): Promise<void> {
    try {
      const walls = await this.opts.query(waiters.map((w) => w.item));
      const at = this.now();
      waiters.forEach((w, i) => {
        const key = keys[i]!;
        const gifts = walls[i]?.gifts ?? [];
        if (this.waiting.get(key) === w) this.waiting.delete(key);
        if ((this.generations.get(key) ?? 0) === w.generation) this.cache.set(key, { gifts, at });
        w.resolve(gifts);
      });
    } catch (err) {
      waiters.forEach((w, i) => {
        const key = keys[i]!;
        if (this.waiting.get(key) === w) this.waiting.delete(key);
        w.reject(err);
      });
    }
  }
}
