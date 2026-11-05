/**
 * Web tray placements (spec 9.3): popover (open/close, Escape, outside click, focus, ARIA,
 * position, no DOM or listeners left), inline (fills the container, columns fit the width) and
 * auto (switches on resize). jsdom has no layout: the container width comes from `PAGE.width`
 * and ResizeObserver is a fake the test fires by hand.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { type Gift, TRAY_WIDE_FROM } from "../src/core";
import { CSS } from "../src/web/styles";
import { GiftTray, type GiftTrayOptions, createGiftTray } from "../src/web";
import { FAKE_TIMERS, PAGE, installWebEnv } from "./web-setup";
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
const GIFTS = Array.from({ length: 12 }, (_, i) => gift(`g${i}`, 10 * (i + 1), i));

class FakeResizeObserver {
  static all = new Set<FakeResizeObserver>();
  targets = new Set<Element>();
  constructor(private cb: () => void) {
    FakeResizeObserver.all.add(this);
  }
  observe(t: Element) {
    this.targets.add(t);
  }
  unobserve(t: Element) {
    this.targets.delete(t);
  }
  disconnect() {
    this.targets.clear();
    FakeResizeObserver.all.delete(this);
  }
  fire() {
    if (this.targets.size) this.cb();
  }
}
/** The container changed size: every live observer hears it. */
const resize = (width: number) => {
  PAGE.width = width;
  for (const ro of [...FakeResizeObserver.all]) ro.fire();
};

let env: ReturnType<typeof installWebEnv>;
let container: HTMLElement;
let anchor: HTMLButtonElement;
let outside: HTMLButtonElement;
let trays: GiftTray[] = [];
const windows = () => new Set<object>([globalThis, document.defaultView!]);

beforeEach(() => {
  env = installWebEnv();
  PAGE.width = 1100;
  for (const w of windows())
    Object.defineProperty(w, "ResizeObserver", {
      configurable: true,
      writable: true,
      value: FakeResizeObserver,
    });
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
  container = document.createElement("div");
  anchor = document.createElement("button");
  anchor.textContent = "Gift";
  outside = document.createElement("button");
  outside.textContent = "Elsewhere";
  document.body.append(container, anchor, outside);
});
afterEach(() => {
  for (const t of trays) t.destroy();
  trays = [];
  container.remove();
  anchor.remove();
  outside.remove();
  vi.useRealTimers();
  for (const w of windows()) delete (w as { ResizeObserver?: unknown }).ResizeObserver;
  FakeResizeObserver.all.clear();
  PAGE.width = 390;
  env.restore();
});

const mk = (options: GiftTrayOptions = {}) => {
  const tray = new GiftTray(container, { gifts: GIFTS, balance: 1000, ...options });
  trays.push(tray);
  return tray;
};
const root = () => document.querySelector("[data-gs-tray]") as HTMLElement;
const cells = () => [...root().querySelectorAll<HTMLButtonElement>(".gs-cell")];
const key = (target: EventTarget, k: string) =>
  target.dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true, cancelable: true }));
const pointerDown = (target: Element) =>
  target.dispatchEvent(new MouseEvent("pointerdown", { bubbles: true, cancelable: true }));

describe("web tray placement: auto", () => {
  it("narrow container without an anchor: exactly today's sheet", () => {
    PAGE.width = 390;
    const tray = mk();
    expect(tray.getPlacement()).toBe("sheet");
    expect(root().className).toBe("gs-tray gs-sheet");
    expect(root().parentElement).toBe(container);
    expect(root().querySelector("[data-gs-sheet-body]")).not.toBeNull();
    expect((root().querySelector("[data-gs-handle]") as HTMLElement).hidden).toBe(false);
    expect(tray.getSheetState()?.snap).toBe("default");
    expect(root().getAttribute("role")).toBeNull();
  });

  it(`from ${TRAY_WIDE_FROM} px (inclusive): popover with an anchor, inline without`, () => {
    PAGE.width = TRAY_WIDE_FROM - 1;
    expect(mk({ anchor }).getPlacement()).toBe("sheet");
    trays.pop()!.destroy();
    PAGE.width = TRAY_WIDE_FROM;
    expect(mk({ anchor }).getPlacement()).toBe("popover");
    trays.pop()!.destroy();
    expect(mk().getPlacement()).toBe("inline");
  });

  it("switches on resize, reports it, closes an open popover and resets the inset", () => {
    PAGE.width = 1100;
    const placements: string[] = [];
    const opens: boolean[] = [];
    const insets: number[] = [];
    const tray = mk({
      anchor,
      onPlacementChange: (p) => placements.push(p),
      onOpenChange: (o) => opens.push(o),
      onInsetChange: (px) => insets.push(px),
    });
    expect(tray.getPlacement()).toBe("popover");
    expect(root().parentElement).toBe(document.body);
    tray.open();
    resize(500);
    expect(tray.getPlacement()).toBe("sheet");
    expect(opens).toEqual([true, false]);
    expect(root().parentElement).toBe(container);
    expect(root().hidden).toBe(false);
    expect(root().getAttribute("role")).toBeNull();
    expect(anchor.hasAttribute("aria-expanded")).toBe(false);
    expect(tray.getSheetState()).not.toBeNull();
    insets.length = 0;
    resize(800);
    expect(tray.getPlacement()).toBe("popover");
    expect(insets).toEqual([0]);
    expect(placements).toEqual(["sheet", "popover"]);
    expect(tray.getSheetState()).toBeNull();
    expect(root().style.height).toBe("");
    expect(root().hidden).toBe(true);
    // The old sheet's listeners are gone: the handle is hidden and clicking it does nothing.
    const handle = root().querySelector("[data-gs-handle]") as HTMLButtonElement;
    expect(handle.hidden).toBe(true);
    handle.click();
    expect(handle.hasAttribute("aria-expanded")).toBe(false);
    // A resize within the same placement changes nothing.
    resize(900);
    expect(placements).toEqual(["sheet", "popover"]);
  });

  it("an explicit placement does not follow resizes", () => {
    const tray = mk({ placement: "inline" });
    resize(300);
    expect(tray.getPlacement()).toBe("inline");
  });

  it("sheet: false keeps the fixed tray whatever the width or placement", () => {
    const tray = mk({ sheet: false, placement: "popover", anchor });
    expect(tray.getPlacement()).toBeNull();
    expect(root().className).toBe("gs-tray");
    expect(anchor.hasAttribute("aria-haspopup")).toBe(false);
  });
});

describe("web tray placement: popover", () => {
  it("starts closed with the anchor's and the dialog's ARIA", () => {
    const tray = mk({ anchor, title: "Gifts for mert" });
    expect(tray.isOpen()).toBe(false);
    expect(root().hidden).toBe(true);
    expect(root().getAttribute("role")).toBe("dialog");
    expect(root().getAttribute("aria-label")).toBe("Gifts for mert");
    expect(anchor.getAttribute("aria-haspopup")).toBe("dialog");
    expect(anchor.getAttribute("aria-expanded")).toBe("false");
    expect(anchor.getAttribute("aria-controls")).toBe(root().id);
    expect(root().querySelector("[data-gs-handle]")!.hasAttribute("hidden")).toBe(true);
    expect(root().querySelector("[data-gs-sheet-body]")).toBeNull();
  });

  it("the anchor toggles it; focus moves to the selected gift and back to the anchor", () => {
    const opens: boolean[] = [];
    const tray = mk({ anchor, defaultSelectedId: "g3", onOpenChange: (o) => opens.push(o) });
    anchor.focus();
    anchor.click();
    expect(tray.isOpen()).toBe(true);
    expect(root().hidden).toBe(false);
    expect(anchor.getAttribute("aria-expanded")).toBe("true");
    expect(document.activeElement).toBe(cells()[3]);
    anchor.click();
    expect(tray.isOpen()).toBe(false);
    expect(document.activeElement).toBe(anchor);
    expect(opens).toEqual([true, false]);
  });

  it("Escape closes it and returns focus to the anchor", () => {
    const tray = mk({ anchor });
    tray.open();
    key(cells()[0]!, "Escape");
    expect(tray.isOpen()).toBe(false);
    expect(root().hidden).toBe(true);
    expect(anchor.getAttribute("aria-expanded")).toBe("false");
    expect(document.activeElement).toBe(anchor);
    // Closed: Escape is not ours any more.
    const ev = new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true });
    document.dispatchEvent(ev);
    expect(ev.defaultPrevented).toBe(false);
  });

  it("a click outside closes it without moving focus; clicks inside and on the anchor do not", () => {
    const tray = mk({ anchor });
    tray.open();
    pointerDown(cells()[2]!);
    expect(tray.isOpen()).toBe(true);
    pointerDown(anchor);
    expect(tray.isOpen()).toBe(true);
    pointerDown(outside);
    expect(tray.isOpen()).toBe(false);
    expect(document.activeElement).not.toBe(anchor);
  });

  it("collapseOnSelect: a pick makes it small; All gifts and reopening bring the grid back; outside still closes it", () => {
    const tray = mk({ anchor, collapseOnSelect: true });
    tray.open();
    const more = root().querySelector("[data-gs-more]") as HTMLButtonElement;
    expect(more.hidden).toBe(true);
    cells()[3]!.click();
    expect(root().hasAttribute("data-gs-compact")).toBe(true);
    expect(more.hidden).toBe(false);
    expect(root().querySelector("[data-gs-picked]")!.textContent).toContain("G3");
    more.click();
    expect(root().hasAttribute("data-gs-compact")).toBe(false);
    cells()[5]!.click();
    expect(root().hasAttribute("data-gs-compact")).toBe(true);
    pointerDown(outside);
    expect(tray.isOpen()).toBe(false);
    tray.open();
    expect(root().hasAttribute("data-gs-compact")).toBe(false);
  });

  it("close() returns focus only when it was inside the panel", () => {
    const tray = mk({ anchor });
    tray.open();
    outside.focus();
    tray.close();
    expect(document.activeElement).toBe(outside);
    tray.toggle();
    expect(tray.isOpen()).toBe(true);
    tray.close();
    expect(document.activeElement).toBe(anchor);
  });

  it("sending keeps it open, so people can send several", () => {
    const onSend = vi.fn();
    const tray = mk({ anchor, onSend });
    tray.open();
    const send = root().querySelector("[data-gs-send]") as HTMLButtonElement;
    pointerDown(send);
    send.click();
    send.click();
    expect(onSend).toHaveBeenCalledTimes(2);
    expect(tray.isOpen()).toBe(true);
  });

  it("is placed with a transform and repositioned once per frame on scroll and resize", () => {
    const tray = mk({ anchor });
    anchor.getBoundingClientRect = () =>
      ({ left: 1000, top: 600, right: 1040, bottom: 636, width: 40, height: 36 }) as DOMRect;
    Object.defineProperty(root(), "offsetHeight", { configurable: true, value: 500 });
    const win = document.defaultView!;
    Object.defineProperty(win, "innerHeight", { configurable: true, value: 800 });
    Object.defineProperty(document.documentElement, "clientWidth", {
      configurable: true,
      value: 1280,
    });
    tray.open();
    expect(root().style.transform).toBe("translate(660px, 92px)");
    expect(root().style.width).toBe("380px");
    expect(root().style.maxHeight).toBe("560px");
    expect(root().getAttribute("data-gs-side")).toBe("above");
    // Scrolled so far that the button is near the top: the next frame flips it below.
    anchor.getBoundingClientRect = () =>
      ({ left: 1000, top: 40, right: 1040, bottom: 76, width: 40, height: 36 }) as DOMRect;
    const spy = vi.spyOn(anchor, "getBoundingClientRect");
    win.dispatchEvent(new Event("scroll"));
    win.dispatchEvent(new Event("scroll"));
    win.dispatchEvent(new Event("resize"));
    expect(root().style.transform).toBe("translate(660px, 92px)");
    vi.advanceTimersByTime(20);
    expect(spy).toHaveBeenCalledTimes(1);
    expect(root().style.transform).toBe("translate(660px, 84px)");
    expect(root().getAttribute("data-gs-side")).toBe("below");
    // Closed: scrolling does not touch it.
    tray.close();
    win.dispatchEvent(new Event("scroll"));
    vi.advanceTimersByTime(20);
    expect(spy).toHaveBeenCalledTimes(1);
    delete (win as { innerHeight?: unknown }).innerHeight;
    delete (document.documentElement as { clientWidth?: unknown }).clientWidth;
  });

  it("grid: 4 columns by default, arrow keys move the selection, tiles have tooltips", () => {
    const tray = mk({ anchor });
    tray.open();
    const grid = root().querySelector(".gs-grid") as HTMLElement;
    expect(grid.style.getPropertyValue("--gs-columns")).toBe("4");
    expect(cells()[1]!.title).toBe("G1, 20 coins");
    key(cells()[0]!, "ArrowRight");
    expect(tray.getSelected()?.id).toBe("g1");
    expect(document.activeElement).toBe(cells()[1]);
    key(cells()[1]!, "End");
    expect(tray.getSelected()?.id).toBe("g11");
  });

  it("destroy leaves no DOM, no anchor attributes and no listeners", () => {
    const added: string[] = [];
    const docAdd = vi.spyOn(document, "addEventListener");
    const winAdd = vi.spyOn(document.defaultView!, "addEventListener");
    anchor.setAttribute("aria-haspopup", "menu");
    const tray = mk({ anchor });
    tray.open();
    for (const c of [...docAdd.mock.calls, ...winAdd.mock.calls]) added.push(c[0]);
    expect(added).toEqual(expect.arrayContaining(["keydown", "pointerdown", "scroll", "resize"]));
    const onOpen = vi.fn();
    tray.update({ onOpenChange: onOpen });
    tray.destroy();
    trays = [];
    expect(document.querySelector("[data-gs-tray]")).toBeNull();
    expect(document.querySelector("style[data-giftingstack]")).toBeNull();
    expect(anchor.getAttribute("aria-haspopup")).toBe("menu");
    expect(anchor.hasAttribute("aria-expanded")).toBe(false);
    expect(anchor.hasAttribute("aria-controls")).toBe(false);
    // Every listener is gone: the anchor, Escape, outside clicks and scrolls do nothing.
    anchor.click();
    key(document, "Escape");
    pointerDown(outside);
    document.defaultView!.dispatchEvent(new Event("scroll"));
    vi.advanceTimersByTime(20);
    expect(onOpen).not.toHaveBeenCalled();
    expect(FakeResizeObserver.all.size).toBe(0);
    docAdd.mockRestore();
    winAdd.mockRestore();
  });

  it("createGiftTray passes placement, anchor and onOpenChange through", async () => {
    const onOpenChange = vi.fn();
    const client = {
      getGifts: async () => GIFTS,
      getMe: async () => ({ user: "ayla", balance: 500 }),
      getReceivedGifts: async () => [],
      sendGift: async () => {
        throw new Error("not used");
      },
      ...componentCallStubs,
    };
    const handle = createGiftTray({
      container,
      client,
      receiver: "mert",
      placement: "popover",
      anchor,
      onOpenChange,
    });
    await vi.advanceTimersByTimeAsync(0);
    expect(handle.tray.getPlacement()).toBe("popover");
    anchor.click();
    expect(onOpenChange).toHaveBeenCalledWith(true);
    handle.destroy();
    expect(anchor.hasAttribute("aria-expanded")).toBe(false);
  });
});

describe("web tray placement: inline", () => {
  it("fills the container: no handle, no dialog, always shown; columns fit the width", () => {
    const tray = mk({ placement: "inline", anchor });
    expect(tray.getPlacement()).toBe("inline");
    expect(root().parentElement).toBe(container);
    expect(root().className).toBe("gs-tray gs-inline");
    expect(root().hidden).toBe(false);
    expect(root().getAttribute("role")).toBeNull();
    expect(anchor.hasAttribute("aria-haspopup")).toBe(false);
    expect(tray.isOpen()).toBe(true);
    const grid = root().querySelector(".gs-grid") as HTMLElement;
    expect(grid.hasAttribute("data-gs-fill")).toBe(true);
    expect(grid.style.getPropertyValue("--gs-columns")).toBe("");
    expect(CSS).toMatch(
      /\.gs-inline \.gs-grid\[data-gs-fill\] \{ grid-template-columns: repeat\(auto-fill, minmax\(84px, 1fr\)\)/,
    );
    expect(CSS).toMatch(/\.gs-inline \.gs-grid \{[^}]*overflow-y: auto/);
    // Clicking the anchor does nothing inline.
    anchor.click();
    expect(root().hidden).toBe(false);
  });

  it("explicit columns win over auto-fill; arrow keys work", () => {
    const tray = mk({ placement: "inline", columns: 6 });
    const grid = root().querySelector(".gs-grid") as HTMLElement;
    expect(grid.hasAttribute("data-gs-fill")).toBe(false);
    expect(grid.style.getPropertyValue("--gs-columns")).toBe("6");
    cells()[0]!.focus();
    key(cells()[0]!, "ArrowLeft");
    expect(tray.getSelected()?.id).toBe("g11");
    expect(document.activeElement).toBe(cells()[11]);
  });

  it("does not touch the inset callback", () => {
    const onInsetChange = vi.fn();
    mk({ placement: "inline", onInsetChange });
    expect(onInsetChange).not.toHaveBeenCalled();
  });

  it("hover and focus states are in the style sheet", () => {
    expect(CSS).toMatch(/@media \(hover: hover\) \{\s*\.gs-cell:hover/);
    expect(CSS).toMatch(/\.gs-cell:focus-visible \{ outline: 2px solid var\(--gs-accent\)/);
  });
});

describe("the hidden warm-up picture", () => {
  it("takes no room in the layout, also next to a page-wide img rule", () => {
    const host = document.createElement("div");
    document.body.appendChild(host);
    const page = document.createElement("style");
    page.textContent = "img { position: static; margin: 12px; }";
    document.head.appendChild(page);
    const tray = new GiftTray(host, {
      gifts: [
        {
          id: "g0",
          name: "G0",
          price: 10,
          description: null,
          icon_url: "i0",
          animation_url: "a0",
          sort_order: 0,
        },
      ],
      balance: 100,
      placement: "inline",
      onSend: async () => {},
    });
    const warm = host.querySelector(".gs-warmup") as HTMLElement | null;
    expect(warm).not.toBeNull();
    expect(getComputedStyle(warm!).position).toBe("absolute");
    tray.destroy();
    page.remove();
    host.remove();
  });
});
