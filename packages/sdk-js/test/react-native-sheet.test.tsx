/**
 * React Native GiftTray as a bottom sheet (spec 9.1), on react-native-web in jsdom. The sizes the
 * sheet measures with onLayout are stubbed per testID: container 780, block above the grid 58,
 * one row 91, footer 70 -> peek 128, default 310, expanded 401 (12 gifts, three rows).
 * Real touch feel and native nested scrolling still need a phone.
 */
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { AccessibilityInfo } from "react-native";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Gift, SheetSnap } from "../src/core";
import { createRef } from "react";
import { GiftTray, type GiftTrayHandle } from "../src/react-native";

const gift = (id: string, price: number): Gift => ({
  id,
  name: id.toUpperCase(),
  description: null,
  price,
  icon_url: `https://assets.test/${id}/256.webp`,
  animation_url: `https://assets.test/${id}/512.webp`,
  sort_order: 0,
});
const GIFTS = Array.from({ length: 12 }, (_, i) => gift(`g${i}`, 10 * (i + 1)));

const HEIGHTS: Record<string, number> = { "gift-sheet": 780, "gift-footer": 70, "gift-g0": 91 };
const TOPS: Record<string, number> = { "gift-grid": 58 };

function installSheetLayout(): () => void {
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
  const saved = {
    h: Object.getOwnPropertyDescriptor(proto, "offsetHeight"),
    t: Object.getOwnPropertyDescriptor(proto, "offsetTop"),
  };
  const id = (el: HTMLElement) => el.getAttribute("data-testid") ?? "";
  Object.defineProperty(proto, "offsetHeight", {
    configurable: true,
    get(this: HTMLElement) {
      return HEIGHTS[id(this)] ?? 0;
    },
  });
  Object.defineProperty(proto, "offsetTop", {
    configurable: true,
    get(this: HTMLElement) {
      return TOPS[id(this)] ?? 0;
    },
  });
  return () => {
    if (saved.h) Object.defineProperty(proto, "offsetHeight", saved.h);
    if (saved.t) Object.defineProperty(proto, "offsetTop", saved.t);
    vi.unstubAllGlobals();
  };
}

let restore = () => {};
beforeEach(() => {
  restore = installSheetLayout();
  // react-native-web reports reduced motion when matchMedia is missing (jsdom): say no.
  vi.spyOn(AccessibilityInfo, "isReduceMotionEnabled").mockResolvedValue(false);
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
  vi.restoreAllMocks();
  restore();
});

async function advance(ms: number) {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(ms);
  });
}

const handle = () => screen.getByTestId("gift-handle");
const translateY = () => {
  const m = /translateY\(([-\d.]+)px\)/.exec(screen.getByTestId("gift-tray").style.transform);
  return m ? Number(m[1]) : NaN;
};

async function mount(props: Partial<Parameters<typeof GiftTray>[0]> = {}) {
  const snaps: SheetSnap[] = [];
  const insets: number[] = [];
  render(
    <GiftTray
      gifts={GIFTS}
      balance={1000}
      onSend={() => {}}
      onSnapChange={(s) => snaps.push(s)}
      onInsetChange={(px) => insets.push(px)}
      {...props}
    />,
  );
  await advance(10); // onLayout runs a tick after mounting
  return { snaps, insets };
}

describe("GiftTray sheet (React Native)", () => {
  it("is a sheet by default: handle, moving body, fixed footer with the selected gift", async () => {
    await mount();
    expect(handle().getAttribute("aria-expanded")).toBe("true");
    expect(screen.getByTestId("gift-footer").textContent).toContain("G0");
    expect(screen.getByTestId("gift-footer").contains(screen.getByTestId("gift-send"))).toBe(true);
  });

  it("measures its content and opens in default; the inset is the visible height", async () => {
    const { insets } = await mount();
    expect(insets[insets.length - 1]).toBe(310);
    await advance(1000);
    expect(translateY()).toBeCloseTo(91, 1); // expanded 401 - default 310
  });

  it("a tap on the handle toggles default <-> peek with a spring on translateY", async () => {
    const { snaps, insets } = await mount();
    await advance(1000);
    fireEvent.click(handle());
    await advance(1000);
    expect(snaps).toEqual(["peek"]);
    expect(insets[insets.length - 1]).toBe(128);
    expect(handle().getAttribute("aria-expanded")).toBe("false");
    expect(translateY()).toBeCloseTo(273, 1);
    fireEvent.click(handle());
    await advance(1000);
    expect(snaps).toEqual(["peek", "default"]);
    expect(translateY()).toBeCloseTo(91, 1);
  });

  it("collapseOnSelect: picking a gift lowers the sheet to peek; a ref can move it", async () => {
    const ref = createRef<GiftTrayHandle>();
    const { snaps } = await mount({ collapseOnSelect: true, ref });
    await advance(1000);
    fireEvent.click(screen.getByTestId("gift-g3"));
    await advance(1000);
    expect(snaps).toEqual(["peek"]);
    expect(screen.getByTestId("gift-footer").textContent).toContain("G3");
    act(() => ref.current!.snapTo("default"));
    await advance(1000);
    expect(snaps).toEqual(["peek", "default"]);
  });

  it("without collapseOnSelect picking a gift keeps the sheet where it is", async () => {
    const { snaps } = await mount();
    await advance(1000);
    fireEvent.click(screen.getByTestId("gift-g3"));
    await advance(1000);
    expect(snaps).toEqual([]);
  });

  it("the spring takes time (not a jump) and never animates height", async () => {
    await mount();
    await advance(1000);
    fireEvent.click(handle());
    await advance(40);
    const mid = translateY();
    expect(mid).toBeGreaterThan(91);
    expect(mid).toBeLessThan(273);
    expect(screen.getByTestId("gift-tray").parentElement!.style.height).toBe("401px");
  });

  it("reduced motion snaps at once", async () => {
    vi.spyOn(AccessibilityInfo, "isReduceMotionEnabled").mockResolvedValue(true);
    await mount();
    await advance(1000);
    fireEvent.click(handle());
    await advance(0);
    expect(translateY()).toBeCloseTo(273, 1);
  });

  it("initialSnap and snaps fractions", async () => {
    const { insets } = await mount({ initialSnap: "expanded", snaps: { expanded: 0.4 } });
    // 0.4 * 780 = 312, above default 310 and below the content: expanded is 312.
    expect(insets[insets.length - 1]).toBe(312);
  });

  it("arrow keys on the handle step the states (react-native-web)", async () => {
    const { snaps } = await mount();
    fireEvent.keyDown(handle(), { key: "ArrowUp" });
    fireEvent.keyDown(handle(), { key: "ArrowUp" });
    fireEvent.keyDown(handle(), { key: "ArrowDown" });
    expect(snaps).toEqual(["expanded", "default"]);
  });

  it("dragging the header moves the sheet and snaps on release", async () => {
    const { snaps, insets } = await mount();
    await advance(1000);
    const title = screen.getByText("Send a gift");
    const at = (y: number) => ({ clientX: 100, clientY: y, pageX: 100, pageY: y, buttons: 1 });
    fireEvent.mouseDown(title, at(500));
    await advance(16);
    fireEvent.mouseMove(title, at(470));
    await advance(16);
    fireEvent.mouseMove(title, at(450));
    expect(insets[insets.length - 1]).toBe(360); // 310 + 50: follows the pointer, slop included
    await advance(300); // rest, so the release has no speed
    fireEvent.mouseUp(title, at(450));
    await advance(1000);
    expect(snaps).toEqual(["expanded"]);
    expect(translateY()).toBeCloseTo(0, 1);
  });

  it("stays invisible until measured, then appears in place at once (no glide from a wrong spot)", async () => {
    render(<GiftTray gifts={GIFTS} balance={1000} onSend={() => {}} />);
    const root = () => screen.getByTestId("gift-tray").parentElement as HTMLElement;
    expect(root().style.opacity).toBe("0");
    await advance(10); // the layout arrives: default = 310 of 401, so the body sits 91 down
    expect(root().style.opacity).toBe("1");
    expect(translateY()).toBeCloseTo(91, 1);
    // Nothing moves afterwards: it was placed, not animated.
    await advance(16);
    expect(translateY()).toBeCloseTo(91, 1);
  });

  it("dragging the handle itself (a button) moves the sheet too, up and down", async () => {
    const { snaps } = await mount();
    await advance(1000);
    const grip = handle();
    const at = (y: number) => ({ clientX: 100, clientY: y, pageX: 100, pageY: y, buttons: 1 });
    // Up from default: expands.
    fireEvent.mouseDown(grip, at(500));
    await advance(16);
    fireEvent.mouseMove(grip, at(470));
    await advance(16);
    fireEvent.mouseMove(grip, at(430));
    await advance(300);
    fireEvent.mouseUp(grip, at(430));
    await advance(1000);
    expect(snaps).toEqual(["expanded"]);
    expect(translateY()).toBeCloseTo(0, 1);
    // Down from expanded: back to default.
    fireEvent.mouseDown(grip, at(430));
    await advance(16);
    fireEvent.mouseMove(grip, at(460));
    await advance(16);
    fireEvent.mouseMove(grip, at(500));
    await advance(300);
    fireEvent.mouseUp(grip, at(500));
    await advance(1000);
    expect(snaps).toEqual(["expanded", "default"]);
  });

  it("sheet={false} keeps the old fixed tray", async () => {
    await mount({ sheet: false });
    expect(screen.queryByTestId("gift-handle")).toBeNull();
    expect(screen.queryByTestId("gift-sheet")).toBeNull();
    expect(screen.getByTestId("gift-tray").contains(screen.getByTestId("gift-send"))).toBe(true);
  });
});

describe("GiftTray scrim, open and close (React Native, spec 9.4)", () => {
  const scrim = () => screen.queryByTestId("gift-scrim");
  const dimOpacity = () => Number(scrim()!.style.opacity);
  const takesTouches = () => getComputedStyle(scrim()!).pointerEvents !== "none";

  it("has no scrim unless asked", async () => {
    await mount();
    await advance(1000);
    expect(scrim()).toBeNull();
  });

  it("fades in over 200 ms once placed (0.4 black), takes touches while shown", async () => {
    await mount({ scrim: true });
    await advance(1000);
    expect(dimOpacity()).toBeCloseTo(0.4, 2);
    expect(takesTouches()).toBe(true);
  });

  it("is hidden at peek and takes no touches there", async () => {
    await mount({ scrim: true });
    await advance(1000);
    fireEvent.click(handle());
    await advance(1000);
    expect(dimOpacity()).toBeCloseTo(0, 2);
    expect(takesTouches()).toBe(false);
  });

  it("scrimTap lower (default): a tap lowers the sheet to peek, no dismissal", async () => {
    const onDismiss = vi.fn();
    const { snaps } = await mount({ scrim: true, onDismiss });
    await advance(1000);
    fireEvent.click(screen.getByTestId("gift-scrim-press"));
    await advance(1000);
    expect(snaps).toEqual(["peek"]);
    expect(onDismiss).not.toHaveBeenCalled();
  });

  it("scrimTap dismiss: calls onDismiss and closes the tray holder first", async () => {
    const order: string[] = [];
    const tray = {
      gifts: GIFTS,
      balance: 1000,
      send: async () => {},
      testMode: false,
      isOpen: true,
      close: () => order.push("close"),
    };
    await mount({
      tray,
      gifts: undefined,
      balance: undefined,
      onSend: undefined,
      scrim: true,
      scrimTap: "dismiss",
      onDismiss: () => order.push("dismiss"),
    });
    await advance(1000);
    fireEvent.click(screen.getByTestId("gift-scrim-press"));
    expect(order).toEqual(["close", "dismiss"]);
  });

  it("with the open prop the host owns closing: only onDismiss runs", async () => {
    const close = vi.fn();
    const onDismiss = vi.fn();
    await mount({
      tray: {
        gifts: GIFTS,
        balance: 1,
        send: async () => {},
        testMode: false,
        isOpen: true,
        close,
      },
      open: true,
      scrim: true,
      scrimTap: "dismiss",
      onDismiss,
    });
    await advance(1000);
    fireEvent.click(screen.getByTestId("gift-scrim-press"));
    expect(onDismiss).toHaveBeenCalledOnce();
    expect(close).not.toHaveBeenCalled();
  });

  it("open false hides the sheet and the dim, reports inset 0; open again places it at initialSnap", async () => {
    const { insets, snaps } = await mount({ scrim: true });
    await advance(1000);
    fireEvent.click(handle()); // peek
    await advance(1000);
    cleanup();
    // A second render of the same tray, driven through the prop.
    const r = render(
      <GiftTray
        gifts={GIFTS}
        balance={1000}
        onSend={() => {}}
        scrim
        open={false}
        onInsetChange={(px) => insets.push(px)}
      />,
    );
    await advance(1000);
    expect(getComputedStyle(screen.getByTestId("gift-sheet")).pointerEvents).toBe("none");
    expect(insets[insets.length - 1]).toBe(0);
    expect(takesTouches()).toBe(false);
    r.rerender(
      <GiftTray
        gifts={GIFTS}
        balance={1000}
        onSend={() => {}}
        scrim
        open
        onInsetChange={(px) => insets.push(px)}
      />,
    );
    await advance(1000);
    expect(insets[insets.length - 1]).toBe(310);
    expect(dimOpacity()).toBeCloseTo(0.4, 2);
    expect(snaps).toEqual(["peek"]);
  });
});
