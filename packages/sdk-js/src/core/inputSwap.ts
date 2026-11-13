/**
 * The gift button in the app's message bar (spec section 20): the button closes the keyboard and
 * opens the tray in its place; a tap on the text field closes the tray and the keyboard comes
 * back. Pure: no UI, no clock; the platform layers blur, focus, open and close.
 */

/** What happened: the gift button (or `toggle()`), or the bound text field got focus. */
export type InputSwapEvent = "button" | "inputFocus";

/** What to do. Run `input: "blur"` before `tray: "open"`, and `tray: "close"` before `input: "focus"`. */
export interface InputSwapStep {
  tray: "open" | "close" | "keep";
  input: "blur" | "focus" | "keep";
}

/** The tray's height in the keyboard's place before any keyboard was seen. */
export const KEYBOARD_PLACE_FALLBACK = 300;

/** A smaller inset is not a keyboard (an accessory bar, a desktop browser). */
export const KEYBOARD_MIN_HEIGHT = 120;

/** The keyboard's place never takes more than this share of the container. */
export const KEYBOARD_PLACE_MAX_FRACTION = 0.6;

/** One step of the keyboard swap (spec 20.2). */
export function inputSwapStep(open: boolean, event: InputSwapEvent): InputSwapStep {
  if (event === "button")
    return open ? { tray: "close", input: "focus" } : { tray: "open", input: "blur" };
  return open ? { tray: "close", input: "keep" } : { tray: "keep", input: "keep" };
}

export interface KeyboardPlaceInput {
  /** The last keyboard height seen, or `null`/0 when none was seen yet. */
  keyboardHeight?: number | null;
  /** The height of the box the tray fills, or `null`/0 when unknown. */
  containerHeight?: number | null;
}

const finite = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);

/** How tall the tray is in the keyboard's place (spec 20.2). */
export function keyboardPlaceHeight({
  keyboardHeight,
  containerHeight,
}: KeyboardPlaceInput): number {
  let k =
    finite(keyboardHeight) && keyboardHeight >= KEYBOARD_MIN_HEIGHT
      ? keyboardHeight
      : KEYBOARD_PLACE_FALLBACK;
  if (finite(containerHeight) && containerHeight > 0)
    k = Math.min(k, Math.floor(containerHeight * KEYBOARD_PLACE_MAX_FRACTION));
  return Math.round(k);
}

/**
 * The sheet's `default` snap as a fraction of the container for the keyboard's place, or
 * `undefined` when the container is not measured yet.
 */
export function keyboardPlaceSnap(input: KeyboardPlaceInput): number | undefined {
  const h = input.containerHeight;
  if (!finite(h) || h <= 0) return undefined;
  return keyboardPlaceHeight(input) / h;
}
