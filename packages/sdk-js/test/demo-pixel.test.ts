/** The web demo's own logic (demo/incoming.ts, demo/devMenu.ts): not SDK code, but the demo relies on it. */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Gift } from "../src/core";
import { type DevMenuActions, attachDevTrigger, createDevMenu } from "../demo/devMenu";
import {
  MAX_DELAY_MS,
  MIN_DELAY_MS,
  pickIncoming,
  rollTier,
  startIncoming,
  tierOf,
} from "../demo/incoming";

const gift = (id: string, price: number): Gift => ({
  id,
  name: id,
  description: null,
  price,
  icon_url: null,
  animation_url: null,
  sort_order: 0,
});
const GIFTS = [gift("a", 10), gift("b", 500), gift("c", 20_000)];

describe("demo incoming gifts", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("rolls mostly small, sometimes medium, rarely large", () => {
    expect([0, 0.5, 0.77].map(rollTier)).toEqual(["small", "small", "small"]);
    expect([0.78, 0.96].map(rollTier)).toEqual(["medium", "medium"]);
    expect(rollTier(0.99)).toBe("large");
    expect([tierOf(99), tierOf(100), tierOf(10_000)]).toEqual(["small", "medium", "large"]);
  });

  it("picks a gift of the rolled tier and a sender from the list", () => {
    const seq = [0.99, 0, 0.5]; // large, first of the tier, middle sender
    let i = 0;
    const inc = pickIncoming(GIFTS, ["x", "y", "z"], () => seq[i++] ?? 0);
    expect(inc).toMatchObject({ tier: "large", sender: "y", quantity: 1 });
    expect(inc.gift.id).toBe("c");
  });

  it("falls back to the nearest tier when one is empty", () => {
    const inc = pickIncoming([gift("a", 10)], ["x"], () => 0.99);
    expect(inc.gift.id).toBe("a");
    expect(inc.tier).toBe("small");
  });

  it("delivers a gift every 20-40 s until stopped", () => {
    const got: string[] = [];
    const run = startIncoming({
      gifts: GIFTS,
      senders: ["x"],
      onGift: (g) => got.push(g.gift.id),
      rand: () => 0,
    });
    vi.advanceTimersByTime(MIN_DELAY_MS - 1);
    expect(got).toHaveLength(0);
    vi.advanceTimersByTime(1);
    expect(got).toHaveLength(1);
    vi.advanceTimersByTime(MAX_DELAY_MS);
    expect(got.length).toBeGreaterThanOrEqual(2);
    run.stop();
    const n = got.length;
    vi.advanceTimersByTime(MAX_DELAY_MS * 3);
    expect(got).toHaveLength(n);
  });
});

describe("demo developer menu", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => {
    vi.useRealTimers();
    document.body.innerHTML = "";
  });

  const press = (el: Element, type: string): void => {
    el.dispatchEvent(new Event(type, { bubbles: true }));
  };

  it("opens on a 1 s long-press, not on a short one", () => {
    const logo = document.createElement("div");
    const open = vi.fn();
    attachDevTrigger(logo, open);
    press(logo, "pointerdown");
    vi.advanceTimersByTime(600);
    press(logo, "pointerup");
    vi.advanceTimersByTime(1000);
    expect(open).not.toHaveBeenCalled();
    press(logo, "pointerdown");
    vi.advanceTimersByTime(1000);
    expect(open).toHaveBeenCalledTimes(1);
  });

  it("opens on 5 quick clicks only", () => {
    const logo = document.createElement("div");
    const open = vi.fn();
    attachDevTrigger(logo, open);
    for (let i = 0; i < 4; i++) logo.click();
    expect(open).not.toHaveBeenCalled();
    vi.advanceTimersByTime(4000);
    logo.click();
    expect(open).not.toHaveBeenCalled();
    for (let i = 0; i < 4; i++) logo.click();
    expect(open).toHaveBeenCalledTimes(1);
  });

  it("is folded by default and its controls call the actions", () => {
    const host = document.createElement("div");
    document.body.append(host);
    const calls: string[] = [];
    const actions: DevMenuActions = {
      playIncoming: (m) => calls.push(`play:${m}`),
      combo: (m) => calls.push(`combo:${m}`),
      awayAgain: () => calls.push("away"),
      wallPlus: () => calls.push("wall"),
      setAwayPattern: (v) => calls.push(`pattern:${v}`),
      setQuality: (v) => calls.push(`quality:${v}`),
      setTheme: (v) => calls.push(`theme:${v}`),
      setMotion: (v) => calls.push(`motion:${v}`),
      reset: () => calls.push("reset"),
      setOffline: (v) => calls.push(`offline:${v}`),
    };
    const menu = createDevMenu(host, actions);
    expect(menu.isOpen()).toBe(false);
    expect(menu.element.hidden).toBe(true);
    menu.open();
    expect(menu.isOpen()).toBe(true);
    const btn = (t: string): HTMLButtonElement =>
      [...host.querySelectorAll("button")].find((b) => b.textContent === t)!;
    btn("Priciest").click();
    btn("Play gift").click();
    btn("x5 combo").click();
    btn("Badge + box").click();
    btn("Low").click();
    btn("Pink").click();
    btn("Reduced").click();
    btn("Wall +5").click();
    btn("Away summary again").click();
    btn("Reset demo").click();
    const off = host.querySelector<HTMLInputElement>('input[type="checkbox"]')!;
    off.click();
    expect(calls).toEqual([
      "play:priciest",
      "combo:priciest",
      "pattern:badge",
      "quality:low",
      "theme:pink",
      "motion:reduced",
      "wall",
      "away",
      "reset",
      "offline:true",
    ]);
    expect(btn("Priciest").getAttribute("aria-pressed")).toBe("true");
    expect(btn("Same as tray").getAttribute("aria-pressed")).toBe("false");
    expect(btn("Badge + box").getAttribute("aria-pressed")).toBe("true");
    expect(btn("Card").getAttribute("aria-pressed")).toBe("false");
    btn("Done").click();
    expect(menu.isOpen()).toBe(false);
  });
});
