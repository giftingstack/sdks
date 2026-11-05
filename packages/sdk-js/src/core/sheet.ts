/**
 * The tray as a draggable bottom sheet, without a UI (spec section 9.1): three snap states, the
 * drag, the release with a velocity bias, tap and keyboard steps, and who owns a drag that starts
 * on the gift grid. Every UI (React Native, web, Flutter, Kotlin, Swift) draws what this says.
 *
 * Geometry: the sheet is laid out once at its tallest (the `expanded` height) and moved down by
 * `offset` (a translateY). `offset` 0 shows the whole expanded sheet; the visible height is
 * `heights.expanded - offset`. All lengths are in the platform's layout unit (px, dp, pt).
 */

export type SheetSnap = "peek" | "default" | "expanded";

/** The snap states from the most closed to the most open. */
export const SHEET_SNAPS: readonly SheetSnap[] = ["peek", "default", "expanded"];

/** A release at least this fast (px per second) moves one state in the direction of the flick. */
export const SHEET_FLICK_VELOCITY = 600;

/**
 * Default snap heights as fractions of the container height. 0 means "as tall as the content
 * needs" (the floor the UI measures), so peek and default fit their content unless the app asks
 * for more.
 */
export const SHEET_DEFAULT_FRACTIONS: Readonly<Record<SheetSnap, number>> = {
  peek: 0,
  default: 0,
  expanded: 0.9,
};

export type SheetHeights = Record<SheetSnap, number>;

export interface SheetLayout {
  /** Height of the area the sheet sits in (usually the screen). */
  containerHeight: number;
  /** Snap heights as fractions of `containerHeight`, each clamped to 0..1. */
  snaps?: Partial<Record<SheetSnap, number>>;
  /** Content that must show in peek: handle, header and the Send bar. */
  peekMinHeight?: number;
  /** Content of the default state: peek plus up to two rows of gifts. */
  defaultMinHeight?: number;
  /** The sheet's natural height with every row of gifts; caps `expanded` (never below default). */
  contentHeight?: number;
}

const finite = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const positive = (v: unknown): number => (finite(v) && v > 0 ? v : 0);

/** The three snap heights for a layout. Always `0 <= peek <= default <= expanded <= container`. */
export function resolveSheetHeights(layout: SheetLayout): SheetHeights {
  const h = positive(layout.containerHeight);
  const fraction = (s: SheetSnap): number => {
    const f = layout.snaps?.[s];
    return finite(f) ? Math.min(1, Math.max(0, f)) : SHEET_DEFAULT_FRACTIONS[s];
  };
  const peek = Math.max(Math.round(fraction("peek") * h), positive(layout.peekMinHeight));
  const def = Math.max(
    Math.round(fraction("default") * h),
    positive(layout.defaultMinHeight),
    peek,
  );
  let expanded = Math.round(fraction("expanded") * h);
  const content = positive(layout.contentHeight);
  if (content > 0) expanded = Math.min(expanded, content);
  expanded = Math.max(expanded, def);
  return { peek: Math.min(peek, h), default: Math.min(def, h), expanded: Math.min(expanded, h) };
}

export interface TraySheetState {
  /** The settled state, or the one the sheet is moving to. Stays the old one during a drag. */
  snap: SheetSnap;
  /** How far the sheet is moved down from fully open. 0 = expanded. */
  offset: number;
  /** `heights.expanded - offset`: the sheet's top edge, measured from the container's bottom. */
  visibleHeight: number;
  dragging: boolean;
  heights: SheetHeights;
  /** The gift grid scrolls by itself only when the sheet is fully open and not being dragged. */
  gridScrollable: boolean;
}

export interface TraySheetControllerOptions {
  /** Default `"default"`. */
  initialSnap?: SheetSnap;
  layout?: SheetLayout;
  /** Called when the settled state changes (release, toggle, step, snapTo), not during a drag. */
  onSnapChange?: (snap: SheetSnap) => void;
}

export class TraySheetController {
  private heights: SheetHeights;
  private snap: SheetSnap;
  private offset: number;
  private dragging = false;
  /** The unclamped drag position, so the sheet stays under the finger after an over-drag. */
  private raw = 0;
  private state: TraySheetState;
  private readonly listeners = new Set<() => void>();
  private onSnapChange: ((snap: SheetSnap) => void) | undefined;

  constructor(options: TraySheetControllerOptions = {}) {
    this.snap = options.initialSnap ?? "default";
    this.onSnapChange = options.onSnapChange;
    this.heights = resolveSheetHeights(options.layout ?? { containerHeight: 0 });
    this.offset = this.offsetOf(this.snap);
    this.state = this.build();
  }

  setOnSnapChange(cb: ((snap: SheetSnap) => void) | undefined): void {
    this.onSnapChange = cb;
  }

  getState = (): TraySheetState => this.state;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  /** The offset at which `snap` is fully shown. */
  offsetOf(snap: SheetSnap): number {
    return this.heights.expanded - this.heights[snap];
  }

  /** New measurements. Keeps the state; during a drag the position is clamped again. */
  setLayout(layout: SheetLayout): void {
    this.heights = resolveSheetHeights(layout);
    this.offset = this.dragging ? this.clamp(this.raw) : this.offsetOf(this.snap);
    this.emit();
  }

  dragStart(): void {
    if (this.dragging) return;
    this.dragging = true;
    this.raw = this.offset;
    this.emit();
  }

  /** The finger moved `dy` (positive = down). Starts a drag if none is running. */
  drag(dy: number): void {
    if (!this.dragging) this.dragStart();
    this.raw += dy;
    this.offset = this.clamp(this.raw);
    this.emit();
  }

  /**
   * The finger lifted with `velocity` (px/s, positive = down). Picks the state and moves there.
   * Without a running drag nothing changes and the current state is returned.
   */
  release(velocity = 0): SheetSnap {
    if (!this.dragging) return this.snap;
    this.dragging = false;
    const target = this.pick(velocity);
    this.settle(target);
    return target;
  }

  /** The drag was interrupted (pointer cancel): back to the state it started from. */
  cancel(): void {
    if (!this.dragging) return;
    this.dragging = false;
    this.offset = this.offsetOf(this.snap);
    this.emit();
  }

  snapTo(snap: SheetSnap): void {
    this.dragging = false;
    this.settle(snap);
  }

  /** Tap on the handle: peek opens to default, default closes to peek, expanded goes to default. */
  toggle(): SheetSnap {
    const next: SheetSnap = this.snap === "default" ? "peek" : "default";
    this.snapTo(next);
    return next;
  }

  /** Keyboard or accessibility step: +1 opens one state (ArrowUp), -1 closes one (ArrowDown). */
  step(direction: 1 | -1): SheetSnap {
    const at = SHEET_SNAPS.indexOf(this.snap);
    const next = SHEET_SNAPS[Math.min(SHEET_SNAPS.length - 1, Math.max(0, at + direction))]!;
    this.snapTo(next);
    return next;
  }

  /**
   * A drag that starts on the gift grid moved `dy` first (positive = down). Who takes it: the
   * sheet (it moves) or the grid (it scrolls)? Decide once per gesture.
   */
  scrollOwner(dy: number, gridScrollTop: number): "sheet" | "grid" {
    if (this.dragging || this.offset > 0) return "sheet";
    if (dy > 0 && gridScrollTop <= 0) return "sheet";
    return "grid";
  }

  private clamp(v: number): number {
    return Math.min(this.offsetOf("peek"), Math.max(0, v));
  }

  /**
   * Flick (|velocity| >= 600): the nearest state beyond the current position in the flick's
   * direction; if there is none, the nearest state. Otherwise the nearest state. Ties go to the
   * more open state.
   */
  private pick(velocity: number): SheetSnap {
    const open = [...SHEET_SNAPS].reverse(); // most open first: ties keep the more open one
    const o = this.offset;
    if (Math.abs(velocity) >= SHEET_FLICK_VELOCITY) {
      const up = velocity < 0;
      let best: SheetSnap | null = null;
      for (const s of open) {
        const so = this.offsetOf(s);
        if (up ? so >= o : so <= o) continue;
        if (best === null || (up ? so > this.offsetOf(best) : so < this.offsetOf(best))) best = s;
      }
      if (best) return best;
    }
    let best: SheetSnap = open[0]!;
    for (const s of open) {
      if (Math.abs(this.offsetOf(s) - o) < Math.abs(this.offsetOf(best) - o)) best = s;
    }
    return best;
  }

  private settle(snap: SheetSnap): void {
    const changed = snap !== this.snap;
    this.snap = snap;
    this.offset = this.offsetOf(snap);
    this.emit();
    if (changed) this.onSnapChange?.(snap);
  }

  private build(): TraySheetState {
    return {
      snap: this.snap,
      offset: this.offset,
      visibleHeight: this.heights.expanded - this.offset,
      dragging: this.dragging,
      heights: { ...this.heights },
      gridScrollable: this.offset === 0 && !this.dragging,
    };
  }

  private emit(): void {
    const prev = this.state;
    const next = this.build();
    if (
      prev.snap === next.snap &&
      prev.offset === next.offset &&
      prev.dragging === next.dragging &&
      prev.heights.peek === next.heights.peek &&
      prev.heights.default === next.heights.default &&
      prev.heights.expanded === next.heights.expanded
    )
      return;
    this.state = next;
    for (const l of this.listeners) l();
  }
}
