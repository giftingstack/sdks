/**
 * The web tray as a popover next to the app's gift button (spec 9.3, web only): open and close,
 * Escape, a click outside, focus in and back, the anchor's ARIA, and the position from the pure
 * `positionPopover` (moved with a transform, updated once per frame on scroll and resize).
 */
import { POPOVER_MAX_HEIGHT_FRACTION, POPOVER_WIDTH, positionPopover } from "../core";

export interface PopoverViewOptions {
  /** The app's gift button. Its clicks toggle the popover. */
  anchor: HTMLElement;
  /** The tray's root: becomes the dialog. */
  root: HTMLElement;
  /** Gets focus on open: its selected cell (tabindex 0), else the dialog itself. */
  grid: HTMLElement;
  label: () => string;
  onOpenChange?: (open: boolean) => void;
}

let ids = 0;

export class PopoverView {
  private readonly o: PopoverViewOptions;
  private readonly doc: Document;
  private readonly win: (Window & typeof globalThis) | null;
  /** Lives as long as the view: the anchor's click. */
  private readonly base = new AbortController();
  /** Lives while open: Escape, outside click, scroll, resize. */
  private openListeners: AbortController | null = null;
  private readonly savedAnchor: Record<string, string | null>;
  private readonly ownId: boolean;
  private isOpenNow = false;
  private raf = 0;
  private remeasure = false;
  private natural = 0;
  private lastMaxHeight = -1;

  constructor(options: PopoverViewOptions) {
    this.o = options;
    const { anchor, root } = options;
    this.doc = root.ownerDocument;
    this.win = this.doc.defaultView as (Window & typeof globalThis) | null;
    this.ownId = !root.id;
    if (this.ownId) root.id = `gs-tray-${++ids}`;
    root.hidden = true;
    root.setAttribute("role", "dialog");
    root.setAttribute("aria-label", options.label());
    this.savedAnchor = {};
    for (const name of ["aria-haspopup", "aria-expanded", "aria-controls"])
      this.savedAnchor[name] = anchor.getAttribute(name);
    anchor.setAttribute("aria-haspopup", "dialog");
    anchor.setAttribute("aria-expanded", "false");
    anchor.setAttribute("aria-controls", root.id);
    anchor.addEventListener("click", () => this.toggle(), { signal: this.base.signal });
  }

  isOpen(): boolean {
    return this.isOpenNow;
  }

  open(): void {
    if (this.isOpenNow) return;
    this.isOpenNow = true;
    const { root, anchor } = this.o;
    root.hidden = false;
    root.setAttribute("aria-label", this.o.label());
    anchor.setAttribute("aria-expanded", "true");
    this.measure();
    this.listen();
    const target = this.o.grid.querySelector<HTMLElement>('[tabindex="0"]');
    if (target) target.focus();
    else {
      root.tabIndex = -1;
      root.focus();
    }
    this.o.onOpenChange?.(true);
  }

  /**
   * `returnFocus`: put focus back on the anchor when it was inside the panel (or nowhere). An
   * outside click passes `false`: the person moved on to what they clicked.
   */
  close(returnFocus = true): void {
    if (!this.isOpenNow) return;
    this.isOpenNow = false;
    const { root, anchor } = this.o;
    const active = this.doc.activeElement;
    const focusInside = !active || active === this.doc.body || root.contains(active);
    this.stopListening();
    root.hidden = true;
    anchor.setAttribute("aria-expanded", "false");
    if (returnFocus && focusInside) anchor.focus();
    this.o.onOpenChange?.(false);
  }

  toggle(): void {
    if (this.isOpenNow) this.close();
    else this.open();
  }

  /** Measure the content again (new gifts, resize) and place the panel. */
  measure(): void {
    if (!this.isOpenNow) return;
    const { root } = this.o;
    const cap = Math.round(this.viewport().height * POPOVER_MAX_HEIGHT_FRACTION);
    root.style.maxHeight = `${cap}px`;
    this.lastMaxHeight = cap;
    this.natural = root.offsetHeight;
    this.position();
  }

  /** Silent teardown: no `onOpenChange`, the anchor and the root get their attributes back. */
  destroy(): void {
    this.stopListening();
    this.base.abort();
    this.isOpenNow = false;
    const { root, anchor } = this.o;
    for (const [name, value] of Object.entries(this.savedAnchor)) {
      if (value === null) anchor.removeAttribute(name);
      else anchor.setAttribute(name, value);
    }
    root.hidden = false;
    root.removeAttribute("role");
    root.removeAttribute("aria-label");
    root.removeAttribute("tabindex");
    root.removeAttribute("data-gs-side");
    if (this.ownId) root.removeAttribute("id");
    root.style.removeProperty("transform");
    root.style.removeProperty("max-height");
    root.style.removeProperty("width");
  }

  private viewport(): { width: number; height: number } {
    const el = this.doc.documentElement;
    return {
      width: el.clientWidth || this.win?.innerWidth || 0,
      height: this.win?.innerHeight || el.clientHeight || 0,
    };
  }

  private position(): void {
    const { root, anchor } = this.o;
    const r = anchor.getBoundingClientRect();
    const pos = positionPopover({
      anchor: { left: r.left, top: r.top, right: r.right, bottom: r.bottom },
      panel: { width: POPOVER_WIDTH, height: this.natural },
      viewport: this.viewport(),
    });
    root.style.width = `${pos.width}px`;
    if (pos.maxHeight !== this.lastMaxHeight) {
      this.lastMaxHeight = pos.maxHeight;
      root.style.maxHeight = `${pos.maxHeight}px`;
    }
    root.style.transform = `translate(${pos.left}px, ${pos.top}px)`;
    root.setAttribute("data-gs-side", pos.side);
  }

  private schedule(remeasure: boolean): void {
    this.remeasure ||= remeasure;
    if (this.raf) return;
    this.raf = requestAnimationFrame(() => {
      this.raf = 0;
      const again = this.remeasure;
      this.remeasure = false;
      if (again) this.measure();
      else this.position();
    });
  }

  private listen(): void {
    this.openListeners = new AbortController();
    const signal = this.openListeners.signal;
    const { root, anchor } = this.o;
    this.doc.addEventListener(
      "keydown",
      (e) => {
        if (e.key === "Escape") {
          e.preventDefault();
          this.close();
        }
      },
      { signal },
    );
    this.doc.addEventListener(
      "pointerdown",
      (e) => {
        const t = e.target as Node | null;
        if (t && (root.contains(t) || anchor.contains(t))) return;
        this.close(false);
      },
      { capture: true, signal },
    );
    this.win?.addEventListener("scroll", () => this.schedule(false), {
      capture: true,
      passive: true,
      signal,
    });
    this.win?.addEventListener("resize", () => this.schedule(true), { signal });
  }

  private stopListening(): void {
    this.openListeners?.abort();
    this.openListeners = null;
    cancelAnimationFrame(this.raf);
    this.raf = 0;
    this.remeasure = false;
  }
}
