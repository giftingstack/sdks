import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { type Gift, type GiftTransaction, type GiftingClient, GiftingError } from "../src/core";
import { GiftEffectLayerElement, GiftTrayElement, defineGiftElements } from "../src/web";
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
const GIFTS = [gift("rose", 10, 0), gift("hat", 350, 1)];
const event = (id: string, price: number) => ({
  gift: { id, name: id, price, image: "i", icon: "i" },
  sender: "ayla",
});

type Sent = Parameters<GiftingClient["sendGift"]>[0];

function fakeClient(overrides: Partial<GiftingClient> = {}): GiftingClient & { sent: Sent[] } {
  const sent: Sent[] = [];
  return {
    sent,
    getGifts: async () => GIFTS,
    getMe: async () => ({ user: "ayla", balance: 500 }),
    getReceivedGifts: async () => [],
    ...componentCallStubs,
    sendGift: async (input) => {
      sent.push(input);
      const g = GIFTS.find((x) => x.id === input.giftId)!;
      return {
        id: "tx1",
        sender: "ayla",
        receiver: input.receiver,
        gift: { id: g.id, name: g.name, icon_url: g.icon_url },
        quantity: input.quantity ?? 1,
        unit_price: g.price,
        total: g.price * (input.quantity ?? 1),
        message: null,
        reference: input.reference ?? null,
        status: "completed",
        created_at: "2026-10-11T00:00:00Z",
        sender_balance_after: 490,
      } satisfies GiftTransaction;
    },
    ...overrides,
  };
}

let env: ReturnType<typeof installWebEnv>;
let page: HTMLElement;

beforeEach(() => {
  env = installWebEnv();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
  defineGiftElements();
  page = document.createElement("div");
  document.body.appendChild(page);
});
afterEach(() => {
  page.remove();
  vi.useRealTimers();
  env.restore();
});

const settle = () => vi.advanceTimersByTimeAsync(0);
const html = (markup: string) => {
  page.innerHTML = markup;
};
const tray = () => page.querySelector("gift-tray") as GiftTrayElement;
const fx = () => page.querySelector("gift-effect-layer") as GiftEffectLayerElement;
const sendButton = () => tray().querySelector<HTMLButtonElement>("[data-gs-send]")!;

describe("defineGiftElements", () => {
  it("registers both tags, and calling it again is harmless", () => {
    defineGiftElements();
    expect(customElements.get("gift-tray")).toBe(GiftTrayElement);
    expect(customElements.get("gift-effect-layer")).toBe(GiftEffectLayerElement);
  });
});

describe("<gift-effect-layer>", () => {
  it("draws a layer inside itself when it is on the page and removes it when it leaves", () => {
    html("<gift-effect-layer></gift-effect-layer>");
    const el = fx();
    expect(el.querySelector("[data-gs-layer]")).not.toBeNull();
    el.remove();
    expect(el.querySelector("[data-gs-layer]")).toBeNull();
    expect(el.layer).toBeNull();
  });

  it("plays a gift: the notice shows who sent what", async () => {
    html("<gift-effect-layer></gift-effect-layer>");
    fx().options = { pictureWaitMs: 0 };
    expect(fx().play(event("hat", 350))).toBeGreaterThan(0);
    await settle();
    expect(fx().textContent).toContain("ayla");
  });

  it("play does nothing (returns 0) before it is on the page", () => {
    const el = document.createElement("gift-effect-layer");
    expect(el.play(event("rose", 10))).toBe(0);
  });

  it("reads attributes, live", () => {
    html('<gift-effect-layer notice-bottom="200"></gift-effect-layer>');
    const region = () => fx().querySelector<HTMLElement>(".gs-notice-region")!;
    expect(region().style.bottom).toBe("200px");
    fx().setAttribute("notice-bottom", "90");
    expect(region().style.bottom).toBe("90px");
  });

  it('reduced-motion="true" shows only the notice, and "false" brings the effect back', () => {
    html('<gift-effect-layer reduced-motion="true"></gift-effect-layer>');
    fx().play(event("hat", 350));
    expect(fx().querySelectorAll(".gs-effect")).toHaveLength(0);
    expect(fx().querySelector("[data-gs-notice]")).not.toBeNull();
    fx().clear();
    fx().setAttribute("reduced-motion", "false");
    fx().options = { pictureWaitMs: 0 };
    fx().play(event("hat", 350));
    expect(fx().querySelectorAll(".gs-effect")).toHaveLength(1);
  });

  it("fires gift-effect-end with the tier", async () => {
    html("<gift-effect-layer></gift-effect-layer>");
    const ends: string[] = [];
    fx().addEventListener("gift-effect-end", (e) => ends.push((e as CustomEvent).detail.tier));
    fx().options = { pictureWaitMs: 0 };
    fx().play(event("rose", 10));
    await vi.advanceTimersByTimeAsync(5000);
    expect(ends).toEqual(["small"]);
  });
});

describe("<gift-tray>", () => {
  it("stays empty without a client or without a receiver", async () => {
    html('<gift-tray receiver="mert"></gift-tray>');
    await settle();
    expect(tray().tray).toBeNull();
    expect(tray().querySelector(".gs-tray")).toBeNull();
    tray().client = fakeClient();
    tray().removeAttribute("receiver");
    await settle();
    expect(tray().tray).toBeNull();
  });

  it("builds the tray once the client is set, and shows the loaded gifts", async () => {
    html('<gift-tray receiver="mert"></gift-tray>');
    tray().client = fakeClient();
    await settle();
    expect(tray().tray).not.toBeNull();
    expect(tray().querySelectorAll('[role="radio"]')).toHaveLength(2);
  });

  it("sends to the receiver with the reference, fires gift-sent, and plays the linked layer", async () => {
    html(`
      <gift-effect-layer id="fx"></gift-effect-layer>
      <gift-tray receiver="mert" reference="post-42" effects="#fx"></gift-tray>`);
    fx().options = { pictureWaitMs: 0 };
    const client = fakeClient();
    tray().client = client;
    await settle();
    const sent: GiftTransaction[] = [];
    tray().addEventListener("gift-sent", (e) => sent.push((e as CustomEvent).detail));
    sendButton().click();
    await settle();
    expect(client.sent).toHaveLength(1);
    expect(client.sent[0]).toMatchObject({
      receiver: "mert",
      giftId: "rose",
      reference: "post-42",
    });
    expect(sent).toHaveLength(1);
    expect(sent[0]!.id).toBe("tx1");
    expect(fx().querySelector("[data-gs-notice]")).not.toBeNull();
  });

  it("fires gift-error for a failed send", async () => {
    html('<gift-effect-layer></gift-effect-layer><gift-tray receiver="mert"></gift-tray>');
    const failure = new GiftingError(402, "insufficient_balance", "rejected");
    tray().client = fakeClient({
      sendGift: async () => {
        throw failure;
      },
    });
    await settle();
    const errors: GiftingError[] = [];
    tray().addEventListener("gift-error", (e) => errors.push((e as CustomEvent).detail));
    sendButton().click();
    await settle();
    expect(errors).toEqual([failure]);
  });

  it("changing the receiver rebuilds the tray and later sends go to the new one", async () => {
    html('<gift-tray receiver="mert"></gift-tray>');
    const client = fakeClient();
    tray().client = client;
    await settle();
    const first = tray().tray;
    tray().receiver = "zeynep";
    await settle();
    expect(tray().tray).not.toBe(first);
    sendButton().click();
    await settle();
    expect(client.sent[0]!.receiver).toBe("zeynep");
  });

  it("several attribute changes in one go build the tray once", async () => {
    html('<gift-tray receiver="mert"></gift-tray>');
    const getGifts = vi.fn(async () => GIFTS);
    tray().client = fakeClient({ getGifts });
    await settle();
    getGifts.mockClear();
    tray().setAttribute("coin-name", "diamonds");
    tray().setAttribute("columns", "3");
    tray().setAttribute("tray-title", "Hi");
    await settle();
    expect(getGifts).toHaveBeenCalledTimes(1);
    expect(tray().querySelector(".gs-title")!.textContent).toBe("Hi");
  });

  it("disabled updates the tray in place, without a rebuild", async () => {
    html('<gift-tray receiver="mert"></gift-tray>');
    const getGifts = vi.fn(async () => GIFTS);
    tray().client = fakeClient({ getGifts });
    await settle();
    const before = tray().tray;
    getGifts.mockClear();
    tray().setAttribute("disabled", "");
    await settle();
    expect(tray().tray).toBe(before);
    expect(getGifts).not.toHaveBeenCalled();
    expect(sendButton().getAttribute("aria-disabled")).toBe("true");
  });

  it("top-up shows the coin button and fires gift-topup", async () => {
    html('<gift-tray receiver="mert" top-up></gift-tray>');
    tray().client = fakeClient();
    await settle();
    let fired = 0;
    tray().addEventListener("gift-topup", () => fired++);
    const button = [...tray().querySelectorAll<HTMLElement>("button")].find((b) =>
      /coins/i.test(b.getAttribute("aria-label") ?? b.textContent ?? ""),
    );
    expect(button).toBeDefined();
    button!.click();
    expect(fired).toBe(1);
  });

  it("marks the host with the placement so a sheet lets clicks through", async () => {
    html('<gift-tray receiver="mert" placement="sheet"></gift-tray>');
    tray().client = fakeClient();
    await settle();
    expect(tray().getAttribute("data-gs-placement")).toBe("sheet");
    tray().setAttribute("placement", "inline");
    await settle();
    expect(tray().getAttribute("data-gs-placement")).toBe("inline");
  });

  describe.each([
    ["a", (px: number) => `${px + 16}px`],
    ["b", () => "33px"],
  ])("the sheet and the notice of layer #%s", (id, expected) => {
    it(
      id === "a" ? "the notice follows the sheet" : "a layer with its own notice-bottom keeps it",
      async () => {
        html(`
        <gift-effect-layer id="a"></gift-effect-layer>
        <gift-effect-layer id="b" notice-bottom="33"></gift-effect-layer>
        <gift-tray receiver="mert" effects="#${id}" placement="sheet"></gift-tray>`);
        tray().client = fakeClient();
        await settle();
        const insets: number[] = [];
        tray().addEventListener("gift-inset-change", (e) => insets.push((e as CustomEvent).detail));
        tray().querySelector<HTMLElement>("[data-gs-handle]")!.click();
        await vi.advanceTimersByTimeAsync(1000);
        expect(insets.length).toBeGreaterThan(0);
        const px = insets[insets.length - 1]!;
        const bottom = page.querySelector<HTMLElement>(`#${id} .gs-notice-region`)!.style.bottom;
        expect(bottom).toBe(expected(px));
        // The layer's own default is 150, so "followed the sheet" is visible in the number.
        if (id === "a") expect(bottom).not.toBe("150px");
      },
    );
  });

  it("a custom player property replaces the linked layer", async () => {
    html('<gift-effect-layer></gift-effect-layer><gift-tray receiver="mert"></gift-tray>');
    const played: string[] = [];
    tray().player = {
      play: (e) => {
        played.push(e.gift.id);
        return 1;
      },
      cancel: () => {},
    };
    tray().client = fakeClient();
    await settle();
    sendButton().click();
    await settle();
    expect(played).toEqual(["rose"]);
    expect(fx().querySelector("[data-gs-notice]")).toBeNull();
  });

  it("an invalid selector in effects or anchor does not throw", async () => {
    html('<gift-tray receiver="mert" effects="((" anchor="[["></gift-tray>');
    tray().client = fakeClient();
    await settle();
    expect(tray().tray).not.toBeNull();
    sendButton().click();
    await settle();
  });

  it("leaving the page destroys the tray; coming back builds it again", async () => {
    html('<gift-tray receiver="mert"></gift-tray>');
    const el = tray();
    el.client = fakeClient();
    await settle();
    el.remove();
    expect(el.tray).toBeNull();
    expect(el.querySelector(".gs-tray")).toBeNull();
    page.appendChild(el);
    await settle();
    expect(el.tray).not.toBeNull();
  });
});
