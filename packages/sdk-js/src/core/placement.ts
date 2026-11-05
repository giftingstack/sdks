/**
 * Where the web tray sits (spec section 9.3, web only; native platforms keep the bottom sheet).
 * Pure: the choice of placement from the container width, and the popover's position next to its
 * anchor. The web UI measures and draws what these return.
 */

/** `sheet`: the bottom sheet of 9.1. `popover`: a panel next to the app's gift button. `inline`: fills its container. */
export type TrayPlacement = "sheet" | "popover" | "inline";
export type TrayPlacementOption = TrayPlacement | "auto";

/** `auto` picks a desktop placement from this container width on (inclusive), in px. */
export const TRAY_WIDE_FROM = 600;
/** Popover width, px (narrower when the viewport is). */
export const POPOVER_WIDTH = 380;
/** Popover height cap as a fraction of the viewport height. */
export const POPOVER_MAX_HEIGHT_FRACTION = 0.7;
/** Space between the anchor and the popover, px. */
export const POPOVER_GAP = 8;
/** The popover keeps this distance from the viewport edges, px. */
export const POPOVER_MARGIN = 8;
/** Default grid columns per placement (`inline` fills the width with tiles of at least 84 px). */
export const PLACEMENT_COLUMNS = { sheet: 4, popover: 4 } as const;
export const INLINE_MIN_TILE = 84;

export interface PlacementInput {
  /** The app's choice. Missing or unknown: `"auto"`. */
  placement?: TrayPlacementOption;
  /** The container's width in px. Not finite or below 0 counts as 0. */
  containerWidth: number;
  /** An anchor element (the app's gift button) was given. */
  hasAnchor: boolean;
}

/**
 * The placement to draw. `auto`: below 600 px the sheet; from 600 px a popover when there is an
 * anchor, otherwise inline. A `popover` without an anchor has nothing to open from: inline.
 */
export function resolveTrayPlacement(input: PlacementInput): TrayPlacement {
  const { placement, hasAnchor } = input;
  if (placement === "popover") return hasAnchor ? "popover" : "inline";
  if (placement === "sheet" || placement === "inline") return placement;
  const w =
    typeof input.containerWidth === "number" && Number.isFinite(input.containerWidth)
      ? Math.max(0, input.containerWidth)
      : 0;
  if (w < TRAY_WIDE_FROM) return "sheet";
  return hasAnchor ? "popover" : "inline";
}

export interface PopoverRect {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface PopoverInput {
  /** The anchor's box in viewport coordinates. */
  anchor: PopoverRect;
  /** The panel's wanted width and its natural (content) height. */
  panel: { width: number; height: number };
  viewport: { width: number; height: number };
  gap?: number;
  margin?: number;
  maxHeightFraction?: number;
}

export interface PopoverPosition {
  /** Top-left corner in viewport coordinates (the web layer moves the panel there with a transform). */
  left: number;
  top: number;
  width: number;
  /** The panel's max height: the 70 % cap or the room on its side, whichever is less. */
  maxHeight: number;
  /** The height the panel ends up with: `min(panel.height, maxHeight)`. */
  height: number;
  side: "above" | "below";
  /** `end`: right edges line up (anchor in the right half of the viewport); `start`: left edges. */
  align: "start" | "end";
}

/**
 * Where the popover goes. Below the anchor when it fits there, else above when it fits there,
 * else on the side with more room (ties: below), shrunk to that room. Its right edge lines up
 * with the anchor's when the anchor's centre is in the right half of the viewport, else the left
 * edges; then it is pushed inside the viewport margins. Integers out.
 */
export function positionPopover(input: PopoverInput): PopoverPosition {
  const m = input.margin ?? POPOVER_MARGIN;
  const g = input.gap ?? POPOVER_GAP;
  const fraction = input.maxHeightFraction ?? POPOVER_MAX_HEIGHT_FRACTION;
  const { anchor, viewport: vp } = input;
  const width = Math.round(Math.max(0, Math.min(input.panel.width, vp.width - 2 * m)));
  const cap = Math.round(vp.height * fraction);
  const wanted = Math.max(0, Math.min(input.panel.height, cap));
  const above = Math.max(0, anchor.top - g - m);
  const below = Math.max(0, vp.height - anchor.bottom - g - m);
  const side: PopoverPosition["side"] =
    below >= wanted ? "below" : above >= wanted ? "above" : below >= above ? "below" : "above";
  const maxHeight = Math.round(Math.min(cap, side === "above" ? above : below));
  const height = Math.min(Math.round(wanted), maxHeight);
  const top = side === "above" ? anchor.top - g - height : anchor.bottom + g;
  const align: PopoverPosition["align"] =
    (anchor.left + anchor.right) / 2 >= vp.width / 2 ? "end" : "start";
  let left = align === "end" ? anchor.right - width : anchor.left;
  left = Math.max(m, Math.min(left, vp.width - m - width));
  return { left: Math.round(left), top: Math.round(top), width, maxHeight, height, side, align };
}
