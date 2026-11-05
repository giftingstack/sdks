import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type AwayGroup,
  type AwaySummary,
  type GiftEffectEvent,
  type GiftingClient,
  GiftingError,
} from "../src/core";
import { type AwaySummaryContext, GiftAwaySummary, type GiftAwaySummaryOptions } from "../src/web";
import { componentCallStubs } from "./stub-client";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";

const group = (
  id: string,
  price: number,
  count: number,
  units: number,
  senders: AwayGroup["senders"] = [{ user: "ayla", count }],
  senderCount = senders.length,
): AwayGroup => ({
  gift: {
    id,
    name: id.charAt(0).toUpperCase() + id.slice(1),
    price,
    icon_url: `https://assets.test/${id}/256.webp`,
    animation_url: `https://assets.test/${id}/512.webp`,
  },
  count,
  units,
  sender_count: senderCount,
  senders,
});

/** The worked example of the design doc: star at 0, rose at 450, hat at 900, dragon at 3300. */
const GROUPS = [
  group("dragon", 40_000, 1, 40_000, [{ user: "ayla", count: 1 }]),
  group(
    "hat",
    350,
    20,
    7_000,
    [
      { user: "mert", count: 9 },
      { user: null, count: 4 },
      { user: "ece", count: 3 },
    ],
    6,
  ),
  group("rose", 10, 50, 500, [{ user: "ayla", count: 50 }]),
  group("star", 5, 3, 15, [{ user: "ece", count: 3 }]),
];

const summary = (patch: Partial<AwaySummary> = {}): AwaySummary => ({
  user: "me",
  since: "2026-10-08T09:12:44.120Z",
  until: "2026-10-11T07:30:02.511Z",
  cursor: "aw1.MTcyODYzMTgwMjUxMS40MjE3",
  truncated: false,
  total_gifts: 37,
  total_units: 47_515,
  sender_count: 12,
  groups: GROUPS,
  top_senders: [
    { user: "ayla", count: 15, units: 41_200 },
    { user: "mert", count: 9, units: 3_000 },
    { user: null, count: 4, units: 900 },
    { user: "ece", count: 3, units: 400 },
    { user: "zoe", count: 1, units: 10 },
  ],
  ...patch,
});

function fakeClient(first: AwaySummary | Error = summary()) {
  const getAway = vi.fn<GiftingClient["getAway"]>(async () => {
    if (first instanceof Error) throw first;
    return first;
  });
  const ackAway = vi.fn<GiftingClient["ackAway"]>(async () => {});
  const client: GiftingClient = {
    getGifts: async () => [],
    getMe: async () => ({ user: "me", balance: 0 }),
    getReceivedGifts: async () => [],
    sendGift: async () => {
      throw new Error("not used");
    },
    ...componentCallStubs,
    getAway,
    ackAway,
  };
  return { client, getAway, ackAway };
}

/** An effect player that records what the card asked for and when. */
function fakePlayer() {
  const plays: { at: number; event: GiftEffectEvent }[] = [];
  const t0 = Date.now();
  return {
    plays,
    play(event: GiftEffectEvent): number {
      plays.push({ at: Date.now() - t0, event });
      return plays.length;
    },
  };
}

let env: ReturnType<typeof installWebEnv>;
let screen: HTMLElement;
let cards: GiftAwaySummary[] = [];

beforeEach(() => {
  env = installWebEnv();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
  screen = document.createElement("div");
  document.body.appendChild(screen);
});
afterEach(() => {
  for (const c of cards) c.destroy();
  cards = [];
  screen.remove();
  vi.useRealTimers();
  env.restore();
});

const mk = (options: Partial<GiftAwaySummaryOptions> & { client: GiftingClient }) => {
  const card = new GiftAwaySummary(screen, options);
  cards.push(card);
  return card;
};
const advance = (ms: number) => vi.advanceTimersByTimeAsync(ms);
const $ = (sel: string) => screen.querySelector(sel) as HTMLElement;
const card = () => screen.querySelector<HTMLElement>("[data-gs-away-card]");
const live = () => screen.querySelector(".gs-sr")!.textContent;

describe("web GiftAwaySummary: the card", () => {
  it("shows the title, 'N gifts from M people', top 3 senders and the gift icons with counts", async () => {
    const { client } = fakeClient();
    mk({ client });
    expect(card()).toBeNull();
    await advance(0);
    expect(card()).not.toBeNull();
    expect($(".gs-away-title").textContent).toBe("While you were away");
    expect($(".gs-away-headline").textContent).toBe("37 gifts from 12 people");
    const senders = [...screen.querySelectorAll(".gs-away-sender")];
    expect(senders).toHaveLength(3); // the 4th and 5th are left out
    expect(senders.map((s) => s.querySelector(".gs-away-name")!.textContent)).toEqual([
      "ayla",
      "mert",
      "Someone",
    ]);
    expect(senders.map((s) => s.querySelector(".gs-away-count")!.textContent)).toEqual([
      "15",
      "9",
      "4",
    ]);
    const chips = [...screen.querySelectorAll(".gs-away-gifts .gs-chip")];
    expect(chips.map((c) => c.getAttribute("data-gs-gift"))).toEqual([
      "dragon",
      "hat",
      "rose",
      "star",
    ]);
    expect(chips.map((c) => c.textContent)).toEqual(["1", "20", "50", "3"]);
    expect(chips[0]!.querySelector("img")!.getAttribute("src")).toBe(
      "https://assets.test/dragon/256.webp",
    );
  });

  it("initial discs for senders without a picture, the picture when resolveUsers gives one", async () => {
    const { client } = fakeClient();
    mk({
      client,
      resolveUsers: async () => ({
        ayla: { name: "Ayla Kaya", avatarUrl: "https://img.test/ayla.png" },
        mert: { name: "Mert" },
      }),
    });
    await advance(0);
    const avatars = [...screen.querySelectorAll(".gs-away-sender .gs-avatar")];
    expect(avatars.map((a) => a.querySelector(".gs-avatar-letter")!.textContent)).toEqual([
      "A",
      "M",
      "S",
    ]);
    expect(avatars[0]!.querySelector("img")!.getAttribute("src")).toBe("https://img.test/ayla.png");
    expect(avatars[1]!.querySelector("img")).toBeNull();
    expect(avatars.every((a) => a.getAttribute("aria-hidden") === "true")).toBe(true);
  });

  it("resolveUsers is asked once, for every id that is not null, and its names reach the card and the replay", async () => {
    const { client } = fakeClient();
    const resolveUsers = vi.fn(async (ids: string[]) =>
      Object.fromEntries(ids.map((id) => [id, { name: `Name ${id}` }])),
    );
    const fx = fakePlayer();
    mk({ client, resolveUsers, effects: fx });
    await advance(0);
    expect(resolveUsers).toHaveBeenCalledOnce();
    expect([...resolveUsers.mock.calls[0]![0]].sort()).toEqual(["ayla", "ece", "mert", "zoe"]);
    expect($(".gs-away-name").textContent).toBe("Name ayla");
    await advance(1_000);
    const hat = fx.plays.find((p) => p.event.gift.id === "hat")!;
    expect(hat.event.sender).toBe("Name mert and 5 others");
    expect(fx.plays.find((p) => p.event.gift.id === "rose")!.event.sender).toBe("Name ayla");
  });

  it("falls back to the id when resolveUsers fails or misses, and reports the failure", async () => {
    const { client } = fakeClient();
    const onError = vi.fn();
    mk({ client, resolveUsers: async () => Promise.reject(new Error("nope")), onError });
    await advance(0);
    expect($(".gs-away-name").textContent).toBe("ayla");
    expect(onError).toHaveBeenCalledOnce();
    expect(onError.mock.calls[0]![0]).toBeInstanceOf(GiftingError);
  });

  it("does not wait for a slow resolveUsers forever (1.5 s)", async () => {
    const { client } = fakeClient();
    mk({ client, resolveUsers: () => new Promise(() => {}) });
    await advance(1_400);
    expect(card()).toBeNull();
    await advance(200);
    expect(card()).not.toBeNull();
    expect($(".gs-away-name").textContent).toBe("ayla");
  });

  it("a deleted sender is 'Someone' (labels.someone) in the card and in the replay", async () => {
    const { client } = fakeClient();
    const fx = fakePlayer();
    mk({ client, effects: fx, labels: { someone: "Biri" } });
    await advance(1_000);
    expect(screen.querySelectorAll(".gs-away-name")[2]!.textContent).toBe("Biri");
    const hat = fx.plays.find((p) => p.event.gift.id === "hat")!;
    // Names in server order: mert, Biri; six people in all.
    expect(hat.event.sender).toBe("mert and 5 others");
  });

  it("singular and plural wording, and a truncated summary says 2,000+", async () => {
    const one = fakeClient(
      summary({ total_gifts: 1, sender_count: 1, groups: [GROUPS[3]!], top_senders: [] }),
    );
    mk({ client: one.client });
    await advance(0);
    expect($(".gs-away-headline").textContent).toBe("1 gift from 1 person");
    cards.pop()!.destroy();
    const big = fakeClient(summary({ total_gifts: 2000, truncated: true, sender_count: 31 }));
    mk({ client: big.client });
    await advance(0);
    expect($(".gs-away-headline").textContent).toBe("2,000+ gifts from 31+ people");
  });

  it("labels translate the words", async () => {
    const { client } = fakeClient();
    mk({
      client,
      labels: {
        awayTitle: "Yokken",
        awaySummary: "{people} kişiden {gifts}",
        giftOther: "{n} hediye",
        personOther: "{n} kişi",
        dismiss: "Kapat",
        awayAnnounce: "Yokken {summary} aldın",
      },
    });
    await advance(0);
    expect($(".gs-away-title").textContent).toBe("Yokken");
    expect($(".gs-away-headline").textContent).toBe("12 kişi kişiden 37 hediye");
    expect($("[data-gs-dismiss]").getAttribute("aria-label")).toBe("Kapat");
    expect(live()).toBe("Yokken 12 kişi kişiden 37 hediye aldın");
  });

  it("theme sets the variables the card uses on the root", async () => {
    const { client } = fakeClient();
    const a = mk({
      client,
      theme: {
        surface: "#ffffff",
        text: "#111111",
        muted: "#555555",
        accent: "#6a54e8",
        accentText: "#ffffff",
      },
    });
    expect(a.element.style.getPropertyValue("--gs-surface")).toBe("#ffffff");
    expect(a.element.style.getPropertyValue("--gs-accent")).toBe("#6a54e8");
    expect(a.element.style.getPropertyValue("--gs-accent-text")).toBe("#ffffff");
  });
});

describe("web GiftAwaySummary: accessibility", () => {
  it("is a non-modal dialog named by its title, with a Dismiss button", async () => {
    const { client } = fakeClient();
    mk({ client });
    await advance(0);
    const c = card()!;
    expect(c.getAttribute("role")).toBe("dialog");
    expect(c.getAttribute("aria-modal")).toBe("false");
    const title = $(".gs-away-title");
    expect(c.getAttribute("aria-labelledby")).toBe(title.id);
    const close = $("[data-gs-dismiss]") as HTMLButtonElement;
    expect(close.tagName).toBe("BUTTON");
    expect(close.getAttribute("aria-label")).toBe("Dismiss");
  });

  it("a polite live region announces the summary, also with reduced motion", async () => {
    env.setReducedMotion(true);
    const { client } = fakeClient();
    mk({ client, effects: fakePlayer() });
    const region = $(".gs-sr");
    expect(region.getAttribute("role")).toBe("status");
    expect(region.getAttribute("aria-live")).toBe("polite");
    expect(region.textContent).toBe("");
    await advance(0);
    expect(region.textContent).toBe("You received 37 gifts from 12 people while you were away");
  });

  it("focus stays where it was, unless focusOnShow", async () => {
    const outside = document.createElement("button");
    screen.appendChild(outside);
    outside.focus();
    const { client } = fakeClient();
    mk({ client });
    await advance(0);
    expect(document.activeElement).toBe(outside);
    cards.pop()!.destroy();
    mk({ client: fakeClient().client, focusOnShow: true });
    await advance(0);
    expect(document.activeElement).toBe(card());
  });

  it("Escape on the card dismisses it", async () => {
    const { client } = fakeClient();
    const onDone = vi.fn();
    mk({ client, onDone, focusOnShow: true });
    await advance(0);
    card()!.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    expect(onDone).toHaveBeenCalledOnce();
  });
});

describe("web GiftAwaySummary: replay in the effect layer", () => {
  it("plays the groups as the design says: star 0, rose 450, hat 900, dragon 3300", async () => {
    const { client } = fakeClient();
    const fx = fakePlayer();
    mk({ client, effects: fx });
    await advance(0);
    expect(fx.plays.map((p) => [p.event.gift.id, p.at])).toEqual([["star", 0]]);
    await advance(449);
    expect(fx.plays).toHaveLength(1);
    await advance(1);
    expect(fx.plays.map((p) => p.event.gift.id)).toEqual(["star", "rose"]);
    await advance(450);
    expect(fx.plays.map((p) => p.event.gift.id)).toEqual(["star", "rose", "hat"]);
    await advance(2_399);
    expect(fx.plays).toHaveLength(3);
    await advance(1);
    expect(fx.plays.map((p) => [p.event.gift.id, p.at])).toEqual([
      ["star", 0],
      ["rose", 450],
      ["hat", 900],
      ["dragon", 3300],
    ]);
    // What the effect layer gets: the group's picture, icon, count and the sender label.
    const dragon = fx.plays[3]!.event;
    expect(dragon).toMatchObject({
      gift: {
        id: "dragon",
        name: "Dragon",
        price: 40_000,
        image: "https://assets.test/dragon/512.webp",
        icon: "https://assets.test/dragon/256.webp",
      },
      quantity: 1,
      sender: "ayla",
    });
  });

  it("calls the layer at most maxEffects times, and the plan ends within the budget", async () => {
    const many = Array.from({ length: 9 }, (_, i) => group(`g${i}`, 20 + i, 2, 100 + i));
    const { client } = fakeClient(summary({ groups: many }));
    const fx = fakePlayer();
    const a = mk({ client, effects: fx, maxEffects: 3 });
    await advance(20_000);
    expect(fx.plays).toHaveLength(3);
    const tight = fakeClient(summary({ groups: many }));
    const fx2 = fakePlayer();
    const b = mk({ client: tight.client, effects: fx2, maxEffects: 9, budgetMs: 3_000 });
    await advance(0);
    const plan = b.controller.getState().plan!;
    expect(plan.endMs).toBeLessThanOrEqual(3_000);
    await advance(20_000);
    expect(fx2.plays.length).toBeLessThan(9);
    expect(fx2.plays.length).toBe(plan.items.length);
    expect(a.controller.getState().plan!.items).toHaveLength(3);
  });

  it("only the first large group is played; the card still lists the others", async () => {
    const groups = [
      group("big1", 50_000, 1, 50_000),
      group("big2", 20_000, 1, 20_000),
      group("rose", 10, 5, 50),
    ];
    const { client } = fakeClient(summary({ groups }));
    const fx = fakePlayer();
    mk({ client, effects: fx });
    await advance(0);
    expect(screen.querySelectorAll(".gs-away-gifts .gs-chip")).toHaveLength(3);
    await advance(10_000);
    expect(fx.plays.map((p) => p.event.gift.id)).toEqual(["rose", "big1"]);
  });

  it("quality low is passed to the planner (large effect 3050 ms)", async () => {
    const { client } = fakeClient(summary({ groups: [group("dragon", 40_000, 1, 40_000)] }));
    const a = mk({ client, effects: fakePlayer(), quality: "low" });
    await advance(0);
    expect(a.controller.getState().plan!.endMs).toBe(3_050);
  });

  it("thresholds are passed to the planner", async () => {
    const { client } = fakeClient(summary({ groups: [group("hat", 350, 1, 350)] }));
    const a = mk({ client, effects: fakePlayer(), thresholds: { largeFrom: 300 } });
    await advance(0);
    expect(a.controller.getState().plan!.items[0]!.tier).toBe("large");
  });

  it("reduced motion: the card only, no replay, no slide-in", async () => {
    env.setReducedMotion(true);
    const { client } = fakeClient();
    const fx = fakePlayer();
    mk({ client, effects: fx });
    await advance(10_000);
    expect(fx.plays).toHaveLength(0);
    expect(env.animations).toHaveLength(0);
  });

  it("the reducedMotion option overrides the system setting", async () => {
    const { client } = fakeClient();
    const fx = fakePlayer();
    mk({ client, effects: fx, reducedMotion: true });
    await advance(10_000);
    expect(fx.plays).toHaveLength(0);
    const fx2 = fakePlayer();
    env.setReducedMotion(true);
    mk({ client: fakeClient().client, effects: fx2, reducedMotion: false });
    await advance(10_000);
    expect(fx2.plays.length).toBeGreaterThan(0);
  });

  it("without effects the card shows and nothing is played", async () => {
    const { client } = fakeClient();
    mk({ client });
    await advance(0);
    expect(card()).not.toBeNull();
  });

  it("the card slides in with motion on (opacity + transform, 240 ms)", async () => {
    const { client } = fakeClient();
    mk({ client });
    await advance(0);
    expect(env.animations).toHaveLength(1);
    expect(env.animations[0]!.options.duration).toBe(240);
    expect(Object.keys(env.animations[0]!.frames[0]!).sort()).toEqual(["opacity", "transform"]);
  });

  it("the effects can be given as a function, read when the replay starts", async () => {
    const { client } = fakeClient();
    const fx = fakePlayer();
    let layer: typeof fx | null = null;
    mk({ client, effects: () => layer });
    layer = fx;
    await advance(0);
    expect(fx.plays).toHaveLength(1);
  });
});

describe("web GiftAwaySummary: dismiss", () => {
  it("closes itself at max(4000, plan end + 1500) ms", async () => {
    const { client } = fakeClient();
    const onDone = vi.fn();
    const a = mk({ client, effects: fakePlayer(), onDone });
    await advance(0);
    const end = a.controller.getState().plan!.endMs; // 7150
    expect(end).toBe(7_150);
    await advance(end + 1_500 - 1);
    expect(card()).not.toBeNull();
    expect(onDone).not.toHaveBeenCalled();
    await advance(1);
    expect(onDone).toHaveBeenCalledOnce();
    await advance(200); // the fade-out
    expect(card()).toBeNull();
  });

  it("a card without a replay stays 4 s", async () => {
    const { client } = fakeClient();
    const onDone = vi.fn();
    mk({ client, onDone });
    await advance(3_999);
    expect(onDone).not.toHaveBeenCalled();
    await advance(1);
    expect(onDone).toHaveBeenCalledOnce();
  });

  it("a tap on the card or on the close button dismisses and drops the plays not started yet", async () => {
    const { client } = fakeClient();
    const fx = fakePlayer();
    const onDone = vi.fn();
    mk({ client, effects: fx, onDone });
    await advance(100);
    expect(fx.plays).toHaveLength(1);
    card()!.click();
    expect(onDone).toHaveBeenCalledOnce();
    await advance(10_000);
    expect(fx.plays).toHaveLength(1);
    expect(card()).toBeNull();

    const second = fakeClient();
    mk({ client: second.client, onDone });
    await advance(0);
    ($("[data-gs-dismiss]") as HTMLButtonElement).click();
    expect(onDone).toHaveBeenCalledTimes(2);
  });

  it("the close button does not also trigger the card tap twice", async () => {
    const { client, ackAway } = fakeClient();
    const onDone = vi.fn();
    mk({ client, onDone, ackOn: "finished" });
    await advance(0);
    ($("[data-gs-dismiss]") as HTMLButtonElement).click();
    expect(onDone).toHaveBeenCalledOnce();
    expect(ackAway).toHaveBeenCalledOnce();
  });

  it("without motion the card leaves at once; with motion it fades for 160 ms", async () => {
    const { client } = fakeClient();
    mk({ client });
    await advance(0);
    env.animations.length = 0;
    card()!.click();
    expect(card()).not.toBeNull(); // still fading
    expect(env.animations.at(-1)!.options.duration).toBe(160);
    await advance(160);
    expect(card()).toBeNull();
  });
});

describe("web GiftAwaySummary: acknowledging", () => {
  it("ackOn shown (default): one PUT with the cursor of the summary, when the card appears", async () => {
    const { client, ackAway } = fakeClient();
    mk({ client });
    expect(ackAway).not.toHaveBeenCalled();
    await advance(0);
    expect(ackAway).toHaveBeenCalledOnce();
    expect(ackAway).toHaveBeenCalledWith("aw1.MTcyODYzMTgwMjUxMS40MjE3");
    card()!.click();
    await advance(0);
    expect(ackAway).toHaveBeenCalledOnce(); // never twice for one summary
  });

  it("ackOn finished: nothing while the card is up, one PUT after it was dismissed", async () => {
    const { client, ackAway } = fakeClient();
    mk({ client, ackOn: "finished" });
    await advance(2_000);
    expect(card()).not.toBeNull();
    expect(ackAway).not.toHaveBeenCalled();
    card()!.click();
    await advance(0);
    expect(ackAway).toHaveBeenCalledOnce();
    expect(ackAway).toHaveBeenCalledWith("aw1.MTcyODYzMTgwMjUxMS40MjE3");
  });

  it("ackOn finished also acks when the card closes by itself", async () => {
    const { client, ackAway } = fakeClient();
    mk({ client, ackOn: "finished" });
    await advance(4_000);
    expect(ackAway).toHaveBeenCalledOnce();
  });

  it("ackOn manual: only ack() sends, even after a dismiss", async () => {
    const { client, ackAway } = fakeClient();
    const a = mk({ client, ackOn: "manual" });
    await advance(0);
    card()!.click();
    await advance(10_000);
    expect(ackAway).not.toHaveBeenCalled();
    await a.ack();
    expect(ackAway).toHaveBeenCalledOnce();
    await a.ack();
    expect(ackAway).toHaveBeenCalledOnce();
  });

  it("a failed ack is reported, and retried once at the next check", async () => {
    const { client, ackAway } = fakeClient();
    ackAway.mockRejectedValueOnce(new GiftingError(500, "x", "boom"));
    const onError = vi.fn();
    const a = mk({ client, onError });
    await advance(0);
    expect(onError).toHaveBeenCalledOnce();
    card()!.click();
    await advance(500);
    await a.check();
    await advance(0);
    expect(ackAway).toHaveBeenCalledTimes(3); // failed, retried at the check, then the new summary
  });
});

describe("web GiftAwaySummary: checking", () => {
  it("an empty summary shows nothing and does not call onShow", async () => {
    const { client, ackAway } = fakeClient(
      summary({ total_gifts: 0, groups: [], top_senders: [], sender_count: 0 }),
    );
    const onShow = vi.fn();
    mk({ client, onShow });
    await advance(0);
    expect(card()).toBeNull();
    expect(onShow).not.toHaveBeenCalled();
    expect(ackAway).not.toHaveBeenCalled();
    expect(live()).toBe("");
  });

  it("onShow gets the summary", async () => {
    const { client } = fakeClient();
    const onShow = vi.fn();
    mk({ client, onShow });
    await advance(0);
    expect(onShow).toHaveBeenCalledOnce();
    expect(onShow.mock.calls[0]![0].total_gifts).toBe(37);
  });

  it("a failed check shows nothing, reports, and the next check can succeed", async () => {
    const { client, getAway } = fakeClient(new GiftingError(500, "x", "boom"));
    const onError = vi.fn();
    const a = mk({ client, onError });
    await advance(0);
    expect(card()).toBeNull();
    expect(onError).toHaveBeenCalledOnce();
    getAway.mockResolvedValueOnce(summary());
    await a.check();
    await advance(0);
    expect(card()).not.toBeNull();
  });

  it("autoCheck false: no request until check() is called", async () => {
    const { client, getAway } = fakeClient();
    const a = mk({ client, autoCheck: false });
    await advance(1_000);
    expect(getAway).not.toHaveBeenCalled();
    await a.check();
    expect(getAway).toHaveBeenCalledOnce();
  });

  it("coming back to the page checks again, but at most once a minute", async () => {
    const { client, getAway } = fakeClient(summary({ total_gifts: 0, groups: [] }));
    mk({ client });
    await advance(0);
    expect(getAway).toHaveBeenCalledOnce();
    const show = () => document.dispatchEvent(new Event("visibilitychange"));
    await advance(59_000);
    show();
    await advance(0);
    expect(getAway).toHaveBeenCalledOnce();
    await advance(1_000);
    show();
    await advance(0);
    expect(getAway).toHaveBeenCalledTimes(2);
  });

  it("autoCheck false also ignores the page coming back", async () => {
    const { client, getAway } = fakeClient();
    mk({ client, autoCheck: false });
    document.dispatchEvent(new Event("visibilitychange"));
    await advance(0);
    expect(getAway).not.toHaveBeenCalled();
  });

  it("check() while a card is showing is ignored", async () => {
    const { client, getAway } = fakeClient();
    const a = mk({ client });
    await advance(0);
    await a.check();
    expect(getAway).toHaveBeenCalledOnce();
  });

  it("destroy removes the card, stops the replay and the page listener", async () => {
    const { client, getAway } = fakeClient();
    const fx = fakePlayer();
    const a = mk({ client, effects: fx });
    await advance(100);
    a.destroy();
    expect(screen.querySelector(".gs-away")).toBeNull();
    await advance(10_000);
    expect(fx.plays).toHaveLength(1);
    document.dispatchEvent(new Event("visibilitychange"));
    expect(getAway).toHaveBeenCalledOnce();
    expect(document.head.querySelector("style[data-giftingstack]")).toBeNull();
  });

  it("makes a static container positioned, and gives it back", () => {
    const { client } = fakeClient();
    const a = mk({ client, autoCheck: false });
    expect(screen.style.position).toBe("relative");
    a.destroy();
    expect(screen.style.position).toBe("");
  });
});

describe("minGifts", () => {
  it("below it: no card, the controller is empty, the summary is still acknowledged", async () => {
    const { client, ackAway } = fakeClient(summary({ total_gifts: 2 }));
    const onShow = vi.fn();
    mk({ client, minGifts: 3, onShow });
    await advance(100);
    expect(card()).toBeNull();
    expect(onShow).not.toHaveBeenCalled();
    expect(ackAway).toHaveBeenCalledExactlyOnceWith("aw1.MTcyODYzMTgwMjUxMS40MjE3");
  });

  it("at it: the card shows", async () => {
    const { client } = fakeClient(summary({ total_gifts: 3 }));
    mk({ client, minGifts: 3 });
    await advance(100);
    expect(card()).not.toBeNull();
  });
});

describe("web GiftAwaySummary: renderSummary", () => {
  it("is called once with the computed data, resolved names and callbacks", async () => {
    const { client } = fakeClient();
    const renderSummary = vi.fn((_c: AwaySummaryContext) => "mine");
    mk({
      client,
      renderSummary,
      resolveUsers: async (ids) =>
        Object.fromEntries(
          ids.map((id) => [
            id,
            {
              name: id.toUpperCase(),
              avatarUrl: id === "ayla" ? "https://img.test/a.png" : undefined,
            },
          ]),
        ),
    });
    await advance(0);
    expect(renderSummary).toHaveBeenCalledOnce();
    const c = renderSummary.mock.calls[0]![0];
    expect(c.summary.total_gifts).toBe(37);
    expect(c.title).toBe("While you were away");
    expect(c.headline).toBe("37 gifts from 12 people");
    expect(c.gifts).toBe("37 gifts");
    expect(c.people).toBe("12 people");
    expect(c.senders).toHaveLength(5);
    expect(c.senders[0]).toEqual({
      user: "ayla",
      name: "AYLA",
      avatarUrl: "https://img.test/a.png",
      count: 15,
    });
    expect(c.senders[2]).toMatchObject({ user: null, name: "Someone" });
    expect(c.doc).toBe(document);
  });

  it("what it returns is the card body; the card keeps role, label, announcement and the replay", async () => {
    const { client, ackAway } = fakeClient();
    const fx = fakePlayer();
    mk({
      client,
      effects: fx,
      renderSummary: (c) => {
        const p = document.createElement("p");
        p.className = "mine";
        p.textContent = c.headline;
        return p;
      },
    });
    await advance(100);
    expect(card()!.getAttribute("role")).toBe("dialog");
    expect(card()!.getAttribute("aria-label")).toBe("While you were away");
    expect(card()!.querySelector(".mine")!.textContent).toBe("37 gifts from 12 people");
    expect(card()!.querySelector(".gs-away-title")).toBeNull();
    expect(card()!.querySelector("[data-gs-dismiss]")).toBeNull();
    expect(live()).toContain("37 gifts from 12 people");
    expect(fx.plays).toHaveLength(1);
    expect(ackAway).toHaveBeenCalledOnce();
  });

  it("dismiss() from the hook closes it; a tap on the custom body does not; Escape does", async () => {
    const { client } = fakeClient();
    const onDone = vi.fn();
    let dismiss: () => void = () => {};
    mk({
      client,
      onDone,
      renderSummary: (c) => {
        dismiss = c.dismiss;
        const b = document.createElement("button");
        b.className = "mine";
        b.textContent = "x";
        return b;
      },
    });
    await advance(0);
    ($(".mine") as HTMLButtonElement).click();
    card()!.click();
    expect(onDone).not.toHaveBeenCalled();
    dismiss();
    expect(onDone).toHaveBeenCalledOnce();
    await advance(500);
    expect(card()).toBeNull();

    mk({ client: fakeClient().client, onDone, renderSummary: () => "again" });
    await advance(0);
    card()!.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    expect(onDone).toHaveBeenCalledTimes(2);
  });

  it("ack() from the hook sends the acknowledgement with ackOn manual", async () => {
    const { client, ackAway } = fakeClient();
    let ack: () => Promise<void> = async () => {};
    mk({
      client,
      ackOn: "manual",
      renderSummary: (c) => {
        ack = c.ack;
        return "x";
      },
    });
    await advance(0);
    expect(ackAway).not.toHaveBeenCalled();
    await ack();
    expect(ackAway).toHaveBeenCalledOnce();
  });

  it("nothing (or a throw) draws the default card; a throw goes to onError", async () => {
    const onError = vi.fn();
    mk({ client: fakeClient().client, renderSummary: () => undefined });
    await advance(0);
    expect($(".gs-away-title").textContent).toBe("While you were away");
    card()!.click(); // the default: a tap dismisses
    await advance(500);
    expect(card()).toBeNull();

    mk({
      client: fakeClient().client,
      onError,
      renderSummary: () => {
        throw new Error("broken");
      },
    });
    await advance(0);
    expect($(".gs-away-headline").textContent).toBe("37 gifts from 12 people");
    expect(onError).toHaveBeenCalledOnce();
  });
});
