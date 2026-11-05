import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type GiftingClient,
  GiftingError,
  type Leaderboard,
  type LeaderboardEntry,
  type LeaderboardMe,
  type LeaderboardQuery,
  RANK_COLORS,
} from "../src/core";
import {
  GiftLeaderboard,
  type GiftLeaderboardOptions,
  type LeaderboardRowContext,
} from "../src/web";
import { CSS } from "../src/web/styles";
import { componentCallStubs } from "./stub-client";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";

const entry = (
  rank: number,
  user: string,
  units: number,
  gifts = Math.ceil(units / 100),
): LeaderboardEntry => ({
  rank,
  user,
  units,
  gifts,
});
/** Ties at 2 and at 5; the next rank after a tie of two is 4 and 7. */
const ROWS = [
  entry(1, "ayla", 54_000, 120),
  entry(2, "mert", 41_000, 300),
  entry(2, "ece", 41_000, 80),
  entry(4, "can", 12_500, 40),
  entry(5, "deniz", 900, 9),
  entry(5, "elif", 900, 3),
  entry(7, "fatma", 20, 2),
];
const ME_OUTSIDE: LeaderboardMe = { user: "me", rank: 417, gifts: 3, units: 120, hidden: false };

function board(patch: Partial<Leaderboard> = {}, query: LeaderboardQuery = {}): Leaderboard {
  return {
    board: "senders",
    period: query.period ?? "week",
    metric: query.metric ?? "units",
    label: "2026-W41",
    starts_at: null,
    ends_at: null,
    as_of: "2026-10-11T07:30:02.511Z",
    data: ROWS,
    has_more: true,
    me: ME_OUTSIDE,
    ...patch,
  };
}

function fakeClient(
  answer: (b: string, q: LeaderboardQuery) => Leaderboard | Error = (_b, q) => board({}, q),
) {
  const getLeaderboard = vi.fn<GiftingClient["getLeaderboard"]>(async (b, q = {}) => {
    const r = answer(b, q);
    if (r instanceof Error) throw r;
    return { ...r, board: b };
  });
  const client: GiftingClient = {
    getGifts: async () => [],
    getMe: async () => ({ user: "me", balance: 0 }),
    getReceivedGifts: async () => [],
    sendGift: async () => {
      throw new Error("not used");
    },
    ...componentCallStubs,
    getLeaderboard,
  };
  return { client, getLeaderboard };
}

let env: ReturnType<typeof installWebEnv>;
let page: HTMLElement;
let boards: GiftLeaderboard[] = [];

beforeEach(() => {
  env = installWebEnv();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS, "setInterval", "clearInterval"] });
  page = document.createElement("div");
  document.body.appendChild(page);
});
afterEach(() => {
  for (const b of boards) b.destroy();
  boards = [];
  page.remove();
  vi.useRealTimers();
  env.restore();
});

const mk = (options: GiftLeaderboardOptions) => {
  const b = new GiftLeaderboard(page, options);
  boards.push(b);
  return b;
};
const advance = (ms: number) => vi.advanceTimersByTimeAsync(ms);
const $ = (sel: string) => page.querySelector(sel) as HTMLElement;
const $$ = (sel: string) => [...page.querySelectorAll<HTMLElement>(sel)];
const tabs = () => $$('[role="tab"]');
const rows = () => $$(".gs-rows > li");
const key = (el: Element, k: string) =>
  el.dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true, cancelable: true }));

describe("web GiftLeaderboard: states", () => {
  it("shows `limit` skeleton rows while loading, then the rows", async () => {
    const { client, getLeaderboard } = fakeClient();
    mk({ client, limit: 7 });
    expect($$(".gs-row-skeleton")).toHaveLength(7);
    expect($(".gs-rows").getAttribute("aria-label")).toBe("Loading");
    expect($$(".gs-row-skeleton").every((r) => r.getAttribute("aria-hidden") === "true")).toBe(
      true,
    );
    expect(getLeaderboard).toHaveBeenCalledWith("senders", {
      period: "week",
      metric: "units",
      limit: 7,
    });
    await advance(0);
    expect($$(".gs-row-skeleton")).toHaveLength(0);
    expect(rows()).toHaveLength(ROWS.length);
  });

  it("the default limit is 10 skeleton rows", () => {
    const { client } = fakeClient();
    mk({ client });
    expect($$(".gs-row-skeleton")).toHaveLength(10);
  });

  it("empty shows the text of the period", async () => {
    const { client } = fakeClient((_b, q) => board({ data: [], me: null }, q));
    mk({ client });
    await advance(0);
    expect($(".gs-board-empty").textContent).toBe("No gifts yet this week");
    tabs()[0]!.click();
    await advance(0);
    expect($(".gs-board-empty").textContent).toBe("No gifts yet today");
    tabs()[3]!.click();
    await advance(0);
    expect($(".gs-board-empty").textContent).toBe("No gifts yet");
  });

  it("empty texts and tab names can be translated", async () => {
    const { client } = fakeClient((_b, q) => board({ data: [], me: null }, q));
    mk({ client, labels: { empty: { week: "Bu hafta hediye yok" }, tabs: { week: "Hafta" } } });
    await advance(0);
    expect($(".gs-board-empty").textContent).toBe("Bu hafta hediye yok");
    expect(tabs().map((t) => t.textContent)).toEqual(["Today", "Hafta", "This month", "All time"]);
  });

  it("an error shows a message and a Try again button that asks again", async () => {
    let fail = true;
    const { client, getLeaderboard } = fakeClient((_b, q) =>
      fail ? new GiftingError(500, "x", "boom") : board({}, q),
    );
    const onError = vi.fn();
    mk({ client, onError });
    await advance(0);
    expect(onError).toHaveBeenCalledOnce();
    expect($(".gs-board-error").getAttribute("role")).toBe("alert");
    expect($(".gs-board-message").textContent).toBe("Could not load the leaderboard.");
    const retry = $(".gs-retry") as HTMLButtonElement;
    expect(retry.tagName).toBe("BUTTON");
    expect(retry.textContent).toBe("Try again");
    fail = false;
    const calls = getLeaderboard.mock.calls.length;
    retry.click();
    expect(getLeaderboard.mock.calls.length).toBe(calls + 1);
    expect($$(".gs-row-skeleton").length).toBeGreaterThan(0); // loading again
    await advance(0);
    expect($(".gs-board-error")).toBeNull();
    expect(rows()).toHaveLength(ROWS.length);
  });

  it("stale rows stay while a refresh runs, with a spinner in the header (none when idle)", async () => {
    let resolveSecond: (b: Leaderboard) => void = () => {};
    const { client, getLeaderboard } = fakeClient();
    mk({ client });
    await advance(0);
    expect(($(".gs-spin") as HTMLElement).hidden).toBe(true);
    getLeaderboard.mockImplementationOnce(() => new Promise((r) => (resolveSecond = r)));
    await advance(30_000);
    tabs()[0]!.click();
    tabs()[1]!.click(); // back to week: cached for 30 s, stale now: shown at once, fetched in the background
    expect(rows()).toHaveLength(ROWS.length);
    expect(($(".gs-spin") as HTMLElement).hidden).toBe(false);
    expect($(".gs-board-body").getAttribute("aria-busy")).toBe("true");
    resolveSecond(board());
    await advance(0);
    expect(($(".gs-spin") as HTMLElement).hidden).toBe(true);
    expect(CSS).toMatch(
      /@media \(prefers-reduced-motion: reduce\) \{ \.gs-spin \{ animation: none; \} \}/,
    );
  });

  it("refresh() asks again now and keeps the rows meanwhile", async () => {
    const { client, getLeaderboard } = fakeClient();
    const b = mk({ client });
    await advance(0);
    b.refresh();
    expect(getLeaderboard).toHaveBeenCalledTimes(2);
    expect(rows()).toHaveLength(ROWS.length);
  });

  it("refreshIntervalMs polls; 0 (default) does not; destroy stops it", async () => {
    const { client, getLeaderboard } = fakeClient();
    mk({ client });
    await advance(120_000);
    expect(getLeaderboard).toHaveBeenCalledTimes(1);
    const polled = fakeClient();
    const b = mk({ client: polled.client, refreshIntervalMs: 10_000 });
    await advance(35_000);
    expect(polled.getLeaderboard).toHaveBeenCalledTimes(4);
    b.destroy();
    await advance(60_000);
    expect(polled.getLeaderboard).toHaveBeenCalledTimes(4);
  });

  it("refreshIntervalMs has a floor of 5 s: 50 ms polls every 5 s, not 20 times a second", async () => {
    const { client, getLeaderboard } = fakeClient();
    mk({ client, refreshIntervalMs: 50 });
    await advance(4_900);
    expect(getLeaderboard).toHaveBeenCalledTimes(1);
    await advance(200);
    expect(getLeaderboard).toHaveBeenCalledTimes(2);
  });
});

describe("web GiftLeaderboard: tabs", () => {
  it("is a tablist of four tabs, week selected, with a tabpanel for the rows", async () => {
    const { client } = fakeClient();
    mk({ client });
    await advance(0);
    expect($('[role="tablist"]')).not.toBeNull();
    expect(tabs().map((t) => t.textContent)).toEqual([
      "Today",
      "This week",
      "This month",
      "All time",
    ]);
    expect(tabs().map((t) => t.getAttribute("aria-selected"))).toEqual([
      "false",
      "true",
      "false",
      "false",
    ]);
    expect(tabs().map((t) => t.tabIndex)).toEqual([-1, 0, -1, -1]);
    const panel = $('[role="tabpanel"]');
    expect(panel.getAttribute("aria-labelledby")).toBe(tabs()[1]!.id);
    expect(tabs()[1]!.getAttribute("aria-controls")).toBe(panel.id);
  });

  it("clicking a tab selects it and asks for that period; coming back uses the cache", async () => {
    const { client, getLeaderboard } = fakeClient();
    mk({ client });
    await advance(0);
    tabs()[2]!.click();
    expect(getLeaderboard).toHaveBeenLastCalledWith("senders", {
      period: "month",
      metric: "units",
      limit: 10,
    });
    await advance(0);
    expect(tabs()[2]!.getAttribute("aria-selected")).toBe("true");
    tabs()[1]!.click(); // week again, answered less than 30 s ago
    expect(rows()).toHaveLength(ROWS.length);
    expect(getLeaderboard).toHaveBeenCalledTimes(2);
  });

  it("update({ board }) drops the cache and shows the other board (default metric of that board)", async () => {
    const { client, getLeaderboard } = fakeClient((b, q) =>
      board({ data: b === "receivers" ? [entry(1, "zoe", 900, 30)] : ROWS }, q),
    );
    const lb = mk({ client });
    await advance(0);
    expect(rows()).toHaveLength(ROWS.length);
    lb.update({ board: "receivers" });
    await advance(0);
    expect(getLeaderboard).toHaveBeenLastCalledWith("receivers", {
      period: "week",
      metric: "gifts",
      limit: 10,
    });
    expect(rows()).toHaveLength(1);
    expect(rows()[0]!.textContent).toContain("zoe");
    lb.update({ board: "senders" });
    await advance(0);
    expect(rows()).toHaveLength(ROWS.length);
  });

  it("an answer for the old board that arrives late is ignored", async () => {
    let release: (v: Leaderboard) => void = () => {};
    const { client } = fakeClient((b, q) =>
      board({ data: b === "receivers" ? [entry(1, "zoe", 900, 30)] : ROWS }, q),
    );
    const slow = vi.fn<GiftingClient["getLeaderboard"]>((b, q = {}) =>
      b === "senders"
        ? new Promise<Leaderboard>((r) => (release = r))
        : client.getLeaderboard(b, q),
    );
    const lb = mk({ client: { ...client, getLeaderboard: slow } });
    await advance(0);
    lb.update({ board: "receivers" });
    await advance(0);
    release({ ...board({}, {}), data: ROWS }); // the senders answer comes after the switch
    await advance(0);
    expect(rows()).toHaveLength(1);
    expect(rows()[0]!.textContent).toContain("zoe");
  });

  it("a tab older than 30 s is shown at once and fetched again", async () => {
    const { client, getLeaderboard } = fakeClient();
    mk({ client });
    await advance(0);
    tabs()[0]!.click();
    await advance(29_999);
    tabs()[1]!.click();
    expect(getLeaderboard).toHaveBeenCalledTimes(2); // 29.999 s: still fresh
    await advance(1);
    tabs()[0]!.click(); // day: fetched 30 s ago
    expect(getLeaderboard).toHaveBeenCalledTimes(3);
    expect(rows()).toHaveLength(ROWS.length); // shown at once
  });

  it("arrow keys, Home and End move the selection and the focus (automatic activation, wraps)", async () => {
    const { client, getLeaderboard } = fakeClient();
    mk({ client, initialPeriod: "day" });
    await advance(0);
    tabs()[0]!.focus();
    key(tabs()[0]!, "ArrowRight");
    expect(tabs()[1]!.getAttribute("aria-selected")).toBe("true");
    expect(document.activeElement).toBe(tabs()[1]);
    expect(getLeaderboard).toHaveBeenLastCalledWith(
      "senders",
      expect.objectContaining({ period: "week" }),
    );
    key(tabs()[1]!, "End");
    expect(tabs()[3]!.getAttribute("aria-selected")).toBe("true");
    expect(document.activeElement).toBe(tabs()[3]);
    key(tabs()[3]!, "ArrowRight"); // wraps
    expect(tabs()[0]!.getAttribute("aria-selected")).toBe("true");
    key(tabs()[0]!, "ArrowLeft"); // wraps back
    expect(tabs()[3]!.getAttribute("aria-selected")).toBe("true");
    key(tabs()[3]!, "Home");
    expect(tabs()[0]!.getAttribute("aria-selected")).toBe("true");
    expect(document.activeElement).toBe(tabs()[0]);
    expect(tabs().map((t) => t.tabIndex)).toEqual([0, -1, -1, -1]);
  });

  it("other keys do nothing and are not swallowed", async () => {
    const { client } = fakeClient();
    mk({ client });
    await advance(0);
    const ev = new KeyboardEvent("keydown", { key: "a", bubbles: true, cancelable: true });
    tabs()[1]!.dispatchEvent(ev);
    expect(ev.defaultPrevented).toBe(false);
    expect(tabs()[1]!.getAttribute("aria-selected")).toBe("true");
  });

  it("keeps the keyboard focus on the tab when data arrives and the rows are redrawn", async () => {
    const { client } = fakeClient();
    mk({ client });
    tabs()[1]!.focus();
    await advance(0);
    expect(document.activeElement).toBe(tabs()[1]);
  });

  it("periods chooses the tabs and their order; initialPeriod picks one of them", async () => {
    const { client, getLeaderboard } = fakeClient();
    mk({ client, periods: ["all", "day"], initialPeriod: "day" });
    await advance(0);
    expect(tabs().map((t) => t.textContent)).toEqual(["All time", "Today"]);
    expect(tabs()[1]!.getAttribute("aria-selected")).toBe("true");
    expect(getLeaderboard).toHaveBeenCalledWith(
      "senders",
      expect.objectContaining({ period: "day" }),
    );
  });

  it("an initialPeriod that is not among the periods falls back to the first", async () => {
    const { client, getLeaderboard } = fakeClient();
    mk({ client, periods: ["month", "all"] });
    await advance(0);
    expect(getLeaderboard).toHaveBeenCalledWith(
      "senders",
      expect.objectContaining({ period: "month" }),
    );
  });

  it("one period: no tabs and no tabpanel", async () => {
    const { client } = fakeClient();
    mk({ client, periods: ["all"] });
    await advance(0);
    expect($('[role="tablist"]')).toBeNull();
    expect($('[role="tabpanel"]')).toBeNull();
    expect(rows()).toHaveLength(ROWS.length);
  });
});

describe("web GiftLeaderboard: metric", () => {
  it("has no switch by default; metricToggle shows one that changes the request and the scores", async () => {
    const { client, getLeaderboard } = fakeClient();
    mk({ client });
    await advance(0);
    expect($(".gs-metric")).toBeNull();
    boards.pop()!.destroy();
    mk({ client, metricToggle: true, coinName: "gems" });
    await advance(0);
    const btns = $$(".gs-metric-btn");
    expect(btns.map((b) => b.textContent)).toEqual(["Gems", "Gifts"]);
    expect(btns.map((b) => b.getAttribute("aria-pressed"))).toEqual(["true", "false"]);
    expect($(".gs-metric").getAttribute("role")).toBe("group");
    expect($(".gs-metric").getAttribute("aria-label")).toBe("Ranked by");
    expect(rows()[0]!.querySelector(".gs-score")!.textContent).toBe("54K");
    btns[1]!.click();
    expect(getLeaderboard).toHaveBeenLastCalledWith("senders", {
      period: "week",
      metric: "gifts",
      limit: 10,
    });
    await advance(0);
    expect($$(".gs-metric-btn").map((b) => b.getAttribute("aria-pressed"))).toEqual([
      "false",
      "true",
    ]);
    expect(rows()[0]!.querySelector(".gs-score")!.textContent).toBe("120gifts");
    expect(rows()[0]!.getAttribute("aria-label")).toBe("Rank 1, ayla, 120 gifts");
    expect(document.activeElement).toBe($$(".gs-metric-btn")[1]);
  });

  it("the receivers board shows gifts by default, the senders board coins", async () => {
    const { client, getLeaderboard } = fakeClient();
    mk({ client, board: "receivers" });
    await advance(0);
    expect(getLeaderboard).toHaveBeenCalledWith(
      "receivers",
      expect.objectContaining({ metric: "gifts" }),
    );
    expect(rows()[0]!.getAttribute("aria-label")).toBe("Rank 1, ayla, 120 gifts");
  });

  it("an explicit metric wins", async () => {
    const { client, getLeaderboard } = fakeClient();
    mk({ client, board: "receivers", metric: "units" });
    await advance(0);
    expect(getLeaderboard).toHaveBeenCalledWith(
      "receivers",
      expect.objectContaining({ metric: "units" }),
    );
  });

  it("update({ metric }) switches the tab", async () => {
    const { client, getLeaderboard } = fakeClient();
    const b = mk({ client });
    await advance(0);
    b.update({ metric: "gifts" });
    expect(getLeaderboard).toHaveBeenLastCalledWith(
      "senders",
      expect.objectContaining({ metric: "gifts" }),
    );
  });
});

describe("web GiftLeaderboard: rows", () => {
  it("each row says 'Rank 1, ayla, 54,000 coins' and is a list item of a list", async () => {
    const { client } = fakeClient();
    mk({ client });
    await advance(0);
    expect($(".gs-rows").tagName).toBe("OL");
    expect($(".gs-rows").getAttribute("role")).toBe("list");
    expect(rows()[0]!.getAttribute("aria-label")).toBe("Rank 1, ayla, 54,000 coins");
    expect(rows()[3]!.getAttribute("aria-label")).toBe("Rank 4, can, 12,500 coins");
    // What is drawn is not read twice.
    expect(rows()[0]!.querySelector(".gs-row-main")!.getAttribute("aria-hidden")).toBe("true");
    expect(rows()[0]!.querySelector(".gs-row-name")!.textContent).toBe("ayla");
  });

  it("coinName and giftsWord change the spoken score", async () => {
    const { client } = fakeClient();
    mk({ client, coinName: "gems" });
    await advance(0);
    expect(rows()[0]!.getAttribute("aria-label")).toBe("Rank 1, ayla, 54,000 gems");
  });

  it("ranks 1 to 3 sit on a medal disc, ties keep their rank, the rest are plain numbers", async () => {
    const { client } = fakeClient();
    mk({ client });
    await advance(0);
    const ranks = rows().map((r) => r.querySelector<HTMLElement>(".gs-rank")!);
    expect(ranks.map((r) => r.textContent)).toEqual(["1", "2", "2", "4", "5", "5", "7"]);
    expect(ranks.map((r) => r.dataset.gsMedal ?? null)).toEqual([
      "1",
      "2",
      "2",
      null,
      null,
      null,
      null,
    ]);
  });

  it("the medal colours are the RANK_COLORS, with the notice text on them", () => {
    expect(CSS).toContain(`--gs-rank1: ${RANK_COLORS.rank1}`);
    expect(CSS).toContain(`--gs-rank2: ${RANK_COLORS.rank2}`);
    expect(CSS).toContain(`--gs-rank3: ${RANK_COLORS.rank3}`);
    expect(CSS).toMatch(/\.gs-rank\[data-gs-medal\] \{ color: var\(--gs-notice-big-text\); \}/);
    expect(CSS).toMatch(/\.gs-row \{[^}]*height: 52px/);
  });

  it("a score is written short with a coin dot for coins, plain with 'gifts' for gifts", async () => {
    const { client } = fakeClient();
    mk({ client, metric: "gifts" });
    await advance(0);
    const score = rows()[1]!.querySelector(".gs-score")!;
    expect(score.querySelector(".gs-score-num")!.textContent).toBe("300");
    expect(score.querySelector(".gs-score-unit")!.textContent).toBe("gifts");
    expect(score.querySelector(".gs-dot")).toBeNull();
    boards.pop()!.destroy();
    mk({ client });
    await advance(0);
    const coins = rows()[3]!.querySelector(".gs-score")!;
    expect(coins.querySelector(".gs-score-num")!.textContent).toBe("12K");
    expect(coins.querySelector(".gs-dot")).not.toBeNull();
  });

  it("the highlighted row (the viewer) uses the selected background marker", async () => {
    const { client } = fakeClient((_b, q) =>
      board({ me: { user: "mert", rank: 2, gifts: 300, units: 41_000, hidden: false } }, q),
    );
    mk({ client });
    await advance(0);
    const marked = rows().filter((r) => r.hasAttribute("data-gs-me"));
    expect(marked).toHaveLength(1);
    expect(marked[0]!.querySelector(".gs-row-name")!.textContent).toBe("mert");
    expect(marked[0]!.getAttribute("aria-current")).toBe("true");
    expect(CSS).toMatch(/\.gs-row\[data-gs-me\] \{ background: var\(--gs-selected\); \}/);
  });

  it("highlightUser overrides the signed-in person", async () => {
    const { client } = fakeClient();
    mk({ client, highlightUser: "can" });
    await advance(0);
    const marked = rows().filter((r) => r.hasAttribute("data-gs-me"));
    expect(marked.map((r) => r.querySelector(".gs-row-name")!.textContent)).toEqual(["can"]);
  });

  it("with onPressUser each row is a button with the spoken label that passes the id", async () => {
    const { client } = fakeClient();
    const onPressUser = vi.fn();
    mk({ client, onPressUser });
    await advance(0);
    const btn = rows()[1]!.querySelector("button")!;
    expect(btn.type).toBe("button");
    expect(btn.getAttribute("aria-label")).toBe("Rank 2, mert, 41,000 coins");
    btn.click();
    expect(onPressUser).toHaveBeenCalledWith("mert");
    expect(rows()[1]!.hasAttribute("aria-label")).toBe(false);
  });

  it("without onPressUser there are no buttons in the rows", async () => {
    const { client } = fakeClient();
    mk({ client });
    await advance(0);
    expect($$(".gs-rows button")).toHaveLength(0);
  });

  it("a stale user id has no picture and draws its initial", async () => {
    const { client } = fakeClient();
    mk({ client });
    await advance(0);
    const letters = rows().map((r) => r.querySelector(".gs-avatar-letter")!.textContent);
    expect(letters).toEqual(["A", "M", "E", "C", "D", "E", "F"]);
  });
});

describe("web GiftLeaderboard: the viewer's own row", () => {
  it("pins 'You: #417' under the list when the viewer is outside the rows", async () => {
    const { client } = fakeClient();
    mk({ client });
    await advance(0);
    const pinned = $("[data-gs-pinned]");
    expect(pinned.textContent).toContain("You: #417");
    expect(pinned.getAttribute("aria-label")).toBe("Your rank: 417, 120 coins");
    expect(pinned.parentElement).toBe($(".gs-board-body"));
    expect(rows()).toHaveLength(ROWS.length);
  });

  it("pins 'You: 1,000+' when the exact rank is unknown", async () => {
    const { client } = fakeClient((_b, q) => board({ me: { ...ME_OUTSIDE, rank: null } }, q));
    mk({ client });
    await advance(0);
    expect($("[data-gs-pinned]").textContent).toContain("You: 1,000+");
    expect($("[data-gs-pinned]").getAttribute("aria-label")).toBe("Your rank: 1,000+, 120 coins");
  });

  it("pins when the rank is above the limit even if the list is long", async () => {
    const { client } = fakeClient((_b, q) => board({ me: { ...ME_OUTSIDE, rank: 8 } }, q));
    mk({ client, limit: 7 });
    await advance(0);
    expect($("[data-gs-pinned]").textContent).toContain("You: #8");
  });

  it("does not pin a viewer who is in the rows (that row is highlighted)", async () => {
    const { client } = fakeClient((_b, q) =>
      board({ me: { user: "can", rank: 4, gifts: 40, units: 12_500, hidden: false } }, q),
    );
    mk({ client });
    await advance(0);
    expect($("[data-gs-pinned]")).toBeNull();
  });

  it("does not pin a hidden viewer, or one without a score", async () => {
    const hidden = fakeClient((_b, q) => board({ me: { ...ME_OUTSIDE, hidden: true } }, q));
    mk({ client: hidden.client });
    await advance(0);
    expect($("[data-gs-pinned]")).toBeNull();
    boards.pop()!.destroy();
    const zero = fakeClient((_b, q) =>
      board({ me: { ...ME_OUTSIDE, rank: null, units: 0, gifts: 0 } }, q),
    );
    mk({ client: zero.client });
    await advance(0);
    expect($("[data-gs-pinned]")).toBeNull();
  });

  it("pins by the gifts score on the gifts metric, and speaks it", async () => {
    const { client } = fakeClient();
    mk({ client, metric: "gifts" });
    await advance(0);
    expect($("[data-gs-pinned]").getAttribute("aria-label")).toBe("Your rank: 417, 3 gifts");
  });

  it("the pinned wording can be translated", async () => {
    const { client } = fakeClient();
    mk({ client, labels: { pinned: "Sen: {rank}", pinnedSpoken: "Sıran {rank}, {score}" } });
    await advance(0);
    expect($("[data-gs-pinned]").textContent).toContain("Sen: #417");
    expect($("[data-gs-pinned]").getAttribute("aria-label")).toBe("Sıran 417, 120 coins");
  });
});

describe("web GiftLeaderboard: names (resolveUsers)", () => {
  it("shows names and pictures from resolveUsers, asked once for the rows", async () => {
    const { client } = fakeClient();
    const resolveUsers = vi.fn(async (ids: string[]) =>
      Object.fromEntries(
        ids.map((id) => [
          id,
          {
            name: id.toUpperCase(),
            avatarUrl: id === "ayla" ? "https://img.test/a.png" : undefined,
          },
        ]),
      ),
    );
    mk({ client, resolveUsers });
    await advance(0);
    expect(resolveUsers).toHaveBeenCalledOnce();
    // The rows, then the viewer (whose own row is pinned).
    expect(resolveUsers.mock.calls[0]![0]).toEqual([...ROWS.map((r) => r.user), "me"]);
    expect(rows()[0]!.querySelector(".gs-row-name")!.textContent).toBe("AYLA");
    expect(rows()[0]!.getAttribute("aria-label")).toBe("Rank 1, AYLA, 54,000 coins");
    expect(rows()[0]!.querySelector("img")!.getAttribute("src")).toBe("https://img.test/a.png");
    expect(rows()[1]!.querySelector("img")).toBeNull();
  });

  it("rows wait (as skeletons) for the names instead of flashing raw ids", async () => {
    const { client } = fakeClient();
    let finish: (v: Record<string, { name: string }>) => void = () => {};
    mk({ client, resolveUsers: () => new Promise((r) => (finish = r)) });
    await advance(0);
    expect(rows()).toHaveLength(0);
    expect($$(".gs-row-skeleton").length).toBeGreaterThan(0);
    finish({ ayla: { name: "Ayla" } });
    await advance(0);
    expect(rows()).toHaveLength(ROWS.length);
    expect(rows()[0]!.querySelector(".gs-row-name")!.textContent).toBe("Ayla");
    expect(rows()[1]!.querySelector(".gs-row-name")!.textContent).toBe("mert"); // missed: the id
  });

  it("gives up after 2 s and shows the ids", async () => {
    const { client } = fakeClient();
    mk({ client, resolveUsers: () => new Promise(() => {}) });
    await advance(1_900);
    expect(rows()).toHaveLength(0);
    await advance(200);
    expect(rows()).toHaveLength(ROWS.length);
    expect(rows()[0]!.querySelector(".gs-row-name")!.textContent).toBe("ayla");
  });

  it("a failing resolveUsers shows the ids and reports once", async () => {
    const { client } = fakeClient();
    const onError = vi.fn();
    mk({ client, resolveUsers: async () => Promise.reject(new Error("x")), onError });
    await advance(0);
    expect(rows()).toHaveLength(ROWS.length);
    expect(onError).toHaveBeenCalledOnce();
  });

  it("known names are not asked for again when the board is fetched again", async () => {
    const { client } = fakeClient();
    const resolveUsers = vi.fn(async (ids: string[]) =>
      Object.fromEntries(ids.map((id) => [id, { name: id }])),
    );
    const b = mk({ client, resolveUsers });
    await advance(0);
    b.refresh();
    await advance(0);
    expect(resolveUsers).toHaveBeenCalledOnce();
  });
});

describe("web GiftLeaderboard: options and clean up", () => {
  it("theme sets the CSS variables on the root", () => {
    const { client } = fakeClient();
    const b = mk({ client, theme: { surface: "#ffffff", accent: "#6a54e8", selected: "#e6e1ff" } });
    expect(b.element.style.getPropertyValue("--gs-surface")).toBe("#ffffff");
    expect(b.element.style.getPropertyValue("--gs-selected")).toBe("#e6e1ff");
    b.update({ theme: { surface: "#000000" } });
    expect(b.element.style.getPropertyValue("--gs-surface")).toBe("#000000");
    expect(b.element.style.getPropertyValue("--gs-selected")).toBe("");
  });

  it("limit goes into the request, and the SDK's images are protected from page CSS", () => {
    const { client, getLeaderboard } = fakeClient();
    mk({ client, limit: 25 });
    expect(getLeaderboard).toHaveBeenCalledWith("senders", expect.objectContaining({ limit: 25 }));
    expect(CSS).toMatch(/\.gs-board img[^{]*\{\s*position: static !important/);
  });

  it("destroy removes the board and the style sheet; late answers change nothing", async () => {
    const { client } = fakeClient();
    const b = mk({ client });
    b.destroy();
    await advance(0);
    expect(page.querySelector(".gs-board")).toBeNull();
    expect(document.head.querySelector("style[data-giftingstack]")).toBeNull();
  });
});

describe("web GiftLeaderboard: renderRow", () => {
  it("is called per ranked row with the entry, the name, the score of the metric and isMe", async () => {
    const { client } = fakeClient();
    const renderRow = vi.fn((r: LeaderboardRowContext) => `${r.rank}|${r.name}|${r.scoreText}`);
    mk({
      client,
      renderRow,
      highlightUser: "mert",
      resolveUsers: async (ids) =>
        Object.fromEntries(ids.map((id) => [id, { name: id.toUpperCase() }])),
    });
    await advance(0);
    expect(renderRow).toHaveBeenCalledTimes(ROWS.length); // the pinned row is not passed
    const first = renderRow.mock.calls[0]![0];
    expect(first).toMatchObject({
      rank: 1,
      name: "AYLA",
      avatarUrl: null,
      metric: "units",
      score: 54_000,
      scoreText: "54K",
      isMe: false,
    });
    expect(first.entry).toEqual(ROWS[0]);
    expect(first.doc).toBe(document);
    expect(renderRow.mock.calls[1]![0].isMe).toBe(true);
    expect(rows()[0]!.querySelector(".gs-row-main")!.textContent).toBe("1|AYLA|54K");
    expect(rows()[6]!.querySelector(".gs-row-main")!.textContent).toBe("7|FATMA|20");
  });

  it("uses the gifts as the score for the gifts metric", async () => {
    const { client } = fakeClient();
    const renderRow = vi.fn((_r: LeaderboardRowContext) => "x");
    mk({ client, renderRow, metric: "gifts" });
    await advance(0);
    expect(renderRow.mock.calls[0]![0]).toMatchObject({ metric: "gifts", score: 120 });
  });

  it("the row keeps its element, label, highlight and press; a node is what is shown", async () => {
    const { client } = fakeClient();
    const onPressUser = vi.fn();
    mk({
      client,
      onPressUser,
      highlightUser: "ayla",
      renderRow: (r) => {
        const s = document.createElement("strong");
        s.textContent = `#${r.rank} ${r.name}`;
        return s;
      },
    });
    await advance(0);
    const row = rows()[0]!;
    const main = row.querySelector<HTMLButtonElement>(".gs-row-main")!;
    expect(main.tagName).toBe("BUTTON");
    expect(main.getAttribute("aria-label")).toBe("Rank 1, ayla, 54,000 coins");
    expect(main.querySelector("strong")!.textContent).toBe("#1 ayla");
    expect(main.querySelector(".gs-rank")).toBeNull();
    expect(row.hasAttribute("data-gs-me")).toBe(true);
    main.click();
    expect(onPressUser).toHaveBeenCalledWith("ayla");
    // The pinned row is still the default.
    expect($(".gs-pinned").textContent).toContain("You: #417");
  });

  it("without a press the drawn row stays hidden from a screen reader behind the row label", async () => {
    const { client } = fakeClient();
    mk({ client, renderRow: () => "custom" });
    await advance(0);
    const row = rows()[0]!;
    expect(row.getAttribute("aria-label")).toBe("Rank 1, ayla, 54,000 coins");
    expect(row.querySelector(".gs-row-main")!.getAttribute("aria-hidden")).toBe("true");
  });

  it("nothing (or a throw) draws the default row; a throw goes to onError", async () => {
    const { client } = fakeClient();
    const onError = vi.fn();
    mk({
      client,
      onError,
      renderRow: (r) => {
        if (r.rank === 1) throw new Error("broken");
        return null;
      },
    });
    await advance(0);
    expect(rows()[0]!.querySelector(".gs-rank")!.textContent).toBe("1");
    expect(rows()[3]!.querySelector(".gs-row-name")!.textContent).toBe("can");
    expect(onError).toHaveBeenCalled();
  });

  it("update() adds or removes it without a new request", async () => {
    const { client, getLeaderboard } = fakeClient();
    const b = mk({ client });
    await advance(0);
    const calls = getLeaderboard.mock.calls.length;
    b.update({ renderRow: () => "mine" });
    expect(rows()[0]!.querySelector(".gs-row-main")!.textContent).toBe("mine");
    b.update({ renderRow: undefined });
    expect(rows()[0]!.querySelector(".gs-rank")).not.toBeNull();
    expect(getLeaderboard.mock.calls.length).toBe(calls);
  });
});
