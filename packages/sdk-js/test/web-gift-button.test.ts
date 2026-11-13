/**
 * The gift button in the app's message bar (spec 20): `GiftButton`, `<gift-button>` and the
 * tray's `input` option (the keyboard swap). jsdom has no layout: the sheet's measured sizes are
 * stubbed as in web-sheet.test.ts (container 780: peek 128, default floor 310) and the keyboard
 * comes from a stubbed `visualViewport`.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Gift } from "../src/core";
import {
  GIFT_GLYPH_PATH,
  GiftButton,
  GiftButtonElement,
  GiftTray,
  type GiftTrayOptions,
  defineGiftElements,
} from "../src/web";
import { FAKE_TIMERS, PAGE, installWebEnv } from "./web-setup";

const gift = (id: string, price: number, order = 0): Gift => ({
  id,
  name: id.toUpperCase(),
  description: null,
  price,
  icon_url: `https://assets.test/${id}/256.webp`,
  animation_url: null,
  sort_order: order,
});
const GIFTS = Array.from({ length: 12 }, (_, i) => gift(`g${i}`, 10 * (i + 1), i));
const SIZES = { gridTop: 58, footer: 70, cell: 83 };

let env: ReturnType<typeof installWebEnv>;
let container: HTMLElement;
let bar: HTMLElement;
let input: HTMLInputElement;
let trays: GiftTray[] = [];
let buttons: GiftButton[] = [];
let restore: (() => void)[] = [];

function stubSizes() {
  const proto = HTMLElement.prototype;
  const top = Object.getOwnPropertyDescriptor(proto, "offsetTop");
  const height = Object.getOwnPropertyDescriptor(proto, "offsetHeight");
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
    if (top) Object.defineProperty(proto, "offsetTop", top);
    else delete (proto as { offsetTop?: unknown }).offsetTop;
    if (height) Object.defineProperty(proto, "offsetHeight", height);
    else delete (proto as { offsetHeight?: unknown }).offsetHeight;
  };
}

/** A phone's visual viewport: `keyboard` px of the window covered at the bottom. */
function stubViewport() {
  const vv = new EventTarget() as EventTarget & { height: number; offsetTop: number };
  vv.height = window.innerHeight;
  vv.offsetTop = 0;
  Object.defineProperty(window, "visualViewport", { configurable: true, value: vv });
  return {
    keyboard(px: number) {
      vv.height = window.innerHeight - px;
      vv.dispatchEvent(new Event("resize"));
    },
    restore: () => delete (window as { visualViewport?: unknown }).visualViewport,
  };
}

let viewport: ReturnType<typeof stubViewport>;

beforeEach(() => {
  env = installWebEnv();
  PAGE.width = 390;
  restore = [stubSizes()];
  viewport = stubViewport();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
  container = document.createElement("div");
  bar = document.createElement("form");
  input = document.createElement("input");
  bar.appendChild(input);
  document.body.append(container, bar);
});
afterEach(() => {
  for (const t of trays) t.destroy();
  for (const b of buttons) b.destroy();
  trays = [];
  buttons = [];
  container.remove();
  bar.remove();
  vi.useRealTimers();
  for (const r of restore) r();
  viewport.restore();
  env.restore();
});

const button = (o: ConstructorParameters<typeof GiftButton>[1] = {}) => {
  const b = new GiftButton(bar, o);
  buttons.push(b);
  return b;
};
const tray = (o: GiftTrayOptions = {}) => {
  const t = new GiftTray(container, { gifts: GIFTS, balance: 1000, ...o });
  trays.push(t);
  return t;
};
const settle = () => vi.advanceTimersByTime(800);
const visible = (t: GiftTray) => t.getSheetState()!.visibleHeight;

describe("GiftButton (spec 20.4)", () => {
  it("is a labelled round button with the gift glyph, plain by default", () => {
    const b = button();
    const el = b.element;
    expect(el.tagName).toBe("BUTTON");
    expect(el.type).toBe("button");
    expect(el.classList.contains("gs-gift-button")).toBe(true);
    expect(el.getAttribute("aria-label")).toBe("Send a gift");
    expect(el.hasAttribute("data-gs-filled")).toBe(false);
    expect(el.style.getPropertyValue("--gs-size")).toBe("36px");
    expect(el.querySelector("svg path")!.getAttribute("d")).toBe(GIFT_GLYPH_PATH);
    expect(el.querySelector("svg")!.getAttribute("aria-hidden")).toBe("true");
  });

  it("takes label, filled, size, disabled and the theme; update changes them", () => {
    const press = vi.fn();
    const b = button({
      label: "Gift",
      filled: true,
      size: "large",
      theme: { accent: "#ff0000" },
      onPress: press,
    });
    expect(b.element.getAttribute("aria-label")).toBe("Gift");
    expect(b.element.hasAttribute("data-gs-filled")).toBe(true);
    expect(b.element.style.getPropertyValue("--gs-size")).toBe("44px");
    expect(b.element.style.getPropertyValue("--gs-accent")).toBe("#ff0000");
    b.element.click();
    expect(press).toHaveBeenCalledTimes(1);
    b.update({ disabled: true });
    expect(b.element.disabled).toBe(true);
    b.element.click();
    expect(press).toHaveBeenCalledTimes(1);
  });

  it("size is one of three names (32 / 36 / 44); anything else is medium", () => {
    const px = (b: GiftButton) => b.element.style.getPropertyValue("--gs-size");
    expect(px(button({ size: "small" }))).toBe("32px");
    expect(px(button({ size: "medium" }))).toBe("36px");
    expect(px(button({ size: "large" }))).toBe("44px");
    expect(px(button({ size: 50 as never }))).toBe("36px");
    expect(px(button({ size: "huge" as never }))).toBe("36px");
    expect(px(button({ size: "toString" as never }))).toBe("36px");
    const b = button({ size: "small" });
    b.update({ size: "nope" as never });
    expect(px(b)).toBe("36px");
  });

  it("icon: SVG markup replaces the glyph and keeps currentColor", () => {
    const b = button({
      icon: '<svg viewBox="0 0 10 10" width="500" height="500"><path d="M0 0h10v10z" fill="currentColor"/></svg>',
    });
    const glyph = b.element.querySelector(".gs-gift-glyph")!;
    expect(glyph.childElementCount).toBe(1);
    const svg = glyph.querySelector("svg")!;
    expect(svg.namespaceURI).toBe("http://www.w3.org/2000/svg");
    expect(svg.classList.contains("gs-gift-default")).toBe(false);
    expect(svg.querySelector("path")!.getAttribute("fill")).toBe("currentColor");
    expect(b.element.querySelector(`path[d="${GIFT_GLYPH_PATH}"]`)).toBeNull();
  });

  it("icon: scripts and handler attributes in the markup are dropped", () => {
    const b = button({
      icon: '<svg onload="x()"><script>x()</script><a href="javascript:x()"><path d="M0 0"/></a></svg>',
    });
    const svg = b.element.querySelector(".gs-gift-glyph svg")!;
    expect(svg.hasAttribute("onload")).toBe(false);
    expect(svg.querySelector("script")).toBeNull();
    expect(svg.querySelector("a")!.hasAttribute("href")).toBe(false);
  });

  it("icon: a Node is used as is (an <img> too)", () => {
    const img = document.createElement("img");
    img.src = "https://assets.test/heart.png";
    const b = button({ icon: img });
    expect(b.element.querySelector(".gs-gift-glyph > img")).toBe(img);
    expect(b.element.querySelector("path")).toBeNull();
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    b.update({ icon: svg });
    expect(b.element.querySelector(".gs-gift-glyph > svg")).toBe(svg);
    expect(img.isConnected).toBe(false);
  });

  it("icon: a string whose root is not <svg> is refused (the gift glyph stays)", () => {
    for (const icon of [
      "<div>x</div>",
      "plain text",
      "",
      '<img src="x">',
      "<svg></svg><svg></svg>",
      "<svg></svg>after",
    ]) {
      const b = button({ icon });
      expect(b.element.querySelector("path")!.getAttribute("d")).toBe(GIFT_GLYPH_PATH);
      expect(b.element.querySelector("[data-gs-custom-icon]")).toBeNull();
    }
  });

  it("update() changes the icon; icon: undefined restores the gift glyph; other patches keep it", () => {
    const b = button();
    b.update({ icon: '<svg id="one"></svg>' });
    expect(b.element.querySelector("#one")).not.toBeNull();
    const kept = b.element.querySelector("#one");
    b.update({ label: "Other" });
    expect(b.element.querySelector("#one")).toBe(kept);
    b.update({ icon: '<svg id="two"></svg>' });
    expect(b.element.querySelector("#one")).toBeNull();
    expect(b.element.querySelector("#two")).not.toBeNull();
    b.update({ icon: undefined });
    expect(b.element.querySelector("path")!.getAttribute("d")).toBe(GIFT_GLYPH_PATH);
    expect(b.element.querySelectorAll(".gs-gift-glyph > *")).toHaveLength(1);
  });

  it("the glyph box is fixed whatever the icon: a clipped wrapper that fits its child", () => {
    const b = button({ icon: '<svg width="999" height="999"></svg>' });
    const sheet = Array.from(document.querySelectorAll("style"))
      .map((x) => x.textContent)
      .join("");
    expect(sheet).toMatch(/\.gs-gift-glyph \{[^}]*overflow: hidden/);
    expect(sheet).toMatch(/\.gs-gift-glyph > \* \{[^}]*max-width: 100%[^}]*max-height: 100%/);
    expect(b.element.querySelector(".gs-gift-glyph")).not.toBeNull();
  });

  it("destroy removes it", () => {
    const b = button();
    b.destroy();
    expect(bar.querySelector(".gs-gift-button")).toBeNull();
  });
});

describe("tray input binding (spec 20.3): the keyboard swap on a phone", () => {
  it("starts closed; an explicit open still wins", () => {
    const b = button();
    expect(tray({ anchor: b.element, input }).isOpen()).toBe(false);
    expect(tray({ anchor: b.element, input, open: true }).isOpen()).toBe(true);
  });

  it("the button closes the keyboard and opens the tray; again: closes it and focuses the field", () => {
    const b = button();
    const opens: boolean[] = [];
    const t = tray({ anchor: b.element, input, onOpenChange: (o) => opens.push(o) });
    expect(b.element.getAttribute("aria-expanded")).toBe("false");
    input.focus();
    expect(document.activeElement).toBe(input);
    b.element.click();
    expect(t.isOpen()).toBe(true);
    expect(document.activeElement).not.toBe(input);
    expect(b.element.getAttribute("aria-expanded")).toBe("true");
    b.element.click();
    expect(t.isOpen()).toBe(false);
    expect(document.activeElement).toBe(input);
    expect(b.element.getAttribute("aria-expanded")).toBe("false");
    expect(opens).toEqual([true, false]);
  });

  it("a focus on the field closes the tray and does nothing else", () => {
    const b = button();
    const t = tray({ anchor: b.element, input });
    b.element.click();
    expect(t.isOpen()).toBe(true);
    input.focus();
    expect(t.isOpen()).toBe(false);
    expect(document.activeElement).toBe(input);
    // Closed: a focus changes nothing.
    input.blur();
    input.focus();
    expect(t.isOpen()).toBe(false);
  });

  it("toggle() is the swap, open() blurs the field, close() leaves the focus alone", () => {
    const t = tray({ input });
    input.focus();
    t.open();
    expect(t.isOpen()).toBe(true);
    expect(document.activeElement).not.toBe(input);
    t.close();
    expect(document.activeElement).not.toBe(input);
    t.toggle();
    expect(t.isOpen()).toBe(true);
    t.toggle();
    expect(t.isOpen()).toBe(false);
    expect(document.activeElement).toBe(input);
  });

  it("no dim by default: the chat above stays visible and touchable", () => {
    const b = button();
    tray({ anchor: b.element, input });
    b.element.click();
    settle();
    expect(container.querySelector("[data-gs-scrim]")).toBeNull();
  });

  it("opens in the keyboard's place: the last keyboard height seen", () => {
    const b = button();
    const t = tray({ anchor: b.element, input });
    input.focus();
    viewport.keyboard(380);
    viewport.keyboard(0); // the keyboard went down: the height is kept
    b.element.click();
    settle();
    expect(t.getSheetState()!.snap).toBe("default");
    expect(visible(t)).toBe(380);
  });

  it("before any keyboard: 300, but never below the tray's own floor; capped at 60 %", () => {
    const b = button();
    const t = tray({ anchor: b.element, input });
    b.element.click();
    settle();
    // fallback 300 < the floor (header, two rows, Send) 310
    expect(visible(t)).toBe(310);
    t.close();
    viewport.keyboard(600);
    t.open();
    settle();
    expect(visible(t)).toBe(Math.floor(780 * 0.6));
  });

  it("an accessory bar is not a keyboard; the host's own snaps.default wins", () => {
    const b = button();
    const t = tray({ anchor: b.element, input, snaps: { default: 0.5 } });
    viewport.keyboard(400);
    viewport.keyboard(44);
    b.element.click();
    settle();
    expect(visible(t)).toBe(390);
  });

  it("without input nothing changes: open by default, the anchor does not toggle the sheet", () => {
    const b = button();
    const t = tray({ anchor: b.element });
    expect(t.isOpen()).toBe(true);
    b.element.click();
    expect(t.isOpen()).toBe(true);
    expect(b.element.hasAttribute("aria-expanded")).toBe(false);
  });

  it("destroy removes the listeners and gives the anchor its attribute back", () => {
    const b = button();
    const t = tray({ anchor: b.element, input });
    b.element.click();
    t.destroy();
    expect(b.element.hasAttribute("aria-expanded")).toBe(false);
    b.element.click();
    input.focus();
    expect(t.isOpen()).toBe(true); // nothing listens any more
  });
});

describe("tray input binding on a wide screen: the popover", () => {
  it("the button opens and closes the popover once per click, and gives the field focus back", () => {
    PAGE.width = 1100;
    const b = button();
    const t = tray({ anchor: b.element, input });
    expect(t.getPlacement()).toBe("popover");
    b.element.click();
    expect(t.isOpen()).toBe(true);
    expect(b.element.getAttribute("aria-expanded")).toBe("true");
    b.element.click();
    expect(t.isOpen()).toBe(false);
    expect(document.activeElement).toBe(input);
    b.element.click();
    expect(t.isOpen()).toBe(true);
    input.focus();
    expect(t.isOpen()).toBe(false);
  });
});

describe("<gift-button> and <gift-tray input>", () => {
  it("renders the button, fires gift-button-press and serves as the tray's anchor", async () => {
    defineGiftElements();
    const el = document.createElement("gift-button") as GiftButtonElement;
    el.setAttribute("label", "Gift");
    el.setAttribute("filled", "");
    bar.appendChild(el);
    const inner = el.button!;
    expect(inner.getAttribute("aria-label")).toBe("Gift");
    expect(inner.hasAttribute("data-gs-filled")).toBe(true);
    const pressed = vi.fn();
    el.addEventListener("gift-button-press", pressed);
    inner.click();
    expect(pressed).toHaveBeenCalledTimes(1);
    expect(inner.style.getPropertyValue("--gs-size")).toBe("36px");
    el.setAttribute("size", "large");
    expect(inner.style.getPropertyValue("--gs-size")).toBe("44px");
    el.setAttribute("size", "small");
    expect(inner.style.getPropertyValue("--gs-size")).toBe("32px");
    el.setAttribute("size", "44"); // a number is not a name
    expect(inner.style.getPropertyValue("--gs-size")).toBe("36px");
    el.icon = '<svg id="el-icon"></svg>';
    expect(inner.querySelector("#el-icon")).not.toBeNull();
    el.icon = undefined;
    expect(inner.querySelector("#el-icon")).toBeNull();
    expect(inner.querySelector("path")).not.toBeNull();
    el.remove();
    await Promise.resolve();
    expect(el.button).toBeNull();
  });
});
