import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { Text } from "react-native";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type GiftWall as GiftWallAnswer,
  type GiftWallQueryItem,
  type GiftingClient,
  GiftingError,
  type ReceivedGift,
} from "../src/core";
import { GiftWall, type WallChipInfo } from "../src/react-native";
import { installPhoneLayout } from "./setup";
import { componentCallStubs } from "./stub-client";

const rg = (
  id: string,
  count: number,
  name = id[0]!.toUpperCase() + id.slice(1),
): ReceivedGift => ({
  gift: { id, name, icon_url: `https://assets.test/${id}/256.webp` },
  count,
});
const ROSE = rg("rose", 12);
const HEART = rg("heart", 3);
const STAR = rg("star", 20);

type Query = (items: GiftWallQueryItem[]) => Promise<GiftWallAnswer[]>;
const answerFrom =
  (walls: Record<string, ReceivedGift[]>): Query =>
  async (items) =>
    items.map((i) => ({
      receiver: i.receiver,
      reference: i.reference ?? null,
      gifts: walls[`${i.receiver}|${i.reference ?? ""}`] ?? [],
    }));

function clientWith(query: Query): GiftingClient & { query: ReturnType<typeof vi.fn> } {
  const q = vi.fn(query);
  return { ...(componentCallStubs as object), queryGiftWalls: q, query: q } as never;
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
const chipIds = () =>
  [...document.querySelectorAll("[data-testid^='gift-wall-chip-']")].map((e) =>
    e.getAttribute("data-testid")!.replace("gift-wall-chip-", ""),
  );

describe("GiftWall", () => {
  it("draws three still skeleton chips until the answer arrives, then the chips", async () => {
    const client = clientWith(answerFrom({ "mert|post_1": [ROSE, HEART] }));
    render(<GiftWall client={client} user="mert" reference="post_1" />);
    expect(screen.getAllByTestId("gift-wall-skeleton-chip")).toHaveLength(3);
    expect(screen.queryByTestId("gift-wall")).toBeNull();
    await advance(50);
    expect(screen.queryByTestId("gift-wall-skeleton")).toBeNull();
    expect(chipIds()).toEqual(["rose", "heart"]);
    expect(client.query).toHaveBeenCalledTimes(1);
    expect(client.query).toHaveBeenCalledWith([{ receiver: "mert", reference: "post_1" }]);
  });

  it("sorts by count and shows the count without an x, shortened like the spec", async () => {
    const client = clientWith(
      answerFrom({ "mert|": [HEART, rg("rose", 1999), rg("star", 12_400)] }),
    );
    render(<GiftWall client={client} user="mert" />);
    await advance(50);
    expect(chipIds()).toEqual(["star", "rose", "heart"]);
    const texts = [...document.querySelectorAll("[data-testid^='gift-wall-chip-']")].map(
      (e) => e.textContent,
    );
    expect(texts).toEqual(["12K", "1.9K", "3"]);
  });

  it("keeps the catalog order with order=catalog", async () => {
    render(
      <GiftWall
        client={clientWith(async () => [])}
        user="u"
        data={[HEART, ROSE]}
        order="catalog"
      />,
    );
    expect(chipIds()).toEqual(["heart", "rose"]);
  });

  it("shows max-1 chips and one overflow chip with the sum of the rest", () => {
    const data = [rg("a", 50), rg("b", 40), rg("c", 30), rg("d", 20), rg("e", 10)];
    render(<GiftWall client={clientWith(async () => [])} user="u" data={data} max={3} />);
    expect(chipIds()).toEqual(["a", "b"]);
    expect(screen.getByTestId("gift-wall-overflow").textContent).toBe("+60");
  });

  it("is one element for a screen reader, naming gifts and the overflow", () => {
    const data = [rg("rose", 12, "Rose"), rg("heart", 3, "Heart"), rg("a", 30), rg("b", 7)];
    render(<GiftWall client={clientWith(async () => [])} user="u" data={data} max={3} />);
    // The two kinds past max-1 become "+37": a (30) and b (7).
    expect(screen.getByLabelText("Gifts: 30 As, 12 Roses, and 10 more")).toBeTruthy();
  });

  it("uses singular names for a count of 1 and translated labels", () => {
    render(
      <GiftWall
        client={clientWith(async () => [])}
        user="u"
        data={[rg("rose", 1, "Gul")]}
        labels={{ wallSummary: "Hediyeler: {list}", plural: "ler" }}
      />,
    );
    expect(screen.getByLabelText("Hediyeler: 1 Gul")).toBeTruthy();
  });

  it("renders nothing for an empty wall, or the empty text when given", async () => {
    const client = clientWith(async () => [{ receiver: "u", reference: null, gifts: [] }]);
    const { container, unmount } = render(<GiftWall client={client} user="u" />);
    await advance(50);
    expect(screen.queryByTestId("gift-wall")).toBeNull();
    expect(screen.queryByTestId("gift-wall-skeleton")).toBeNull();
    expect(container.textContent).toBe("");
    unmount();
    // Zero counts are dropped as well.
    render(
      <GiftWall
        client={client}
        user="u"
        data={[rg("rose", 0)]}
        labels={{ emptyText: "No gifts" }}
      />,
    );
    expect(screen.getByText("No gifts")).toBeTruthy();
  });

  it("never draws an error: it renders nothing and reports through onError", async () => {
    const onError = vi.fn();
    const client = clientWith(async () => {
      throw new GiftingError(500, "server_error", "boom");
    });
    const { container } = render(<GiftWall client={client} user="u" onError={onError} />);
    await advance(50);
    expect(onError).toHaveBeenCalledTimes(1);
    expect(onError.mock.calls[0]![0]).toBeInstanceOf(GiftingError);
    expect(container.textContent).toBe("");
    expect(screen.queryByTestId("gift-wall-skeleton")).toBeNull();
  });

  it("makes no request when data is given", async () => {
    const client = clientWith(async () => []);
    render(<GiftWall client={client} user="u" data={[ROSE]} />);
    await advance(200);
    expect(client.query).not.toHaveBeenCalled();
    expect(chipIds()).toEqual(["rose"]);
  });

  it("batches the walls of a feed into one request, in order", async () => {
    const client = clientWith(answerFrom({ "a|p1": [ROSE], "b|p2": [HEART], "c|": [STAR] }));
    render(
      <>
        <GiftWall client={client} user="a" reference="p1" />
        <GiftWall client={client} user="b" reference="p2" />
        <GiftWall client={client} user="c" />
      </>,
    );
    await advance(49);
    expect(client.query).not.toHaveBeenCalled();
    await advance(1);
    expect(client.query).toHaveBeenCalledTimes(1);
    expect(client.query.mock.calls[0]![0]).toEqual([
      { receiver: "a", reference: "p1" },
      { receiver: "b", reference: "p2" },
      { receiver: "c" },
    ]);
    expect(chipIds().sort()).toEqual(["heart", "rose", "star"]);
  });

  it("splits more than 25 walls into several requests", async () => {
    const client = clientWith(async (items) =>
      items.map((i) => ({ receiver: i.receiver, reference: null, gifts: [] })),
    );
    render(
      <>
        {Array.from({ length: 26 }, (_, i) => (
          <GiftWall key={i} client={client} user={`u${i}`} />
        ))}
      </>,
    );
    await advance(50);
    expect(client.query.mock.calls.map((c) => (c[0] as unknown[]).length)).toEqual([25, 1]);
  });

  it("asks again when refreshKey changes, not otherwise", async () => {
    let n = 0;
    const client = clientWith(async (items) =>
      items.map((i) => ({ receiver: i.receiver, reference: null, gifts: [rg("rose", ++n)] })),
    );
    const { rerender } = render(<GiftWall client={client} user="u" refreshKey={1} />);
    await advance(50);
    expect(client.query).toHaveBeenCalledTimes(1);
    expect(screen.getByTestId("gift-wall-chip-rose").textContent).toBe("1");
    rerender(<GiftWall client={client} user="u" refreshKey={1} />);
    await advance(100);
    expect(client.query).toHaveBeenCalledTimes(1);
    rerender(<GiftWall client={client} user="u" refreshKey={2} />);
    await advance(50);
    expect(client.query).toHaveBeenCalledTimes(2);
    expect(screen.getByTestId("gift-wall-chip-rose").textContent).toBe("2");
  });

  it("reuses an answer for 60 seconds across mounts", async () => {
    const client = clientWith(answerFrom({ "u|": [ROSE] }));
    const first = render(<GiftWall client={client} user="u" />);
    await advance(50);
    first.unmount();
    render(<GiftWall client={client} user="u" />);
    // Drawn at once from the cache: no skeleton, no new request.
    expect(chipIds()).toEqual(["rose"]);
    await advance(100);
    expect(client.query).toHaveBeenCalledTimes(1);
    cleanup();
    await advance(60_000);
    render(<GiftWall client={client} user="u" />);
    await advance(50);
    expect(client.query).toHaveBeenCalledTimes(2);
  });

  it("is not tappable without onPressChip: no buttons", () => {
    render(<GiftWall client={clientWith(async () => [])} user="u" data={[ROSE, HEART]} />);
    expect(screen.queryAllByRole("button")).toHaveLength(0);
  });

  it("makes each chip a labelled button with a 44 dp touch target when onPressChip is set", () => {
    const onPressChip = vi.fn();
    render(
      <GiftWall
        client={clientWith(async () => [])}
        user="u"
        data={[ROSE, HEART]}
        onPressChip={onPressChip}
      />,
    );
    expect(screen.getAllByRole("button")).toHaveLength(2);
    fireEvent.click(screen.getByLabelText("Rose, 12"));
    expect(onPressChip).toHaveBeenCalledWith(ROSE.gift);
    expect(screen.getByLabelText("Heart, 3")).toBeTruthy();
    // hitSlop is drawn as an invisible extension: md chip 24 + 2 * 10 = 44.
    const chip = screen.getByTestId("gift-wall-chip-rose");
    expect(chip.getAttribute("data-testid")).toBe("gift-wall-chip-rose");
  });

  it("does not make the overflow chip a button", () => {
    const data = [rg("a", 5), rg("b", 4), rg("c", 3)];
    render(
      <GiftWall
        client={clientWith(async () => [])}
        user="u"
        data={data}
        max={2}
        onPressChip={() => {}}
      />,
    );
    expect(screen.getAllByRole("button")).toHaveLength(1);
    expect(screen.getByTestId("gift-wall-overflow").textContent).toBe("+7");
  });

  it("sizes chips: sm 20 high, md 24 high", () => {
    const { rerender } = render(
      <GiftWall client={clientWith(async () => [])} user="u" data={[ROSE]} size="sm" />,
    );
    expect(getComputedStyle(screen.getByTestId("gift-wall-chip-rose")).height).toBe("20px");
    rerender(<GiftWall client={clientWith(async () => [])} user="u" data={[ROSE]} />);
    expect(getComputedStyle(screen.getByTestId("gift-wall-chip-rose")).height).toBe("24px");
  });

  it("fades in over 120 ms when data arrives, and not under reduced motion", async () => {
    const client = clientWith(answerFrom({ "u|": [ROSE] }));
    const { unmount } = render(<GiftWall client={client} user="u" reducedMotion={false} />);
    await advance(50);
    expect(Number(getComputedStyle(screen.getByTestId("gift-wall")).opacity)).toBeLessThan(0.99);
    await advance(200);
    expect(Number(getComputedStyle(screen.getByTestId("gift-wall")).opacity)).toBe(1);
    unmount();

    const calm = clientWith(answerFrom({ "z|": [ROSE] }));
    render(<GiftWall client={calm} user="z" reducedMotion />);
    await advance(50);
    expect(Number(getComputedStyle(screen.getByTestId("gift-wall")).opacity)).toBe(1);
  });
});

describe("GiftWall: renderChip", () => {
  it("is called per gift chip with the gift, the exact count, the short text and the theme", async () => {
    const client = clientWith(answerFrom({ "mert|": [HEART, rg("rose", 1999), STAR] }));
    const renderChip = vi.fn((c: WallChipInfo) => (
      <Text>{`${c.gift.id}:${c.count}:${c.countText}`}</Text>
    ));
    render(<GiftWall client={client} user="mert" renderChip={renderChip} />);
    expect(renderChip).not.toHaveBeenCalled(); // not while loading
    await advance(50);
    expect(renderChip.mock.calls.map((c) => c[0].gift.id)).toEqual(["rose", "star", "heart"]);
    expect(renderChip.mock.calls[0]![0]).toMatchObject({ count: 1999, countText: "1.9K" });
    expect(renderChip.mock.calls[1]![0].theme.text).toBeTruthy();
    expect(screen.getByText("star:20:20")).toBeTruthy();
    expect(screen.getByText("rose:1999:1.9K")).toBeTruthy();
  });

  it("what it returns replaces the icon and count; the chip keeps its test id, press and label", async () => {
    const client = clientWith(answerFrom({ "mert|": [ROSE] }));
    const onPressChip = vi.fn();
    render(
      <GiftWall
        client={client}
        user="mert"
        onPressChip={onPressChip}
        renderChip={(c) => <Text testID="mine">{`x${c.count}`}</Text>}
      />,
    );
    await advance(50);
    const chip = screen.getByTestId("gift-wall-chip-rose");
    expect(chip.getAttribute("aria-label")).toBe("Rose, 12");
    expect(within(chip).getByTestId("mine").textContent).toBe("x12");
    expect(chip.querySelector("img")).toBeNull();
    fireEvent.click(chip);
    expect(onPressChip).toHaveBeenCalledWith(ROSE.gift);
  });

  it("null, undefined or false draws the default chip", async () => {
    const client = clientWith(answerFrom({ "mert|": [ROSE, HEART, STAR] }));
    const answers = [null, undefined, false];
    let i = 0;
    render(<GiftWall client={client} user="mert" renderChip={() => answers[i++]} />);
    await advance(50);
    expect(chipIds()).toEqual(["star", "rose", "heart"]);
    expect(screen.getByTestId("gift-wall-chip-rose").textContent).toBe("12");
  });

  it("the overflow chip is not passed to the hook", async () => {
    const client = clientWith(answerFrom({ "mert|": [ROSE, HEART, STAR] }));
    const renderChip = vi.fn(() => <Text>c</Text>);
    render(<GiftWall client={client} user="mert" max={2} renderChip={renderChip} />);
    await advance(50);
    expect(renderChip).toHaveBeenCalledTimes(1);
    expect(screen.getByTestId("gift-wall-overflow").textContent).toMatch(/^\+\d+$/);
  });
});
