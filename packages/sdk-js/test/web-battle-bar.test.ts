import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { BattleView, RoomBattle } from "../src/core";
import { battleView } from "../src/core";
import { GiftBattleBar, type GiftBattleBarOptions, defineGiftElements } from "../src/web";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";

const round = (a: number, b: number, ends = 60_000): RoomBattle => ({
  round: "r1",
  started: 0,
  ends,
  scores: [
    { id: "mia", units: a, gifts: a ? 1 : 0 },
    { id: "theo", units: b, gifts: b ? 1 : 0 },
  ],
});
const at = (a: number, b: number, now = 1_000, ends = 60_000): BattleView =>
  battleView(round(a, b, ends), now);

/** The part of a room the bar uses. */
function fakeRoom(initial: BattleView | null) {
  let view = initial;
  const listeners = new Set<() => void>();
  const room = {
    battleView: () => view,
    onBattle: (l: () => void) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
  };
  return {
    room: room as unknown as NonNullable<GiftBattleBarOptions["room"]>,
    raw: room,
    set(v: BattleView | null) {
      view = v;
      for (const l of listeners) l();
    },
    listeners,
  };
}

let env: ReturnType<typeof installWebEnv>;
let page: HTMLElement;
let bars: GiftBattleBar[] = [];

beforeEach(() => {
  env = installWebEnv();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS, "setInterval", "clearInterval"] });
  page = document.createElement("div");
  document.body.appendChild(page);
});
afterEach(() => {
  for (const b of bars) b.destroy();
  bars = [];
  page.remove();
  vi.useRealTimers();
  env.restore();
});

const mk = (options: GiftBattleBarOptions = {}) => {
  const b = new GiftBattleBar(page, options);
  bars.push(b);
  return b;
};
const $ = (sel: string) => page.querySelector(sel) as HTMLElement;
const text = (sel: string) => $(sel)?.textContent;

describe("GiftBattleBar", () => {
  it("is hidden without a round and draws both sides when one arrives", () => {
    const bar = mk({ reducedMotion: true });
    expect(bar.element.hidden).toBe(true);
    bar.setView(at(300, 100));
    expect(bar.element.hidden).toBe(false);
    expect(text(".gs-vs-s0 .gs-vs-name")).toBe("mia");
    expect(text(".gs-vs-s0 .gs-vs-score")).toBe("300");
    expect(text(".gs-vs-s1 .gs-vs-score")).toBe("100");
    expect(text(".gs-vs-clock")).toBe("0:59");
    expect($(".gs-vs-a").style.width).toBe("75%");
    expect($(".gs-vs-spark").style.left).toBe("75%");
    expect($(".gs-vs-bar").getAttribute("aria-label")).toBe("mia 300, theo 100");
    bar.setView(null);
    expect(bar.element.hidden).toBe(true);
  });

  it("names the sides with resolveUsers and reports a failed lookup", async () => {
    const resolveUsers = vi.fn(async () => ({
      mia: { name: "Mia R.", avatarUrl: "https://img.test/mia.png" },
      theo: { name: "Theo M." },
    }));
    const bar = mk({ reducedMotion: true, resolveUsers });
    bar.setView(at(1, 2));
    expect(text(".gs-vs-s0 .gs-vs-name")).toBe("mia");
    await vi.advanceTimersByTimeAsync(0);
    expect(resolveUsers).toHaveBeenCalledTimes(1);
    expect(text(".gs-vs-s0 .gs-vs-name")).toBe("Mia R.");
    expect(text(".gs-vs-s1 .gs-vs-name")).toBe("Theo M.");
    expect($(".gs-vs-s0 img")?.getAttribute("src")).toBe("https://img.test/mia.png");
    expect($(".gs-vs-bar").getAttribute("aria-label")).toBe("Mia R. 1, Theo M. 2");
    bar.setView(at(5, 2)); // same round, same people: no new lookup
    expect(resolveUsers).toHaveBeenCalledTimes(1);

    const onError = vi.fn();
    const failing = mk({
      reducedMotion: true,
      resolveUsers: async () => {
        throw new Error("down");
      },
      onError,
    });
    failing.setView(at(0, 0));
    await vi.advanceTimersByTimeAsync(0);
    expect(onError).toHaveBeenCalledTimes(1);
  });

  it("follows a room: scores frames and the clock tick", () => {
    const r = fakeRoom(at(0, 0, 0));
    mk({ room: r.room, reducedMotion: true });
    expect(text(".gs-vs-clock")).toBe("1:00");
    r.set(at(50, 0, 0));
    expect(text(".gs-vs-s0 .gs-vs-score")).toBe("50");
    // The room's view moves with the server clock; the bar re-reads it each second.
    let now = 0;
    r.raw.battleView = () => battleView(round(50, 0), now);
    now = 30_000;
    vi.advanceTimersByTime(1_000);
    expect(text(".gs-vs-clock")).toBe("0:30");
  });

  it("stops listening and ticking once destroyed", () => {
    const r = fakeRoom(at(0, 0));
    const bar = mk({ room: r.room, reducedMotion: true });
    expect(r.listeners.size).toBe(1);
    bar.destroy();
    expect(r.listeners.size).toBe(0);
    expect(page.querySelector(".gs-battle")).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });

  it("marks the winner and the loser when the round ends, and a draw has neither", () => {
    const bar = mk({ reducedMotion: true });
    bar.setView(at(9, 2, 61_000));
    expect(text(".gs-vs-clock")).toBe("Final");
    expect(text(".gs-vs-banner")).toBe("mia wins the round");
    expect($(".gs-vs-s0").classList.contains("gs-win")).toBe(true);
    expect($(".gs-vs-s1").classList.contains("gs-lose")).toBe(true);
    expect($(".gs-vs").classList.contains("gs-done")).toBe(true);
    bar.setView(at(4, 4, 61_000));
    expect(text(".gs-vs-banner")).toBe("Draw: nobody wins this round");
    expect(page.querySelector(".gs-win, .gs-lose")).toBeNull();
  });

  it("turns the clock urgent in the last ten seconds", () => {
    const bar = mk({ reducedMotion: true });
    bar.setView(at(1, 1, 49_000));
    expect($(".gs-vs-clock").classList.contains("gs-urgent")).toBe(false);
    bar.setView(at(1, 1, 50_500));
    expect($(".gs-vs-clock").classList.contains("gs-urgent")).toBe(true);
  });

  it("pulses the side that gained, but not on the first frame or in reduced motion", () => {
    const bar = mk({ reducedMotion: false });
    bar.setView(at(10, 10));
    expect(page.querySelector(".gs-pulse")).toBeNull();
    bar.setView(at(10, 30));
    expect($(".gs-vs-s1").classList.contains("gs-pulse")).toBe(true);
    expect($(".gs-vs-b").classList.contains("gs-pulse")).toBe(true);
    expect($(".gs-vs-s0").classList.contains("gs-pulse")).toBe(false);
    expect(bar.element.hasAttribute("data-calm")).toBe(false);

    const calm = mk({ reducedMotion: true });
    calm.setView(at(10, 10));
    calm.setView(at(10, 30));
    expect(calm.element.hasAttribute("data-calm")).toBe(true);
    expect(calm.element.querySelector(".gs-pulse")).toBeNull();
  });

  it("counts a score up when motion is on and jumps to it when it is off", async () => {
    const bar = mk({ reducedMotion: false });
    bar.setView(at(0, 0));
    bar.setView(at(1_000, 0));
    const score = () => text(".gs-vs-s0 .gs-vs-score");
    await vi.advanceTimersByTimeAsync(100);
    const mid = Number(score()!.replace(",", ""));
    expect(mid).toBeGreaterThan(0);
    expect(mid).toBeLessThan(1_000);
    await vi.advanceTimersByTimeAsync(800);
    expect(score()).toBe("1,000");
    bar.update({ reducedMotion: true });
    bar.setView(at(5_000, 0));
    expect(score()).toBe("5,000");
  });

  it("starts a new round from zero without pulsing", () => {
    const bar = mk({ reducedMotion: true });
    bar.setView(at(40, 10));
    bar.setView({ ...at(0, 0), round: "r2" });
    expect(text(".gs-vs-s0 .gs-vs-score")).toBe("0");
    expect(page.querySelector(".gs-pulse")).toBeNull();
  });

  it("colours the sides from the theme or from sideColors, and keeps the theme live", () => {
    const bar = mk({ reducedMotion: true, theme: { accent: "#112233", accentText: "#ffffff" } });
    bar.setView(at(1, 1));
    const root = $(".gs-vs");
    expect(root.style.getPropertyValue("--gs-side-a")).toBe("#112233");
    expect(root.style.getPropertyValue("--gs-side-b")).toBe("#ffd27a");
    bar.update({ sideColors: ["#ff0000", "#00ff00"] });
    const next = $(".gs-vs");
    expect(next.style.getPropertyValue("--gs-side-a")).toBe("#ff0000");
    expect(next.style.getPropertyValue("--gs-side-b-text")).toBe("#000000");
    bar.update({ theme: { accent: "#abcdef" } });
    expect(bar.element.style.getPropertyValue("--gs-accent")).toBe("#abcdef");
  });

  it("speaks the result through a status line, in the labels' words", () => {
    const bar = mk({ reducedMotion: true, labels: { wins: "{name} won", final: "Done" } });
    bar.setView(at(3, 1, 61_000));
    expect($(".gs-vs-banner").getAttribute("role")).toBe("status");
    expect(text(".gs-vs-banner")).toBe("mia won");
    expect(text(".gs-vs-clock")).toBe("Done");
  });
});

describe("<gift-battle-bar>", () => {
  it("is a registered tag that draws a view and takes side-colors from an attribute", () => {
    defineGiftElements();
    page.innerHTML =
      '<gift-battle-bar reduced-motion side-colors="#ff0000, #0000ff"></gift-battle-bar>';
    const el = page.querySelector("gift-battle-bar") as HTMLElement & { view: BattleView | null };
    expect(customElements.get("gift-battle-bar")).toBeDefined();
    expect(el.querySelector(".gs-battle")!.hasAttribute("hidden")).toBe(true);
    el.view = at(7, 3);
    expect(el.querySelector(".gs-vs-s0 .gs-vs-score")!.textContent).toBe("7");
    expect((el.querySelector(".gs-vs") as HTMLElement).style.getPropertyValue("--gs-side-b")).toBe(
      "#0000ff",
    );
    el.remove();
    expect(document.querySelector(".gs-battle")).toBeNull();
  });
});
