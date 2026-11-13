/**
 * One gift button for a battle (spec 21): the tray's "Send to" row (`receivers`) and the battle
 * bar's tappable sides (`onPressSide`). jsdom has no layout; the sheet's sizes are not needed here.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type Gift,
  type GiftTransaction,
  type GiftingClient,
  type RoomBattle,
  battleView,
} from "../src/core";
import {
  GiftBattleBar,
  GiftTray,
  type GiftTrayHandle,
  type TrayReceiver,
  createGiftTray,
} from "../src/web";
import { revealOffset } from "../src/core";
import { componentCallStubs } from "./stub-client";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";

const gift = (id: string, price: number): Gift => ({
  id,
  name: id.toUpperCase(),
  description: null,
  price,
  icon_url: null,
  animation_url: null,
  sort_order: 0,
});
const GIFTS = [gift("rose", 10), gift("hat", 50)];
const SIDES: TrayReceiver[] = [
  { id: "mia", name: "Mia", color: "#ff4fa3" },
  { id: "theo", name: "Theo", color: "#ffd27a" },
  { id: "ava", name: "Ava" },
];

let env: ReturnType<typeof installWebEnv>;
let container: HTMLElement;
let handles: GiftTrayHandle[] = [];
let trays: GiftTray[] = [];

beforeEach(() => {
  env = installWebEnv();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
  container = document.createElement("div");
  document.body.appendChild(container);
});
afterEach(() => {
  for (const h of handles) h.destroy();
  for (const t of trays) t.destroy();
  handles = [];
  trays = [];
  container.remove();
  vi.useRealTimers();
  env.restore();
});

function fakeClient() {
  const sendGift = vi.fn(
    async (input: { receiver: string; giftId: string }) =>
      ({
        id: "gtx_1",
        sender: "ayla",
        receiver: input.receiver,
        gift: { id: input.giftId, name: input.giftId, icon_url: null },
        quantity: 1,
        unit_price: 10,
        total: 10,
        message: null,
        reference: null,
        status: "completed",
        created_at: "2026-11-13T00:00:00.000Z",
        sender_balance_after: 990,
      }) satisfies GiftTransaction,
  );
  const client = {
    getGifts: vi.fn(async () => GIFTS),
    getMe: vi.fn(async () => ({ user: "ayla", balance: 1000 })),
    getReceivedGifts: vi.fn(async () => []),
    ...componentCallStubs,
    sendGift,
  } as unknown as GiftingClient;
  return { client, sendGift };
}

const settle = async () => {
  await vi.advanceTimersByTimeAsync(50);
};
const row = () => container.querySelector<HTMLElement>("[data-gs-receivers]")!;
const side = (id: string) => container.querySelector<HTMLElement>(`[data-gs-receiver="${id}"]`)!;
const checked = () =>
  [...container.querySelectorAll("[data-gs-receiver]")]
    .filter((b) => b.getAttribute("aria-checked") === "true")
    .map((b) => b.getAttribute("data-gs-receiver"));
const send = () => container.querySelector<HTMLElement>("[data-gs-send]")!.click();

describe("tray receiver picker (spec 21.3)", () => {
  it("no receivers: no row, the tray is as before", () => {
    trays.push(new GiftTray(container, { gifts: GIFTS, balance: 100, receiver: "mia" }));
    expect(row().hidden).toBe(true);
    expect(row().childElementCount).toBe(0);
    expect(trays[0]!.getReceiver()).toBe("mia");
  });

  it("one receiver: no row, the send goes to it", () => {
    const t = new GiftTray(container, { gifts: GIFTS, receivers: [SIDES[0]!] });
    trays.push(t);
    expect(row().hidden).toBe(true);
    expect(t.getReceiver()).toBe("mia");
  });

  it("two or more: a labelled radio row under the header, the first picked by default", () => {
    const t = new GiftTray(container, { gifts: GIFTS, receivers: SIDES });
    trays.push(t);
    expect(row().hidden).toBe(false);
    expect(row().getAttribute("role")).toBe("radiogroup");
    expect(row().getAttribute("aria-label")).toBe("Send to");
    expect(row().previousElementSibling!.classList.contains("gs-head")).toBe(true);
    expect(row().nextElementSibling!.classList.contains("gs-grid")).toBe(true);
    expect(checked()).toEqual(["mia"]);
    expect(side("theo").getAttribute("aria-label")).toBe("Theo");
    expect(side("mia").style.getPropertyValue("--gs-side")).toBe("#ff4fa3");
    // No colour given: the battle palette's third colour (teal).
    expect(side("ava").style.getPropertyValue("--gs-side")).toBe("#2ec4b6");
  });

  it("a tap picks a side and reports it; selectReceiver too; an unknown id is ignored", () => {
    const changes: (string | null)[] = [];
    const t = new GiftTray(container, {
      gifts: GIFTS,
      receivers: SIDES,
      onReceiverChange: (id) => changes.push(id),
      sendToLabel: "Gift to",
    });
    trays.push(t);
    expect(row().getAttribute("aria-label")).toBe("Gift to");
    side("theo").click();
    expect(checked()).toEqual(["theo"]);
    t.selectReceiver("ava");
    t.selectReceiver("nobody");
    expect(t.getReceiver()).toBe("ava");
    expect(changes).toEqual(["theo", "ava"]);
  });

  it("arrow keys move the pick", () => {
    trays.push(new GiftTray(container, { gifts: GIFTS, receivers: SIDES }));
    side("mia").dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }));
    expect(checked()).toEqual(["theo"]);
    side("theo").dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true }));
    side("mia").dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true }));
    expect(checked()).toEqual(["ava"]);
  });

  it("createGiftTray: the send goes to the picked side; the side gifted last is the next default", async () => {
    const { client, sendGift } = fakeClient();
    const h = createGiftTray({ container, client, receiver: "mia", receivers: SIDES });
    handles.push(h);
    await settle();
    side("theo").click();
    send();
    await settle();
    expect(sendGift.mock.calls[0]![0]).toMatchObject({ receiver: "theo", giftId: "rose" });
    // A new round (a new list) starts at the side this viewer gifted last.
    h.tray.update({ receivers: [...SIDES] });
    expect(h.getReceiver()).toBe("theo");
    h.selectReceiver("ava");
    send();
    await settle();
    expect(sendGift.mock.calls[1]![0]).toMatchObject({ receiver: "ava" });
  });

  it("a pick that leaves the list falls back to the last side, then the plain receiver", () => {
    const t = new GiftTray(container, { gifts: GIFTS, receivers: SIDES, receiver: "theo" });
    trays.push(t);
    expect(t.getReceiver()).toBe("theo");
    t.selectReceiver("ava");
    t.update({ receivers: SIDES.slice(0, 2) });
    expect(t.getReceiver()).toBe("theo");
    t.update({ receivers: undefined });
    expect(row().hidden).toBe(true);
    expect(t.getReceiver()).toBe("theo");
  });
});

describe("battle bar: tappable sides (spec 21.4)", () => {
  const round = (ids: string[]): RoomBattle => ({
    round: "r1",
    started: 0,
    ends: 60_000,
    scores: ids.map((id) => ({ id, units: 1, gifts: 1 })),
  });

  it("without onPressSide the bar has no buttons", () => {
    const bar = new GiftBattleBar(container, {});
    bar.setView(battleView(round(["mia", "theo"]), 1_000));
    expect(container.querySelector(".gs-vs-pick")).toBeNull();
    bar.destroy();
  });

  for (const ids of [
    ["mia", "theo"],
    ["mia", "theo", "ava", "zoe"],
  ]) {
    it(`${ids.length} sides: each avatar is a labelled button that reports its side`, () => {
      const pressed: string[] = [];
      const bar = new GiftBattleBar(container, { onPressSide: (id) => pressed.push(id) });
      bar.setView(battleView(round(ids), 1_000));
      const buttons = [...container.querySelectorAll<HTMLButtonElement>(".gs-vs-pick")];
      expect(buttons).toHaveLength(ids.length);
      expect(buttons[1]!.getAttribute("aria-label")).toBe(`Send ${ids[1]} a gift`);
      expect(buttons[1]!.querySelector(".gs-vs-avatar")).not.toBeNull();
      buttons[1]!.click();
      expect(pressed).toEqual([ids[1]]);
      bar.update({ pressSideLabel: "Gift {name}" });
      expect(container.querySelector(".gs-vs-pick")!.getAttribute("aria-label")).toBe(
        `Gift ${ids[0]}`,
      );
      bar.destroy();
    });
  }
});

describe("the selected side stays in sight (spec 21.3)", () => {
  it("revealOffset: least movement, unchanged when visible", () => {
    expect(revealOffset({ scroll: 0, viewport: 300, start: 100, end: 140 })).toBe(0);
    expect(revealOffset({ scroll: 0, viewport: 300, start: 280, end: 345 })).toBe(45);
    expect(revealOffset({ scroll: 200, viewport: 300, start: 60, end: 96 })).toBe(60);
    expect(revealOffset({ scroll: 50, viewport: 30, start: 100, end: 200 })).toBe(100);
  });

  it("an overflowing row scrolls itself to the picked chip; nothing else scrolls", () => {
    const many: TrayReceiver[] = Array.from({ length: 8 }, (_, i) => ({
      id: `s${i}`,
      name: `Side ${i}`,
    }));
    const proto = HTMLElement.prototype;
    const saved = ["scrollWidth", "offsetLeft", "offsetWidth"].map(
      (k) => [k, Object.getOwnPropertyDescriptor(proto, k)] as const,
    );
    Object.defineProperty(proto, "scrollWidth", {
      configurable: true,
      get(this: HTMLElement) {
        return this.hasAttribute("data-gs-receivers") ? 600 : 0;
      },
    });
    Object.defineProperty(proto, "offsetLeft", {
      configurable: true,
      get(this: HTMLElement) {
        const id = this.getAttribute("data-gs-receiver");
        return id ? 58 + Number(id.slice(1)) * 44 : 0;
      },
    });
    Object.defineProperty(proto, "offsetWidth", {
      configurable: true,
      get(this: HTMLElement) {
        return this.getAttribute("aria-checked") === "true" ? 90 : 36;
      },
    });
    const pageScroll = vi.fn();
    const intoView = vi.fn();
    Element.prototype.scrollIntoView = intoView;
    window.scrollTo = pageScroll as typeof window.scrollTo;
    try {
      const t = new GiftTray(container, { gifts: GIFTS, receivers: many });
      trays.push(t);
      const r = row();
      // jsdom's clientWidth is the page stub (390): the row is 600 wide inside.
      expect(r.scrollLeft).toBe(0);
      t.selectReceiver("s7"); // 58 + 7 * 44 = 366 .. 456
      expect(r.scrollLeft).toBe(456 - 390);
      t.selectReceiver("s0");
      expect(r.scrollLeft).toBe(58);
      expect(intoView).not.toHaveBeenCalled();
      expect(pageScroll).not.toHaveBeenCalled();
    } finally {
      for (const [k, d] of saved)
        if (d) Object.defineProperty(proto, k, d);
        else delete (proto as unknown as Record<string, unknown>)[k];
    }
  });
});

describe("the Send to row keeps its height in a height-capped tray (popover, inline)", () => {
  it("the row and its chips never shrink (a squashed row clipped the avatars to flat pills)", async () => {
    const { CSS } = await import("../src/web/styles");
    const rule = /\.gs-receivers\s*\{([^}]*)\}/.exec(CSS)?.[1] ?? "";
    expect(rule).toMatch(/flex:\s*none/);
    expect(CSS).toMatch(/\.gs-receivers > \*\s*\{\s*flex-shrink:\s*0;/);
    expect(/\.gs-receiver-avatar\s*\{([^}]*)\}/.exec(CSS)?.[1]).toMatch(/flex:\s*none/);
  });
});
