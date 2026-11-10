/**
 * The web tray as a bottom sheet (spec 9.1): structure, snap heights from measured content,
 * handle tap and arrow keys, pointer drags with velocity, the nested-scroll decision on the grid,
 * touch-action, reduced motion and the inset callback. jsdom has no layout, so the sizes the
 * sheet measures are stubbed (container 780, header block 58, footer 70, cell 83).
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Gift, SheetSnap } from "../src/core";
import { GiftTray, type GiftTrayOptions, createGiftTray } from "../src/web";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";
import { componentCallStubs } from "./stub-client";

const gift = (id: string, price: number, order = 0): Gift => ({
  id,
  name: id.charAt(0).toUpperCase() + id.slice(1),
  description: null,
  price,
  icon_url: `https://assets.test/${id}/256.webp`,
  animation_url: `https://assets.test/${id}/512.webp`,
  sort_order: order,
});
/** 12 gifts: three rows of four. */
const GIFTS = Array.from({ length: 12 }, (_, i) => gift(`g${i}`, 10 * (i + 1), i));

// Measured sizes -> peek 58 + 70 = 128, default 128 + 2 * 91 = 310, content 128 + 3 * 91 = 401.
const SIZES = { gridTop: 58, footer: 70, cell: 83 };

let env: ReturnType<typeof installWebEnv>;
let container: HTMLElement;
let trays: GiftTray[] = [];
let restoreSizes = () => {};

function stubSizes() {
  const proto = HTMLElement.prototype;
  const saved = {
    top: Object.getOwnPropertyDescriptor(proto, "offsetTop"),
    height: Object.getOwnPropertyDescriptor(proto, "offsetHeight"),
  };
  Object.defineProperty(proto, "offsetTop", {
    configurable: true,
    get(this: HTMLElement) {
      return this.classList.contains("gs-grid") ? SIZES.gridTop : 0;
    },
  });
  Object.defineProperty(proto, "offsetHeight", {
    configurable: true,
    get(this: HTMLElement) {
      if (this.classList.contains("gs-footer")) return SIZES.footer;
      if (this.classList.contains("gs-cell")) return SIZES.cell;
      return 0;
    },
  });
  return () => {
    if (saved.top) Object.defineProperty(proto, "offsetTop", saved.top);
    else delete (proto as { offsetTop?: unknown }).offsetTop;
    if (saved.height) Object.defineProperty(proto, "offsetHeight", saved.height);
    else delete (proto as { offsetHeight?: unknown }).offsetHeight;
  };
}

beforeEach(() => {
  env = installWebEnv();
  restoreSizes = stubSizes();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
  container = document.createElement("div");
  document.body.appendChild(container);
});
afterEach(() => {
  for (const t of trays) t.destroy();
  trays = [];
  container.remove();
  vi.useRealTimers();
  restoreSizes();
  env.restore();
});

const mk = (options: GiftTrayOptions = {}) => {
  const tray = new GiftTray(container, { gifts: GIFTS, balance: 1000, ...options });
  trays.push(tray);
  return tray;
};
const $ = (sel: string) => container.querySelector(sel) as HTMLElement;
const root = () => $("[data-gs-tray]");
const body = () => $("[data-gs-sheet-body]");
const handle = () => $("[data-gs-handle]") as HTMLButtonElement;
const grid = () => $(".gs-grid");
const offset = () => Number(/translateY\(([-\d.]+)px\)/.exec(body().style.transform)![1]);

/** A pointer event (jsdom may lack PointerEvent; a MouseEvent with the fields does the job). */
function pointer(target: Element, type: string, y: number, x = 100, id = 1) {
  const ev = new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y });
  Object.defineProperty(ev, "pointerId", { value: id });
  Object.defineProperty(ev, "pointerType", { value: "mouse" });
  target.dispatchEvent(ev);
}

/** Press at `from`, move by `steps` (each `dy` px after `ms` ms), release. */
function drag(target: Element, from: number, steps: { dy: number; ms: number }[], release = true) {
  let y = from;
  pointer(target, "pointerdown", y);
  for (const s of steps) {
    vi.advanceTimersByTime(s.ms);
    y += s.dy;
    pointer(target, "pointermove", y);
  }
  if (release) pointer(target, "pointerup", y);
}

describe("web sheet: collapseOnSelect", () => {
  it("picking a gift lowers the sheet to peek, with that gift and Send in sight", () => {
    const snaps: SheetSnap[] = [];
    const tray = mk({ collapseOnSelect: true, onSnapChange: (s) => snaps.push(s) });
    expect(tray.getSheetState()?.snap).toBe("default");
    (grid().children[3] as HTMLElement).click();
    expect(tray.getSheetState()?.snap).toBe("peek");
    expect(snaps).toEqual(["peek"]);
    expect($("[data-gs-footer]").querySelector("[data-gs-picked]")!.textContent).toContain("G3");
    // The handle brings the grid back.
    handle().click();
    expect(tray.getSheetState()?.snap).toBe("default");
  });

  it("is off by default: picking a gift keeps the sheet where it is", () => {
    const tray = mk();
    (grid().children[3] as HTMLElement).click();
    expect(tray.getSheetState()?.snap).toBe("default");
  });
});

describe("web sheet: structure and heights", () => {
  it("is a sheet by default: a moving body (handle, header, grid) and a fixed footer", () => {
    mk();
    expect(root().classList.contains("gs-sheet")).toBe(true);
    expect(body().contains(handle())).toBe(true);
    expect(body().contains(grid())).toBe(true);
    const footer = $("[data-gs-footer]");
    expect(footer.contains($("[data-gs-send]"))).toBe(true);
    expect(footer.querySelector("[data-gs-picked]")!.textContent).toContain("G0");
    expect(handle().getAttribute("type")).toBe("button");
    expect(grid().style.maxHeight).toBe("");
  });

  it("builds the snap heights from the measured content; opens in default", () => {
    const tray = mk();
    expect(tray.getSheetState()).toMatchObject({
      snap: "default",
      heights: { peek: 128, default: 310, expanded: 401 },
      offset: 91,
      visibleHeight: 310,
    });
    // Laid out once at the expanded height and moved down: no height animation.
    expect(root().style.height).toBe("401px");
    expect(offset()).toBe(91);
    expect(root().getAttribute("data-gs-snap")).toBe("default");
  });

  it("stays invisible until measured, then appears in place without a transition, then animates", () => {
    const footer = SIZES.footer;
    SIZES.footer = 0; // not laid out yet (images and fonts still loading)
    const tray = mk();
    expect(root().style.opacity).toBe("0");
    expect(body().style.transition).toBe("none");
    SIZES.footer = footer;
    tray.measure(); // the layout arrives
    expect(root().style.opacity).toBe("");
    expect(offset()).toBe(91); // placed at default at once
    expect(body().style.transition).toBe("none"); // no glide from the first guess
    vi.advanceTimersByTime(40);
    expect(body().style.transition).toBe(""); // from now on a snap animates
  });

  it("expanded is 90 % of the container when the content is taller (0.9 * 780 = 702)", () => {
    const many = Array.from({ length: 40 }, (_, i) => gift(`m${i}`, i + 1, i));
    const tray = mk({ gifts: many });
    // 40 gifts: content 128 + 10 * 91 = 1038, taller than 702.
    expect(tray.getSheetState()!.heights).toEqual({ peek: 128, default: 310, expanded: 702 });
  });

  it("initialSnap and snaps fractions", () => {
    const tray = mk({ initialSnap: "peek", snaps: { peek: 0.25 } });
    expect(tray.getSheetState()).toMatchObject({ snap: "peek", visibleHeight: 195 });
  });

  it("new gifts measure again (rows change the heights)", () => {
    const tray = mk({ gifts: GIFTS.slice(0, 4) });
    expect(tray.getSheetState()!.heights).toEqual({ peek: 128, default: 219, expanded: 219 });
    tray.update({ gifts: GIFTS });
    expect(tray.getSheetState()!.heights.expanded).toBe(401);
  });

  it("sheet: false keeps the old fixed tray", () => {
    const tray = mk({ sheet: false });
    expect(root().classList.contains("gs-sheet")).toBe(false);
    expect(container.querySelector("[data-gs-handle]")).toBeNull();
    expect($("[data-gs-send]").parentElement).toBe(root());
    expect(grid().style.maxHeight).toBe("230px");
    expect(tray.getSheetState()).toBeNull();
  });

  it("makes a static container relative, and restores it on destroy", () => {
    const tray = mk();
    expect(container.style.position).toBe("relative");
    tray.destroy();
    expect(container.style.position).toBe("");
  });
});

describe("web sheet: handle, keyboard, accessibility", () => {
  it("a tap on the handle toggles default <-> peek; aria-expanded and inert follow", () => {
    const changes: SheetSnap[] = [];
    const insets: number[] = [];
    mk({ onSnapChange: (s) => changes.push(s), onInsetChange: (px) => insets.push(px) });
    expect(handle().getAttribute("aria-expanded")).toBe("true");
    handle().click();
    expect(root().getAttribute("data-gs-snap")).toBe("peek");
    expect(offset()).toBe(273);
    expect(handle().getAttribute("aria-expanded")).toBe("false");
    // Out of sight in peek: out of the tab order and the accessibility tree too.
    expect(grid().hasAttribute("inert")).toBe(true);
    expect(grid().getAttribute("aria-hidden")).toBe("true");
    handle().click();
    expect(root().getAttribute("data-gs-snap")).toBe("default");
    expect(grid().hasAttribute("inert")).toBe(false);
    expect(changes).toEqual(["peek", "default"]);
    expect(insets).toEqual([310, 128, 310]);
  });

  it("arrow keys on the handle step the states and stop at the ends", () => {
    mk();
    const key = (k: string) =>
      handle().dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true }));
    key("ArrowUp");
    expect(root().getAttribute("data-gs-snap")).toBe("expanded");
    expect(offset()).toBe(0);
    key("ArrowUp");
    expect(root().getAttribute("data-gs-snap")).toBe("expanded");
    key("ArrowDown");
    key("ArrowDown");
    expect(root().getAttribute("data-gs-snap")).toBe("peek");
    key("ArrowDown");
    expect(root().getAttribute("data-gs-snap")).toBe("peek");
  });

  it("snapTo moves the sheet from code", () => {
    const tray = mk();
    tray.snapTo("expanded");
    expect(tray.getSheetState()!.snap).toBe("expanded");
  });
});

describe("web sheet: pointer drags", () => {
  it("dragging the header follows the pointer without a transition, then snaps with one", () => {
    mk();
    const head = $(".gs-head");
    drag(head, 500, [{ dy: -50, ms: 200 }], false);
    expect(root().classList.contains("gs-dragging")).toBe(true);
    expect(body().style.transition).toBe("none");
    expect(offset()).toBe(41);
    pointer(head, "pointermove", 430);
    expect(offset()).toBe(21);
    vi.advanceTimersByTime(200); // the finger rests: no flick
    pointer(head, "pointerup", 430);
    expect(root().getAttribute("data-gs-snap")).toBe("expanded");
    expect(root().classList.contains("gs-dragging")).toBe(false);
    expect(body().style.transition).toBe("");
    expect(offset()).toBe(0);
  });

  it("a press that moves less than the slop is not a drag", () => {
    mk();
    drag($(".gs-head"), 500, [{ dy: -5, ms: 50 }]);
    expect(root().getAttribute("data-gs-snap")).toBe("default");
    expect(offset()).toBe(91);
  });

  it("a quick flick down moves one state (velocity >= 600 px/s)", () => {
    mk();
    drag($(".gs-head"), 500, [
      { dy: 10, ms: 10 },
      { dy: 10, ms: 10 },
    ]);
    expect(root().getAttribute("data-gs-snap")).toBe("peek");
  });

  it("the same distance, slowly, snaps back to the nearest state", () => {
    mk();
    drag($(".gs-head"), 500, [
      { dy: 10, ms: 100 },
      { dy: 10, ms: 100 },
    ]);
    expect(root().getAttribute("data-gs-snap")).toBe("default");
  });

  it("below fully open, a drag on the grid moves the sheet and does not select a cell", () => {
    const tray = mk();
    const cell = container.querySelectorAll<HTMLElement>(".gs-cell")[3]!;
    drag(cell, 600, [{ dy: -100, ms: 300 }]);
    cell.click(); // the click a browser fires after the pointerup
    expect(tray.getSheetState()!.snap).toBe("expanded");
    expect(tray.getSelected()!.id).toBe("g0");
    vi.advanceTimersByTime(1);
    cell.click(); // a real click later counts again
    expect(tray.getSelected()!.id).toBe("g3");
  });

  it("fully open, the grid scrolls when dragged up; at the top a drag down collapses the sheet", () => {
    const tray = mk({ initialSnap: "expanded" });
    const cell = container.querySelector<HTMLElement>(".gs-cell")!;
    drag(cell, 600, [{ dy: -100, ms: 300 }]);
    expect(tray.getSheetState()).toMatchObject({ snap: "expanded", offset: 0 });
    expect(grid().scrollTop).toBe(100); // scrolled by hand (mouse); touch scrolls natively
    // Scrolled down, a drag down scrolls back instead of moving the sheet.
    vi.advanceTimersByTime(1);
    drag(cell, 400, [{ dy: 60, ms: 300 }]);
    expect(tray.getSheetState()!.snap).toBe("expanded");
    expect(grid().scrollTop).toBe(40);
    grid().scrollTop = 0;
    vi.advanceTimersByTime(1);
    drag(cell, 400, [
      { dy: 150, ms: 200 },
      { dy: 0, ms: 200 },
    ]);
    expect(tray.getSheetState()!.snap).toBe("default");
  });

  it("pointercancel returns to the state the drag started from", () => {
    const tray = mk();
    const head = $(".gs-head");
    drag(head, 500, [{ dy: -80, ms: 100 }], false);
    pointer(head, "pointercancel", 420);
    expect(tray.getSheetState()).toMatchObject({ snap: "default", offset: 91, dragging: false });
  });

  it("the inset follows the pointer live during a drag", () => {
    const insets: number[] = [];
    mk({ onInsetChange: (px) => insets.push(px) });
    drag($(".gs-head"), 500, [
      { dy: -20, ms: 100 },
      { dy: -20, ms: 100 },
    ]);
    expect(insets.slice(0, 3)).toEqual([310, 330, 350]);
  });
});

describe("web sheet: touch-action and reduced motion", () => {
  it("the grid gives touches to the sheet below fully open, and pulls at the top when open", () => {
    const tray = mk();
    expect(grid().style.touchAction).toBe("none");
    tray.snapTo("expanded");
    expect(grid().style.touchAction).toBe("pan-down");
    expect(root().getAttribute("data-gs-grid-scroll")).toBe("true");
  });

  it("the header and handle never let the browser pan (CSS)", () => {
    mk();
    const css = document.querySelector("style[data-giftingstack]")!.textContent!;
    expect(css).toMatch(/\.gs-handle \{[^}]*touch-action: none/);
    expect(css).toMatch(/\.gs-sheet \.gs-head \{[^}]*touch-action: none/);
    expect(css).toMatch(/\.gs-sheet-body \{[^}]*transition: transform 280ms/);
  });

  it("reduced motion snaps without a transition", () => {
    env.setReducedMotion(true);
    mk();
    handle().click();
    expect(body().style.transition).toBe("none");
    expect(offset()).toBe(273);
  });
});

describe("web sheet: entrance (SPEC 9.4: fade 200 ms, rise from 3 % over 220 ms)", () => {
  const animationEnd = (name: string) => {
    const ev = new Event("animationend", { bubbles: true });
    Object.assign(ev, { animationName: name });
    root().dispatchEvent(ev);
  };

  it("the CSS fades in over 200 ms and rises from 3 % over 220 ms, and is off for reduced motion", () => {
    mk();
    const css = document.querySelector("style[data-giftingstack]")!.textContent!;
    expect(css).toMatch(
      /\.gs-tray\.gs-sheet\[data-gs-entering\] \{[^}]*gs-sheet-fade 200ms ease-out[^}]*gs-sheet-rise 220ms cubic-bezier\(0\.215, 0\.61, 0\.355, 1\)/,
    );
    expect(css).toMatch(/@keyframes gs-sheet-rise \{ from \{ transform: translateY\(3%\); \}/);
    expect(css).toMatch(
      /prefers-reduced-motion: reduce\) \{ \.gs-tray\.gs-sheet\[data-gs-entering\] \{ animation: none/,
    );
  });

  it("starts when the sheet is placed and ends with the rise", () => {
    mk();
    expect(root().hasAttribute("data-gs-entering")).toBe(true);
    animationEnd("gs-sheet-fade"); // the shorter one ends first: still entering
    expect(root().hasAttribute("data-gs-entering")).toBe(true);
    animationEnd("gs-sheet-rise");
    expect(root().hasAttribute("data-gs-entering")).toBe(false);
  });

  it("plays again when the tray is opened again, not while it is closed", () => {
    const tray = mk();
    animationEnd("gs-sheet-rise");
    tray.close();
    expect(root().hasAttribute("data-gs-entering")).toBe(false);
    tray.open();
    vi.advanceTimersByTime(40);
    expect(root().hasAttribute("data-gs-entering")).toBe(true);
  });

  it("reduced motion: no entrance", () => {
    env.setReducedMotion(true);
    mk();
    expect(root().hasAttribute("data-gs-entering")).toBe(false);
  });
});

/** A wheel tick; returns whether the sheet stopped the page from scrolling (preventDefault). */
function wheel(target: Element, deltaY: number, deltaX = 0): boolean {
  const ev = new WheelEvent("wheel", { bubbles: true, cancelable: true, deltaY, deltaX });
  target.dispatchEvent(ev);
  return ev.defaultPrevented;
}

describe("web sheet: mouse wheel", () => {
  it("wheel down over the sheet opens one state at a time and keeps the page still", () => {
    const tray = mk({ initialSnap: "peek" });
    expect(wheel(grid(), 100)).toBe(true);
    expect(tray.getSheetState()!.snap).toBe("default");
    // The rest of the same flick (and trackpad inertia) does nothing more.
    expect(wheel(grid(), 100)).toBe(true);
    expect(tray.getSheetState()!.snap).toBe("default");
    vi.advanceTimersByTime(450);
    expect(wheel(grid(), 100)).toBe(true);
    expect(tray.getSheetState()!.snap).toBe("expanded");
  });

  it("wheel up where the wheel can do nothing is left to the page (peek, default)", () => {
    const tray = mk({ initialSnap: "peek" });
    expect(wheel(grid(), -100)).toBe(false);
    expect(tray.getSheetState()!.snap).toBe("peek");
    tray.snapTo("default");
    expect(wheel(grid(), -100)).toBe(false);
    expect(tray.getSheetState()!.snap).toBe("default");
  });

  it("fully open, the grid scrolls natively; wheel up at the top closes one state", () => {
    const tray = mk({ initialSnap: "expanded" });
    // Not at the bottom: the grid takes the wheel (no preventDefault, the browser scrolls it).
    Object.defineProperty(grid(), "scrollHeight", { configurable: true, value: 600 });
    Object.defineProperty(grid(), "clientHeight", { configurable: true, value: 300 });
    expect(wheel(grid(), 100)).toBe(false);
    grid().scrollTop = 40;
    expect(wheel(grid(), -100)).toBe(false);
    expect(tray.getSheetState()!.snap).toBe("expanded");
    grid().scrollTop = 0;
    expect(wheel(grid(), -100)).toBe(true);
    expect(tray.getSheetState()!.snap).toBe("default");
  });

  it("at the bottom of the open grid the page does not scroll behind it", () => {
    const tray = mk({ initialSnap: "expanded" });
    Object.defineProperty(grid(), "scrollHeight", { configurable: true, value: 600 });
    Object.defineProperty(grid(), "clientHeight", { configurable: true, value: 300 });
    grid().scrollTop = 300;
    expect(wheel(grid(), 100)).toBe(true);
    expect(tray.getSheetState()!.snap).toBe("expanded");
  });

  it("horizontal wheel and pinch-zoom are left alone", () => {
    const tray = mk({ initialSnap: "peek" });
    expect(wheel(grid(), 10, 100)).toBe(false);
    const zoom = new WheelEvent("wheel", {
      bubbles: true,
      cancelable: true,
      deltaY: 100,
      ctrlKey: true,
    });
    grid().dispatchEvent(zoom);
    expect(zoom.defaultPrevented).toBe(false);
    expect(tray.getSheetState()!.snap).toBe("peek");
  });
});

describe("web sheet: createGiftTray", () => {
  it("passes the sheet options through", async () => {
    const changes: SheetSnap[] = [];
    const client = {
      getGifts: async () => GIFTS,
      getMe: async () => ({ user: "ayla", balance: 500 }),
      getReceivedGifts: async () => [],
      sendGift: async () => {
        throw new Error("not used");
      },
      ...componentCallStubs,
    };
    const handleObj = createGiftTray({
      container,
      client,
      receiver: "mert",
      initialSnap: "peek",
      onSnapChange: (s) => changes.push(s),
    });
    await vi.advanceTimersByTimeAsync(0);
    expect(handleObj.tray.getSheetState()!.snap).toBe("peek");
    handle().click();
    expect(changes).toEqual(["default"]);
    handleObj.destroy();
  });
});

describe("web sheet: scrim, toggle, open and close (spec 9.4)", () => {
  const scrim = () => container.querySelector("[data-gs-scrim]") as HTMLElement | null;
  const shown = () => scrim()!.hasAttribute("data-gs-visible");
  const settle = () => vi.advanceTimersByTime(800);

  it("has no scrim unless asked: default and options off", () => {
    mk();
    settle();
    expect(scrim()).toBeNull();
  });

  it("draws a dim over the container behind the sheet, fading in once the sheet is placed", () => {
    mk({ scrim: true });
    expect(scrim()!.nextElementSibling).toBe(root());
    expect(scrim()!.getAttribute("aria-hidden")).toBe("true");
    settle();
    expect(shown()).toBe(true);
    expect(scrim()!.style.transitionDuration).toBe("200ms");
  });

  it("reduced motion: the dim appears at once (0 ms)", () => {
    env.setReducedMotion(true);
    mk({ scrim: true });
    settle();
    expect(shown()).toBe(true);
    expect(scrim()!.style.transitionDuration).toBe("0ms");
  });

  it("is hidden at peek and back above it", () => {
    const tray = mk({ scrim: true });
    settle();
    tray.snapTo("peek");
    expect(shown()).toBe(false);
    tray.snapTo("expanded");
    expect(shown()).toBe(true);
  });

  it("at peek the dim is hidden but still takes the tap, and a tap there closes the tray", () => {
    const dismissed = vi.fn();
    const tray = mk({ scrim: true, onDismiss: dismissed });
    settle();
    tray.snapTo("peek");
    expect(shown()).toBe(false);
    expect(scrim()!.hasAttribute("data-gs-active")).toBe(true);
    scrim()!.click();
    expect(dismissed).toHaveBeenCalledTimes(1);
    expect(tray.isOpen()).toBe(false);
    // Closed: no touches taken any more.
    expect(scrim()!.hasAttribute("data-gs-active")).toBe(false);
  });

  it("scrimTap lower (default): a tap lowers the sheet to peek; the dim goes away", () => {
    const dismissed = vi.fn();
    const tray = mk({ scrim: true, onDismiss: dismissed });
    settle();
    scrim()!.click();
    expect(tray.getSheetState()?.snap).toBe("peek");
    expect(shown()).toBe(false);
    expect(dismissed).not.toHaveBeenCalled();
    expect(tray.isOpen()).toBe(true);
  });

  it("scrimTap dismiss: a tap closes the tray, then calls onDismiss", () => {
    const order: string[] = [];
    const tray = mk({
      scrim: true,
      scrimTap: "dismiss",
      onOpenChange: (o) => order.push(`open:${o}`),
      onDismiss: () => order.push("dismiss"),
    });
    settle();
    scrim()!.click();
    expect(order).toEqual(["open:false", "dismiss"]);
    expect(tray.isOpen()).toBe(false);
    expect(root().hidden).toBe(true);
    expect(shown()).toBe(false);
  });

  it("toggle closes and opens the sheet; opening returns to initialSnap; the inset follows", () => {
    const insets: number[] = [];
    const opens: boolean[] = [];
    const tray = mk({
      scrim: true,
      onInsetChange: (px) => insets.push(px),
      onOpenChange: (o) => opens.push(o),
    });
    settle();
    tray.snapTo("expanded");
    tray.toggle();
    expect(tray.isOpen()).toBe(false);
    expect(root().hidden).toBe(true);
    expect(insets[insets.length - 1]).toBe(0);
    tray.toggle();
    expect(tray.isOpen()).toBe(true);
    expect(root().hidden).toBe(false);
    expect(tray.getSheetState()?.snap).toBe("default");
    settle();
    expect(shown()).toBe(true);
    expect(insets[insets.length - 1]).toBe(310);
    expect(opens).toEqual([false, true]);
  });

  it("open false: starts hidden until open()", () => {
    const tray = mk({ open: false, scrim: true });
    settle();
    expect(root().hidden).toBe(true);
    expect(shown()).toBe(false);
    tray.open();
    settle();
    expect(root().hidden).toBe(false);
    expect(shown()).toBe(true);
  });

  it("destroy removes the dim", () => {
    const tray = mk({ scrim: true });
    tray.destroy();
    expect(scrim()).toBeNull();
  });

  it("createGiftTray handle: toggle, open, close, isOpen reach the tray", () => {
    const handleTray = createGiftTray({
      container,
      client: { getGifts: async () => ({ data: [] }) } as never,
      receiver: "bob",
      scrim: true,
    });
    settle();
    expect(handleTray.isOpen()).toBe(true);
    handleTray.toggle();
    expect(handleTray.isOpen()).toBe(false);
    handleTray.open();
    expect(handleTray.isOpen()).toBe(true);
    handleTray.close();
    expect(handleTray.isOpen()).toBe(false);
    handleTray.destroy();
  });
});
