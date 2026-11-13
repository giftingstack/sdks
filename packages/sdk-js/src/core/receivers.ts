/**
 * The receiver picker of a battle tray (spec section 21): one gift button, the tray's "Send to"
 * row picks the side. Pure: the platform layers draw the row and keep `selected` and `last`.
 */

/** One side the viewer can send to. */
export interface TrayReceiver {
  /** Your user id of the receiver. */
  id: string;
  /** The name shown under the avatar. */
  name: string;
  /** The side colour (ring). Default: the battle palette (`battleSidePalette`). */
  color?: string;
  /** A picture; default the name's first letter on the side colour. */
  avatarUrl?: string | null;
}

export interface ResolveReceiverInput {
  /** The pick so far (a tap on a side, or `selectReceiver`). */
  selected?: string | null;
  /** The receiver of this tray's last successful send. */
  last?: string | null;
  /** The plain `receiver` option. */
  fallback?: string | null;
}

/** Which side the next gift goes to (spec 21.2). */
export function resolveReceiver(
  ids: readonly string[],
  { selected, last, fallback }: ResolveReceiverInput = {},
): string | null {
  if (ids.length === 0) return fallback ?? null;
  for (const id of [selected, last, fallback]) if (id != null && ids.includes(id)) return id;
  return ids[0]!;
}

/** The default "Send to" label. */
export const SEND_TO_LABEL = "Send to";

/** The default label of a tappable battle side; `{name}` is replaced. */
export const PRESS_SIDE_LABEL = "Send {name} a gift";

/**
 * The row's scroll offset that shows the whole chip `[start, end)` (row content coordinates) with
 * the least movement (spec 21.3): unchanged when it is already in sight; a chip wider than the row
 * shows its start.
 */
export function revealOffset(o: {
  scroll: number;
  viewport: number;
  start: number;
  end: number;
}): number {
  const { scroll, viewport, start, end } = o;
  if (start < scroll || end - start > viewport) return Math.max(0, start);
  if (end > scroll + viewport) return Math.max(0, end - viewport);
  return scroll;
}
