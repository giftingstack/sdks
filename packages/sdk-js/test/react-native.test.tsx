import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { createRef } from "react";
import { Image } from "react-native";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { type Gift, type GiftTransaction, type GiftingClient, GiftingError } from "../src/core";
import {
  GiftEffectLayer,
  type GiftEffectLayerHandle,
  GiftTray,
  useGiftTray,
} from "../src/react-native";
import { installPhoneLayout } from "./setup";
import { componentCallStubs } from "./stub-client";

const gift = (id: string, price: number, over: Partial<Gift> = {}): Gift => ({
  id,
  name: id[0]!.toUpperCase() + id.slice(1),
  description: null,
  price,
  icon_url: `https://assets.test/${id}/256.webp`,
  animation_url: `https://assets.test/${id}/512.webp`,
  sort_order: 0,
  ...over,
});

const ROSE = gift("rose", 10);
const HAT = gift("hat", 350);
const DRAGON = gift("dragon", 40_000);
const DRAGON2 = gift("lion", 20_000);

const event = (g: Gift, sender = "ayla") => ({
  gift: { id: g.id, name: g.name, price: g.price, image: g.animation_url },
  sender,
});

let restoreLayout = () => {};
beforeEach(() => {
  restoreLayout = installPhoneLayout();
  // Date too, because the Animated library times itself with Date.now().
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

const lastNotice = () => {
  const all = screen.getAllByTestId("gift-notice");
  return all[all.length - 1]!;
};

async function advance(ms: number) {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(ms);
  });
}

describe("GiftTray", () => {
  it("shows every gift with its price and the balance", () => {
    render(<GiftTray gifts={[ROSE, HAT]} balance={1234} onSend={() => {}} />);
    expect(screen.getByLabelText("Rose, 10 coins")).toBeTruthy();
    expect(screen.getByLabelText("Hat, 350 coins")).toBeTruthy();
    expect(screen.getByLabelText("Balance: 1,234 coins")).toBeTruthy();
  });

  it("selects the first gift and sends the one you tapped", () => {
    const onSend = vi.fn();
    render(<GiftTray gifts={[ROSE, HAT]} balance={1000} onSend={onSend} />);
    fireEvent.click(screen.getByTestId("gift-send"));
    expect(onSend).toHaveBeenLastCalledWith(ROSE);
    fireEvent.click(screen.getByLabelText("Hat, 350 coins"));
    fireEvent.click(screen.getByTestId("gift-send"));
    expect(onSend).toHaveBeenLastCalledWith(HAT);
    expect(onSend).toHaveBeenCalledTimes(2);
  });

  it("marks the selected gift for screen readers", () => {
    render(
      <GiftTray gifts={[ROSE, HAT]} balance={1000} onSend={() => {}} defaultSelectedId="hat" />,
    );
    expect(screen.getByLabelText("Hat, 350 coins").getAttribute("aria-checked")).toBe("true");
    expect(screen.getByLabelText("Rose, 10 coins").getAttribute("aria-checked")).toBe("false");
  });

  it("cannot send what you cannot afford, and says so", () => {
    const onSend = vi.fn();
    render(
      <GiftTray gifts={[ROSE, DRAGON]} balance={100} onSend={onSend} defaultSelectedId="dragon" />,
    );
    const send = screen.getByTestId("gift-send");
    expect(send.textContent).toBe("Not enough coins");
    fireEvent.click(send);
    expect(onSend).not.toHaveBeenCalled();
  });

  it("offers the store instead when you can top up", () => {
    const onTopUp = vi.fn();
    const onSend = vi.fn();
    render(<GiftTray gifts={[DRAGON]} balance={5} onSend={onSend} onTopUp={onTopUp} />);
    const send = screen.getByTestId("gift-send");
    expect(send.textContent).toBe("Get coins");
    fireEvent.click(send);
    expect(onTopUp).toHaveBeenCalledTimes(1);
    expect(onSend).not.toHaveBeenCalled();
    fireEvent.click(screen.getByLabelText("Get more coins"));
    expect(onTopUp).toHaveBeenCalledTimes(2);
  });

  it("is switched off while disabled", () => {
    const onSend = vi.fn();
    render(<GiftTray gifts={[ROSE]} balance={100} onSend={onSend} disabled />);
    fireEvent.click(screen.getByTestId("gift-send"));
    expect(onSend).not.toHaveBeenCalled();
  });

  it("counts the balance to its new value", async () => {
    const { rerender } = render(<GiftTray gifts={[ROSE]} balance={1000} onSend={() => {}} />);
    rerender(<GiftTray gifts={[ROSE]} balance={400} onSend={() => {}} />);
    await advance(100);
    const mid = Number(screen.getByTestId("gift-balance").textContent!.replace(/,/g, ""));
    expect(mid).toBeGreaterThan(400);
    expect(mid).toBeLessThan(1000);
    await advance(800);
    expect(screen.getByTestId("gift-balance").textContent).toBe("400");
  });

  it("warms up the pictures: every icon, and the big picture of the selected gift", () => {
    const spy = vi.spyOn(Image, "prefetch").mockResolvedValue(true);
    render(<GiftTray gifts={[ROSE, HAT]} balance={1000} onSend={() => {}} />);
    const urls = spy.mock.calls.map((c) => c[0]);
    expect(urls).toContain(ROSE.icon_url);
    expect(urls).toContain(HAT.icon_url);
    expect(urls).toContain(ROSE.animation_url); // the first gift is selected
    spy.mockClear();
    fireEvent.click(screen.getByLabelText("Hat, 350 coins"));
    expect(spy.mock.calls.map((c) => c[0])).toContain(HAT.animation_url);
    spy.mockRestore();
  });

  it("draws the selected gift's big picture out of sight so the phone decodes it before the tap", () => {
    render(<GiftTray gifts={[ROSE, HAT]} balance={1000} onSend={() => {}} />);
    const warm = screen.getByTestId("gift-warmup");
    expect(warm.querySelector("img")?.getAttribute("src") ?? "").toContain("rose/512");
    expect(warm.style.opacity).toBe("0");
    fireEvent.click(screen.getByLabelText("Hat, 350 coins"));
    const next = screen.getByTestId("gift-warmup");
    expect(next.querySelector("img")?.getAttribute("src") ?? "").toContain("hat/512");
  });

  it("uses your own wording", () => {
    render(
      <GiftTray
        gifts={[ROSE]}
        balance={100}
        onSend={() => {}}
        title="Hediye gönder"
        sendLabel="Gönder"
        coinName="jeton"
      />,
    );
    expect(screen.getByText("Hediye gönder")).toBeTruthy();
    expect(screen.getByTestId("gift-send").textContent).toBe("Gönder");
    expect(screen.getByLabelText("Rose, 10 jeton")).toBeTruthy();
  });
});

describe("GiftEffectLayer", () => {
  function mountLayer(props: Partial<React.ComponentProps<typeof GiftEffectLayer>> = {}) {
    const ref = createRef<GiftEffectLayerHandle>();
    render(<GiftEffectLayer ref={ref} reducedMotion={false} pictureWaitMs={0} {...props} />);
    return ref;
  }
  const play = (ref: React.RefObject<GiftEffectLayerHandle | null>, e: ReturnType<typeof event>) =>
    act(() => ref.current!.play(e));

  it("picks the effect by the gift's price", async () => {
    const ref = mountLayer();
    await advance(10);
    play(ref, event(ROSE));
    play(ref, event(HAT));
    play(ref, event(DRAGON));
    await advance(10);
    expect(screen.queryAllByTestId("gift-effect-small")).toHaveLength(1);
    expect(screen.queryAllByTestId("gift-effect-medium")).toHaveLength(1);
    expect(screen.queryAllByTestId("gift-effect-large")).toHaveLength(1);
  });

  it("uses your thresholds", async () => {
    const ref = mountLayer({ thresholds: { mediumFrom: 5, largeFrom: 20 } });
    await advance(10);
    play(ref, event(ROSE)); // 10: medium here
    play(ref, event(HAT)); // 350: large here
    await advance(10);
    expect(screen.queryAllByTestId("gift-effect-small")).toHaveLength(0);
    expect(screen.queryAllByTestId("gift-effect-medium")).toHaveLength(1);
    expect(screen.queryAllByTestId("gift-effect-large")).toHaveLength(1);
  });

  it("shows who sent what, and counts a combo from the same person", async () => {
    const ref = mountLayer();
    await advance(10);
    play(ref, event(ROSE, "ayla"));
    await advance(50);
    const notice = screen.getByTestId("gift-notice");
    expect(notice.textContent).toContain("ayla");
    expect(notice.textContent).toContain("sent Rose");
    expect(screen.queryByTestId("gift-combo")).toBeNull();
    play(ref, event(ROSE, "ayla"));
    play(ref, event(ROSE, "ayla"));
    await advance(50);
    expect(screen.getByTestId("gift-combo").textContent).toBe("x3");
    // Someone else sending the same gift starts a new run.
    play(ref, event(ROSE, "mert"));
    await advance(50);
    expect(screen.getAllByTestId("gift-notice")).toHaveLength(2);
    expect(lastNotice().textContent).toContain("mert");
    expect(lastNotice().querySelector('[data-testid="gift-combo"]')).toBeNull();
    expect(screen.getAllByTestId("gift-combo")).toHaveLength(1);
  });

  it("stacks up to three lines, newest at the bottom, each on its own timer", async () => {
    const ref = mountLayer();
    await advance(10);
    play(ref, event(ROSE, "a"));
    await advance(1000);
    play(ref, event(ROSE, "b"));
    await advance(50);
    const names = () => screen.getAllByTestId("gift-notice").map((n) => n.textContent ?? "");
    expect(names()).toHaveLength(2);
    expect(names()[0]).toContain("a");
    expect(names()[1]).toContain("b");
    // Same sender and gift updates its line in place.
    play(ref, event(ROSE, "b"));
    await advance(50);
    expect(names()).toHaveLength(2);
    expect(screen.getAllByTestId("gift-combo")).toHaveLength(1);
    // "a" expires first (2400 ms after its play), "b" stays.
    await advance(1400);
    await advance(300);
    expect(names()).toHaveLength(1);
    expect(names()[0]).toContain("b");
    // A fourth line drops the oldest.
    play(ref, event(ROSE, "c"));
    play(ref, event(ROSE, "d"));
    play(ref, event(ROSE, "e"));
    await advance(50);
    expect(names()).toHaveLength(3);
    expect(names()[0]).toContain("c");
    expect(names()[2]).toContain("e");
    act(() => ref.current!.clear());
    await advance(10);
    expect(screen.queryAllByTestId("gift-notice")).toHaveLength(0);
  });

  it("ends a combo after the window", async () => {
    const ref = mountLayer({ comboWindowMs: 1000 });
    await advance(10);
    play(ref, event(ROSE));
    await advance(1500);
    play(ref, event(ROSE));
    await advance(50);
    expect(screen.queryByTestId("gift-combo")).toBeNull();
  });

  it("plays large gifts one at a time, in the order they came", async () => {
    const ended: string[] = [];
    const ref = mountLayer({ onEffectEnd: (e) => ended.push(e.gift.id) });
    await advance(10);
    play(ref, event(DRAGON));
    play(ref, event(DRAGON2));
    await advance(50);
    expect(screen.queryAllByTestId("gift-effect-large")).toHaveLength(1);
    expect(ended).toEqual([]);
    await advance(5000);
    expect(ended).toEqual(["dragon"]);
    expect(screen.queryAllByTestId("gift-effect-large")).toHaveLength(1);
    await advance(5000);
    expect(ended).toEqual(["dragon", "lion"]);
    expect(screen.queryAllByTestId("gift-effect-large")).toHaveLength(0);
  });

  it("keeps the queue of large gifts short, dropping the oldest", async () => {
    const ended: string[] = [];
    const ref = mountLayer({ onEffectEnd: (e) => ended.push(e.gift.id) });
    await advance(10);
    for (let i = 0; i < 9; i++) play(ref, event(gift(`big${i}`, 50_000)));
    // Step by step: React only renders the next queued gift between steps.
    for (let i = 0; i < 120; i++) await advance(500);
    // One running + at most five waiting; the oldest waiting ones were dropped.
    expect(ended).toHaveLength(6);
    expect(ended[0]).toBe("big0");
    expect(ended).toContain("big8");
    expect(ended).not.toContain("big1");
  });

  it("limits how many small gifts float at once", async () => {
    const ref = mountLayer();
    await advance(10);
    for (let i = 0; i < 20; i++) play(ref, event(ROSE, `u${i}`));
    await advance(10);
    expect(screen.queryAllByTestId("gift-effect-small").length).toBeLessThanOrEqual(6);
    // The notice stack holds at most three lines, the latest at the bottom.
    expect(screen.getAllByTestId("gift-notice")).toHaveLength(3);
    expect(lastNotice().textContent).toContain("u19");
  });

  it("with reduced motion shows only the notice", async () => {
    const ref = mountLayer({ reducedMotion: true });
    await advance(10);
    play(ref, event(DRAGON));
    await advance(50);
    expect(screen.queryAllByTestId("gift-effect-large")).toHaveLength(0);
    expect(screen.getByTestId("gift-notice").textContent).toContain("sent Dragon");
  });

  it("low quality still shows the gift", async () => {
    const ref = mountLayer({ quality: "low" });
    await advance(10);
    play(ref, event(DRAGON));
    await advance(50);
    expect(screen.queryAllByTestId("gift-effect-large")).toHaveLength(1);
  });

  it("clear stops everything and forgets the queue", async () => {
    const ended: string[] = [];
    const ref = mountLayer({ onEffectEnd: (e) => ended.push(e.gift.id) });
    await advance(10);
    play(ref, event(DRAGON));
    play(ref, event(DRAGON2));
    await advance(100);
    act(() => ref.current!.clear());
    await advance(20_000);
    expect(screen.queryAllByTestId("gift-effect-large")).toHaveLength(0);
    expect(ended).toEqual([]);
  });

  it("cancel takes back a gift that is playing, and the next large one starts", async () => {
    const ended: string[] = [];
    const ref = mountLayer({ onEffectEnd: (e) => ended.push(e.gift.id) });
    await advance(10);
    const first = ref.current!.play(event(DRAGON));
    ref.current!.play(event(DRAGON2));
    await advance(50);
    expect(screen.queryAllByTestId("gift-effect-large")).toHaveLength(1);
    act(() => ref.current!.cancel(first));
    await advance(50);
    // The first is gone at once and not reported as finished; the waiting one took its place.
    expect(screen.queryAllByTestId("gift-effect-large")).toHaveLength(1);
    expect(ended).toEqual([]);
    await advance(5000);
    expect(ended).toEqual(["lion"]);
  });

  it("cancel also removes a gift that is still waiting in the queue", async () => {
    const ended: string[] = [];
    const ref = mountLayer({ onEffectEnd: (e) => ended.push(e.gift.id) });
    await advance(10);
    ref.current!.play(event(DRAGON));
    const waiting = ref.current!.play(event(DRAGON2));
    act(() => ref.current!.cancel(waiting));
    for (let i = 0; i < 20; i++) await advance(500);
    expect(ended).toEqual(["dragon"]);
  });

  it("cancel hides the notice of the gift it took back, not another gift's", async () => {
    const ref = mountLayer();
    await advance(10);
    let rose = 0;
    act(() => {
      rose = ref.current!.play(event(ROSE, "ayla"));
    });
    await advance(600);
    expect(screen.getByTestId("gift-notice").style.opacity).toBe("1");
    act(() => ref.current!.cancel(rose));
    await advance(100);
    expect(screen.getByTestId("gift-notice").style.opacity).not.toBe("1");
    await advance(600);
    expect(screen.queryAllByTestId("gift-notice")).toHaveLength(0);

    let older = 0;
    act(() => {
      older = ref.current!.play(event(ROSE, "mert"));
      ref.current!.play(event(HAT, "zeynep"));
    });
    await advance(600);
    act(() => ref.current!.cancel(older)); // an older gift: the newer notice stays
    await advance(600);
    expect(screen.getAllByTestId("gift-notice")).toHaveLength(2);
    expect(lastNotice().textContent).toContain("zeynep");
    expect(lastNotice().style.opacity).toBe("1");
  });

  it("a notice for a new gift shows the new picture, not the previous one", async () => {
    const ref = mountLayer();
    await advance(10);
    act(() => void ref.current!.play(event(ROSE, "ayla")));
    await advance(100);
    const before = screen.getByTestId("gift-notice").querySelector("img");
    act(() => void ref.current!.play(event(HAT, "ayla")));
    await advance(100);
    const after = lastNotice().querySelector("img");
    expect(after?.getAttribute("src")).toContain("hat");
    // A new element, so a phone cannot keep drawing the old bitmap while it loads the new one.
    expect(after).not.toBe(before);
  });

  it("shows the gift at once, in step with the notice, not fading in over a fifth of a second", async () => {
    const ref = mountLayer();
    await advance(10);
    for (const g of [ROSE, HAT, DRAGON]) {
      act(() => void ref.current!.play(event(g)));
      await advance(70);
      const tier = g.price >= 10_000 ? "large" : g.price >= 100 ? "medium" : "small";
      const effect = screen.getByTestId("gift-effect-" + tier);
      const picture = effect.lastElementChild as HTMLElement;
      expect(Number(picture.style.opacity), g.id).toBeGreaterThanOrEqual(0.9);
      act(() => ref.current!.clear());
    }
  });

  it("the notice uses the small icon when one is given, not the big picture", async () => {
    const ref = mountLayer();
    await advance(10);
    act(
      () =>
        void ref.current!.play({
          gift: {
            id: "rose",
            name: "Rose",
            price: 10,
            image: "https://x/rose/512.webp",
            icon: "https://x/rose/256.webp",
          },
          sender: "ayla",
        }),
    );
    await advance(100);
    const img = screen.getByTestId("gift-notice").querySelector("img");
    expect(img?.getAttribute("src")).toContain("256");
  });

  it("waits for the picture, then starts the effect and its notice together", async () => {
    // jsdom never loads pictures, so this runs into the wait limit, like a slow network would.
    const ref = mountLayer({ pictureWaitMs: 300 });
    await advance(10);
    act(() => void ref.current!.play(event(DRAGON)));
    await advance(150);
    const effect = screen.getByTestId("gift-effect-large");
    const picture = effect.lastElementChild as HTMLElement;
    // Nothing yet: no half-shown gift, no notice running ahead of it.
    expect(Number(picture.style.opacity)).toBe(0);
    expect(screen.queryByTestId("gift-notice")).toBeNull();
    await advance(200); // the wait runs out at 300 ms
    await advance(450); // the effect has started and the notice slid in
    expect(Number(picture.style.opacity)).toBeGreaterThanOrEqual(0.9);
    expect(screen.getByTestId("gift-notice").style.opacity).toBe("1");
  });

  it("a queued large gift shows its notice when its own effect starts, not when it was sent", async () => {
    const ref = mountLayer();
    await advance(10);
    act(() => {
      ref.current!.play(event(DRAGON, "ayla"));
      ref.current!.play(event(DRAGON2, "mert"));
    });
    await advance(500);
    expect(screen.getByTestId("gift-notice").textContent).toContain("ayla");
    for (let i = 0; i < 10; i++) await advance(500);
    expect(screen.getByTestId("gift-notice").textContent).toContain("mert");
  });

  it("never takes touches away from the screen below", () => {
    mountLayer();
    expect(getComputedStyle(screen.getByTestId("gift-effect-layer")).pointerEvents).toBe("none");
  });
});

function fakeClient(over: Partial<GiftingClient> = {}): GiftingClient {
  return {
    getGifts: vi.fn(async () => [HAT, ROSE]),
    getMe: vi.fn(async () => ({ user: "ayla", balance: 1000 })),
    getReceivedGifts: vi.fn(async () => []),
    ...componentCallStubs,
    sendGift: vi.fn(
      async (input) =>
        ({
          id: "gtx_1",
          sender: "ayla",
          receiver: input.receiver,
          gift: { id: input.giftId, name: input.giftId, icon_url: null },
          quantity: 1,
          unit_price: 10,
          total: 10,
          message: null,
          reference: input.reference ?? null,
          status: "completed",
          created_at: "2026-10-10T00:00:00.000Z",
          sender_balance_after: 990,
        }) satisfies GiftTransaction,
    ),
    ...over,
  };
}

function Harness({
  client,
  effects,
  probe,
}: {
  client: GiftingClient;
  effects?: React.RefObject<GiftEffectLayerHandle | null>;
  probe: (t: ReturnType<typeof useGiftTray>) => void;
}) {
  const tray = useGiftTray({ client, receiver: "mert", reference: "post_1", effects });
  probe(tray);
  return null;
}

describe("test mode badge", () => {
  it("GiftTray shows it only with testMode, with your label", () => {
    const { rerender } = render(<GiftTray gifts={[ROSE]} balance={10} onSend={() => {}} />);
    expect(screen.queryByTestId("gift-test-mode")).toBeNull();
    rerender(<GiftTray gifts={[ROSE]} balance={10} onSend={() => {}} testMode />);
    expect(screen.getByTestId("gift-test-mode").textContent).toBe("Test mode");
    rerender(
      <GiftTray gifts={[ROSE]} balance={10} onSend={() => {}} testMode testModeLabel="Deneme" />,
    );
    expect(screen.getByTestId("gift-test-mode").textContent).toBe("Deneme");
  });

  it("GiftTray takes the badge, gifts, balance and send from `tray` without a testMode prop", () => {
    const send = vi.fn(async () => {});
    const tray = { gifts: [ROSE], balance: 10, send, testMode: true };
    const { rerender } = render(<GiftTray tray={tray} />);
    expect(screen.getByTestId("gift-test-mode").textContent).toBe("Test mode");
    fireEvent.click(screen.getByTestId("gift-send"));
    expect(send).toHaveBeenCalledWith(ROSE);
    // `false` forces it off, `true` forces it on without a tray, an own onSend wins.
    rerender(<GiftTray tray={tray} testMode={false} />);
    expect(screen.queryByTestId("gift-test-mode")).toBeNull();
    rerender(<GiftTray tray={{ ...tray, testMode: false }} />);
    expect(screen.queryByTestId("gift-test-mode")).toBeNull();
    rerender(<GiftTray tray={{ ...tray, testMode: false }} testMode />);
    expect(screen.getByTestId("gift-test-mode")).toBeTruthy();
    const own = vi.fn();
    rerender(<GiftTray tray={tray} onSend={own} />);
    fireEvent.click(screen.getByTestId("gift-send"));
    expect(own).toHaveBeenCalledWith(ROSE);
  });

  it("useGiftTray + GiftTray(tray): a test key shows the badge by itself", async () => {
    for (const [livemode, shown] of [
      [false, true],
      [true, false],
      [undefined, false],
    ] as const) {
      const client = fakeClient({
        getGifts: vi.fn(async () => [ROSE]),
        getMe: vi.fn(async () => ({ user: "ayla", balance: 50, livemode })),
      });
      function Screen() {
        const tray = useGiftTray({ client, receiver: "mert" });
        return <GiftTray tray={tray} />;
      }
      render(<Screen />);
      expect(screen.queryByTestId("gift-test-mode")).toBeNull();
      await advance(10);
      expect(screen.queryByTestId("gift-test-mode") !== null, `livemode ${livemode}`).toBe(shown);
      cleanup();
    }
  });

  it("useGiftTray: testMode follows me.livemode (absent = not test mode)", async () => {
    for (const [me, expected] of [
      [{ user: "ayla", balance: 1, livemode: false }, true],
      [{ user: "ayla", balance: 1, livemode: true }, false],
      [{ user: "ayla", balance: 1 }, false],
    ] as const) {
      let last!: ReturnType<typeof useGiftTray>;
      const client = fakeClient({ getMe: vi.fn(async () => me) });
      render(<Harness client={client} probe={(t) => (last = t)} />);
      expect(last.testMode).toBe(false);
      await advance(10);
      expect(last.testMode).toBe(expected);
      cleanup();
    }
  });
});

describe("useGiftTray", () => {
  it("open, close, toggle and isOpen (spec 9.4); open: false starts closed", async () => {
    let last!: ReturnType<typeof useGiftTray>;
    const changes: boolean[] = [];
    const Closed = () => {
      last = useGiftTray({
        client: fakeClient(),
        receiver: "mert",
        open: false,
        onOpenChange: (o) => changes.push(o),
      });
      return null;
    };
    render(<Closed />);
    expect(last.isOpen).toBe(false);
    act(() => last.toggle());
    expect(last.isOpen).toBe(true);
    act(() => last.toggle());
    expect(last.isOpen).toBe(false);
    act(() => last.close());
    act(() => last.open());
    act(() => last.open());
    expect(last.isOpen).toBe(true);
    expect(changes).toEqual([true, false, true]);
  });

  it("is open by default (a tray you render is shown)", async () => {
    let last!: ReturnType<typeof useGiftTray>;
    render(<Harness client={fakeClient()} probe={(t) => (last = t)} />);
    expect(last.isOpen).toBe(true);
  });

  it("loads the catalog in your sort order and the balance", async () => {
    const client = fakeClient({
      getGifts: vi.fn(async () => [
        gift("b", 5, { sort_order: 2 }),
        gift("a", 9, { sort_order: 1 }),
      ]),
    });
    let last!: ReturnType<typeof useGiftTray>;
    render(<Harness client={client} probe={(t) => (last = t)} />);
    expect(last.loading).toBe(true);
    await advance(10);
    expect(last.loading).toBe(false);
    expect(last.gifts.map((g) => g.id)).toEqual(["a", "b"]);
    expect(last.balance).toBe(1000);
    expect(last.user).toBe("ayla");
  });

  it("downloads the icons of the catalog as soon as it is loaded, the big pictures lazily", async () => {
    const spy = vi.spyOn(Image, "prefetch").mockResolvedValue(true);
    const client = fakeClient();
    render(<Harness client={client} probe={() => {}} />);
    await advance(10);
    const urls = spy.mock.calls.map((c) => c[0]);
    for (const g of [HAT, ROSE]) {
      expect(urls).toContain(g.icon_url);
      expect(urls).not.toContain(g.animation_url);
    }
    spy.mockRestore();
  });

  it("GiftTray warms only the selected gift's big picture", async () => {
    const spy = vi.spyOn(Image, "prefetch").mockResolvedValue(true);
    render(
      <GiftTray gifts={[ROSE, HAT]} balance={1000} onSend={() => {}} defaultSelectedId="hat" />,
    );
    await advance(10);
    const urls = spy.mock.calls.map((c) => c[0]);
    expect(urls).toContain(HAT.animation_url);
    expect(urls).not.toContain(ROSE.animation_url);
    expect(urls).toContain(ROSE.icon_url);
    expect(urls).toContain(HAT.icon_url);
    spy.mockRestore();
  });

  it("a refused picture URL is never requested and draws the placeholder", () => {
    const spy = vi.spyOn(Image, "prefetch").mockResolvedValue(true);
    const bad = gift("bad", 5, {
      icon_url: "javascript:alert(1)",
      animation_url: "http://assets.example.com/512.webp",
    });
    render(<GiftTray gifts={[bad]} balance={10} onSend={() => {}} />);
    expect(spy).not.toHaveBeenCalled();
    expect(screen.queryByTestId("gift-warmup")).toBeNull();
    spy.mockRestore();
  });

  it("reports a load failure and recovers on refresh", async () => {
    let fail = true;
    const client = fakeClient({
      getGifts: vi.fn(async () => {
        if (fail) throw new GiftingError(0, "network_error", "offline");
        return [ROSE];
      }),
    });
    let last!: ReturnType<typeof useGiftTray>;
    render(<Harness client={client} probe={(t) => (last = t)} />);
    await advance(10);
    expect(last.error?.type).toBe("network_error");
    fail = false;
    await act(async () => {
      await last.refresh();
    });
    expect(last.error).toBeNull();
    expect(last.gifts).toHaveLength(1);
  });

  /** A stand-in layer that records what the hook shows and takes back. */
  function stubLayer() {
    const played: {
      gift: { id: string; icon?: string | null; image?: string | null };
      sender?: string;
      quantity?: number;
    }[] = [];
    const cancelled: number[] = [];
    const layer = {
      current: {
        play: (e: (typeof played)[number]) => played.push(e),
        cancel: (id: number) => cancelled.push(id),
        clear: () => {},
      },
    } as React.RefObject<GiftEffectLayerHandle | null>;
    return { layer, played, cancelled };
  }

  function slowClient(delayMs: number, over: Partial<GiftingClient> = {}) {
    return fakeClient({
      sendGift: vi.fn(async (input) => {
        await new Promise((r) => setTimeout(r, delayMs));
        return {
          id: "gtx_1",
          sender: "ayla",
          receiver: input.receiver,
          gift: { id: input.giftId, name: input.giftId, icon_url: null },
          quantity: 1,
          unit_price: 10,
          total: 10,
          message: null,
          reference: input.reference ?? null,
          status: "completed" as const,
          created_at: "2026-10-10T00:00:00.000Z",
          sender_balance_after: 990,
        };
      }),
      ...over,
    });
  }

  function mountTray(
    client: GiftingClient,
    layer: React.RefObject<GiftEffectLayerHandle | null>,
    extra: { playOn?: "tap" | "success"; onSent?: () => void } = {},
  ) {
    const box = {} as { tray: ReturnType<typeof useGiftTray> };
    function Probe() {
      box.tray = useGiftTray({
        client,
        receiver: "mert",
        reference: "post_1",
        effects: layer,
        ...extra,
      });
      return null;
    }
    render(<Probe />);
    return box;
  }

  it("takes the coins at once and plays the effect at the tap, before the server answers", async () => {
    const client = slowClient(300);
    const { layer, played } = stubLayer();
    const onSent = vi.fn();
    const box = mountTray(client, layer, { onSent });
    await advance(10);
    let pending!: Promise<void>;
    act(() => {
      pending = box.tray.send(ROSE);
    });
    expect(box.tray.balance).toBe(990); // coins taken before the server answered
    expect(played).toHaveLength(1); // and the gift already showing
    expect(played[0]).toMatchObject({
      gift: { id: "rose", icon: ROSE.icon_url, image: ROSE.animation_url },
      sender: "ayla",
      quantity: 1,
    });
    expect(onSent).not.toHaveBeenCalled();
    await advance(400);
    await act(async () => {
      await pending;
    });
    expect(played).toHaveLength(1); // not shown a second time
    expect(onSent).toHaveBeenCalledTimes(1);
    expect(client.sendGift).toHaveBeenCalledWith({
      receiver: "mert",
      giftId: "rose",
      reference: "post_1",
    });
  });

  it("with playOn success waits for the server before showing the gift", async () => {
    const client = slowClient(300);
    const { layer, played } = stubLayer();
    const box = mountTray(client, layer, { playOn: "success" });
    await advance(10);
    let pending!: Promise<void>;
    act(() => {
      pending = box.tray.send(ROSE);
    });
    expect(played).toHaveLength(0);
    await advance(400);
    await act(async () => {
      await pending;
    });
    expect(played).toHaveLength(1);
    expect(played[0]).toMatchObject({ gift: { id: "rose" }, sender: "ayla", quantity: 1 });
  });

  it("takes back a gift it showed early when the send fails, and gives the coins back", async () => {
    const onError = vi.fn();
    // The balance lookup that follows a send also fails, so only the refund can fix the number.
    let meCalls = 0;
    const client = fakeClient({
      getMe: vi.fn(async () => {
        if (++meCalls > 1) throw new GiftingError(0, "network_error", "offline");
        return { user: "ayla", balance: 1000 };
      }),
      sendGift: vi.fn(async () => {
        throw new GiftingError(422, "insufficient_balance", "no coins", "req_1");
      }),
    });
    const { layer, played, cancelled } = stubLayer();
    let last!: ReturnType<typeof useGiftTray>;
    function Probe() {
      last = useGiftTray({ client, receiver: "mert", effects: layer, onError });
      return null;
    }
    render(<Probe />);
    await advance(10);
    await act(async () => {
      await last.send(DRAGON);
    });
    expect(last.balance).toBe(1000);
    expect(played).toHaveLength(1); // it was shown at the tap...
    expect(cancelled).toHaveLength(1); // ...and taken back
    expect(last.error?.insufficientBalance).toBe(true);
    expect(onError).toHaveBeenCalledTimes(1);
  });

  it("with playOn success a failed send shows nothing and cancels nothing", async () => {
    const client = fakeClient({
      sendGift: vi.fn(async () => {
        throw new GiftingError(422, "insufficient_balance", "no coins");
      }),
    });
    const { layer, played, cancelled } = stubLayer();
    const box = mountTray(client, layer, { playOn: "success" });
    await advance(10);
    await act(async () => {
      await box.tray.send(DRAGON);
    });
    expect(played).toHaveLength(0);
    expect(cancelled).toHaveLength(0);
  });

  it("keeps the number right while the person taps fast, then trusts the server", async () => {
    let serverBalance = 1000;
    const client = fakeClient({
      sendGift: vi.fn(async (input) => {
        serverBalance -= 10;
        return {
          id: "gtx_x",
          sender: "ayla",
          receiver: input.receiver,
          gift: { id: input.giftId, name: "Rose", icon_url: null },
          quantity: 1,
          unit_price: 10,
          total: 10,
          message: null,
          reference: null,
          status: "completed" as const,
          created_at: "2026-10-10T00:00:00.000Z",
          sender_balance_after: serverBalance,
        };
      }),
      getMe: vi.fn(async () => ({ user: "ayla", balance: serverBalance })),
    });
    let last!: ReturnType<typeof useGiftTray>;
    render(<Harness client={client} probe={(t) => (last = t)} />);
    await advance(10);
    await act(async () => {
      await Promise.all([
        last.send(ROSE),
        last.send(ROSE),
        last.send(ROSE),
        last.send(ROSE),
        last.send(ROSE),
      ]);
    });
    await advance(10);
    expect(client.sendGift).toHaveBeenCalledTimes(5);
    expect(last.balance).toBe(950);
    expect(client.getMe).toHaveBeenCalledTimes(2); // once on load, once after the burst
  });

  it("does not touch state after the screen is gone", async () => {
    const client = fakeClient({
      getGifts: vi.fn(async () => {
        await new Promise((r) => setTimeout(r, 500));
        return [ROSE];
      }),
    });
    const err = vi.spyOn(console, "error").mockImplementation(() => {});
    const { unmount } = render(<Harness client={client} probe={() => {}} />);
    unmount();
    await advance(1000);
    expect(err).not.toHaveBeenCalled();
    err.mockRestore();
  });
});

describe("pictures", () => {
  it("every Image turns off Android's 300 ms fade-in, which made gifts appear late", async () => {
    const { readdirSync, readFileSync } = await import("node:fs");
    const { join } = await import("node:path");
    const dir = join(process.cwd(), "src", "react-native");
    let images = 0;
    let faded = 0;
    for (const file of readdirSync(dir).filter((f) => f.endsWith(".tsx"))) {
      const source = readFileSync(join(dir, file), "utf8");
      images += (source.match(/<Image\b/g) ?? []).length;
      faded += (source.match(/fadeDuration=\{0\}/g) ?? []).length;
    }
    expect(images).toBeGreaterThan(0);
    expect(faded).toBe(images);
  });
});
