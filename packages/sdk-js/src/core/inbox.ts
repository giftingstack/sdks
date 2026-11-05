/**
 * Gift inbox logic (SPEC section 19): the pure helpers (time label, rows, unread count) and a
 * small controller that loads the first page, appends older pages and reloads. No drawing.
 */
import type { GiftingClient, GiftingError } from "./client";
import { asGiftingError } from "./tray";
import type { InboxItem } from "./types";

const MINUTE_MS = 60_000;
const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

/** The shown name of a deleted sender. */
export const INBOX_SOMEONE = "Someone";
export const DEFAULT_INBOX_PAGE_SIZE = 20;

/** `"now"`, `"5m"`, `"3h"`, `"1d"`: how long ago a gift came. A clock that went back is `"now"`. */
export function inboxTimeLabel(createdAtMs: number, nowMs: number): string {
  const d = nowMs - createdAtMs;
  if (d < MINUTE_MS) return "now";
  if (d < HOUR_MS) return `${Math.floor(d / MINUTE_MS)}m`;
  if (d < DAY_MS) return `${Math.floor(d / HOUR_MS)}h`;
  return `${Math.floor(d / DAY_MS)}d`;
}

export interface InboxRow {
  id: string;
  /** The display name: `"Someone"` for a deleted sender, else the mapped name, else the id. */
  senderName: string;
  giftName: string;
  quantity: number;
  /** `inboxTimeLabel` of the gift. */
  time: string;
  iconUrl: string | null;
  /** The sender's external id; `null` for a deleted sender. */
  sender: string | null;
}

/** The rows to draw: reversed gifts dropped, the order kept. `names` maps sender ids to names. */
export function inboxRows(
  items: readonly InboxItem[],
  nowMs: number,
  names: Readonly<Record<string, string>> = {},
): InboxRow[] {
  const out: InboxRow[] = [];
  for (const i of items) {
    if (i.status === "reversed") continue;
    out.push({
      id: i.id,
      senderName: i.sender === null ? INBOX_SOMEONE : (names[i.sender] ?? i.sender),
      giftName: i.gift.name,
      quantity: i.quantity,
      time: inboxTimeLabel(Date.parse(i.created_at), nowMs),
      iconUrl: i.gift.icon_url,
      sender: i.sender,
    });
  }
  return out;
}

/**
 * The number of completed gifts strictly newer than `lastSeenMs` (all of them when it is `null`
 * or missing): the badge. Keep the time of the newest row you showed as the last seen time.
 */
export function inboxUnread(
  items: readonly Pick<InboxItem, "created_at" | "status">[],
  lastSeenMs?: number | null,
): number {
  let n = 0;
  for (const i of items) {
    if (i.status !== "completed") continue;
    if (lastSeenMs === null || lastSeenMs === undefined || Date.parse(i.created_at) > lastSeenMs)
      n++;
  }
  return n;
}

export interface InboxState {
  status: "loading" | "empty" | "error" | "ready";
  /** Every loaded item, newest first (reversed ones included: use `inboxRows`). */
  items: InboxItem[];
  hasMore: boolean;
  /** The next page is on its way. */
  loadingMore: boolean;
  /** A reload is on its way while the old rows stay shown. */
  refreshing: boolean;
  /** The last failure, cleared by the next success. */
  error: GiftingError | null;
}

export interface InboxControllerOptions {
  client: GiftingClient;
  /** Rows per page, 1 to 100. Default 20. */
  pageSize?: number;
  /** Called with every loaded item after each successful load. */
  onLoaded?: (items: InboxItem[]) => void;
  onError?: (error: GiftingError) => void;
}

export class InboxController {
  private options: InboxControllerOptions;
  private cursor: string | null = null;
  private readonly listeners = new Set<() => void>();
  /** Bumped by every reload: an answer that began before it is dropped. */
  private epoch = 0;
  private alive = true;
  private state: InboxState = {
    status: "loading",
    items: [],
    hasMore: false,
    loadingMore: false,
    refreshing: false,
    error: null,
  };

  constructor(options: InboxControllerOptions) {
    this.options = options;
  }

  /** Callbacks and `pageSize` are read when used. */
  setOptions(options: InboxControllerOptions): void {
    this.options = options;
  }

  getState = (): InboxState => this.state;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  private set(patch: Partial<InboxState>): void {
    this.state = { ...this.state, ...patch };
    for (const l of this.listeners) l();
  }

  private limit(): number {
    const n = this.options.pageSize ?? DEFAULT_INBOX_PAGE_SIZE;
    return Math.min(100, Math.max(1, Math.trunc(n)));
  }

  /** The screen opened: load the first page. */
  start = (): void => {
    void this.load(false);
  };

  /** Reload from the first page ("Try again", pull to refresh). The shown rows stay meanwhile. */
  refresh = (): void => {
    void this.load(false);
  };

  /** Append the next (older) page. Does nothing without one or while it is loading. */
  loadMore = (): void => {
    const s = this.state;
    if (!s.hasMore || s.loadingMore || this.cursor === null || s.status === "loading") return;
    void this.load(true);
  };

  private async load(more: boolean): Promise<void> {
    const epoch = more ? this.epoch : ++this.epoch;
    const first = this.state.items.length === 0 && !more;
    this.set(
      more
        ? { loadingMore: true }
        : first || this.state.status === "error"
          ? { status: "loading", loadingMore: false, refreshing: false }
          : { refreshing: true, loadingMore: false },
    );
    try {
      const page = await this.options.client.getInbox({
        ...(more && this.cursor !== null ? { cursor: this.cursor } : {}),
        limit: this.limit(),
      });
      if (!this.alive || epoch !== this.epoch) return;
      this.cursor = page.has_more ? page.next_cursor : null;
      const items = more ? [...this.state.items, ...page.data] : page.data;
      this.set({
        items,
        hasMore: page.has_more && page.next_cursor !== null,
        status: items.length ? "ready" : "empty",
        loadingMore: false,
        refreshing: false,
        error: null,
      });
      this.options.onLoaded?.(items);
    } catch (err) {
      if (!this.alive || epoch !== this.epoch) return;
      const e = asGiftingError(err);
      // A failed first load is the error screen; a failed reload or "Show more" keeps the rows.
      this.set({
        status: this.state.items.length && this.state.status !== "error" ? "ready" : "error",
        loadingMore: false,
        refreshing: false,
        error: e,
      });
      this.options.onError?.(e);
    }
  }

  /** The screen is gone: answers that arrive later change nothing. */
  dispose(): void {
    this.alive = false;
  }
}
