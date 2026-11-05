import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type AwaySummary,
  type GiftEffectEvent,
  type GiftingClient,
  GiftingError,
  type Leaderboard,
  type ReceivedGift,
} from "../src/core";
import {
  GiftAwaySummaryElement,
  GiftEffectLayerElement,
  GiftLeaderboardElement,
  GiftWallElement,
  defineGiftElements,
} from "../src/web";
import { componentCallStubs } from "./stub-client";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";

const rg = (id: string, count: number): ReceivedGift => ({
  gift: {
    id,
    name: id.charAt(0).toUpperCase() + id.slice(1),
    icon_url: `https://assets.test/${id}.webp`,
  },
  count,
});

const AWAY: AwaySummary = {
  user: "me",
  since: "2026-10-08T00:00:00.000Z",
  until: "2026-10-11T00:00:00.000Z",
  cursor: "aw1.abc",
  truncated: false,
  total_gifts: 4,
  total_units: 40,
  sender_count: 2,
  groups: [
    {
      gift: {
        id: "rose",
        name: "Rose",
        price: 10,
        icon_url: "https://assets.test/rose.webp",
        animation_url: null,
      },
      count: 4,
      units: 40,
      sender_count: 2,
      senders: [
        { user: "ayla", count: 3 },
        { user: "mert", count: 1 },
      ],
    },
  ],
  top_senders: [{ user: "ayla", count: 3, units: 30 }],
};

const BOARD: Leaderboard = {
  board: "senders",
  period: "week",
  metric: "units",
  label: "2026-W41",
  starts_at: null,
  ends_at: null,
  as_of: "2026-10-11T00:00:00.000Z",
  data: [
    { rank: 1, user: "ayla", gifts: 3, units: 300 },
    { rank: 2, user: "mert", gifts: 1, units: 100 },
  ],
  has_more: false,
  me: null,
};

function fakeClient() {
  const queryGiftWalls = vi.fn<GiftingClient["queryGiftWalls"]>(async (items) =>
    items.map((i) => ({
      receiver: i.receiver,
      reference: i.reference ?? null,
      gifts: [rg("rose", 12), rg("heart", 3)],
    })),
  );
  const getAway = vi.fn<GiftingClient["getAway"]>(async () => AWAY);
  const ackAway = vi.fn<GiftingClient["ackAway"]>(async () => {});
  const getLeaderboard = vi.fn<GiftingClient["getLeaderboard"]>(async (board, q = {}) => ({
    ...BOARD,
    board,
    period: q.period ?? "week",
    metric: q.metric ?? "units",
  }));
  const client: GiftingClient = {
    getGifts: async () => [],
    getMe: async () => ({ user: "me", balance: 0 }),
    getReceivedGifts: async () => [],
    sendGift: async () => {
      throw new Error("not used");
    },
    ...componentCallStubs,
    queryGiftWalls,
    getAway,
    ackAway,
    getLeaderboard,
  };
  return { client, queryGiftWalls, getAway, ackAway, getLeaderboard };
}

let env: ReturnType<typeof installWebEnv>;
let page: HTMLElement;

beforeEach(() => {
  env = installWebEnv();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS, "setInterval", "clearInterval"] });
  defineGiftElements();
  page = document.createElement("div");
  document.body.appendChild(page);
});
afterEach(() => {
  page.remove();
  vi.useRealTimers();
  env.restore();
});

const settle = (ms = 0) => vi.advanceTimersByTimeAsync(ms);
const html = (markup: string) => {
  page.innerHTML = markup;
};
const give = (selector: string, client: GiftingClient) => {
  for (const el of page.querySelectorAll<HTMLElement & { client: GiftingClient | null }>(selector))
    el.client = client;
};

describe("defineGiftElements: the new tags", () => {
  it("registers all five tags, and calling it again is harmless", () => {
    defineGiftElements();
    for (const tag of [
      "gift-effect-layer",
      "gift-tray",
      "gift-wall",
      "gift-away-summary",
      "gift-leaderboard",
    ])
      expect(customElements.get(tag), tag).toBeDefined();
    expect(customElements.get("gift-wall")).toBe(GiftWallElement);
    expect(customElements.get("gift-away-summary")).toBe(GiftAwaySummaryElement);
    expect(customElements.get("gift-leaderboard")).toBe(GiftLeaderboardElement);
  });
});

describe("<gift-wall>", () => {
  it("stays empty without a client or a user, and draws once it has both", async () => {
    const { client, queryGiftWalls } = fakeClient();
    html("<gift-wall></gift-wall>");
    const el = page.querySelector("gift-wall") as GiftWallElement;
    el.client = client;
    await settle(50);
    expect(el.querySelector(".gs-wall")).toBeNull();
    el.setAttribute("user", "mert");
    await settle(50);
    expect(queryGiftWalls).toHaveBeenCalledOnce();
    expect(el.querySelectorAll(".gs-chip")).toHaveLength(2);
    el.removeAttribute("user");
    expect(el.querySelector(".gs-wall")).toBeNull();
  });

  it("several walls of a feed make one request, with their references", async () => {
    const { client, queryGiftWalls } = fakeClient();
    html(`
      <gift-wall user="a" reference="p1"></gift-wall>
      <gift-wall user="b" reference="p2"></gift-wall>
      <gift-wall user="c"></gift-wall>`);
    give("gift-wall", client);
    await settle(50);
    expect(queryGiftWalls).toHaveBeenCalledOnce();
    expect(queryGiftWalls.mock.calls[0]![0]).toEqual([
      { receiver: "a", reference: "p1" },
      { receiver: "b", reference: "p2" },
      { receiver: "c" },
    ]);
  });

  it("max, order and size attributes reach the wall", async () => {
    const { client } = fakeClient();
    html('<gift-wall user="a" max="1" size="sm" order="catalog"></gift-wall>');
    give("gift-wall", client);
    await settle(50);
    const wall = page.querySelector(".gs-wall")!;
    expect(wall.classList.contains("gs-wall-sm")).toBe(true);
    expect(wall.textContent).toBe("+15");
  });

  it("data is drawn without a request; theme and labels properties apply", async () => {
    const { client, queryGiftWalls } = fakeClient();
    html('<gift-wall user="a"></gift-wall>');
    const el = page.querySelector("gift-wall") as GiftWallElement;
    el.data = [rg("rose", 2500)];
    el.theme = { surface: "#112233" };
    el.labels = { thousand: " bin" };
    el.client = client;
    await settle(50);
    expect(queryGiftWalls).not.toHaveBeenCalled();
    expect(el.querySelector(".gs-chip")!.textContent).toBe("2.5 bin");
    expect(
      (el.querySelector(".gs-wall") as HTMLElement).style.getPropertyValue("--gs-surface"),
    ).toBe("#112233");
  });

  it("pressable makes chips buttons that fire a bubbling gift-chip-press", async () => {
    const { client } = fakeClient();
    html('<gift-wall user="a" pressable></gift-wall>');
    give("gift-wall", client);
    await settle(50);
    const heard = vi.fn();
    page.addEventListener("gift-chip-press", (e) => heard((e as CustomEvent).detail));
    page.querySelector<HTMLButtonElement>("button.gs-chip")!.click();
    expect(heard).toHaveBeenCalledWith(expect.objectContaining({ id: "rose" }));
  });

  it("without pressable the chips are plain", async () => {
    const { client } = fakeClient();
    html('<gift-wall user="a"></gift-wall>');
    give("gift-wall", client);
    await settle(50);
    expect(page.querySelectorAll("button")).toHaveLength(0);
  });

  it("refresh-key refetches; a failure is a bubbling gift-error and draws nothing", async () => {
    const { client, queryGiftWalls } = fakeClient();
    html('<gift-wall user="a" refresh-key="1"></gift-wall>');
    const el = page.querySelector("gift-wall") as GiftWallElement;
    el.client = client;
    await settle(50);
    el.setAttribute("refresh-key", "2");
    await settle(50);
    expect(queryGiftWalls).toHaveBeenCalledTimes(2);
    const errors = vi.fn();
    page.addEventListener("gift-error", (e) => errors((e as CustomEvent).detail));
    queryGiftWalls.mockRejectedValueOnce(new GiftingError(500, "x", "boom"));
    el.setAttribute("refresh-key", "3");
    await settle(50);
    expect(errors).toHaveBeenCalledOnce();
    expect(errors.mock.calls[0]![0]).toBeInstanceOf(GiftingError);
  });

  it("removing the element cleans up", async () => {
    const { client } = fakeClient();
    html('<gift-wall user="a"></gift-wall>');
    give("gift-wall", client);
    await settle(50);
    page.innerHTML = "";
    expect(document.head.querySelector("style[data-giftingstack]")).toBeNull();
  });
});

describe("<gift-away-summary>", () => {
  const screen = (attrs = "") => `
    <div id="screen" style="position: relative">
      <gift-effect-layer id="fx" remote-recipes="false"></gift-effect-layer>
      <gift-away-summary ${attrs}></gift-away-summary>
    </div>`;
  const el = () => page.querySelector("gift-away-summary") as GiftAwaySummaryElement;

  it("checks when it has a client, shows the card and replays in the first <gift-effect-layer>", async () => {
    const { client, getAway } = fakeClient();
    html(screen());
    const layer = page.querySelector("gift-effect-layer") as GiftEffectLayerElement;
    const play = vi.spyOn(layer.layer!, "play");
    el().client = client;
    await settle();
    expect(getAway).toHaveBeenCalledOnce();
    expect(el().querySelector("[data-gs-away-card]")).not.toBeNull();
    expect(play).toHaveBeenCalledOnce();
    expect((play.mock.calls[0]![0] as GiftEffectEvent).gift.id).toBe("rose");
  });

  it("effects selects a layer; effects=none means card only; player wins over both", async () => {
    const { client } = fakeClient();
    html(screen('effects="#fx"'));
    const layer = page.querySelector("gift-effect-layer") as GiftEffectLayerElement;
    const play = vi.spyOn(layer.layer!, "play");
    el().client = client;
    await settle();
    expect(play).toHaveBeenCalledOnce();

    html(screen('effects="none"'));
    const layer2 = page.querySelector("gift-effect-layer") as GiftEffectLayerElement;
    const play2 = vi.spyOn(layer2.layer!, "play");
    el().client = client;
    await settle();
    expect(play2).not.toHaveBeenCalled();
    expect(el().querySelector("[data-gs-away-card]")).not.toBeNull();

    html(screen());
    const mine = { play: vi.fn(() => 1) };
    el().player = mine;
    el().client = client;
    await settle();
    expect(mine.play).toHaveBeenCalledOnce();
  });

  it("auto-check=false waits for check(); ack-on=manual waits for ack()", async () => {
    const { client, getAway, ackAway } = fakeClient();
    html(screen('auto-check="false" ack-on="manual"'));
    el().client = client;
    await settle();
    expect(getAway).not.toHaveBeenCalled();
    await el().check();
    await settle();
    expect(getAway).toHaveBeenCalledOnce();
    expect(ackAway).not.toHaveBeenCalled();
    await el().ack();
    expect(ackAway).toHaveBeenCalledWith("aw1.abc");
  });

  it("fires bubbling gift-away-show and gift-away-done; dismiss() closes the card", async () => {
    const { client } = fakeClient();
    html(screen('effects="none"'));
    const shown = vi.fn();
    const done = vi.fn();
    page.addEventListener("gift-away-show", (e) => shown((e as CustomEvent).detail));
    page.addEventListener("gift-away-done", () => done());
    el().client = client;
    await settle();
    expect(shown).toHaveBeenCalledOnce();
    expect(shown.mock.calls[0]![0].total_gifts).toBe(4);
    el().dismiss();
    expect(done).toHaveBeenCalledOnce();
  });

  it("resolveUsers, labels and theme properties apply to the card", async () => {
    const { client } = fakeClient();
    html(screen('effects="none"'));
    el().resolveUsers = async (ids) =>
      Object.fromEntries(ids.map((id) => [id, { name: `@${id}` }]));
    el().labels = { awayTitle: "Yokken" };
    el().theme = { surface: "#102030" };
    el().client = client;
    await settle();
    expect(el().querySelector(".gs-away-title")!.textContent).toBe("Yokken");
    expect(el().querySelector(".gs-away-name")!.textContent).toBe("@ayla");
    expect(
      (el().querySelector(".gs-away") as HTMLElement).style.getPropertyValue("--gs-surface"),
    ).toBe("#102030");
  });

  it("a failed check is a bubbling gift-error", async () => {
    const { client, getAway } = fakeClient();
    getAway.mockRejectedValueOnce(new GiftingError(500, "x", "boom"));
    html(screen());
    const errors = vi.fn();
    page.addEventListener("gift-error", (e) => errors((e as CustomEvent).detail));
    el().client = client;
    await settle();
    expect(errors).toHaveBeenCalledOnce();
    expect(el().querySelector("[data-gs-away-card]")).toBeNull();
  });

  it("covers its positioned parent and lets clicks through (host style)", async () => {
    const { client } = fakeClient();
    html(screen());
    el().client = client;
    await settle();
    expect(document.head.querySelector("style[data-gs-elements]")!.textContent).toMatch(
      /:where\(gift-away-summary\) \{[^}]*position: absolute; inset: 0; pointer-events: none/,
    );
  });
});

describe("<gift-leaderboard>", () => {
  const el = () => page.querySelector("gift-leaderboard") as GiftLeaderboardElement;

  it("stays empty until it has a client, then loads the tab from the attributes", async () => {
    const { client, getLeaderboard } = fakeClient();
    html(
      '<gift-leaderboard board="receivers" limit="5" initial-period="month" coin-name="gems"></gift-leaderboard>',
    );
    await settle();
    expect(el().querySelector(".gs-board")).toBeNull();
    el().client = client;
    await settle();
    expect(getLeaderboard).toHaveBeenCalledWith("receivers", {
      period: "month",
      metric: "gifts",
      limit: 5,
    });
    expect(el().querySelectorAll(".gs-rows > li")).toHaveLength(2);
    expect(el().querySelector(".gs-rows > li")!.getAttribute("aria-label")).toBe(
      "Rank 1, ayla, 3 gifts",
    );
  });

  it("periods is a comma list; unknown names are ignored", async () => {
    const { client } = fakeClient();
    html('<gift-leaderboard periods="all, day, nope"></gift-leaderboard>');
    el().client = client;
    await settle();
    expect([...el().querySelectorAll('[role="tab"]')].map((t) => t.textContent)).toEqual([
      "All time",
      "Today",
    ]);
  });

  it("metric-toggle shows the switch; several attribute changes rebuild once", async () => {
    const { client, getLeaderboard } = fakeClient();
    html("<gift-leaderboard></gift-leaderboard>");
    el().client = client;
    await settle();
    getLeaderboard.mockClear();
    el().setAttribute("metric-toggle", "");
    el().setAttribute("limit", "3");
    el().setAttribute("metric", "gifts");
    await settle();
    expect(getLeaderboard).toHaveBeenCalledOnce();
    expect(el().querySelector(".gs-metric")).not.toBeNull();
  });

  it("pressable rows fire a bubbling gift-user-press with the id", async () => {
    const { client } = fakeClient();
    html("<gift-leaderboard pressable></gift-leaderboard>");
    el().client = client;
    await settle();
    const heard = vi.fn();
    page.addEventListener("gift-user-press", (e) => heard((e as CustomEvent).detail));
    el().querySelectorAll<HTMLButtonElement>(".gs-rows button")[1]!.click();
    expect(heard).toHaveBeenCalledWith("mert");
  });

  it("resolveUsers, labels and theme properties apply; refresh() asks again", async () => {
    const { client, getLeaderboard } = fakeClient();
    html("<gift-leaderboard></gift-leaderboard>");
    el().resolveUsers = async (ids) =>
      Object.fromEntries(ids.map((id) => [id, { name: id.toUpperCase() }]));
    el().labels = { tabs: { week: "Hafta" } };
    el().theme = { surface: "#445566" };
    el().client = client;
    await settle();
    expect(el().querySelector(".gs-row-name")!.textContent).toBe("AYLA");
    expect(el().querySelector('[role="tab"][aria-selected="true"]')!.textContent).toBe("Hafta");
    expect(
      (el().querySelector(".gs-board") as HTMLElement).style.getPropertyValue("--gs-surface"),
    ).toBe("#445566");
    el().refresh();
    expect(getLeaderboard).toHaveBeenCalledTimes(2);
  });

  it("a failed load is a bubbling gift-error and the board shows Try again", async () => {
    const { client, getLeaderboard } = fakeClient();
    getLeaderboard.mockRejectedValue(new GiftingError(500, "x", "boom"));
    html("<gift-leaderboard></gift-leaderboard>");
    const errors = vi.fn();
    page.addEventListener("gift-error", (e) => errors((e as CustomEvent).detail));
    el().client = client;
    await settle();
    expect(errors).toHaveBeenCalled();
    expect(el().querySelector(".gs-retry")).not.toBeNull();
  });

  it("removing the element stops polling and cleans up", async () => {
    const { client, getLeaderboard } = fakeClient();
    html('<gift-leaderboard refresh-interval-ms="1000"></gift-leaderboard>');
    el().client = client;
    await settle();
    page.innerHTML = "";
    await settle(10_000);
    expect(getLeaderboard).toHaveBeenCalledOnce();
    expect(document.head.querySelector("style[data-giftingstack]")).toBeNull();
  });
});

describe("elements: render hooks through the options property", () => {
  it("<gift-wall> options.renderChip draws the chip contents", async () => {
    const { client } = fakeClient();
    html('<gift-wall user="mert"></gift-wall>');
    const el = page.querySelector("gift-wall") as GiftWallElement;
    el.options = { renderChip: (c) => `${c.gift.id}=${c.count}` };
    el.client = client;
    await settle(50);
    const chips = [...el.querySelectorAll(".gs-chip")].map((c) => c.textContent);
    expect(chips.length).toBeGreaterThan(0);
    for (const t of chips) expect(t).toMatch(/^[a-z]+=\d+$/);
  });

  it("<gift-leaderboard> options.renderRow draws the row contents", async () => {
    const { client } = fakeClient();
    html("<gift-leaderboard></gift-leaderboard>");
    const el = page.querySelector("gift-leaderboard") as GiftLeaderboardElement;
    el.options = { renderRow: (r) => `#${r.rank} ${r.name}` };
    el.client = client;
    await settle();
    expect(el.querySelector(".gs-rows > li .gs-row-main")!.textContent).toBe("#1 ayla");
  });

  it("<gift-away-summary> options.renderSummary draws the card body, and dismiss works", async () => {
    const { client } = fakeClient();
    html('<div style="position: relative"><gift-away-summary></gift-away-summary></div>');
    const el = page.querySelector("gift-away-summary") as GiftAwaySummaryElement;
    el.options = {
      renderSummary: (c) => {
        const b = document.createElement("button");
        b.className = "mine";
        b.textContent = c.headline;
        b.onclick = c.dismiss;
        return b;
      },
    };
    el.client = client;
    await settle(100);
    const mine = el.querySelector<HTMLButtonElement>("[data-gs-away-card] .mine")!;
    expect(mine.textContent).toMatch(/gift/);
    expect(el.querySelector(".gs-away-title")).toBeNull();
    const done = vi.fn();
    el.addEventListener("gift-away-done", done);
    mine.click();
    expect(done).toHaveBeenCalledOnce();
  });
});
