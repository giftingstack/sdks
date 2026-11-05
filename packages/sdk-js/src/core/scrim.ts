/**
 * The tray's surroundings (spec 9.4): the dim behind a bottom sheet (`scrim`) and the open/closed
 * state the host's Gift button toggles. Pure: no UI, no clock; the platform layers draw it.
 */
import type { SheetSnap } from "./sheet";

/** What a tap on the scrim does. `"lower"`: lowers the sheet to peek first. `"dismiss"`: asks to close. */
export type ScrimTap = "lower" | "dismiss";

/** The scrim fades in and out over this long (ms); at once with reduced motion. */
export const SCRIM_FADE_MS = 200;

/** The scrim is black at this opacity. */
export const SCRIM_OPACITY = 0.4;

export interface ScrimState {
  /** The `scrim` option (default `false`). */
  scrim: boolean;
  /** The tray is open (not closed by `close()` or a dismissal). */
  open: boolean;
  /** The sheet's settled state, or the target of a running snap (`TraySheetState.snap`). */
  snap: SheetSnap;
  /** The sheet is measured and drawn where it belongs (the UI's "ready" or "shown"). */
  placed: boolean;
}

/** The dim is drawn: asked for, open, in place, and the sheet is above peek (peek keeps the page in sight). */
export function scrimVisible(s: ScrimState): boolean {
  return s.scrim && s.open && s.placed && s.snap !== "peek";
}

/** Fade duration in ms: `SCRIM_FADE_MS`, or 0 with reduced motion. */
export function scrimFadeMs(reducedMotion: boolean): number {
  return reducedMotion ? 0 : SCRIM_FADE_MS;
}

export type ScrimTapOutcome = "ignored" | "lower" | "dismiss";

/**
 * A tap on the scrim. `"ignored"`: no scrim or the tray is closed. `"lower"`: move the sheet to
 * peek. `"dismiss"`: call `onDismiss` (and close the tray when it holds its own open state).
 * `scrimTap` "lower" (default) lowers any state above peek and dismisses from peek; "dismiss"
 * dismisses from every state. A hidden scrim takes no touches, so from peek this is only reached
 * by calling it directly.
 */
export function scrimTapOutcome(s: {
  scrim: boolean;
  scrimTap?: ScrimTap;
  open: boolean;
  snap: SheetSnap;
}): ScrimTapOutcome {
  if (!s.scrim || !s.open) return "ignored";
  if ((s.scrimTap ?? "lower") === "lower" && s.snap !== "peek") return "lower";
  return "dismiss";
}

export interface TrayOpenStateOptions {
  /** Initial state. Default `true` (a tray that exists is shown, as before this existed). */
  open?: boolean;
  /** Called after the state changed, never for a call that changes nothing. */
  onChange?: (open: boolean) => void;
}

/**
 * The open/closed state behind `open()`, `close()` and `toggle()` (the host's Gift button is
 * `tray.toggle()`). Every method returns the new state.
 */
export class TrayOpenState {
  private value: boolean;
  private onChange: ((open: boolean) => void) | undefined;
  private readonly listeners = new Set<() => void>();

  constructor(options: TrayOpenStateOptions = {}) {
    this.value = options.open ?? true;
    this.onChange = options.onChange;
  }

  setOnChange(cb: ((open: boolean) => void) | undefined): void {
    this.onChange = cb;
  }

  isOpen = (): boolean => this.value;

  open = (): boolean => this.set(true);

  close = (): boolean => this.set(false);

  /** Open if closed, close if open. */
  toggle = (): boolean => this.set(!this.value);

  subscribe = (cb: () => void): (() => void) => {
    this.listeners.add(cb);
    return () => {
      this.listeners.delete(cb);
    };
  };

  private set(next: boolean): boolean {
    if (next === this.value) return this.value;
    this.value = next;
    for (const cb of [...this.listeners]) cb();
    this.onChange?.(next);
    return next;
  }
}
