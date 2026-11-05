import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { createRef } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type GiftingClient,
  GiftingError,
  type Leaderboard,
  type LeaderboardBoard,
  type LeaderboardQuery,
  RANK_COLORS,
  defaultTheme,
} from "../src/core";
import { Text } from "react-native";
import {
  GiftLeaderboard,
  type GiftLeaderboardHandle,
  type LeaderboardRowInfo,
} from "../src/react-native";
import { installPhoneLayout } from "./setup";
import { componentCallStubs } from "./stub-client";

const row = (rank: number, user: string, units: number, gifts = units / 100) => ({
  rank,
  user,
  gifts,
  units,
});

const ROWS = [
  row(1, "ayla", 54_000, 120),
  row(2, "mert", 41_000, 300),
  row(2, "ece", 41_000, 80),
  row(4, "can", 900, 9),
];

const board = (over: Partial<Leaderboard> = {}): Leaderboard => ({
  board: "senders",
  period: "week",
  metric: "units",
  label: "2026-W41",
  starts_at: "2026-10-05T00:00:00.000Z",
  ends_at: "2026-10-12T00:00:00.000Z",
  as_of: "2026-10-11T07:30:02.511Z",
  data: ROWS,
  has_more: false,
  me: { user: "me", rank: null, gifts: 0, units: 0, hidden: false },
  ...over,
});

type Get = (b: LeaderboardBoard, q: LeaderboardQuery) => Promise<Leaderboard>;
function clientWith(get: Get): GiftingClient & { get: ReturnType<typeof vi.fn> } {
  const g = vi.fn(get);
  return { ...(componentCallStubs as object), getLeaderboard: g, get: g } as never;
}
/** Answers with the asked period and metric filled in. */
const echo =
  (over: Partial<Leaderboard> | ((q: LeaderboardQuery) => Partial<Leaderboard>) = {}): Get =>
  async (b, q) =>
    board({
      board: b,
      period: q.period ?? "week",
      metric: q.metric ?? "units",
      ...(typeof over === "function" ? over(q) : over),
    });

let restoreLayout = () => {};
beforeEach(() => {
  restoreLayout = installPhoneLayout();
  vi.useFakeTimers({
    toFake: [
      "setTimeout",
      "clearTimeout",
      "setInterval",
      "clearInterval",
      "requestAnimationFrame",
      "cancelAnimationFrame",
      "performance",
      "Date",
    ],
  });
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
  restoreLayout();
});
async function advance(ms: number) {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(ms);
  });
}
async function open(ui: React.ReactElement) {
  const r = render(ui);
  await advance(0);
  return r;
}
const bg = (el: HTMLElement) => getComputedStyle(el).backgroundColor;
/** `#e8a93a` as jsdom writes it. */
const rgb = (hex: string) =>
  `rgb(${[1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)).join(", ")})`;

describe("GiftLeaderboard: rows", () => {
  it("shows `limit` skeleton rows while loading, then the rows", async () => {
    let release!: (b: Leaderboard) => void;
    const client = clientWith(() => new Promise((r) => (release = r)));
    render(<GiftLeaderboard client={client} limit={7} />);
    expect(screen.getAllByTestId("gift-lb-skeleton-row")).toHaveLength(7);
    expect(client.get).toHaveBeenCalledTimes(1);
    await act(async () => release(board()));
    expect(screen.queryByTestId("gift-lb-skeleton-row")).toBeNull();
    expect(screen.getByTestId("gift-lb-list")).toBeTruthy();
  });

  it("asks for the board with the default tab week, units, the limit and me", async () => {
    const client = clientWith(echo());
    await open(<GiftLeaderboard client={client} limit={15} board="receivers" metric="units" />);
    expect(client.get).toHaveBeenCalledWith("receivers", {
      period: "week",
      metric: "units",
      limit: 15,
    });
  });

  it("labels each row for a screen reader and keeps tied ranks", async () => {
    await open(<GiftLeaderboard client={clientWith(echo())} />);
    expect(screen.getByLabelText("Rank 1, ayla, 54,000 coins")).toBeTruthy();
    expect(screen.getByLabelText("Rank 2, mert, 41,000 coins")).toBeTruthy();
    expect(screen.getByLabelText("Rank 2, ece, 41,000 coins")).toBeTruthy();
    expect(screen.getByLabelText("Rank 4, can, 900 coins")).toBeTruthy();
    expect(screen.getByTestId("gift-lb-list").getAttribute("role")).toBe("list");
  });

  it("writes scores short for units and as a plain number for gifts", async () => {
    const client = clientWith(echo());
    await open(<GiftLeaderboard client={client} />);
    expect(screen.getByTestId("gift-lb-row-ayla").textContent).toContain("54K");
    cleanup();
    await open(<GiftLeaderboard client={clientWith(echo())} metric="gifts" />);
    expect(screen.getByTestId("gift-lb-row-mert").textContent).toContain("300");
    expect(screen.getByTestId("gift-lb-row-mert").textContent).toContain("gifts");
    expect(screen.getByLabelText("Rank 2, mert, 300 gifts")).toBeTruthy();
  });

  it("puts ranks 1 to 3 on medal discs with the spec colours and the dark notice text", async () => {
    await open(<GiftLeaderboard client={clientWith(echo())} />);
    expect(bg(screen.getByTestId("gift-lb-medal-1"))).toBe(rgb(RANK_COLORS.rank1));
    expect(bg(screen.getAllByTestId("gift-lb-medal-2")[0]!)).toBe(rgb(RANK_COLORS.rank2));
    // Two people share rank 2: both rows get the silver disc.
    expect(screen.getAllByTestId("gift-lb-medal-2")).toHaveLength(2);
    expect(screen.queryByTestId("gift-lb-medal-4")).toBeNull();
    const one = within(screen.getByTestId("gift-lb-medal-1")).getByText("1");
    expect(getComputedStyle(one).color).toBe(rgb(defaultTheme.noticeBigText));
    expect(RANK_COLORS.rank3).toBe("#c07a45");
  });

  it("shows initials avatars", async () => {
    await open(<GiftLeaderboard client={clientWith(echo())} />);
    const ayla = screen.getByTestId("gift-lb-row-ayla");
    expect(within(ayla).getByTestId("gift-avatar").textContent).toBe("A");
  });

  it("uses names and pictures from resolveUsers, once per id", async () => {
    const resolveUsers = vi.fn(async (ids: string[]) =>
      Object.fromEntries(
        ids
          .filter((i) => i !== "can")
          .map((i) => [
            i,
            { name: i.toUpperCase(), avatarUrl: i === "ayla" ? "https://a.test/ayla.png" : null },
          ]),
      ),
    );
    await open(<GiftLeaderboard client={clientWith(echo())} resolveUsers={resolveUsers} />);
    expect(resolveUsers).toHaveBeenCalledTimes(1);
    expect(resolveUsers.mock.calls[0]![0]).toEqual(["ayla", "mert", "ece", "can"]);
    expect(screen.getByLabelText("Rank 1, AYLA, 54,000 coins")).toBeTruthy();
    // An id it did not answer keeps its id.
    expect(screen.getByLabelText("Rank 4, can, 900 coins")).toBeTruthy();
    expect(
      within(screen.getByTestId("gift-lb-row-ayla")).getByTestId("gift-avatar-image"),
    ).toBeTruthy();
  });

  it("highlights the viewer's row (me) with the selected colour, or highlightUser", async () => {
    const withMe = echo({
      me: { user: "mert", rank: 2, gifts: 300, units: 41_000, hidden: false },
    });
    const { unmount } = await open(<GiftLeaderboard client={clientWith(withMe)} />);
    expect(bg(screen.getByTestId("gift-lb-row-mert"))).toBe(rgb(defaultTheme.selected));
    expect(bg(screen.getByTestId("gift-lb-row-ayla"))).not.toBe(rgb(defaultTheme.selected));
    unmount();
    await open(<GiftLeaderboard client={clientWith(withMe)} highlightUser="ece" />);
    expect(bg(screen.getByTestId("gift-lb-row-ece"))).toBe(rgb(defaultTheme.selected));
    expect(bg(screen.getByTestId("gift-lb-row-mert"))).not.toBe(rgb(defaultTheme.selected));
  });

  it("makes rows buttons only with onPressUser", async () => {
    const onPressUser = vi.fn();
    const { unmount } = await open(<GiftLeaderboard client={clientWith(echo())} />);
    expect(screen.queryAllByRole("button")).toHaveLength(0);
    unmount();
    await open(<GiftLeaderboard client={clientWith(echo())} onPressUser={onPressUser} />);
    fireEvent.click(screen.getByLabelText("Rank 4, can, 900 coins"));
    expect(onPressUser).toHaveBeenCalledWith("can");
  });

  it("uses coinName and translated labels in the spoken rows", async () => {
    await open(
      <GiftLeaderboard
        client={clientWith(echo())}
        coinName="gems"
        labels={{ rowSpoken: "{rank}. sira, {name}, {score}" }}
      />,
    );
    expect(screen.getByLabelText("1. sira, ayla, 54,000 gems")).toBeTruthy();
  });
});

describe("GiftLeaderboard: the viewer's own row", () => {
  const me = (rank: number | null, units = 120, over = {}) => ({
    user: "me",
    rank,
    gifts: 3,
    units,
    hidden: false,
    ...over,
  });

  it("pins 'You: #417' under the list when the viewer is outside the rows", async () => {
    await open(<GiftLeaderboard client={clientWith(echo({ me: me(417) }))} />);
    const pinned = screen.getByTestId("gift-lb-pinned");
    expect(pinned.textContent).toContain("You: #417");
    expect(pinned.getAttribute("aria-label")).toBe("Your rank: 417, 120 coins");
    expect(bg(pinned)).toBe(rgb(defaultTheme.selected));
  });

  it("pins 'You: 1,000+' when the rank is unknown", async () => {
    await open(<GiftLeaderboard client={clientWith(echo({ me: me(null) }))} />);
    expect(screen.getByTestId("gift-lb-pinned").textContent).toContain("You: 1,000+");
    expect(screen.getByLabelText("Your rank: 1,000+, 120 coins")).toBeTruthy();
  });

  it("does not pin a viewer who is in the list, hidden, or without a score", async () => {
    for (const m of [
      me(2, 41_000, { user: "mert" }),
      me(417, 120, { hidden: true }),
      me(417, 0),
      null,
    ]) {
      const { unmount } = await open(<GiftLeaderboard client={clientWith(echo({ me: m }))} />);
      expect(screen.queryByTestId("gift-lb-pinned")).toBeNull();
      unmount();
    }
  });

  it("scores the pinned row on the shown metric", async () => {
    await open(
      <GiftLeaderboard
        client={clientWith(echo({ me: me(417) }))}
        metric="gifts"
        labels={{ giftsWord: "gifts" }}
      />,
    );
    expect(screen.getByLabelText("Your rank: 417, 3 gifts")).toBeTruthy();
  });
});

describe("GiftLeaderboard: tabs and the metric switch", () => {
  it("draws a tablist with week selected, and no tabs for a single period", async () => {
    const { unmount } = await open(<GiftLeaderboard client={clientWith(echo())} />);
    const tabs = screen.getAllByRole("tab");
    expect(tabs.map((t) => t.getAttribute("aria-label"))).toEqual([
      "Today",
      "This week",
      "This month",
      "All time",
    ]);
    expect(screen.getByTestId("gift-lb-tabs").getAttribute("role")).toBe("tablist");
    expect(tabs.map((t) => t.getAttribute("aria-selected"))).toEqual([
      "false",
      "true",
      "false",
      "false",
    ]);
    unmount();
    await open(<GiftLeaderboard client={clientWith(echo())} periods={["month"]} />);
    expect(screen.queryAllByRole("tab")).toHaveLength(0);
    expect(screen.queryByTestId("gift-lb-tabs")).toBeNull();
  });

  it("honours periods order and initialPeriod", async () => {
    const client = clientWith(echo());
    await open(<GiftLeaderboard client={client} periods={["all", "day"]} initialPeriod="day" />);
    expect(screen.getAllByRole("tab").map((t) => t.getAttribute("aria-label"))).toEqual([
      "All time",
      "Today",
    ]);
    expect(client.get).toHaveBeenCalledWith("senders", {
      period: "day",
      metric: "units",
      limit: 10,
    });
  });

  it("switches tab: asks for the period, selects it, and shows the cached tab at once on return", async () => {
    const client = clientWith(echo((q) => ({ data: [row(1, `top-${q.period}`, 10)] })));
    await open(<GiftLeaderboard client={client} />);
    expect(screen.getByTestId("gift-lb-row-top-week")).toBeTruthy();
    fireEvent.click(screen.getByLabelText("This month"));
    // Not cached yet: skeleton rows until the answer.
    expect(screen.getAllByTestId("gift-lb-skeleton-row").length).toBeGreaterThan(0);
    await advance(0);
    expect(client.get).toHaveBeenLastCalledWith("senders", {
      period: "month",
      metric: "units",
      limit: 10,
    });
    expect(screen.getByTestId("gift-lb-row-top-month")).toBeTruthy();
    expect(screen.getByLabelText("This month").getAttribute("aria-selected")).toBe("true");
    expect(screen.getByLabelText("This week").getAttribute("aria-selected")).toBe("false");
    fireEvent.click(screen.getByLabelText("This week"));
    // Straight from the cache (younger than 30 s): no skeleton, no new request.
    expect(screen.getByTestId("gift-lb-row-top-week")).toBeTruthy();
    expect(client.get).toHaveBeenCalledTimes(2);
  });

  it("shows a cached tab older than 30 s at once and refreshes it in the background", async () => {
    let n = 0;
    const client = clientWith(echo(() => ({ data: [row(1, `v${++n}`, 10)] })));
    await open(<GiftLeaderboard client={client} reducedMotion={false} />);
    fireEvent.click(screen.getByLabelText("Today"));
    await advance(0);
    await advance(31_000);
    fireEvent.click(screen.getByLabelText("This week"));
    // Old rows stay visible while the request runs, with the small spinner.
    expect(screen.getByTestId("gift-lb-row-v1")).toBeTruthy();
    expect(screen.getByTestId("gift-lb-spinner")).toBeTruthy();
    await advance(0);
    expect(screen.getByTestId("gift-lb-row-v3")).toBeTruthy();
    expect(screen.queryByTestId("gift-lb-spinner")).toBeNull();
  });

  it("has no spinner under reduced motion, rows still stay visible", async () => {
    const client = clientWith(echo());
    const ref = createRef<GiftLeaderboardHandle>();
    await open(<GiftLeaderboard ref={ref} client={client} reducedMotion />);
    let release!: (b: Leaderboard) => void;
    client.get.mockImplementationOnce(() => new Promise((r) => (release = r)));
    act(() => ref.current!.refresh());
    expect(screen.queryByTestId("gift-lb-spinner")).toBeNull();
    expect(screen.getByTestId("gift-lb-list")).toBeTruthy();
    await act(async () => release(board()));
  });

  it("switches between coins and gifts with metricToggle", async () => {
    const client = clientWith(echo());
    await open(<GiftLeaderboard client={client} metricToggle coinName="gems" />);
    const group = screen.getByTestId("gift-lb-metric");
    expect(group.getAttribute("role")).toBe("radiogroup");
    expect(within(group).getByLabelText("Gems").getAttribute("aria-checked")).toBe("true");
    fireEvent.click(within(group).getByLabelText("Gifts"));
    await advance(0);
    expect(client.get).toHaveBeenLastCalledWith("senders", {
      period: "week",
      metric: "gifts",
      limit: 10,
    });
    expect(within(group).getByLabelText("Gifts").getAttribute("aria-checked")).toBe("true");
    expect(screen.getByLabelText("Rank 2, mert, 300 gifts")).toBeTruthy();
  });

  it("has no metric switch by default", async () => {
    await open(<GiftLeaderboard client={clientWith(echo())} />);
    expect(screen.queryByTestId("gift-lb-metric")).toBeNull();
  });

  it("receivers start on gifts", async () => {
    const client = clientWith(echo());
    await open(<GiftLeaderboard client={client} board="receivers" />);
    expect(client.get).toHaveBeenCalledWith("receivers", {
      period: "week",
      metric: "gifts",
      limit: 10,
    });
  });
});

describe("GiftLeaderboard: empty, error, polling", () => {
  it("says what is missing for the period", async () => {
    const client = clientWith(echo({ data: [], me: null }));
    await open(<GiftLeaderboard client={client} />);
    expect(screen.getByText("No gifts yet this week")).toBeTruthy();
    fireEvent.click(screen.getByLabelText("Today"));
    await advance(0);
    expect(screen.getByText("No gifts yet today")).toBeTruthy();
    fireEvent.click(screen.getByLabelText("All time"));
    await advance(0);
    expect(screen.getByText("No gifts yet")).toBeTruthy();
  });

  it("translates the empty text", async () => {
    await open(
      <GiftLeaderboard
        client={clientWith(echo({ data: [] }))}
        labels={{ empty: { week: "Bos" } }}
      />,
    );
    expect(screen.getByText("Bos")).toBeTruthy();
  });

  it("shows an inline message and Try again, which asks again", async () => {
    const onError = vi.fn();
    let fail = true;
    const client = clientWith(async (b, q) => {
      if (fail) throw new GiftingError(503, "leaderboard_building", "building");
      return echo()(b, q);
    });
    await open(<GiftLeaderboard client={client} onError={onError} />);
    expect(screen.getByText("Could not load the leaderboard.")).toBeTruthy();
    expect(onError).toHaveBeenCalledTimes(1);
    expect(screen.queryByTestId("gift-lb-skeleton-row")).toBeNull();
    // The tabs stay usable.
    expect(screen.getAllByRole("tab")).toHaveLength(4);
    fail = false;
    fireEvent.click(screen.getByText("Try again"));
    await advance(0);
    expect(client.get).toHaveBeenCalledTimes(2);
    expect(screen.queryByTestId("gift-lb-error")).toBeNull();
    expect(screen.getByLabelText("Rank 1, ayla, 54,000 coins")).toBeTruthy();
  });

  it("keeps the rows when a background refresh fails", async () => {
    const client = clientWith(echo());
    const ref = createRef<GiftLeaderboardHandle>();
    await open(<GiftLeaderboard ref={ref} client={client} />);
    client.get.mockRejectedValueOnce(new GiftingError(500, "server_error", "x"));
    await act(async () => ref.current!.refresh());
    await advance(0);
    expect(screen.queryByTestId("gift-lb-error")).toBeNull();
    expect(screen.getByTestId("gift-lb-list")).toBeTruthy();
  });

  it("does not poll by default, and polls every refreshIntervalMs when set", async () => {
    const client = clientWith(echo());
    const { unmount } = await open(<GiftLeaderboard client={client} />);
    await advance(120_000);
    expect(client.get).toHaveBeenCalledTimes(1);
    unmount();
    const polled = clientWith(echo());
    await open(<GiftLeaderboard client={polled} refreshIntervalMs={10_000} />);
    await advance(35_000);
    expect(polled.get).toHaveBeenCalledTimes(4);
  });

  it("makes no pulse under reduced motion, and a pulse otherwise", async () => {
    const never = () => new Promise<Leaderboard>(() => {});
    const calm = render(<GiftLeaderboard client={clientWith(never)} reducedMotion />);
    await advance(0);
    const idle = vi.getTimerCount();
    await advance(500);
    expect(vi.getTimerCount()).toBe(idle);
    calm.unmount();
    render(<GiftLeaderboard client={clientWith(never)} reducedMotion={false} />);
    await advance(100);
    // The loop keeps asking for frames.
    expect(vi.getTimerCount()).toBeGreaterThan(idle);
  });

  it("does not update after it was unmounted", async () => {
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    let release!: (b: Leaderboard) => void;
    const client = clientWith(() => new Promise((r) => (release = r)));
    const { unmount } = render(<GiftLeaderboard client={client} />);
    unmount();
    await act(async () => release(board()));
    expect(errors).not.toHaveBeenCalled();
    errors.mockRestore();
  });
});

describe("GiftLeaderboard: renderRow", () => {
  it("is called per ranked row with the entry, name, score of the metric, isMe and the theme", async () => {
    const renderRow = vi.fn((r: LeaderboardRowInfo) => (
      <Text>{`${r.rank}|${r.name}|${r.scoreText}`}</Text>
    ));
    await open(
      <GiftLeaderboard
        client={clientWith(echo())}
        renderRow={renderRow}
        highlightUser="mert"
        resolveUsers={async (ids) =>
          Object.fromEntries(ids.map((id) => [id, { name: id.toUpperCase(), avatarUrl: null }]))
        }
      />,
    );
    expect(renderRow.mock.calls.length).toBeGreaterThanOrEqual(ROWS.length);
    const first = [...renderRow.mock.calls].reverse().find((c) => c[0].rank === 1)![0];
    expect(first).toMatchObject({
      name: "AYLA",
      avatarUrl: null,
      metric: "units",
      score: 54_000,
      scoreText: "54K",
      isMe: false,
    });
    expect(first.entry).toEqual(ROWS[0]);
    expect(first.theme.text).toBeTruthy();
    expect(renderRow.mock.calls.find((c) => c[0].entry.user === "mert")![0].isMe).toBe(true);
    expect(screen.getByText("1|AYLA|54K")).toBeTruthy();
    expect(screen.getByText("4|CAN|900")).toBeTruthy();
  });

  it("uses the gifts as the score for the gifts metric", async () => {
    const renderRow = vi.fn((_r: LeaderboardRowInfo) => <Text>x</Text>);
    await open(
      <GiftLeaderboard client={clientWith(echo())} metric="gifts" renderRow={renderRow} />,
    );
    expect(renderRow.mock.calls[0]![0]).toMatchObject({ metric: "gifts", score: 120 });
  });

  it("the row keeps its test id, label, highlight and press; what you return is the inside", async () => {
    const onPressUser = vi.fn();
    await open(
      <GiftLeaderboard
        client={clientWith(echo())}
        onPressUser={onPressUser}
        highlightUser="ayla"
        renderRow={(r) => <Text testID="mine">{`#${r.rank} ${r.name}`}</Text>}
      />,
    );
    const row = screen.getByTestId("gift-lb-row-ayla");
    expect(row.getAttribute("aria-label")).toBe("Rank 1, ayla, 54,000 coins");
    expect(within(row).getByTestId("mine").textContent).toBe("#1 ayla");
    expect(within(row).queryByTestId("gift-lb-medal-1")).toBeNull();
    expect(bg(row)).toBe(rgb(defaultTheme.selected));
    fireEvent.click(row);
    expect(onPressUser).toHaveBeenCalledWith("ayla");
  });

  it("null, undefined or false draws the default row; the pinned row stays the default", async () => {
    const answers = [null, undefined, false];
    let i = 0;
    await open(
      <GiftLeaderboard
        client={clientWith(
          echo({ me: { user: "me", rank: 417, gifts: 3, units: 120, hidden: false } }),
        )}
        renderRow={() => answers[i++ % 3]}
      />,
    );
    expect(
      within(screen.getByTestId("gift-lb-row-ayla")).getByTestId("gift-lb-medal-1"),
    ).toBeTruthy();
    expect(screen.getByTestId("gift-lb-pinned").textContent).toContain("You: #417");
  });
});
