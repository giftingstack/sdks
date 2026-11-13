/**
 * React Native: `GiftButton` and `useGiftTray({ input })`, the keyboard swap of spec 20, on
 * react-native-web in jsdom. The keyboard is simulated through the `Keyboard` listeners the hook
 * registers; the sheet's sizes are stubbed per testID as in react-native-sheet.test.tsx
 * (container 780 -> default floor 128 + 2 * 91 = 310). Real keyboard timing needs a phone.
 */
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { type ElementRef, type RefObject, createRef, useRef, useState } from "react";
import { AccessibilityInfo, Keyboard, Text, TextInput } from "react-native";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Gift, GiftingClient } from "../src/core";
import {
  GiftButton,
  GiftTray,
  type UseGiftTray,
  giftIconFitScale,
  useGiftTray,
} from "../src/react-native";
import { componentCallStubs } from "./stub-client";

const gift = (id: string, price: number): Gift => ({
  id,
  name: id.toUpperCase(),
  description: null,
  price,
  icon_url: `https://assets.test/${id}/256.webp`,
  animation_url: null,
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

const client = (): GiftingClient => ({
  getGifts: vi.fn(async () => GIFTS),
  getMe: vi.fn(async () => ({ user: "ayla", balance: 1000 })),
  getReceivedGifts: vi.fn(async () => []),
  ...componentCallStubs,
  sendGift: vi.fn(),
});

/** The keyboard: the handlers the hook gave `Keyboard.addListener`. */
let shows: ((e: { endCoordinates: { height: number } }) => void)[] = [];
let restore = () => {};

beforeEach(() => {
  restore = installSheetLayout();
  shows = [];
  vi.spyOn(AccessibilityInfo, "isReduceMotionEnabled").mockResolvedValue(false);
  vi.spyOn(Keyboard, "addListener").mockImplementation(((
    _: string,
    cb: (e: { endCoordinates: { height: number } }) => void,
  ) => {
    shows.push(cb);
    return { remove: () => (shows = shows.filter((s) => s !== cb)) };
  }) as unknown as typeof Keyboard.addListener);
  vi.spyOn(Keyboard, "dismiss").mockImplementation(() => {});
  vi.useFakeTimers({
    toFake: ["setTimeout", "clearTimeout", "requestAnimationFrame", "cancelAnimationFrame", "Date"],
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

/** The keyboard came up for the field, `height` tall. */
function keyboardShows(height: number) {
  act(() => {
    for (const cb of [...shows]) cb({ endCoordinates: { height } });
  });
}

/** A message bar: the app's TextInput, the SDK's GiftButton and the tray bound to the field. */
function Chat({
  probe,
  input,
  open,
  snaps,
}: {
  probe: (t: UseGiftTray) => void;
  input: RefObject<ElementRef<typeof TextInput> | null>;
  open?: boolean;
  snaps?: { default?: number };
}) {
  const [c] = useState(client);
  const tray = useGiftTray({ client: c, receiver: "mia", input, open });
  probe(tray);
  return (
    <>
      <TextInput ref={input} testID="field" />
      <GiftButton tray={tray} />
      <GiftTray tray={tray} snaps={snaps} />
    </>
  );
}

async function mount(extra: { open?: boolean; snaps?: { default?: number } } = {}) {
  let last!: UseGiftTray;
  // The idiom an app uses: a ref to its own TextInput.
  const input = createRef<ElementRef<typeof TextInput>>();
  render(<Chat probe={(t) => (last = t)} input={input} {...extra} />);
  await advance(10);
  const focus = vi.spyOn(input.current!, "focus");
  const blur = vi.spyOn(input.current!, "blur");
  const focused = vi.spyOn(input.current!, "isFocused" as never) as unknown as {
    mockReturnValue(v: boolean): void;
  };
  return { tray: () => last, focus, blur, focused };
}

const press = () => fireEvent.click(screen.getByTestId("gift-button"));
const visible = () => {
  const m = /translateY\(([-\d.]+)px\)/.exec(screen.getByTestId("gift-tray").style.transform);
  // The body is laid out at its expanded height (here 401) and moved down by the offset.
  return 401 - (m ? Number(m[1]) : NaN);
};

describe("GiftButton (React Native, spec 20.4)", () => {
  it("is a labelled button with the gift glyph; onPress without a tray", () => {
    const onPress = vi.fn();
    render(<GiftButton onPress={onPress} />);
    const b = screen.getByTestId("gift-button");
    expect(b.getAttribute("aria-label")).toBe("Send a gift");
    expect(b.getAttribute("role")).toBe("button");
    expect(screen.getByTestId("gift-button-glyph")).toBeTruthy();
    fireEvent.click(b);
    expect(onPress).toHaveBeenCalledTimes(1);
  });

  it("plain: no background; filled: accent; active: selected (the tray's tokens)", () => {
    const theme = { accent: "#ff0000", selected: "#00ff00" };
    const bg = () => getComputedStyle(screen.getByTestId("gift-button")).backgroundColor;
    const { rerender } = render(<GiftButton theme={theme} />);
    expect(bg()).toMatch(/transparent|rgba\(0, 0, 0, 0\)/);
    rerender(<GiftButton theme={theme} filled />);
    expect(bg()).toBe("rgb(255, 0, 0)");
    rerender(<GiftButton theme={theme} tray={{ isOpen: true, toggle: () => {} }} />);
    expect(bg()).toBe("rgb(0, 255, 0)");
    expect(screen.getByTestId("gift-button").getAttribute("aria-expanded")).toBe("true");
  });

  it("size is one of three names (32 / 36 / 44); anything else is medium", () => {
    const w = () => getComputedStyle(screen.getByTestId("gift-button")).width;
    const g = () => getComputedStyle(screen.getByTestId("gift-button-glyph")).width;
    const { rerender } = render(<GiftButton size="small" />);
    expect(w()).toBe("32px");
    expect(parseFloat(g())).toBeCloseTo((32 * 22) / 36, 3);
    rerender(<GiftButton size="large" />);
    expect(w()).toBe("44px");
    expect(parseFloat(g())).toBeCloseTo((44 * 22) / 36, 3);
    rerender(<GiftButton />);
    expect(w()).toBe("36px");
    expect(parseFloat(g())).toBe(22);
    rerender(<GiftButton size={50 as never} />);
    expect(w()).toBe("36px");
  });

  it("icon (an element) replaces the glyph inside a fixed, clipped box", () => {
    render(<GiftButton icon={<Text testID="mine">hi</Text>} size="large" />);
    expect(screen.queryByTestId("gift-button-glyph")).toBeNull();
    const box = screen.getByTestId("gift-button-icon");
    expect(box.contains(screen.getByTestId("mine"))).toBe(true);
    const st = getComputedStyle(box);
    expect(parseFloat(st.width)).toBeCloseTo((44 * 22) / 36, 3);
    expect(parseFloat(st.height)).toBeCloseTo((44 * 22) / 36, 3);
    expect(box.style.overflowX).toBe("hidden");
    expect(box.style.overflowY).toBe("hidden");
  });

  it("icon (a function) gets the glyph colour: accent plain, accentText filled, accent active", () => {
    const theme = { accent: "#ff0000", accentText: "#0000ff" };
    const icon = (color: string) => <Text testID="mine">{color}</Text>;
    const { rerender } = render(<GiftButton theme={theme} icon={icon} />);
    expect(screen.getByTestId("mine").textContent).toBe("#ff0000");
    rerender(<GiftButton theme={theme} icon={icon} filled />);
    expect(screen.getByTestId("mine").textContent).toBe("#0000ff");
    rerender(
      <GiftButton theme={theme} icon={icon} filled tray={{ isOpen: true, toggle: () => {} }} />,
    );
    expect(screen.getByTestId("mine").textContent).toBe("#ff0000");
  });

  it("removing the icon brings the gift glyph back", () => {
    const { rerender } = render(<GiftButton icon={<Text>x</Text>} />);
    expect(screen.queryByTestId("gift-button-glyph")).toBeNull();
    rerender(<GiftButton />);
    expect(screen.getByTestId("gift-button-glyph")).toBeTruthy();
  });

  it("disabled: no presses", () => {
    const onPress = vi.fn();
    render(<GiftButton onPress={onPress} disabled />);
    fireEvent.click(screen.getByTestId("gift-button"));
    expect(onPress).not.toHaveBeenCalled();
  });
});

describe("GiftButton icon fit (React Native, spec 20.4)", () => {
  it("scales an icon down into the glyph box, never up", () => {
    expect(giftIconFitScale(10, 10, 22)).toBe(1);
    expect(giftIconFitScale(44, 22, 22)).toBe(0.5);
    expect(giftIconFitScale(22, 88, 22)).toBe(0.25);
    expect(giftIconFitScale(500, 500, 22)).toBeCloseTo(22 / 500, 6);
    expect(giftIconFitScale(0, 0, 22)).toBe(1);
  });
});

describe("useGiftTray({ input }): the keyboard swap (spec 20.3)", () => {
  it("starts closed and says a field is bound; an explicit open wins", async () => {
    const a = await mount();
    expect(a.tray().isOpen).toBe(false);
    expect(a.tray().inputBound).toBe(true);
    cleanup();
    const b = await mount({ open: true });
    expect(b.tray().isOpen).toBe(true);
  });

  it("the button closes the keyboard and opens the tray; again: closes it and focuses the field", async () => {
    const t = await mount();
    press();
    expect(t.tray().isOpen).toBe(true);
    expect(t.blur).toHaveBeenCalledTimes(1);
    expect(Keyboard.dismiss).toHaveBeenCalledTimes(1);
    expect(t.focus).not.toHaveBeenCalled();
    press();
    expect(t.tray().isOpen).toBe(false);
    expect(t.focus).toHaveBeenCalledTimes(1);
  });

  it("the keyboard coming up for the field closes the tray; for another field it does not", async () => {
    const t = await mount();
    press();
    t.focused.mockReturnValue(false);
    keyboardShows(320);
    expect(t.tray().isOpen).toBe(true);
    t.focused.mockReturnValue(true);
    keyboardShows(320);
    expect(t.tray().isOpen).toBe(false);
    expect(t.focus).not.toHaveBeenCalled();
  });

  it("react-native-web: a focus on the field (a DOM focus event) closes the tray", async () => {
    const t = await mount();
    press();
    expect(t.tray().isOpen).toBe(true);
    act(() => screen.getByTestId("field").focus());
    expect(t.tray().isOpen).toBe(false);
  });

  it("react-native-web: a field that mounts after the hook (another screen) still closes the tray", async () => {
    let last!: UseGiftTray;
    let show!: (v: boolean) => void;
    const Late = () => {
      const [c] = useState(client);
      const [shown, setShown] = useState(false);
      show = setShown;
      const input = useRef<ElementRef<typeof TextInput>>(null);
      last = useGiftTray({ client: c, receiver: "mia", input });
      return shown ? <TextInput ref={input} testID="late-field" /> : null;
    };
    render(<Late />);
    act(() => show(true));
    act(() => last.toggle());
    expect(last.isOpen).toBe(true);
    act(() => screen.getByTestId("late-field").focus());
    expect(last.isOpen).toBe(false);
  });

  it("opens in the keyboard's place: the last keyboard height seen", async () => {
    const t = await mount();
    t.focused.mockReturnValue(true);
    keyboardShows(380);
    keyboardShows(40); // not a keyboard: kept 380
    expect(t.tray().keyboardHeight).toBe(380);
    press();
    await advance(50);
    expect(visible()).toBe(380);
  });

  it("before any keyboard: 300, but never below the tray's floor (310 here)", async () => {
    await mount();
    press();
    await advance(50);
    expect(visible()).toBe(310);
  });

  it("the host's snaps.default wins", async () => {
    const t = await mount({ snaps: { default: 0.5 } });
    t.focused.mockReturnValue(true);
    keyboardShows(380);
    press();
    await advance(50);
    expect(visible()).toBe(390);
  });

  it("open() blurs the field, close() leaves the focus alone", async () => {
    const t = await mount();
    act(() => t.tray().open());
    expect(t.blur).toHaveBeenCalledTimes(1);
    act(() => t.tray().close());
    expect(t.focus).not.toHaveBeenCalled();
  });

  it("without input nothing changes: open by default, no keyboard listener", async () => {
    let last!: UseGiftTray;
    const Plain = () => {
      const [c] = useState(client);
      last = useGiftTray({ client: c, receiver: "mia" });
      return null;
    };
    render(<Plain />);
    expect(last.isOpen).toBe(true);
    expect(last.inputBound).toBe(false);
    expect(shows).toHaveLength(0);
  });
});
