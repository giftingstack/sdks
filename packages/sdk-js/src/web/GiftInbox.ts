import {
  type GiftingClient,
  type GiftingError,
  type InboxItem,
  type InboxRow,
  InboxController,
  type InboxState,
  asGiftingError,
  inboxRows,
} from "../core";
import { type GiftLabels, type GiftLabelsInput, fill, resolveLabels } from "./labels";
import { acquireStyles, releaseStyles } from "./styles";
import { type GiftTheme, applyTheme } from "./theme";
import {
  type ResolveUsers,
  type UserInfo,
  avatar,
  giftIcon,
  make,
  missingIds,
  withTimeout,
} from "./ui";

export interface GiftInboxOptions {
  client: GiftingClient;
  /** Rows per page, 1 to 100. Default 20. */
  pageSize?: number;
  /** Names (and pictures) for the sender ids. Fallback: the id. */
  resolveUsers?: ResolveUsers;
  /** Called with every loaded item after each load: count your own badge with `inboxUnread`. */
  onLoaded?: (items: InboxItem[]) => void;
  onError?: (error: GiftingError) => void;
  theme?: Partial<GiftTheme>;
  labels?: GiftLabelsInput;
  /** The clock, in ms. Default `Date.now`. */
  now?: () => number;
}

/** How long the first rows wait for `resolveUsers` before they show with the ids. */
const RESOLVE_WAIT_MS = 2000;
const NAME_MARK = "\u0000";

/**
 * Who sent you which gift over the last 24 hours: one row per gift, newest first, an initial
 * avatar, "Name sent you Gift x3", the gift picture and how long ago on the right. Loads its own
 * first page, "Show more" appends the next one. Reversed gifts are not shown.
 */
export class GiftInbox {
  readonly element: HTMLElement;
  /** The pure controller behind the list, for state and tests. */
  readonly controller: InboxController;
  private o: GiftInboxOptions;
  private readonly doc: Document;
  private readonly names = new Map<string, UserInfo>();
  private readonly asking = new Set<string>();
  /** The first rows were drawn: later pages never blank the list while names load. */
  private drawn = false;
  private destroyed = false;
  private readonly unsubscribe: () => void;

  constructor(container: HTMLElement, options: GiftInboxOptions) {
    this.doc = container.ownerDocument;
    this.o = options;
    acquireStyles(this.doc);
    this.element = make(this.doc, "section", "gs-board gs-inbox");
    this.element.setAttribute("data-gs-inbox", "");
    container.appendChild(this.element);

    this.controller = new InboxController(this.controllerOptions());
    this.unsubscribe = this.controller.subscribe(() => this.onState());
    this.render();
    this.controller.start();
  }

  private controllerOptions() {
    return {
      client: this.o.client,
      pageSize: this.o.pageSize,
      onLoaded: (items: InboxItem[]) => this.o.onLoaded?.(items),
      onError: (e: GiftingError) => this.o.onError?.(e),
    };
  }

  /** Change options later (theme, labels, callbacks, `pageSize` for the next request). */
  update(patch: Partial<GiftInboxOptions>): void {
    if (this.destroyed) return;
    this.o = { ...this.o, ...patch };
    this.controller.setOptions(this.controllerOptions());
    this.render();
  }

  /** Load again from the first page. */
  refresh(): void {
    this.controller.refresh();
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.unsubscribe();
    this.controller.dispose();
    this.element.remove();
    releaseStyles();
  }

  // ------------------------------------------------------------------ names

  private onState(): void {
    if (this.destroyed) return;
    const resolve = this.o.resolveUsers;
    if (resolve) {
      const wanted = this.controller
        .getState()
        .items.flatMap((i) => (i.sender === null ? [] : [i.sender]));
      const fresh = missingIds(wanted, this.names).filter((id) => !this.asking.has(id));
      if (fresh.length) {
        for (const id of fresh) this.asking.add(id);
        void this.lookUp(resolve, fresh);
      }
    }
    this.render();
  }

  private async lookUp(resolve: ResolveUsers, ids: string[]): Promise<void> {
    try {
      const found = await withTimeout(resolve(ids), RESOLVE_WAIT_MS);
      for (const [id, info] of Object.entries(found ?? {})) this.names.set(id, info);
    } catch (err) {
      this.o.onError?.(asGiftingError(err));
    } finally {
      for (const id of ids) this.asking.delete(id);
    }
    if (!this.destroyed) this.render();
  }

  // ------------------------------------------------------------------ drawing

  private render(): void {
    if (this.destroyed) return;
    const state = this.controller.getState();
    const labels = resolveLabels(this.o.labels);
    const root = this.element;
    const doc = this.doc;
    applyTheme(root, this.o.theme);
    const active = doc.activeElement;
    const focusKey = active && root.contains(active) ? active.getAttribute("data-gs-focus") : null;
    root.replaceChildren();

    const body = make(doc, "div", "gs-board-body", root);
    body.setAttribute(
      "aria-busy",
      state.status === "loading" || state.refreshing ? "true" : "false",
    );
    const waiting = !this.drawn && this.asking.size > 0;

    if (state.status === "loading" || (state.status === "ready" && waiting)) {
      this.drawSkeleton(body, labels);
    } else if (state.status === "error") {
      const box = make(doc, "div", "gs-board-error", body);
      box.setAttribute("role", "alert");
      make(doc, "p", "gs-board-message", box).textContent = labels.inboxError;
      const retry = make(doc, "button", "gs-retry", box);
      retry.type = "button";
      retry.setAttribute("data-gs-focus", "retry");
      retry.textContent = labels.tryAgain;
      retry.addEventListener("click", () => this.controller.refresh());
    } else if (state.status === "empty") {
      this.drawn = true;
      make(doc, "p", "gs-board-empty", body).textContent = labels.inboxEmpty;
    } else {
      this.drawn = true;
      this.drawRows(body, state, labels);
    }

    if (focusKey) root.querySelector<HTMLElement>(`[data-gs-focus="${focusKey}"]`)?.focus();
  }

  private drawSkeleton(body: HTMLElement, labels: GiftLabels): void {
    const list = make(this.doc, "div", "gs-rows", body);
    list.setAttribute("role", "status");
    list.setAttribute("aria-label", labels.loading);
    const rows = Math.min(this.o.pageSize ?? 20, 5);
    for (let i = 0; i < rows; i++) {
      const row = make(this.doc, "div", "gs-row gs-row-skeleton", list);
      row.setAttribute("aria-hidden", "true");
      make(this.doc, "span", "gs-skel gs-skel-disc", row);
      make(this.doc, "span", "gs-skel gs-skel-bar", row);
      make(this.doc, "span", "gs-skel gs-skel-score", row);
    }
  }

  private nameMap(): Record<string, string> {
    const out: Record<string, string> = {};
    for (const [id, info] of this.names) out[id] = info.name;
    return out;
  }

  /** The sentence for a row, with the name in `<b>` (a template without `{name}` has none). */
  private sentence(row: InboxRow, labels: GiftLabels): { spoken: string; parts: string[] } {
    const template = row.quantity > 1 ? labels.inboxSentMany : labels.inboxSent;
    const values = { gift: row.giftName, n: row.quantity };
    return {
      spoken: fill(template, { ...values, name: row.senderName }),
      parts: fill(template, { ...values, name: NAME_MARK }).split(NAME_MARK),
    };
  }

  private drawRows(body: HTMLElement, state: InboxState, labels: GiftLabels): void {
    const doc = this.doc;
    const rows = inboxRows(state.items, (this.o.now ?? Date.now)(), this.nameMap());
    const list = make(doc, "ul", "gs-rows", body);
    list.setAttribute("role", "list");
    for (const row of rows) {
      const li = make(doc, "li", "gs-row gs-inbox-row", list);
      li.setAttribute("data-gs-inbox-row", row.id);
      const { spoken, parts } = this.sentence(row, labels);
      li.setAttribute("aria-label", fill(labels.inboxSpoken, { sentence: spoken, time: row.time }));
      const main = make(doc, "div", "gs-row-main", li);
      // The label says it all; what is drawn is not read a second time.
      main.setAttribute("aria-hidden", "true");
      const info = row.sender === null ? undefined : this.names.get(row.sender);
      main.append(avatar(doc, row.senderName, info?.avatarUrl, 36));
      const text = make(doc, "span", "gs-row-name gs-inbox-text", main);
      if (parts.length > 1) {
        text.append(parts[0] ?? "");
        make(doc, "b", "", text).textContent = row.senderName;
        text.append(parts.slice(1).join(""));
      } else text.textContent = spoken;
      main.append(giftIcon(doc, row.iconUrl));
      make(doc, "time", "gs-inbox-time", main).textContent = row.time;
    }
    if (state.hasMore) {
      const more = make(doc, "button", "gs-inbox-more", body);
      more.type = "button";
      more.setAttribute("data-gs-focus", "more");
      more.disabled = state.loadingMore;
      more.textContent = labels.showMore;
      more.addEventListener("click", () => this.controller.loadMore());
    }
  }
}
