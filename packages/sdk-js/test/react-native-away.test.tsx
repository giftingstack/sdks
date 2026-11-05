import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { createRef } from "react";
import { Pressable, Text } from "react-native";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type AwayGroup,
  type AwaySummary,
  type GiftEffectEvent,
  type GiftingClient,
  GiftingError,
  planAwayReplay,
} from "../src/core";
import {
  type AwaySummaryInfo,
  GiftAwaySummary,
  type GiftAwaySummaryHandle,
  type GiftEffectLayerHandle,
} from "../src/react-native";
import { installPhoneLayout } from "./setup";
import { componentCallStubs } from "./stub-client";

const group = (
  id: string,
  price: number,
  count: number,
  senders: { user: string | null; count: number }[] = [{ user: "ayla", count }],
  senderCount = senders.length,
): AwayGroup => ({
  gift: {
    id,
    name: id[0]!.toUpperCase() + id.slice(1),
    price,
    icon_url: `https://assets.test/${id}/256.webp`,
    animation_url: `https://assets.test/${id}/512.webp`,
  },
  count,
  units: price * count,
  sender_count: senderCount,
  senders,
});

// The worked example of the spec: star at 0, rose at 450, hat at 900, dragon at 3300.
const GROUPS: AwayGroup[] = [
  group("dragon", 40_000, 1, [{ user: "ayla", count: 1 }]),
  group(
    "hat",
    350,
    20,
    [
      { user: "mert", count: 9 },
      { user: null, count: 4 },
      { user: "ece", count: 3 },
    ],
    6,
  ),
  group("rose", 10, 50, [{ user: "ece", count: 50 }]),
  group("star", 5, 3, [{ user: "mert", count: 3 }]),
];

const summary = (over: Partial<AwaySummary> = {}): AwaySummary => ({
  user: "me",
  since: "2026-10-08T09:12:44.120Z",
  until: "2026-10-11T07:30:02.511Z",
  cursor: "aw1.abc",
  truncated: false,
  total_gifts: 37,
  total_units: 47_515,
  sender_count: 12,
  groups: GROUPS,
  top_senders: [
    { user: "ayla", count: 15, units: 41_200 },
    { user: "mert", count: 12, units: 3_000 },
    { user: null, count: 4, units: 1_000 },
    { user: "ece", count: 3, units: 900 },
  ],
  ...over,
});

function clientWith(
  getAway: () => Promise<AwaySummary>,
): GiftingClient & { getAway: ReturnType<typeof vi.fn>; ackAway: ReturnType<typeof vi.fn> } {
  return {
    ...(componentCallStubs as object),
    getAway: vi.fn(getAway),
    ackAway: vi.fn(async () => {}),
  } as never;
}

function layer() {
  const play = vi.fn((_e: GiftEffectEvent) => 1);
  const handle: GiftEffectLayerHandle = { play, cancel: vi.fn(), clear: vi.fn() };
  return { ref: { current: handle }, play };
}

let restoreLayout = () => {};
beforeEach(() => {
  restoreLayout = installPhoneLayout();
  vi.useFakeTimers({
    toFake: [
      "setTimeout",
      "clearTimeout",
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
/** Mounted, checked, resolved: the card is up (the test setup counts as reduced motion by default). */
async function open(ui: React.ReactElement) {
  const r = render(ui);
  await advance(0);
  return r;
}

describe("GiftAwaySummary: the card", () => {
  it("asks once on mount and shows the totals, top senders and gifts", async () => {
    const client = clientWith(async () => summary());
    await open(<GiftAwaySummary client={client} />);
    expect(client.getAway).toHaveBeenCalledTimes(1);
    expect(screen.getByText("While you were away")).toBeTruthy();
    expect(screen.getByText("37 gifts from 12 people")).toBeTruthy();
    expect(screen.getAllByTestId("gift-away-sender")).toHaveLength(3);
    expect(screen.getAllByTestId("gift-away-group")).toHaveLength(4);
    expect(screen.getByLabelText("ayla, 15 gifts")).toBeTruthy();
    // A deleted sender is "Someone".
    expect(screen.getByLabelText("Someone, 4 gifts")).toBeTruthy();
    expect(screen.getByLabelText("Dragon, 1")).toBeTruthy();
    expect(screen.getByLabelText("Hat, 20")).toBeTruthy();
  });

  it("announces the summary in a live region", async () => {
    await open(<GiftAwaySummary client={clientWith(async () => summary())} />);
    const live = screen.getByLabelText("You received 37 gifts from 12 people while you were away");
    expect(live.getAttribute("aria-live")).toBe("polite");
  });

  it("writes a truncated total as 2,000+ and one gift or person in the singular", async () => {
    const one = summary({ total_gifts: 1, sender_count: 1, groups: [GROUPS[3]!], top_senders: [] });
    const { unmount } = await open(<GiftAwaySummary client={clientWith(async () => one)} />);
    expect(screen.getByText("1 gift from 1 person")).toBeTruthy();
    unmount();
    await open(
      <GiftAwaySummary
        client={clientWith(async () => summary({ truncated: true, total_gifts: 2000 }))}
      />,
    );
    expect(screen.getByText("2,000+ gifts from 12 people")).toBeTruthy();
  });

  it("draws nothing when nothing is new, and does not move the cursor", async () => {
    const client = clientWith(async () =>
      summary({ total_gifts: 0, total_units: 0, sender_count: 0, groups: [], top_senders: [] }),
    );
    const { container } = await open(<GiftAwaySummary client={client} />);
    expect(container.textContent).toBe("");
    await advance(10_000);
    expect(client.ackAway).not.toHaveBeenCalled();
  });

  it("draws nothing on a failure and reports it; the next check can try again", async () => {
    let fail = true;
    const onError = vi.fn();
    const client = clientWith(async () => {
      if (fail) throw new GiftingError(500, "server_error", "boom");
      return summary();
    });
    const ref = createRef<GiftAwaySummaryHandle>();
    const { container } = await open(
      <GiftAwaySummary ref={ref} client={client} onError={onError} />,
    );
    expect(container.textContent).toBe("");
    expect(onError).toHaveBeenCalledTimes(1);
    fail = false;
    await act(async () => ref.current!.check());
    await advance(0);
    expect(screen.getByText("37 gifts from 12 people")).toBeTruthy();
  });

  it("does not check on mount with autoCheck=false, only when asked", async () => {
    const client = clientWith(async () => summary());
    const ref = createRef<GiftAwaySummaryHandle>();
    await open(<GiftAwaySummary ref={ref} client={client} autoCheck={false} />);
    expect(client.getAway).not.toHaveBeenCalled();
    await act(async () => ref.current!.check());
    await advance(0);
    expect(client.getAway).toHaveBeenCalledTimes(1);
    expect(screen.getByText("While you were away")).toBeTruthy();
  });

  it("calls onShow with the summary", async () => {
    const onShow = vi.fn();
    await open(<GiftAwaySummary client={clientWith(async () => summary())} onShow={onShow} />);
    expect(onShow).toHaveBeenCalledTimes(1);
    expect(onShow.mock.calls[0]![0].total_gifts).toBe(37);
  });

  it("goes on a tap on the card, or the Dismiss button, and calls onDone once", async () => {
    const onDone = vi.fn();
    const client = clientWith(async () => summary());
    const { unmount } = await open(<GiftAwaySummary client={client} onDone={onDone} />);
    fireEvent.click(screen.getByTestId("gift-away-body"));
    expect(screen.queryByTestId("gift-away-card")).toBeNull();
    expect(onDone).toHaveBeenCalledTimes(1);
    unmount();
    const onDone2 = vi.fn();
    await open(<GiftAwaySummary client={clientWith(async () => summary())} onDone={onDone2} />);
    fireEvent.click(screen.getByLabelText("Dismiss"));
    expect(screen.queryByTestId("gift-away-card")).toBeNull();
    expect(onDone2).toHaveBeenCalledTimes(1);
  });

  it("goes by itself after max(4000, replay end + 1500) ms", async () => {
    // Card only (no effect layer): 4000 ms.
    await open(<GiftAwaySummary client={clientWith(async () => summary())} />);
    await advance(3_999);
    expect(screen.queryByTestId("gift-away-card")).not.toBeNull();
    await advance(1);
    expect(screen.queryByTestId("gift-away-card")).toBeNull();
  });

  it("uses names from resolveUsers, keeps the id for an unknown one, and Someone for a deleted sender", async () => {
    const resolveUsers = vi.fn(async (ids: string[]) =>
      Object.fromEntries(
        ids
          .filter((i) => i === "ayla")
          .map((i) => [i, { name: "Ayla Y.", avatarUrl: "https://a.test/a.png" }]),
      ),
    );
    await open(
      <GiftAwaySummary client={clientWith(async () => summary())} resolveUsers={resolveUsers} />,
    );
    expect(resolveUsers).toHaveBeenCalledTimes(1);
    expect([...resolveUsers.mock.calls[0]![0]].sort()).toEqual(["ayla", "ece", "mert"]);
    expect(screen.getByLabelText("Ayla Y., 15 gifts")).toBeTruthy();
    expect(screen.getByLabelText("mert, 12 gifts")).toBeTruthy();
    expect(screen.getByLabelText("Someone, 4 gifts")).toBeTruthy();
    expect(screen.getAllByTestId("gift-avatar-image")).toHaveLength(1);
  });

  it("waits for resolveUsers at most 1.5 s, then shows the ids", async () => {
    const never = () => new Promise<Record<string, { name: string }>>(() => {});
    await open(<GiftAwaySummary client={clientWith(async () => summary())} resolveUsers={never} />);
    expect(screen.queryByTestId("gift-away-card")).toBeNull();
    await advance(1_499);
    expect(screen.queryByTestId("gift-away-card")).toBeNull();
    await advance(1);
    expect(screen.getByLabelText("ayla, 15 gifts")).toBeTruthy();
  });

  it("shows the ids when resolveUsers fails", async () => {
    const resolveUsers = async () => {
      throw new Error("no");
    };
    await open(
      <GiftAwaySummary client={clientWith(async () => summary())} resolveUsers={resolveUsers} />,
    );
    expect(screen.getByLabelText("ayla, 15 gifts")).toBeTruthy();
  });

  it("translates through labels", async () => {
    await open(
      <GiftAwaySummary
        client={clientWith(async () => summary())}
        labels={{
          awayTitle: "Yokken",
          awaySummary: "{people} kisiden {gifts}",
          giftOther: "{n} hediye",
          personOther: "{n} kisi",
          dismiss: "Kapat",
          someone: "Biri",
        }}
      />,
    );
    expect(screen.getByText("Yokken")).toBeTruthy();
    expect(screen.getByText("12 kisi kisiden 37 hediye")).toBeTruthy();
    expect(screen.getByLabelText("Kapat")).toBeTruthy();
    expect(screen.getByLabelText("Biri, 4 hediye")).toBeTruthy();
  });
});

describe("GiftAwaySummary: acknowledging", () => {
  it("ackOn=shown (default) sends the cursor once, when the card is up", async () => {
    const client = clientWith(async () => summary());
    await open(<GiftAwaySummary client={client} />);
    expect(client.ackAway).toHaveBeenCalledTimes(1);
    expect(client.ackAway).toHaveBeenCalledWith("aw1.abc");
    fireEvent.click(screen.getByLabelText("Dismiss"));
    await advance(10);
    expect(client.ackAway).toHaveBeenCalledTimes(1);
  });

  it("ackOn=finished waits for the dismissal", async () => {
    const client = clientWith(async () => summary());
    await open(<GiftAwaySummary client={client} ackOn="finished" />);
    expect(client.ackAway).not.toHaveBeenCalled();
    fireEvent.click(screen.getByLabelText("Dismiss"));
    await advance(0);
    expect(client.ackAway).toHaveBeenCalledTimes(1);
    expect(client.ackAway).toHaveBeenCalledWith("aw1.abc");
  });

  it("ackOn=manual never acknowledges until ack() is called", async () => {
    const client = clientWith(async () => summary());
    const ref = createRef<GiftAwaySummaryHandle>();
    await open(<GiftAwaySummary ref={ref} client={client} ackOn="manual" />);
    fireEvent.click(screen.getByLabelText("Dismiss"));
    await advance(5_000);
    expect(client.ackAway).not.toHaveBeenCalled();
    await act(async () => ref.current!.ack());
    expect(client.ackAway).toHaveBeenCalledTimes(1);
  });

  it("a failed acknowledgement is reported, not shown, and retried once at the next check", async () => {
    const onError = vi.fn();
    const client = clientWith(async () => summary());
    client.ackAway.mockRejectedValueOnce(new GiftingError(500, "server_error", "x"));
    const ref = createRef<GiftAwaySummaryHandle>();
    await open(<GiftAwaySummary ref={ref} client={client} onError={onError} />);
    expect(onError).toHaveBeenCalledTimes(1);
    expect(screen.getByText("While you were away")).toBeTruthy();
    fireEvent.click(screen.getByLabelText("Dismiss"));
    await act(async () => ref.current!.check());
    await advance(0);
    // The failed attempt, its retry, then the new summary's own acknowledgement.
    expect(client.ackAway.mock.calls.map((c) => c[0])).toEqual(["aw1.abc", "aw1.abc", "aw1.abc"]);
  });
});

describe("GiftAwaySummary: the replay", () => {
  const noMotion = { reducedMotion: false } as const;

  it("plays the planned groups through the effect layer at the planned times", async () => {
    const fx = layer();
    const client = clientWith(async () => summary());
    await open(<GiftAwaySummary client={client} effects={fx.ref} {...noMotion} />);
    const plan = planAwayReplay(GROUPS, {});
    expect(plan.items.map((i) => [i.group.gift.id, i.atMs])).toEqual([
      ["star", 0],
      ["rose", 450],
      ["hat", 900],
      ["dragon", 3300],
    ]);
    await advance(0);
    expect(fx.play.mock.calls.map((c) => c[0].gift.id)).toEqual(["star"]);
    await advance(449);
    expect(fx.play).toHaveBeenCalledTimes(1);
    await advance(1);
    expect(fx.play).toHaveBeenCalledTimes(2);
    await advance(450);
    expect(fx.play).toHaveBeenCalledTimes(3);
    await advance(2_399);
    expect(fx.play).toHaveBeenCalledTimes(3);
    await advance(1);
    expect(fx.play.mock.calls.map((c) => c[0].gift.id)).toEqual(["star", "rose", "hat", "dragon"]);
  });

  it("gives each play the gift, the quantity and who sent it", async () => {
    const fx = layer();
    const resolveUsers = async () => ({ mert: { name: "Mert" }, ece: { name: "Ece" } });
    await open(
      <GiftAwaySummary
        client={clientWith(async () => summary())}
        effects={fx.ref}
        resolveUsers={resolveUsers}
        {...noMotion}
      />,
    );
    await advance(900);
    const hat = fx.play.mock.calls.map((c) => c[0]).find((e) => e.gift.id === "hat")!;
    expect(hat.quantity).toBe(20);
    expect(hat.gift).toMatchObject({
      price: 350,
      image: "https://assets.test/hat/512.webp",
      icon: "https://assets.test/hat/256.webp",
    });
    // Six senders: the first named and "5 others".
    expect(hat.sender).toBe("Mert and 5 others");
    const star = fx.play.mock.calls.map((c) => c[0]).find((e) => e.gift.id === "star")!;
    expect(star.sender).toBe("Mert");
  });

  it("plays at most maxEffects groups", async () => {
    const fx = layer();
    const many = Array.from({ length: 8 }, (_, i) => group(`g${i}`, 20 + i, 5 + i));
    const s = summary({ groups: many });
    await open(
      <GiftAwaySummary
        client={clientWith(async () => s)}
        effects={fx.ref}
        maxEffects={3}
        {...noMotion}
      />,
    );
    await advance(10_000);
    expect(fx.play).toHaveBeenCalledTimes(3);
  });

  it("keeps the whole replay inside budgetMs, dropping the smallest first", async () => {
    const fx = layer();
    const many = Array.from({ length: 5 }, (_, i) => group(`m${i}`, 150 + i, 10 + i));
    const s = summary({ groups: many });
    const budgetMs = 3_000;
    const plan = planAwayReplay(many, { budgetMs });
    expect(plan.endMs).toBeLessThanOrEqual(budgetMs);
    expect(plan.items.length).toBeLessThan(5);
    await open(
      <GiftAwaySummary
        client={clientWith(async () => s)}
        effects={fx.ref}
        budgetMs={budgetMs}
        {...noMotion}
      />,
    );
    await advance(10_000);
    expect(fx.play).toHaveBeenCalledTimes(plan.items.length);
    // The group with the lowest units is the one left out.
    expect(fx.play.mock.calls.map((c) => c[0].gift.id)).not.toContain("m0");
  });

  it("drops plays that have not started when the card is dismissed", async () => {
    const fx = layer();
    await open(
      <GiftAwaySummary client={clientWith(async () => summary())} effects={fx.ref} {...noMotion} />,
    );
    await advance(500);
    expect(fx.play).toHaveBeenCalledTimes(2);
    fireEvent.click(screen.getByLabelText("Dismiss"));
    await advance(10_000);
    expect(fx.play).toHaveBeenCalledTimes(2);
  });

  it("stays at least until the replay ended + 1.5 s", async () => {
    const fx = layer();
    await open(
      <GiftAwaySummary client={clientWith(async () => summary())} effects={fx.ref} {...noMotion} />,
    );
    const end = planAwayReplay(GROUPS, {}).endMs; // 7150
    await advance(end + 1_499);
    expect(screen.queryByTestId("gift-away-card")).not.toBeNull();
    await advance(1);
    expect(screen.queryByTestId("gift-away-card")).toBeNull();
  });

  it("shows only the card under reduced motion", async () => {
    const fx = layer();
    await open(
      <GiftAwaySummary client={clientWith(async () => summary())} effects={fx.ref} reducedMotion />,
    );
    await advance(10_000);
    expect(fx.play).not.toHaveBeenCalled();
  });

  it("shows only the card without an effect layer", async () => {
    await open(<GiftAwaySummary client={clientWith(async () => summary())} {...noMotion} />);
    expect(screen.getByText("While you were away")).toBeTruthy();
  });
});

describe("GiftAwaySummary: renderSummary", () => {
  it("is called with the computed data, resolved names, callbacks and the theme", async () => {
    const renderSummary = vi.fn((_i: AwaySummaryInfo) => <Text>mine</Text>);
    await open(
      <GiftAwaySummary
        client={clientWith(async () => summary())}
        renderSummary={renderSummary}
        resolveUsers={async (ids) =>
          Object.fromEntries(
            ids.map((id) => [
              id,
              { name: id.toUpperCase(), avatarUrl: `https://img.test/${id}.png` },
            ]),
          )
        }
      />,
    );
    const info = renderSummary.mock.calls.at(-1)![0];
    expect(info.summary.total_gifts).toBe(37);
    expect(info.title).toBe("While you were away");
    expect(info.headline).toBe("37 gifts from 12 people");
    expect(info.senders).toHaveLength(4);
    expect(info.senders[0]).toEqual({
      user: "ayla",
      name: "AYLA",
      avatarUrl: "https://img.test/ayla.png",
      count: 15,
    });
    expect(info.senders[2]).toMatchObject({ user: null, name: "Someone", avatarUrl: null });
    expect(typeof info.dismiss).toBe("function");
    expect(info.theme.text).toBeTruthy();
  });

  it("what it returns is the card body; the card keeps its container and the replay", async () => {
    const client = clientWith(async () => summary());
    const fx = layer();
    await open(
      <GiftAwaySummary
        client={client}
        effects={fx.ref}
        reducedMotion={false}
        renderSummary={(i) => <Text testID="mine">{i.headline}</Text>}
      />,
    );
    expect(screen.getByTestId("gift-away-card")).toBeTruthy();
    expect(within(screen.getByTestId("gift-away-custom")).getByTestId("mine").textContent).toBe(
      "37 gifts from 12 people",
    );
    expect(screen.queryByText("While you were away")).toBeNull();
    expect(screen.queryByTestId("gift-away-sender")).toBeNull();
    expect(screen.queryByTestId("gift-away-dismiss")).toBeNull();
    await advance(100);
    expect(fx.play).toHaveBeenCalled();
    expect(client.ackAway).toHaveBeenCalledTimes(1);
  });

  it("dismiss() from the hook closes it; a tap on the custom body does not", async () => {
    const onDone = vi.fn();
    await open(
      <GiftAwaySummary
        client={clientWith(async () => summary())}
        onDone={onDone}
        renderSummary={(i) => (
          <Pressable testID="mine" onPress={i.dismiss}>
            <Text>close</Text>
          </Pressable>
        )}
      />,
    );
    fireEvent.click(screen.getByTestId("gift-away-custom"));
    expect(onDone).not.toHaveBeenCalled();
    expect(screen.getByTestId("gift-away-card")).toBeTruthy();
    fireEvent.click(screen.getByTestId("mine"));
    await advance(0);
    expect(onDone).toHaveBeenCalledTimes(1);
    expect(screen.queryByTestId("gift-away-card")).toBeNull();
  });

  it("null, undefined or false draws the default card", async () => {
    await open(
      <GiftAwaySummary client={clientWith(async () => summary())} renderSummary={() => null} />,
    );
    expect(screen.getByText("While you were away")).toBeTruthy();
    expect(screen.getAllByTestId("gift-away-sender")).toHaveLength(3);
    expect(screen.getByTestId("gift-away-dismiss")).toBeTruthy();
    expect(screen.queryByTestId("gift-away-custom")).toBeNull();
  });
});
