/**
 * The web tray as a bottom sheet (spec 9.1): pointer events with pointer capture, `touch-action`,
 * the handle button (`aria-expanded`, arrow keys), reduced motion. All decisions come from the
 * core `TraySheetController`; this file only measures, moves the body with `translateY` and
 * passes the pointer through.
 */
import {
  type SheetLayout,
  type SheetSnap,
  type TraySheetState,
  TraySheetController,
} from "../core";

/** Movement before a press becomes a drag, px. Below it, a press stays a tap or a click. */
export const SHEET_SLOP = 6;
/** The longest the tray stays invisible while it waits for its first measurements, ms. */
const SHEET_READY_MAX_MS = 700;

/** After a wheel step the next ticks are ignored this long (one state per flick, trackpad inertia). */
const WHEEL_LOCK_MS = 400;

/** Velocity is measured over the last part of the gesture, ms. */
export const VELOCITY_WINDOW_MS = 100;

export interface SheetElements {
  root: HTMLElement;
  body: HTMLElement;
  handle: HTMLButtonElement;
  head: HTMLElement;
  grid: HTMLElement;
  footer: HTMLElement;
}

export interface SheetViewOptions {
  container: HTMLElement;
  initialSnap?: SheetSnap;
  snaps?: SheetLayout["snaps"];
  columns: () => number;
  onSnapChange?: (snap: SheetSnap) => void;
  onInsetChange?: (px: number) => void;
  /** Start closed (`TrayOpenState`, spec 9.4): hidden and reporting inset 0. Default open. */
  open?: boolean;
  /** Called at the end of every paint (a state change, a drag frame, a phase change). */
  onPaint?: () => void;
}

/** Px per second (positive = down) from samples of the last `VELOCITY_WINDOW_MS`. */
export function velocityOf(samples: { t: number; y: number }[]): number {
  const last = samples[samples.length - 1];
  if (!last) return 0;
  const first = samples.find((s) => last.t - s.t <= VELOCITY_WINDOW_MS) ?? last;
  const dt = last.t - first.t;
  return dt > 0 ? ((last.y - first.y) / dt) * 1000 : 0;
}

interface Gesture {
  id: number;
  startX: number;
  startY: number;
  lastY: number;
  onGrid: boolean;
  mode: "pending" | "sheet" | "grid" | "none";
  samples: { t: number; y: number }[];
}

export class SheetView {
  readonly controller: TraySheetController;
  private readonly e: SheetElements;
  private readonly o: SheetViewOptions;
  private readonly motion: MediaQueryList | null;
  private readonly resizeObserver: ResizeObserver | null;
  private readonly savedPosition: string | null;
  private readonly unsubscribe: () => void;
  private readonly doc: Document;
  // While a press lasts, its moves and its end are followed on the whole document: before the
  // drag starts there is no pointer capture, and the finger may leave the sheet.
  private readonly onMove = (ev: PointerEvent): void => this.moveTo(ev);
  private readonly onUp = (ev: PointerEvent): void => this.up(ev);
  private readonly onCancel = (ev: PointerEvent): void => this.cancel(ev);
  private gesture: Gesture | null = null;
  private suppressClick = false;
  private wheelLockUntil = 0;
  private lastInset = -1;
  private closed: boolean;
  /**
   * Until the container, the footer and the first gift are measured the snap heights are guesses, and
   * the body would glide (CSS transition) from a wrong spot to the right one. So: "measuring" keeps
   * the tray invisible, "placing" shows it at its place without a transition, "live" animates.
   */
  private phase: "measuring" | "placing" | "live" = "measuring";
  private phaseTimer: ReturnType<typeof setTimeout> | undefined;
  private snaps: SheetLayout["snaps"];
  private readonly listeners = new AbortController();

  constructor(elements: SheetElements, options: SheetViewOptions) {
    this.e = elements;
    this.o = options;
    this.snaps = options.snaps;
    this.closed = options.open === false;
    this.doc = options.container.ownerDocument;
    const win = options.container.ownerDocument.defaultView;
    this.motion = win?.matchMedia?.("(prefers-reduced-motion: reduce)") ?? null;

    this.savedPosition = null;
    if (win && win.getComputedStyle(options.container).position === "static") {
      this.savedPosition = options.container.style.position;
      options.container.style.position = "relative";
    }

    this.controller = new TraySheetController({
      initialSnap: options.initialSnap,
      onSnapChange: (snap) => this.o.onSnapChange?.(snap),
    });
    this.unsubscribe = this.controller.subscribe(() => this.paint());

    const { body, handle, grid, root } = elements;
    // The tray's elements outlive the sheet when its placement changes: one signal removes all.
    const signal = this.listeners.signal;
    handle.addEventListener(
      "click",
      () => {
        if (!this.consumeSuppressedClick()) this.controller.toggle();
      },
      { signal },
    );
    handle.addEventListener(
      "keydown",
      (ev) => {
        if (ev.key === "ArrowUp" || ev.key === "ArrowDown") {
          ev.preventDefault();
          this.controller.step(ev.key === "ArrowUp" ? 1 : -1);
        }
      },
      { signal },
    );
    body.addEventListener("pointerdown", (ev) => this.down(ev), { signal });
    grid.addEventListener("scroll", () => this.paintTouchAction(), { passive: true, signal });
    // A mouse wheel has no drag: over the sheet it opens and closes it (not passive: it must stop
    // the page behind from scrolling).
    body.addEventListener("wheel", (ev) => this.wheel(ev), { passive: false, signal });
    // A drag must not end in a click on whatever is under the finger (a cell, the handle).
    root.addEventListener(
      "click",
      (ev) => {
        if (ev.target !== handle && this.consumeSuppressedClick()) {
          ev.stopPropagation();
          ev.preventDefault();
        }
      },
      { capture: true, signal },
    );

    const RO = win?.ResizeObserver;
    this.resizeObserver = RO ? new RO(() => this.measure()) : null;
    this.resizeObserver?.observe(options.container);
    this.resizeObserver?.observe(elements.footer);
    this.resizeObserver?.observe(elements.head);
    elements.root.hidden = this.closed;
    this.measure();
    this.paint();
    // An empty catalog never has a first gift to wait for: do not stay invisible for it.
    this.phaseTimer = setTimeout(() => this.advance(true), SHEET_READY_MAX_MS);
  }

  setSnaps(snaps: SheetLayout["snaps"]): void {
    this.snaps = snaps;
    this.measure();
  }

  /** Reads the sizes the snap heights are built from (spec 9.1, "Content floors"). */
  measure(): void {
    const { grid, footer } = this.e;
    const containerHeight = this.o.container.clientHeight;
    const top = grid.offsetTop;
    const peekMinHeight = top + footer.offsetHeight;
    const first = grid.firstElementChild as HTMLElement | null;
    const rowHeight = first ? first.offsetHeight + 8 : 0; // cell margins 4 + 4
    const rows = Math.ceil(grid.children.length / Math.max(1, this.o.columns()));
    this.controller.setLayout({
      containerHeight,
      snaps: this.snaps,
      peekMinHeight,
      defaultMinHeight: peekMinHeight + Math.min(2, rows) * rowHeight,
      contentHeight: peekMinHeight + rows * rowHeight,
    });
    this.advance();
  }

  getState(): TraySheetState {
    return this.controller.getState();
  }

  /** The sheet is measured and drawn where it belongs (spec 9.4: the scrim waits for it). */
  isPlaced(): boolean {
    return !this.closed && this.phase !== "measuring";
  }

  /**
   * Show or hide the whole sheet (spec 9.4). Closing hides it and reports inset 0. Opening moves
   * it to `initialSnap` without a glide, measures again, shows it when placed and reports the
   * inset again.
   */
  setOpen(open: boolean): void {
    if (open === !this.closed) return;
    this.closed = !open;
    clearTimeout(this.phaseTimer);
    this.endGesture();
    this.e.root.hidden = this.closed;
    this.phase = "measuring";
    if (open) {
      this.lastInset = -1;
      this.controller.snapTo(this.o.initialSnap ?? "default");
      this.measure();
      this.phaseTimer = setTimeout(() => this.advance(true), SHEET_READY_MAX_MS);
    }
    this.paint();
  }

  /** The sizes the snap heights are built from are all known (or the wait was given up). */
  private ready(): boolean {
    const { grid, footer } = this.e;
    return this.o.container.clientHeight > 0 && footer.offsetHeight > 0 && grid.children.length > 0;
  }

  /** measuring -> placing (visible, no transition) -> live (transitions on, next frame). */
  private advance(force = false): void {
    if (this.closed || this.phase !== "measuring" || !(force || this.ready())) return;
    clearTimeout(this.phaseTimer);
    this.phase = "placing";
    this.paint();
    const win = this.doc.defaultView;
    const next = (): void => {
      if (this.phase !== "placing") return;
      this.phase = "live";
      this.paint();
    };
    if (win?.requestAnimationFrame)
      win.requestAnimationFrame(() => win.requestAnimationFrame(next));
    else this.phaseTimer = setTimeout(next, 32);
  }

  /** Stops listening and takes back every style and attribute it put on the tray's elements. */
  destroy(): void {
    clearTimeout(this.phaseTimer);
    this.phase = "live";
    this.closed = false;
    this.e.root.hidden = false;
    this.e.root.style.removeProperty("opacity");
    this.endGesture();
    this.unsubscribe();
    this.listeners.abort();
    this.resizeObserver?.disconnect();
    if (this.savedPosition !== null) this.o.container.style.position = this.savedPosition;
    const { root, body, handle, grid } = this.e;
    root.style.removeProperty("height");
    root.removeAttribute("data-gs-snap");
    root.removeAttribute("data-gs-grid-scroll");
    root.classList.remove("gs-dragging");
    body.style.removeProperty("transition");
    body.style.removeProperty("transform");
    handle.removeAttribute("aria-expanded");
    grid.removeAttribute("inert");
    grid.removeAttribute("aria-hidden");
    grid.style.removeProperty("touch-action");
  }

  private reduced(): boolean {
    return this.motion?.matches ?? false;
  }

  private paint(): void {
    const s = this.controller.getState();
    const { root, body, handle, grid } = this.e;
    root.style.height = `${s.heights.expanded}px`;
    root.setAttribute("data-gs-snap", s.snap);
    root.setAttribute("data-gs-grid-scroll", String(s.gridScrollable));
    root.classList.toggle("gs-dragging", s.dragging);
    root.style.opacity = this.phase === "measuring" ? "0" : "";
    body.style.transition = s.dragging || this.reduced() || this.phase !== "live" ? "none" : "";
    body.style.transform = `translateY(${Math.round(s.offset * 100) / 100}px)`;
    handle.setAttribute("aria-expanded", String(s.snap !== "peek"));
    // In peek the grid is out of sight: keep it out of the tab order and the accessibility tree.
    const hidden = s.snap === "peek" && !s.dragging;
    grid.toggleAttribute("inert", hidden);
    if (hidden) grid.setAttribute("aria-hidden", "true");
    else grid.removeAttribute("aria-hidden");
    this.paintTouchAction();
    const inset = this.closed ? 0 : s.visibleHeight;
    if (inset !== this.lastInset) {
      this.lastInset = inset;
      this.o.onInsetChange?.(inset);
    }
    if (this.phase === "measuring" && !this.closed) this.advance();
    this.o.onPaint?.();
  }

  /**
   * Below fully open the grid gives every touch to us (`none`). Fully open it scrolls natively
   * (`pan-y`), except at the top, where a pull down is ours (`pan-down`: the browser only takes
   * gestures that scroll the grid down, that is a finger moving up).
   */
  private paintTouchAction(): void {
    const s = this.controller.getState();
    const { grid } = this.e;
    grid.style.touchAction = !s.gridScrollable
      ? "none"
      : grid.scrollTop <= 0
        ? "pan-down"
        : "pan-y";
  }

  private consumeSuppressedClick(): boolean {
    const was = this.suppressClick;
    this.suppressClick = false;
    return was;
  }

  private listen(on: boolean): void {
    const method = on ? "addEventListener" : "removeEventListener";
    this.doc[method]("pointermove", this.onMove as EventListener, true);
    this.doc[method]("pointerup", this.onUp as EventListener, true);
    this.doc[method]("pointercancel", this.onCancel as EventListener, true);
  }

  private endGesture(): Gesture | null {
    const g = this.gesture;
    this.gesture = null;
    if (g) this.listen(false);
    return g;
  }

  /**
   * Wheel over the sheet. Wheel down opens one state, and once fully open the grid scrolls by
   * itself. Wheel up at the top of the fully open grid closes one state (like a pull down). Where
   * the wheel can do nothing here (peek, wheel up; default, wheel up) the page keeps it.
   */
  private wheel(ev: WheelEvent): void {
    if (ev.ctrlKey || this.gesture || ev.deltaY === 0 || Math.abs(ev.deltaX) > Math.abs(ev.deltaY))
      return;
    const s = this.controller.getState();
    const { grid } = this.e;
    const down = ev.deltaY > 0;
    let action: "open" | "close" | "scroll" | "hold" | null = null;
    if (!s.gridScrollable) {
      if (down && s.snap !== "expanded") action = "open";
    } else if (down) {
      const atBottom = grid.scrollTop + grid.clientHeight >= grid.scrollHeight - 1;
      action = atBottom ? "hold" : "scroll";
    } else if (grid.scrollTop <= 0) {
      action = "close";
    } else {
      action = "scroll";
    }
    if (action === null) return;
    if (action === "scroll") return; // the grid scrolls natively and does not chain (CSS)
    ev.preventDefault();
    const now = performance.now();
    if (action === "hold" || now < this.wheelLockUntil) return;
    this.wheelLockUntil = now + WHEEL_LOCK_MS;
    this.controller.step(action === "open" ? 1 : -1);
  }

  private down(ev: PointerEvent): void {
    if (ev.pointerType === "mouse" && ev.button !== 0) return;
    if (this.gesture) {
      // A second finger, or a press whose end never arrived: start over from this one.
      if (this.gesture.mode === "sheet") this.controller.cancel();
      this.endGesture();
    }
    this.suppressClick = false;
    this.listen(true);
    this.gesture = {
      id: ev.pointerId,
      startX: ev.clientX,
      startY: ev.clientY,
      lastY: ev.clientY,
      onGrid: this.e.grid.contains(ev.target as Node),
      mode: "pending",
      samples: [{ t: performance.now(), y: ev.clientY }],
    };
  }

  private moveTo(ev: PointerEvent): void {
    const g = this.gesture;
    if (!g || g.id !== ev.pointerId) return;
    const y = ev.clientY;
    const now = performance.now();
    g.samples.push({ t: now, y });
    while (g.samples.length > 2 && now - g.samples[0]!.t > VELOCITY_WINDOW_MS) g.samples.shift();
    if (g.mode === "pending") {
      const dy = y - g.startY;
      const dx = ev.clientX - g.startX;
      if (Math.abs(dy) < SHEET_SLOP && Math.abs(dx) < SHEET_SLOP) return;
      if (Math.abs(dx) > Math.abs(dy)) {
        g.mode = "none";
        return;
      }
      const owner = g.onGrid ? this.controller.scrollOwner(dy, this.e.grid.scrollTop) : "sheet";
      g.mode = owner;
      this.suppressClick = true;
      if (owner === "sheet") {
        try {
          this.e.body.setPointerCapture(ev.pointerId);
        } catch {
          // The pointer is already gone; the next events end the gesture.
        }
        this.controller.dragStart();
        this.controller.drag(dy);
      } else {
        this.e.grid.scrollTop -= dy;
      }
      g.lastY = y;
      return;
    }
    const delta = y - g.lastY;
    g.lastY = y;
    if (g.mode === "sheet") {
      ev.preventDefault();
      this.controller.drag(delta);
    } else if (g.mode === "grid") {
      // Mouse, or a browser that did not take the touch: scroll by hand. When the browser scrolls
      // natively it sends pointercancel first, so this never doubles up.
      this.e.grid.scrollTop -= delta;
    }
  }

  private up(ev: PointerEvent): void {
    const g = this.gesture;
    if (!g || g.id !== ev.pointerId) return;
    this.endGesture();
    // The click that follows this pointerup (if any) is swallowed; after that, clicks count again.
    if (this.suppressClick) setTimeout(() => (this.suppressClick = false), 0);
    if (g.mode !== "sheet") return;
    // A finger that rested before lifting has no speed: only the last 100 ms count.
    g.samples.push({ t: performance.now(), y: ev.clientY });
    this.controller.release(velocityOf(g.samples));
  }

  private cancel(ev: PointerEvent): void {
    const g = this.gesture;
    if (!g || g.id !== ev.pointerId) return;
    this.endGesture();
    this.suppressClick = false;
    if (g.mode === "sheet") this.controller.cancel();
  }
}
