/**
 * Gifts that arrive by themselves, like a live app: every 20-40 s, mostly small, now and then
 * medium, rarely large. Pure logic with an injectable random source and timer, so it can be
 * tested with fake timers. Not part of the SDK.
 */
import type { Gift } from "../src/core";

export type Tier = "small" | "medium" | "large";

export interface Incoming {
  gift: Gift;
  sender: string;
  quantity: number;
  tier: Tier;
}

/** Same default limits as the effect layer: medium from 100, large from 10,000. */
export const TIER_FROM = { medium: 100, large: 10_000 } as const;
export const MIN_DELAY_MS = 20_000;
export const MAX_DELAY_MS = 40_000;

export const tierOf = (price: number): Tier =>
  price >= TIER_FROM.large ? "large" : price >= TIER_FROM.medium ? "medium" : "small";

/** 78 % small, 19 % medium, 3 % large. */
export function rollTier(r: number): Tier {
  return r < 0.78 ? "small" : r < 0.97 ? "medium" : "large";
}

export function nextDelay(rand: () => number): number {
  return MIN_DELAY_MS + Math.floor(rand() * (MAX_DELAY_MS - MIN_DELAY_MS));
}

export function pickIncoming(gifts: Gift[], senders: string[], rand: () => number): Incoming {
  const order: Tier[] = ["small", "medium", "large"];
  const want = rollTier(rand());
  // An empty tier falls back to the nearest one that has gifts.
  const tier =
    [...order]
      .sort(
        (a, b) =>
          Math.abs(order.indexOf(a) - order.indexOf(want)) -
          Math.abs(order.indexOf(b) - order.indexOf(want)),
      )
      .find((t) => gifts.some((g) => tierOf(g.price) === t)) ?? want;
  const pool = gifts.filter((g) => tierOf(g.price) === tier);
  const gift = (pool.length > 0 ? pool : gifts)[
    Math.floor(rand() * Math.max(1, pool.length || gifts.length))
  ]!;
  const sender = senders[Math.floor(rand() * senders.length)]!;
  const quantity =
    tier === "small"
      ? 1 + Math.floor(rand() * 3)
      : tier === "medium"
        ? 1 + Math.floor(rand() * 2)
        : 1;
  return { gift, sender, quantity, tier: tierOf(gift.price) };
}

export interface IncomingOptions {
  gifts: Gift[];
  senders: string[];
  onGift: (incoming: Incoming) => void;
  rand?: () => number;
  setTimer?: (fn: () => void, ms: number) => unknown;
  clearTimer?: (id: unknown) => void;
}

/** Starts the stream; `stop()` ends it. The first gift comes after one random delay. */
export function startIncoming(o: IncomingOptions): { stop(): void } {
  const rand = o.rand ?? Math.random;
  const setTimer = o.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
  const clearTimer = o.clearTimer ?? ((id) => clearTimeout(id as ReturnType<typeof setTimeout>));
  let timer: unknown;
  let stopped = false;
  const arm = (): void => {
    timer = setTimer(() => {
      if (stopped) return;
      if (o.gifts.length > 0 && o.senders.length > 0)
        o.onGift(pickIncoming(o.gifts, o.senders, rand));
      arm();
    }, nextDelay(rand));
  };
  arm();
  return {
    stop() {
      stopped = true;
      clearTimer(timer);
    },
  };
}
