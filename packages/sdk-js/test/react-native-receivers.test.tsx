/**
 * React Native: one gift button for a battle (spec 21) on react-native-web in jsdom: the tray's
 * "Send to" row from `useGiftTray({ receivers })` and the battle bar's tappable sides.
 */
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { AccessibilityInfo } from "react-native";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type Gift,
  type GiftTransaction,
  type GiftingClient,
  type RoomBattle,
  battleView,
} from "../src/core";
import {
  BattleBar,
  GiftTray,
  type TrayReceiver,
  type UseGiftTray,
  useGiftTray,
} from "../src/react-native";
import { componentCallStubs } from "./stub-client";

const gift = (id: string, price: number): Gift => ({
  id,
  name: id.toUpperCase(),
  description: null,
  price,
  icon_url: null,
  animation_url: null,
  sort_order: 0,
});
const GIFTS = [gift("rose", 10)];
const SIDES: TrayReceiver[] = [
  { id: "mia", name: "Mia", color: "#ff4fa3" },
  { id: "theo", name: "Theo", color: "#ffd27a" },
];

function fakeClient() {
  const sendGift = vi.fn(
    async (input: { receiver: string; giftId: string }) =>
      ({
        id: "gtx_1",
        sender: "ayla",
        receiver: input.receiver,
        gift: { id: input.giftId, name: input.giftId, icon_url: null },
        quantity: 1,
        unit_price: 10,
        total: 10,
        message: null,
        reference: null,
        status: "completed",
        created_at: "2026-11-13T00:00:00.000Z",
        sender_balance_after: 990,
      }) satisfies GiftTransaction,
  );
  const client = {
    getGifts: vi.fn(async () => GIFTS),
    getMe: vi.fn(async () => ({ user: "ayla", balance: 1000 })),
    getReceivedGifts: vi.fn(async () => []),
    ...componentCallStubs,
    sendGift,
  } as unknown as GiftingClient;
  return { client, sendGift };
}

beforeEach(() => {
  vi.spyOn(AccessibilityInfo, "isReduceMotionEnabled").mockResolvedValue(false);
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const flush = () => act(async () => await new Promise((r) => setTimeout(r, 10)));

function Battle(props: {
  client: GiftingClient;
  receivers?: TrayReceiver[];
  probe: (t: UseGiftTray) => void;
  onReceiverChange?: (id: string | null) => void;
}) {
  const tray = useGiftTray({
    client: props.client,
    receiver: "mia",
    receivers: props.receivers,
    onReceiverChange: props.onReceiverChange,
  });
  props.probe(tray);
  return <GiftTray tray={tray} sheet={false} />;
}

describe("useGiftTray({ receivers }) + GiftTray (spec 21)", () => {
  it("no receivers: no row; one receiver: no row", async () => {
    const { client } = fakeClient();
    let last!: UseGiftTray;
    const { rerender } = render(<Battle client={client} probe={(t) => (last = t)} />);
    await flush();
    expect(screen.queryByTestId("gift-receivers")).toBeNull();
    expect(last.receiver).toBe("mia");
    rerender(<Battle client={client} receivers={[SIDES[1]!]} probe={(t) => (last = t)} />);
    expect(screen.queryByTestId("gift-receivers")).toBeNull();
    expect(last.receiver).toBe("theo");
  });

  it("two sides: a radio row; a tap picks, the send goes there, and it stays the default", async () => {
    const { client, sendGift } = fakeClient();
    const changes: (string | null)[] = [];
    let last!: UseGiftTray;
    const [c] = [client];
    const Holder = () => {
      const [list] = useState(SIDES);
      return (
        <Battle
          client={c}
          receivers={list}
          probe={(t) => (last = t)}
          onReceiverChange={(id) => changes.push(id)}
        />
      );
    };
    render(<Holder />);
    await flush();
    expect(screen.getByTestId("gift-receivers")).toBeTruthy();
    const theo = screen.getByTestId("gift-receiver-theo");
    expect(theo.getAttribute("aria-label")).toBe("Theo");
    expect(screen.getByTestId("gift-receiver-mia").getAttribute("aria-checked")).toBe("true");
    fireEvent.click(theo);
    expect(last.receiver).toBe("theo");
    expect(theo.getAttribute("aria-checked")).toBe("true");
    await act(async () => {
      await last.send(GIFTS[0]!);
    });
    expect(sendGift.mock.calls[0]![0]).toMatchObject({ receiver: "theo" });
    act(() => last.selectReceiver("nobody"));
    expect(last.receiver).toBe("theo");
    act(() => last.selectReceiver("mia"));
    expect(changes).toEqual(["theo", "mia"]);
  });
});

describe("BattleBar onPressSide (spec 21.4)", () => {
  const round: RoomBattle = {
    round: "r1",
    started: 0,
    ends: 60_000,
    scores: [
      { id: "mia", units: 3, gifts: 1 },
      { id: "theo", units: 1, gifts: 1 },
    ],
  };

  it("without it: no buttons", () => {
    render(<BattleBar view={battleView(round, 1_000)} reducedMotion />);
    expect(screen.queryByTestId("battle-side-mia")).toBeNull();
  });

  it("with it: each avatar is a labelled button reporting its side", () => {
    const pressed: string[] = [];
    render(
      <BattleBar
        view={battleView(round, 1_000)}
        reducedMotion
        users={{ theo: { name: "Theo" } }}
        onPressSide={(id) => pressed.push(id)}
      />,
    );
    const theo = screen.getByTestId("battle-side-theo");
    expect(theo.getAttribute("aria-label")).toBe("Send Theo a gift");
    fireEvent.click(theo);
    expect(pressed).toEqual(["theo"]);
  });
});

describe("the Send to row fits a phone and keeps the pick in sight (spec 21.3)", () => {
  it("only the picked side shows its name", async () => {
    const { client } = fakeClient();
    render(<Battle client={client} receivers={SIDES} probe={() => {}} />);
    await flush();
    expect(screen.getByTestId("gift-receiver-mia").textContent).toContain("Mia");
    expect(screen.getByTestId("gift-receiver-theo").textContent).not.toContain("Theo");
    fireEvent.click(screen.getByTestId("gift-receiver-theo"));
    expect(screen.getByTestId("gift-receiver-theo").textContent).toContain("Theo");
    expect(screen.getByTestId("gift-receiver-mia").textContent).not.toContain("Mia");
  });

  it("picking a side outside the row scrolls the row, not the page", async () => {
    class FakeResizeObserver {
      constructor(private cb: ResizeObserverCallback) {}
      observe(target: Element) {
        this.cb([{ target } as unknown as ResizeObserverEntry], this as unknown as ResizeObserver);
      }
      unobserve() {}
      disconnect() {}
    }
    vi.stubGlobal("ResizeObserver", FakeResizeObserver);
    const proto = HTMLElement.prototype;
    const id = (el: HTMLElement) => el.getAttribute("data-testid") ?? "";
    const saved = ["offsetLeft", "offsetWidth", "offsetHeight"].map(
      (k) => [k, Object.getOwnPropertyDescriptor(proto, k)] as const,
    );
    Object.defineProperty(proto, "offsetWidth", {
      configurable: true,
      get(this: HTMLElement) {
        if (id(this) === "gift-receivers") return 300;
        if (id(this).startsWith("gift-receiver-")) return 36;
        return 0;
      },
    });
    Object.defineProperty(proto, "offsetHeight", {
      configurable: true,
      get(this: HTMLElement) {
        return id(this).startsWith("gift-receiver") ? 34 : 0;
      },
    });
    Object.defineProperty(proto, "offsetLeft", {
      configurable: true,
      get(this: HTMLElement) {
        const m = /^gift-receiver-s(\d+)$/.exec(id(this));
        return m ? 58 + Number(m[1]) * 44 : 0;
      },
    });
    const pageScroll = vi.fn();
    window.scrollTo = pageScroll as typeof window.scrollTo;
    try {
      const many: TrayReceiver[] = Array.from({ length: 8 }, (_, i) => ({
        id: `s${i}`,
        name: `Side ${i}`,
      }));
      const { client } = fakeClient();
      let last!: UseGiftTray;
      render(<Battle client={client} receivers={many} probe={(t) => (last = t)} />);
      await flush();
      const row = screen.getByTestId("gift-receivers");
      const scrolls = vi.spyOn(row as unknown as { scrollTo: (o: unknown) => void }, "scrollTo");
      act(() => last.selectReceiver("s7")); // 58 + 7 * 44 = 366 .. 402: past 300
      await flush();
      const calls = (scrolls.mock.calls as unknown[][]).map((c) => c[0]);
      const left = row.scrollLeft || (calls.at(-1) as { left?: number } | undefined)?.left;
      expect(left).toBe(102);
      expect(pageScroll).not.toHaveBeenCalled();
    } finally {
      for (const [k, d] of saved)
        if (d) Object.defineProperty(proto, k, d);
        else delete (proto as unknown as Record<string, unknown>)[k];
      vi.unstubAllGlobals();
    }
  });
});
