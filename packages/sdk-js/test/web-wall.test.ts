import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type GiftWall as GiftWallAnswer,
  type GiftWallQueryItem,
  type GiftingClient,
  GiftingError,
  type ReceivedGift,
} from "../src/core";
import { GiftWall, type GiftWallOptions, type WallChipContext } from "../src/web";
import { CSS } from "../src/web/styles";
import { componentCallStubs } from "./stub-client";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";

const rg = (id: string, count: number): ReceivedGift => ({
  gift: {
    id,
    name: id.charAt(0).toUpperCase() + id.slice(1),
    icon_url: `https://assets.test/${id}/256.webp`,
  },
  count,
});
/** In catalog order, as the API sends them. */
const WALL = [rg("rose", 12), rg("heart", 3), rg("dragon", 1), rg("star", 20), rg("hat", 5)];

type Query = (items: GiftWallQueryItem[]) => Promise<GiftWallAnswer[]>;

function fakeClient(answer: (item: GiftWallQueryItem) => ReceivedGift[] = () => WALL) {
  const query = vi.fn<Query>(async (items) =>
    items.map((i) => ({ receiver: i.receiver, reference: i.reference ?? null, gifts: answer(i) })),
  );
  const client: GiftingClient = {
    getGifts: async () => [],
    getMe: async () => ({ user: "ayla", balance: 0 }),
    getReceivedGifts: async () => [],
    sendGift: async () => {
      throw new Error("not used");
    },
    ...componentCallStubs,
    queryGiftWalls: query,
  };
  return { client, query };
}

let env: ReturnType<typeof installWebEnv>;
let page: HTMLElement;
let walls: GiftWall[] = [];

beforeEach(() => {
  env = installWebEnv();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
  page = document.createElement("div");
  document.body.appendChild(page);
});
afterEach(() => {
  for (const w of walls) w.destroy();
  walls = [];
  page.remove();
  vi.useRealTimers();
  env.restore();
});

const mk = (options: GiftWallOptions, container: HTMLElement = page) => {
  const wall = new GiftWall(container, options);
  walls.push(wall);
  return wall;
};
const advance = (ms: number) => vi.advanceTimersByTimeAsync(ms);
const chips = (w: GiftWall) => [...w.element.querySelectorAll<HTMLElement>(".gs-chip")];
const counts = (w: GiftWall) => chips(w).map((c) => c.textContent);

describe("web GiftWall: states", () => {
  it("shows three static skeleton chips while loading, then the chips", async () => {
    const { client } = fakeClient();
    const wall = mk({ client, user: "mert" });
    expect(wall.element.querySelectorAll(".gs-chip-skeleton")).toHaveLength(3);
    expect(wall.element.getAttribute("aria-hidden")).toBe("true");
    expect(env.animations).toHaveLength(0);
    await advance(50);
    expect(wall.element.querySelectorAll(".gs-chip-skeleton")).toHaveLength(0);
    expect(wall.element.hasAttribute("aria-hidden")).toBe(false);
    expect(counts(wall)).toEqual(["20", "12", "5", "3", "1"]);
  });

  it("draws nothing when there are no gifts (empty), and the optional emptyText", async () => {
    const { client } = fakeClient(() => []);
    const wall = mk({ client, user: "mert" });
    await advance(50);
    expect(wall.element.hidden).toBe(true);
    expect(wall.element.children).toHaveLength(0);
    const second = mk({ client, user: "zed", labels: { emptyText: "No gifts yet" } });
    await advance(50);
    expect(second.element.hidden).toBe(false);
    expect(second.element.textContent).toBe("No gifts yet");
  });

  it("zero counts are dropped, so an all-zero wall is empty", async () => {
    const { client } = fakeClient(() => [rg("rose", 0)]);
    const wall = mk({ client, user: "mert" });
    await advance(50);
    expect(wall.element.hidden).toBe(true);
  });

  it("a failed request draws nothing and only reports to onError", async () => {
    const { client, query } = fakeClient();
    query.mockRejectedValue(new GiftingError(500, "server_error", "boom"));
    const onError = vi.fn();
    const wall = mk({ client, user: "mert", onError });
    await advance(50);
    expect(onError).toHaveBeenCalledOnce();
    expect(onError.mock.calls[0]![0]).toBeInstanceOf(GiftingError);
    expect(wall.element.hidden).toBe(true);
    expect(wall.element.textContent).toBe("");
  });

  it("a network error that is not a GiftingError is wrapped for onError", async () => {
    const { client, query } = fakeClient();
    query.mockRejectedValue(new TypeError("offline"));
    const onError = vi.fn();
    mk({ client, user: "mert", onError });
    await advance(50);
    expect(onError.mock.calls[0]![0]).toBeInstanceOf(GiftingError);
  });

  it("data skips the request and draws at once", () => {
    const { client, query } = fakeClient();
    const wall = mk({ client, user: "mert", data: [rg("rose", 2)] });
    expect(counts(wall)).toEqual(["2"]);
    expect(query).not.toHaveBeenCalled();
  });
});

describe("web GiftWall: props", () => {
  it("order count sorts by count then catalog order; order catalog keeps the server order", async () => {
    const { client } = fakeClient(() => [rg("a", 5), rg("b", 9), rg("c", 5)]);
    const byCount = mk({ client, user: "u1" });
    const byCatalog = mk({ client, user: "u2", order: "catalog" });
    await advance(50);
    expect(chips(byCount).map((c) => c.dataset.gsGift)).toEqual(["b", "a", "c"]);
    expect(chips(byCatalog).map((c) => c.dataset.gsGift)).toEqual(["a", "b", "c"]);
  });

  it("max includes the overflow chip, which carries the SUM of the hidden counts", async () => {
    const { client } = fakeClient();
    const wall = mk({ client, user: "mert", max: 3 });
    await advance(50);
    expect(counts(wall)).toEqual(["20", "12", "+9"]); // 5 + 3 + 1 hidden
    expect(wall.element.querySelector("[data-gs-overflow]")!.textContent).toBe("+9");
    const one = mk({ client, user: "zed", max: 1 });
    await advance(50);
    expect(counts(one)).toEqual(["+41"]);
  });

  it("writes counts short and rounded down", async () => {
    const { client } = fakeClient(() => [rg("rose", 1999), rg("heart", 12_000), rg("star", 999)]);
    const wall = mk({ client, user: "mert" });
    await advance(50);
    expect(counts(wall)).toEqual(["12K", "1.9K", "999"]);
  });

  it("labels change the count suffixes and the words", async () => {
    const { client } = fakeClient(() => [rg("rose", 2500)]);
    const wall = mk({
      client,
      user: "mert",
      labels: { thousand: " bin", wallSummary: "Hediyeler: {list}", plural: "" },
    });
    await advance(50);
    expect(counts(wall)).toEqual(["2.5 bin"]);
    expect(wall.element.getAttribute("aria-label")).toBe("Hediyeler: 2,500 Rose");
  });

  it("size sm and md set the class (icon 16 / 20 and text sizes live in the CSS)", async () => {
    const { client } = fakeClient();
    const sm = mk({ client, user: "a", size: "sm" });
    const md = mk({ client, user: "b" });
    expect(sm.element.classList.contains("gs-wall-sm")).toBe(true);
    expect(md.element.classList.contains("gs-wall-md")).toBe(true);
    expect(CSS).toMatch(/\.gs-wall-sm \.gs-chip-icon \{ width: 16px; height: 16px; \}/);
    expect(CSS).toMatch(/\.gs-chip-icon \{[^}]*width: 20px; height: 20px/);
    expect(CSS).toMatch(/\.gs-wall-sm \.gs-chip \{ height: 20px;[^}]*font-size: 11px/);
  });

  it("the reference goes into the request; no reference is a profile wall", async () => {
    const { client, query } = fakeClient();
    mk({ client, user: "mert", reference: "post_99" });
    mk({ client, user: "ayla" });
    await advance(50);
    expect(query).toHaveBeenCalledOnce();
    expect(query.mock.calls[0]![0]).toEqual([
      { receiver: "mert", reference: "post_99" },
      { receiver: "ayla" },
    ]);
  });

  it("theme sets the CSS variables on the wall root", () => {
    const { client } = fakeClient();
    const wall = mk({
      client,
      user: "mert",
      data: [rg("rose", 1)],
      theme: { surface: "#101010", border: "#202020", text: "#fafafa", muted: "#bbbbbb" },
    });
    const s = wall.element.style;
    expect(s.getPropertyValue("--gs-surface")).toBe("#101010");
    expect(s.getPropertyValue("--gs-border")).toBe("#202020");
    expect(s.getPropertyValue("--gs-text")).toBe("#fafafa");
    expect(s.getPropertyValue("--gs-muted")).toBe("#bbbbbb");
    wall.update({ theme: undefined });
    expect(s.getPropertyValue("--gs-surface")).toBe("");
  });

  it("a gift without a picture gets a plain disc, and the images are marked for the hardening CSS", () => {
    const { client } = fakeClient();
    const wall = mk({
      client,
      user: "mert",
      data: [{ gift: { id: "x", name: "X", icon_url: null }, count: 1 }, rg("rose", 1)],
    });
    expect(wall.element.querySelectorAll(".gs-chip-fallback")).toHaveLength(1);
    expect(wall.element.querySelectorAll("img.gs-chip-icon")).toHaveLength(1);
    // Page CSS must not move or squeeze the SDK's pictures: the same rules as the tray.
    expect(CSS).toMatch(/\.gs-wall img[^{]*\{\s*position: static !important/);
  });
});

describe("web GiftWall: accessibility", () => {
  it("the row is one labelled element and the chips are not focusable", async () => {
    const { client } = fakeClient(() => [rg("rose", 12), rg("heart", 3), rg("dragon", 37)]);
    const wall = mk({ client, user: "mert", max: 3 });
    await advance(50);
    expect(wall.element.getAttribute("role")).toBe("img");
    expect(wall.element.getAttribute("aria-label")).toBe("Gifts: 37 Dragons, 12 Roses, 3 Hearts");
    expect(wall.element.querySelectorAll("button")).toHaveLength(0);
    expect(wall.element.querySelectorAll("[tabindex]")).toHaveLength(0);
  });

  it("names the overflow like 'and 37 more' and uses the singular for one", async () => {
    const { client } = fakeClient(() => [
      rg("rose", 12),
      rg("heart", 3),
      rg("dragon", 1),
      rg("star", 36),
    ]);
    const wall = mk({ client, user: "mert", max: 3 });
    await advance(50);
    // star 36, rose 12, then overflow = heart 3 + dragon 1
    expect(wall.element.getAttribute("aria-label")).toBe("Gifts: 36 Stars, 12 Roses, and 4 more");
    const single = mk({ client, user: "zed", data: [rg("dragon", 1)] });
    expect(single.element.getAttribute("aria-label")).toBe("Gifts: 1 Dragon");
  });

  it("with onPressChip each gift chip is a button 'Rose, 12' and the row is a group", async () => {
    const { client } = fakeClient();
    const onPressChip = vi.fn();
    const wall = mk({ client, user: "mert", onPressChip, max: 3 });
    await advance(50);
    expect(wall.element.getAttribute("role")).toBe("group");
    const buttons = [...wall.element.querySelectorAll<HTMLButtonElement>("button")];
    expect(buttons.map((b) => b.getAttribute("aria-label"))).toEqual(["Star, 20", "Rose, 12"]);
    expect(buttons.every((b) => b.type === "button")).toBe(true);
    buttons[1]!.click();
    expect(onPressChip).toHaveBeenCalledOnce();
    expect(onPressChip.mock.calls[0]![0]).toMatchObject({ id: "rose", name: "Rose" });
    // The overflow chip stands for several gifts: it is not a button.
    expect(wall.element.querySelector("[data-gs-overflow]")!.tagName).toBe("SPAN");
  });

  it("a tappable chip keeps a 44 px touch target through a hit area larger than the pill", () => {
    expect(CSS).toMatch(
      /button\.gs-chip::after \{ content: ""; position: absolute; inset: -10px -3px/,
    );
    // 24 px pill + 2 x 10 px = 44 px; the small pill (20) gets 12 px each side.
    expect(CSS).toMatch(/\.gs-wall-sm button\.gs-chip::after \{ inset: -12px -3px/);
  });
});

describe("web GiftWall: motion", () => {
  it("fades in over 120 ms when data arrives", async () => {
    const { client } = fakeClient();
    mk({ client, user: "mert" });
    await advance(50);
    expect(env.animations).toHaveLength(1);
    expect(env.animations[0]!.options.duration).toBe(120);
    expect(env.animations[0]!.frames).toEqual([{ opacity: 0 }, { opacity: 1 }]);
  });

  it("does not animate under reduced motion", async () => {
    env.setReducedMotion(true);
    const { client } = fakeClient();
    mk({ client, user: "mert" });
    await advance(50);
    expect(env.animations).toHaveLength(0);
  });

  it("preloaded data and cached walls appear without a fade", () => {
    const { client } = fakeClient();
    mk({ client, user: "mert", data: [rg("rose", 1)] });
    expect(env.animations).toHaveLength(0);
  });
});

describe("web GiftWall: batching and cache (shared loader)", () => {
  it("several walls made within 50 ms go out as ONE request, in order", async () => {
    const { client, query } = fakeClient();
    const made = ["a", "b", "c"].map((u) => mk({ client, user: u, reference: `post_${u}` }));
    await advance(49);
    expect(query).not.toHaveBeenCalled();
    await advance(1);
    expect(query).toHaveBeenCalledOnce();
    expect(query.mock.calls[0]![0].map((i) => i.receiver)).toEqual(["a", "b", "c"]);
    expect(made.every((w) => chips(w).length === 5)).toBe(true);
  });

  it("a wall asked after the window closed goes out in a second request", async () => {
    const { client, query } = fakeClient();
    mk({ client, user: "a" });
    await advance(50);
    mk({ client, user: "b" });
    await advance(50);
    expect(query).toHaveBeenCalledTimes(2);
  });

  it("more than 25 walls make several requests of at most 25", async () => {
    const { client, query } = fakeClient();
    for (let i = 0; i < 26; i++) mk({ client, user: `u${i}` });
    await advance(50);
    expect(query.mock.calls.map((c) => c[0].length)).toEqual([25, 1]);
  });

  it("the same wall twice is asked once; the answer is reused for 60 s, not longer", async () => {
    const { client, query } = fakeClient();
    mk({ client, user: "mert", reference: "p" });
    mk({ client, user: "mert", reference: "p" });
    await advance(50);
    expect(query.mock.calls[0]![0]).toHaveLength(1);
    const later = mk({ client, user: "mert", reference: "p" });
    expect(chips(later)).toHaveLength(5); // from the cache, at once
    expect(query).toHaveBeenCalledOnce();
    await advance(59_950);
    mk({ client, user: "mert", reference: "p" });
    await advance(50);
    expect(query).toHaveBeenCalledOnce();
    await advance(60_000);
    mk({ client, user: "mert", reference: "p" });
    await advance(50);
    expect(query).toHaveBeenCalledTimes(2);
  });

  it("walls of different clients do not share requests", async () => {
    const one = fakeClient();
    const two = fakeClient();
    mk({ client: one.client, user: "a" });
    mk({ client: two.client, user: "a" });
    await advance(50);
    expect(one.query).toHaveBeenCalledOnce();
    expect(two.query).toHaveBeenCalledOnce();
  });
});

describe("web GiftWall: refreshKey and update", () => {
  it("changing refreshKey asks again and keeps the chips on screen meanwhile", async () => {
    let n = 1;
    const { client, query } = fakeClient(() => [rg("rose", n)]);
    const wall = mk({ client, user: "mert", refreshKey: 0 });
    await advance(50);
    expect(counts(wall)).toEqual(["1"]);
    n = 2;
    wall.update({ refreshKey: 1 });
    expect(counts(wall)).toEqual(["1"]); // still the old chips: no skeleton flash
    await advance(50);
    expect(query).toHaveBeenCalledTimes(2);
    expect(counts(wall)).toEqual(["2"]);
    wall.update({ refreshKey: 1 }); // same key: nothing
    await advance(50);
    expect(query).toHaveBeenCalledTimes(2);
  });

  it("a new user starts over with the skeleton", async () => {
    const { client } = fakeClient((i) => (i.receiver === "a" ? [rg("rose", 1)] : [rg("heart", 7)]));
    const wall = mk({ client, user: "a" });
    await advance(50);
    wall.update({ user: "b" });
    expect(wall.element.querySelectorAll(".gs-chip-skeleton")).toHaveLength(3);
    await advance(50);
    expect(counts(wall)).toEqual(["7"]);
  });

  it("an answer that arrives after the user changed is ignored", async () => {
    const { client } = fakeClient((i) => (i.receiver === "a" ? [rg("rose", 1)] : [rg("heart", 7)]));
    const wall = mk({ client, user: "a" });
    wall.update({ user: "b" });
    await advance(50);
    expect(counts(wall)).toEqual(["7"]);
  });

  it("update can switch the press handler on and the size", async () => {
    const { client } = fakeClient();
    const wall = mk({ client, user: "mert", data: [rg("rose", 2)] });
    expect(wall.element.querySelectorAll("button")).toHaveLength(0);
    wall.update({ onPressChip: () => {}, size: "sm" });
    expect(wall.element.querySelectorAll("button")).toHaveLength(1);
    expect(wall.element.classList.contains("gs-wall-sm")).toBe(true);
  });

  it("destroy removes the wall and the shared style sheet, and later answers do nothing", async () => {
    const { client } = fakeClient();
    const wall = mk({ client, user: "mert" });
    expect(document.head.querySelector("style[data-giftingstack]")).not.toBeNull();
    wall.destroy();
    await advance(50);
    expect(page.querySelector(".gs-wall")).toBeNull();
    expect(document.head.querySelector("style[data-giftingstack]")).toBeNull();
    wall.update({ user: "x" }); // harmless
  });
});

describe("web GiftWall: renderChip", () => {
  it("is called per gift chip with the gift, the exact count and the short text, in shown order", async () => {
    const { client } = fakeClient(() => [rg("rose", 1999), rg("star", 12_400)]);
    const renderChip = vi.fn((c: WallChipContext) => `${c.gift.id}:${c.count}:${c.countText}`);
    const wall = mk({ client, user: "mert", renderChip });
    expect(renderChip).not.toHaveBeenCalled(); // not while loading
    await advance(50);
    expect(renderChip.mock.calls.map((c) => c[0].gift.id)).toEqual(["star", "rose"]);
    expect(renderChip.mock.calls[0]![0]).toMatchObject({ count: 12_400, countText: "12K" });
    expect(renderChip.mock.calls[0]![0].doc).toBe(document);
    expect(counts(wall)).toEqual(["star:12400:12K", "rose:1999:1.9K"]);
  });

  it("what it returns replaces the inside of the chip; the chip keeps its data, role and press", async () => {
    const { client } = fakeClient(() => [rg("rose", 12)]);
    const onPressChip = vi.fn();
    const wall = mk({
      client,
      user: "mert",
      onPressChip,
      renderChip: (c) => {
        const b = document.createElement("b");
        b.className = "mine";
        b.textContent = `x${c.count}`;
        return b;
      },
    });
    await advance(50);
    const chip = chips(wall)[0] as HTMLButtonElement;
    expect(chip.tagName).toBe("BUTTON");
    expect(chip.dataset.gsGift).toBe("rose");
    expect(chip.getAttribute("aria-label")).toBe("Rose, 12");
    expect(chip.querySelector(".mine")!.textContent).toBe("x12");
    expect(chip.querySelector(".gs-chip-count")).toBeNull();
    expect(chip.querySelector("img")).toBeNull();
    chip.click();
    expect(onPressChip).toHaveBeenCalledWith(expect.objectContaining({ id: "rose" }));
  });

  it("a string is text, never HTML; the overflow chip is not passed to the hook", async () => {
    const { client } = fakeClient();
    const renderChip = vi.fn(() => "<i>1</i>");
    const wall = mk({ client, user: "mert", max: 3, renderChip });
    await advance(50);
    expect(renderChip).toHaveBeenCalledTimes(2); // 2 gifts + the "+N" overflow chip
    expect(chips(wall)[0]!.querySelector("i")).toBeNull();
    expect(chips(wall)[0]!.textContent).toBe("<i>1</i>");
    expect(wall.element.querySelector("[data-gs-overflow]")!.textContent).toMatch(/^\+\d+$/);
  });

  it("nothing (or a throw) draws the default chip; a throw also goes to onError", async () => {
    const { client } = fakeClient(() => [rg("rose", 12), rg("heart", 3)]);
    const onError = vi.fn();
    const wall = mk({
      client,
      user: "mert",
      onError,
      renderChip: (c) => {
        if (c.gift.id === "heart") throw new Error("broken");
        return undefined;
      },
    });
    await advance(50);
    expect(counts(wall)).toEqual(["12", "3"]);
    expect(chips(wall)[0]!.querySelector("img")).not.toBeNull();
    expect(onError).toHaveBeenCalledOnce();
  });

  it("without the hook the chips are the default ones, and update() can add or remove it", async () => {
    const { client } = fakeClient(() => [rg("rose", 12)]);
    const wall = mk({ client, user: "mert" });
    await advance(50);
    expect(counts(wall)).toEqual(["12"]);
    wall.update({ renderChip: () => "hi" });
    expect(counts(wall)).toEqual(["hi"]);
    wall.update({ renderChip: undefined });
    expect(counts(wall)).toEqual(["12"]);
  });
});
