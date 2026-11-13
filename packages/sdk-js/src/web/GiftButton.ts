import { acquireStyles, releaseStyles } from "./styles";
import { type GiftTheme, applyTheme } from "./theme";

/** The three fixed sizes of spec 20.4. */
export type GiftButtonSize = "small" | "medium" | "large";

/** The circle diameter in px of each size name. */
export const GIFT_BUTTON_SIZES: Record<GiftButtonSize, number> = {
  small: 32,
  medium: 36,
  large: 44,
};

/** The circle diameter for a size name; anything unknown is `medium` (36). */
export function giftButtonDiameter(size: unknown): number {
  return typeof size === "string" && Object.hasOwn(GIFT_BUTTON_SIZES, size)
    ? GIFT_BUTTON_SIZES[size as GiftButtonSize]
    : GIFT_BUTTON_SIZES.medium;
}

export interface GiftButtonOptions {
  /** Screen reader label. Default "Send a gift". */
  label?: string;
  /** `false` (default): no background, the glyph in `accent`, like an emoji button. `true`: an `accent` circle. */
  filled?: boolean;
  /** One of three fixed sizes (circle 32 / 36 / 44 px). Default `"medium"`; an unknown value is `"medium"`. */
  size?: GiftButtonSize;
  /**
   * Replaces the gift glyph (spec 20.4). A string is SVG markup (its root must be `<svg>`, else the
   * default glyph stays); `currentColor` follows the glyph colour. A Node (an `<svg>`, an `<img>`)
   * is used as is; an `<img>` is not tinted. It is centred in the fixed glyph box and fitted into
   * it: scaled down, never up, clipped, so it can never change the button's size. `undefined`
   * restores the gift glyph.
   */
  icon?: string | Node;
  disabled?: boolean;
  /** The tray's theme tokens (`accent`, `accentText`, `selected`). */
  theme?: Partial<GiftTheme>;
  /**
   * Called on every press. With a tray, pass `element` as the tray's `anchor` instead: the tray
   * opens and closes from it (and swaps with the keyboard when it has an `input`).
   */
  onPress?: () => void;
}

/** The gift glyph of spec 20.4, drawn with strokes in a 24 x 24 box. */
export const GIFT_GLYPH_PATH =
  "M4 11h16v10H4zM3 7h18v4H3zM12 7v14M12 7C10 7 8 6 8 4.5C8 3 10 3 12 7zM12 7C14 7 16 6 16 4.5C16 3 14 3 12 7z";

const SVG_NS = "http://www.w3.org/2000/svg";

/**
 * Host SVG markup -> an `<svg>` element, or null when the root is not an `<svg>`. Parsed in an
 * inert `<template>`; scripts, event handler attributes and `javascript:` links are dropped.
 */
function parseSvg(doc: Document, markup: string): SVGSVGElement | null {
  const tpl = doc.createElement("template");
  tpl.innerHTML = markup.trim();
  const roots = Array.from(tpl.content.childNodes).filter(
    (n) => n.nodeType !== 8 && !(n.nodeType === 3 && !n.textContent?.trim()),
  );
  const root = roots[0];
  if (roots.length !== 1 || root?.nodeType !== 1) return null;
  const svg = root as Element;
  if (svg.localName !== "svg" || svg.namespaceURI !== SVG_NS) return null;
  for (const el of [svg, ...Array.from(svg.querySelectorAll("*"))]) {
    if (el.localName === "script") {
      el.remove();
      continue;
    }
    for (const a of Array.from(el.attributes)) {
      if (/^on/i.test(a.name) || /^\s*javascript:/i.test(a.value)) el.removeAttribute(a.name);
    }
  }
  svg.setAttribute("aria-hidden", "true");
  svg.setAttribute("focusable", "false");
  return svg as SVGSVGElement;
}

/**
 * A small round gift button for the app's own message bar, next to its text field or emoji
 * button (spec 20.4). Pass `element` as the tray's `anchor` and the text field as its `input`:
 * a press closes the keyboard and opens the tray in its place.
 */
export class GiftButton {
  /** The `<button>`: pass it as the tray's `anchor`. */
  readonly element: HTMLButtonElement;
  private o: GiftButtonOptions;
  private glyph: HTMLSpanElement;
  private shownIcon: string | Node | undefined;
  private destroyed = false;

  constructor(container: HTMLElement, options: GiftButtonOptions = {}) {
    const doc = container.ownerDocument;
    acquireStyles(doc);
    this.o = options;
    const el = doc.createElement("button");
    el.type = "button";
    el.className = "gs-gift-button";
    el.setAttribute("data-gs-gift-button", "");
    this.glyph = doc.createElement("span");
    this.glyph.className = "gs-gift-glyph";
    this.glyph.setAttribute("aria-hidden", "true");
    el.appendChild(this.glyph);
    el.addEventListener("click", () => {
      if (!this.o.disabled) this.o.onPress?.();
    });
    this.element = el;
    this.render();
    container.appendChild(el);
  }

  /** Change the label, look, icon, theme or callback. */
  update(patch: GiftButtonOptions): void {
    this.o = { ...this.o, ...patch };
    this.render();
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.element.remove();
    releaseStyles();
  }

  private defaultGlyph(doc: Document): SVGSVGElement {
    const svg = doc.createElementNS(SVG_NS, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("focusable", "false");
    svg.setAttribute("class", "gs-gift-default");
    const path = doc.createElementNS(SVG_NS, "path");
    path.setAttribute("d", GIFT_GLYPH_PATH);
    svg.appendChild(path);
    return svg;
  }

  private renderIcon(): void {
    const icon = this.o.icon;
    if (this.glyph.firstChild && icon === this.shownIcon) return;
    this.shownIcon = icon;
    const doc = this.element.ownerDocument;
    let node: Node | null = null;
    if (typeof icon === "string") node = parseSvg(doc, icon);
    else if (icon) node = icon;
    this.glyph.replaceChildren(node ?? this.defaultGlyph(doc));
    this.glyph.toggleAttribute("data-gs-custom-icon", node !== null);
  }

  private render(): void {
    const el = this.element;
    const { label = "Send a gift", filled = false, size, disabled = false } = this.o;
    el.setAttribute("aria-label", label);
    el.title = label;
    el.toggleAttribute("data-gs-filled", filled);
    el.disabled = disabled;
    el.style.setProperty("--gs-size", `${giftButtonDiameter(size)}px`);
    this.renderIcon();
    applyTheme(el, this.o.theme);
  }
}
