import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type Gift,
  type GiftTransaction,
  type GiftingClient,
  GiftingError,
  type GiftEffectEvent,
} from "../src/core";
import { GiftEffectLayer, GiftTray, createGiftTray } from "../src/web";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";
import { componentCallStubs } from "./stub-client";

const gift = (id: string, price: number, order = 0): Gift => ({
  id,
  name: id.charAt(0).toUpperCase() + id.slice(1),
  description: null,
  price,
  icon_url: `https://assets.test/${id}/256.webp`,
  animation_url: `https://assets.test/${id}/512.webp`,
  sort_order: order,
});
const GIFTS = [gift("rose", 10, 0), gift("hat", 350, 1), gift("dragon", 40_000, 2)];

let env: ReturnType<typeof installWebEnv>;
let container: HTMLElement;
let trays: GiftTray[] = [];
/** A tray that is destroyed after the test, so the shared style element does not leak. */
const mk = (options: ConstructorParameters<typeof GiftTray>[1]) => {
  const tray = new GiftTray(container, options);
  trays.push(tray);
  return tray;
};

beforeEach(() => {
  env = installWebEnv();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
  container = document.createElement("div");
  document.body.appendChild(container);
});
afterEach(() => {
  for (const t of trays) t.destroy();
  trays = [];
  container.remove();
  vi.useRealTimers();
  env.restore();
});

const advance = (ms: number) => vi.advanceTimersByTimeAsync(ms);
const $ = (sel: string) => container.querySelector(sel) as HTMLElement;
const cells = () => [...container.querySelectorAll<HTMLElement>('[role="radio"]')];
const cell = (i: number) => cells()[i]!;
const send = () => $("[data-gs-send]") as HTMLButtonElement;
const shownBalance = () => $("[data-gs-balance] span:nth-child(2)").textContent;

describe("web GiftTray: rendering and accessibility", () => {
  it("draws a grid of gifts with pictures, prices and radio roles", () => {
    mk({ gifts: GIFTS, balance: 1234 });
    expect(cells()).toHaveLength(3);
    expect(cell(0).getAttribute("aria-label")).toBe("Rose, 10 coins");
    expect(cell(2).getAttribute("aria-label")).toBe("Dragon, 40,000 coins");
    expect(cell(1).querySelector("img")!.getAttribute("src")).toBe(
      "https://assets.test/hat/256.webp",
    );
    expect(cell(2).textContent).toBe("40,000");
    expect($('[role="radiogroup"]')).not.toBeNull();
    expect($(".gs-title").textContent).toBe("Send a gift");
  });

  it("selects the first gift, or defaultSelectedId, and moves the selection on click", () => {
    const tray = mk({ gifts: GIFTS, balance: 1000, defaultSelectedId: "hat" });
    expect(cells().map((c) => c.getAttribute("aria-checked"))).toEqual(["false", "true", "false"]);
    cell(0).click();
    expect(cells().map((c) => c.getAttribute("aria-checked"))).toEqual(["true", "false", "false"]);
    expect(tray.getSelected()!.id).toBe("rose");
    expect(send().getAttribute("aria-label")).toBe("Send: Rose");
  });

  it("an unknown selected id shows the first gift as selected", () => {
    mk({ gifts: GIFTS, balance: 1000, defaultSelectedId: "gone" });
    expect(cell(0).getAttribute("aria-checked")).toBe("true");
  });

  it("an empty tray draws no cells and a disabled button", () => {
    mk({ balance: 0 });
    expect(cells()).toHaveLength(0);
    expect(send().getAttribute("aria-disabled")).toBe("true");
  });

  it("arrow keys move the selection like a radio group, with one tab stop", () => {
    mk({ gifts: GIFTS, balance: 1000 });
    expect(cells().map((c) => c.tabIndex)).toEqual([0, -1, -1]);
    const key = (k: string) =>
      cells()
        .find((c) => c.getAttribute("aria-checked") === "true")!
        .dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true, cancelable: true }));
    key("ArrowRight");
    expect(cell(1).getAttribute("aria-checked")).toBe("true");
    expect(cell(1).tabIndex).toBe(0);
    expect(document.activeElement).toBe(cell(1));
    key("ArrowDown");
    key("ArrowRight"); // wraps
    expect(cell(0).getAttribute("aria-checked")).toBe("true");
    key("ArrowLeft"); // wraps back
    expect(cell(2).getAttribute("aria-checked")).toBe("true");
    key("Home");
    expect(cell(0).getAttribute("aria-checked")).toBe("true");
    key("End");
    expect(cell(2).getAttribute("aria-checked")).toBe("true");
  });

  it("the balance is a polite live region that says the target number", () => {
    mk({ gifts: GIFTS, balance: 1234, coinName: "gems" });
    const balance = $("[data-gs-balance]");
    expect(balance.getAttribute("role")).toBe("status");
    expect(balance.getAttribute("aria-live")).toBe("polite");
    expect(balance.querySelector(".gs-sr")!.textContent).toBe("Balance: 1,234 gems");
    expect(shownBalance()).toBe("1,234");
  });

  it("buttons are real buttons with labels; + Coins only with onTopUp", () => {
    const tray = mk({ gifts: GIFTS, balance: 1000 });
    expect($(".gs-topup").hidden).toBe(true);
    tray.update({ onTopUp: () => {} });
    expect($(".gs-topup").hidden).toBe(false);
    expect($(".gs-topup").getAttribute("aria-label")).toBe("Get more coins");
    expect(send().tagName).toBe("BUTTON");
    expect(cell(0).tagName).toBe("BUTTON");
  });

  it("uses en-US grouping whatever the locale", () => {
    mk({ gifts: [gift("big", 1_234_567)], balance: 9_876_543 });
    expect(shownBalance()).toBe("9,876,543");
    expect(cell(0).textContent).toBe("1,234,567");
  });

  it("takes the theme as CSS variables and has a visible focus ring in the style sheet", () => {
    const tray = mk({
      gifts: GIFTS,
      balance: 0,
      theme: { accent: "#ff0000" },
    });
    expect(tray.element.style.getPropertyValue("--gs-accent")).toBe("#ff0000");
    tray.update({ theme: { noticeBigBackground: "#123456" } });
    expect(tray.element.style.getPropertyValue("--gs-notice-big-background")).toBe("#123456");
    const css = document.head.querySelector("style[data-giftingstack]")!.textContent!;
    expect(css).toContain(":focus-visible");
  });

  it("destroy removes the tray, its pictures and the style", () => {
    const tray = mk({ gifts: GIFTS, balance: 5 });
    tray.update({ balance: 50 });
    tray.destroy();
    expect(container.children).toHaveLength(0);
    expect(document.head.querySelector("style[data-giftingstack]")).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });
});

describe("web GiftTray: send button states", () => {
  it("send: calls onSend with the selected gift", () => {
    const onSend = vi.fn();
    mk({ gifts: GIFTS, balance: 1000, onSend });
    expect(send().textContent).toBe("Send");
    expect(send().getAttribute("aria-disabled")).toBe("false");
    cell(1).click();
    send().click();
    expect(onSend).toHaveBeenCalledTimes(1);
    expect(onSend.mock.calls[0]?.[0].id).toBe("hat");
  });

  it("too expensive and no store: 'Not enough coins', off, and a press does nothing", () => {
    const onSend = vi.fn();
    mk({ gifts: GIFTS, balance: 100, onSend, defaultSelectedId: "hat" });
    expect(send().textContent).toBe("Not enough coins");
    expect(send().getAttribute("aria-disabled")).toBe("true");
    expect(send().getAttribute("data-gs-action")).toBe("none");
    send().click();
    expect(onSend).not.toHaveBeenCalled();
  });

  it("too expensive with onTopUp: 'Get coins', pressable, opens the store, in the coin colour", () => {
    const onSend = vi.fn();
    const onTopUp = vi.fn();
    mk({
      gifts: GIFTS,
      balance: 100,
      onSend,
      onTopUp,
      defaultSelectedId: "hat",
    });
    expect(send().textContent).toBe("Get coins");
    expect(send().getAttribute("aria-disabled")).toBe("false");
    expect(send().classList.contains("gs-coin-state")).toBe(true);
    expect(send().getAttribute("aria-label")).toBe("Get coins: Hat");
    send().click();
    expect(onTopUp).toHaveBeenCalledTimes(1);
    expect(onSend).not.toHaveBeenCalled();
    $(".gs-topup").click();
    expect(onTopUp).toHaveBeenCalledTimes(2);
  });

  it("disabled turns every state off", () => {
    const onSend = vi.fn();
    const onTopUp = vi.fn();
    const tray = mk({
      gifts: GIFTS,
      balance: 100,
      onSend,
      onTopUp,
      disabled: true,
    });
    send().click();
    tray.update({ defaultSelectedId: "dragon" });
    expect(send().getAttribute("aria-disabled")).toBe("true");
    expect(onSend).not.toHaveBeenCalled();
  });

  it("the state follows the balance and the labels are customisable", () => {
    const tray = mk({
      gifts: GIFTS,
      balance: 5,
      notEnoughLabel: "Zu wenig",
      sendLabel: "Senden",
    });
    expect(send().textContent).toBe("Zu wenig");
    tray.update({ balance: 50 });
    expect(send().textContent).toBe("Senden");
  });
});

describe("web GiftTray: balance count-up", () => {
  it("counts from the old to the new balance in 600 ms, ease-out, rounded", async () => {
    const tray = mk({ gifts: GIFTS, balance: 1000 });
    tray.update({ balance: 0 });
    expect($(".gs-sr").textContent).toBe("Balance: 0 coins"); // the target at once
    expect(shownBalance()).toBe("1,000");
    await advance(100);
    const early = Number(shownBalance()!.replace(/,/g, ""));
    expect(early).toBeGreaterThan(0);
    expect(early).toBeLessThan(600); // ease-out: more than a third in the first sixth
    await advance(200);
    const mid = Number(shownBalance()!.replace(/,/g, ""));
    expect(mid).toBeLessThan(early);
    await advance(320);
    expect(shownBalance()).toBe("0");
    await advance(100); // past the sheet's 700 ms "give up waiting for measurements" timer
    expect(vi.getTimerCount()).toBe(0);
  });

  it("a new target mid-count starts from what is shown", async () => {
    const tray = mk({ gifts: GIFTS, balance: 0 });
    tray.update({ balance: 1000 });
    await advance(200);
    const shown = Number(shownBalance()!.replace(/,/g, ""));
    tray.update({ balance: 1000 - 10 });
    await advance(0);
    expect(Math.abs(Number(shownBalance()!.replace(/,/g, "")) - shown)).toBeLessThan(40);
    await advance(700);
    expect(shownBalance()).toBe("990");
  });
});

describe("web GiftTray: prefetch", () => {
  it("prefetches every icon, and the selected gift's big picture on each selection change", () => {
    const prefetch = vi.fn();
    mk({ gifts: GIFTS, balance: 1000, prefetch });
    const urls = () => prefetch.mock.calls.map((c) => c[0]);
    expect(urls()).toEqual(expect.arrayContaining(GIFTS.map((g) => g.icon_url)));
    expect(urls()).toContain("https://assets.test/rose/512.webp");
    const warm = () => $("[data-gs-warmup]") as HTMLImageElement;
    expect(warm().getAttribute("src")).toBe("https://assets.test/rose/512.webp");
    expect(warm().getAttribute("aria-hidden")).toBe("true");
    cell(2).click();
    expect(urls()).toContain("https://assets.test/dragon/512.webp");
    expect(warm().getAttribute("src")).toBe("https://assets.test/dragon/512.webp");
    expect(container.querySelectorAll("[data-gs-warmup]")).toHaveLength(1);
  });

  it("falls back to the icon when a gift has no big picture", () => {
    mk({ gifts: [{ ...gift("pin", 5), animation_url: null }], balance: 1 });
    expect($("[data-gs-warmup]").getAttribute("src")).toBe("https://assets.test/pin/256.webp");
  });
});

describe("web createGiftTray", () => {
  function mockClient(balance: number, failWith?: GiftingError, livemode?: boolean) {
    const calls: string[] = [];
    const client: GiftingClient = {
      async getGifts() {
        calls.push("getGifts");
        return GIFTS;
      },
      async getMe() {
        calls.push("getMe");
        return livemode === undefined
          ? { user: "ayla", balance }
          : { user: "ayla", balance, livemode };
      },
      async getReceivedGifts() {
        return [];
      },
      ...componentCallStubs,
      async sendGift(input) {
        calls.push(`sendGift:${input.giftId}:${input.reference}`);
        await new Promise((r) => setTimeout(r, 250));
        if (failWith) throw failWith;
        const g = GIFTS.find((x) => x.id === input.giftId)!;
        balance -= g.price;
        return {
          id: "tx1",
          sender: "ayla",
          receiver: input.receiver,
          gift: { id: g.id, name: g.name, icon_url: g.icon_url },
          quantity: 1,
          unit_price: g.price,
          total: g.price,
          message: null,
          reference: input.reference ?? null,
          status: "completed",
          created_at: "2026-01-01T00:00:00Z",
          sender_balance_after: balance,
        } satisfies GiftTransaction;
      },
    };
    return { client, calls };
  }
  const player = () => {
    const played: GiftEffectEvent[] = [];
    const cancelled: number[] = [];
    return {
      played,
      cancelled,
      play: (e: GiftEffectEvent) => played.push(e),
      cancel: (id: number) => cancelled.push(id),
    };
  };

  it('shows "Test mode" only when the server says livemode: false', async () => {
    const badge = () => $("[data-gs-test-mode]") as HTMLElement;
    for (const [livemode, shown] of [
      [false, true],
      [true, false],
      [undefined, false],
    ] as const) {
      const { client } = mockClient(500, undefined, livemode);
      const handle = createGiftTray({ container, client, receiver: "mert" });
      expect(badge().hidden).toBe(true); // nothing known before the first answer
      await advance(10);
      expect(badge().hidden).toBe(!shown);
      expect(badge().textContent).toBe("Test mode");
      expect(handle.controller.getState().testMode).toBe(shown);
      handle.destroy();
    }
    const tray = mk({ gifts: GIFTS, balance: 1, testMode: true, testModeLabel: "Deneme" });
    expect(badge().hidden).toBe(false);
    expect(badge().textContent).toBe("Deneme");
    tray.update({ testMode: false });
    expect(badge().hidden).toBe(true);
  });

  it("loads the catalog and the balance, sorted, and shows them", async () => {
    const { client } = mockClient(500);
    const handle = createGiftTray({ container, client, receiver: "mert" });
    await advance(0);
    expect(cells().map((c) => c.getAttribute("data-gs-gift"))).toEqual(["rose", "hat", "dragon"]);
    await advance(700);
    expect(shownBalance()).toBe("500");
    expect(handle.controller.getState().user).toBe("ayla");
    handle.destroy();
    expect(container.children).toHaveLength(0);
  });

  it("send: optimistic balance, effect at the tap, reference passed, reconcile after", async () => {
    const { client, calls } = mockClient(500);
    const effects = player();
    const onSent = vi.fn();
    const handle = createGiftTray({
      container,
      client,
      receiver: "mert",
      effects,
      reference: "post_1",
      onSent,
    });
    await advance(1000);
    cell(1).click(); // hat, 350
    send().click();
    expect(effects.played).toHaveLength(1);
    expect(effects.played[0]).toMatchObject({
      sender: "ayla",
      quantity: 1,
      gift: { id: "hat", price: 350 },
    });
    expect($(".gs-sr").textContent).toBe("Balance: 150 coins");
    await advance(300);
    expect(onSent).toHaveBeenCalledTimes(1);
    expect(calls).toContain("sendGift:hat:post_1");
    expect(calls.filter((c) => c === "getMe")).toHaveLength(2); // refresh + reconcile
    await advance(1000);
    expect(shownBalance()).toBe("150");
    handle.destroy();
  });

  it("a failed send takes the effect back and refunds the balance", async () => {
    const { client } = mockClient(500, new GiftingError(500, "internal_error", "boom"));
    const effects = player();
    const onError = vi.fn();
    const handle = createGiftTray({ container, client, receiver: "mert", effects, onError });
    await advance(1000);
    send().click();
    expect($(".gs-sr").textContent).toBe("Balance: 490 coins");
    await advance(1000);
    expect(effects.cancelled).toEqual([1]);
    expect(onError).toHaveBeenCalledTimes(1);
    expect($(".gs-sr").textContent).toBe("Balance: 500 coins");
    handle.destroy();
  });

  it("takes the effect layer as a function too, and works with a real layer", async () => {
    const { client } = mockClient(50_000);
    const layer = new GiftEffectLayer(container, { pictureWaitMs: 0 });
    const handle = createGiftTray({ container, client, receiver: "mert", effects: () => layer });
    await advance(1000);
    cell(2).click();
    send().click();
    expect(container.querySelectorAll('[data-gs-effect="large"]')).toHaveLength(1);
    await advance(10);
    expect(container.querySelector("[data-gs-notice]")!.textContent).toContain("ayla");
    handle.destroy();
    layer.destroy();
    expect(container.children).toHaveLength(0);
  });

  it("not enough coins and onTopUp: the button opens the store", async () => {
    const { client } = mockClient(5);
    const onTopUp = vi.fn();
    const handle = createGiftTray({ container, client, receiver: "mert", onTopUp });
    await advance(1000);
    expect(send().textContent).toBe("Get coins");
    send().click();
    expect(onTopUp).toHaveBeenCalledTimes(1);
    handle.destroy();
  });

  it("destroy stops late answers from touching the page", async () => {
    const { client } = mockClient(500);
    const handle = createGiftTray({ container, client, receiver: "mert" });
    handle.destroy();
    await advance(1000);
    expect(container.children).toHaveLength(0);
  });
});
