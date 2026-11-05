import {
  type GiftingClient,
  type GiftingError,
  type Leaderboard,
  type LeaderboardBoard,
  type LeaderboardEntry,
  type LeaderboardMe,
  type LeaderboardMetric,
  type LeaderboardPeriod,
  type LeaderboardState,
  LeaderboardController,
  asGiftingError,
  groupThousands,
  leaderboardPollMs,
  leaderboardRankLabel,
} from "../core";
import { type GiftLabels, type GiftLabelsInput, fill, resolveLabels } from "./labels";
import { acquireStyles, releaseStyles } from "./styles";
import { type GiftTheme, applyTheme } from "./theme";
import {
  type RenderResult,
  type ResolveUsers,
  type UserInfo,
  avatar,
  make,
  missingIds,
  runRender,
  shortCount,
  uniqueId,
  withTimeout,
} from "./ui";

/** What `renderRow` receives for one ranked row. */
export interface LeaderboardRowContext {
  entry: LeaderboardEntry;
  rank: number;
  /** The display name (from `resolveUsers`), else the id. */
  name: string;
  avatarUrl: string | null;
  metric: LeaderboardMetric;
  /** The score for the shown metric: coins (`"units"`) or gifts. */
  score: number;
  /** The score as the default row shows it (`54K`). */
  scoreText: string;
  /** Whether this is the highlighted (signed-in) person. */
  isMe: boolean;
  /** The document to create elements with. */
  doc: Document;
}

export interface GiftLeaderboardOptions {
  client: GiftingClient;
  /** Default `"senders"`. */
  board?: LeaderboardBoard;
  /** Tabs in this order. Default day, week, month, all. One item: no tabs. */
  periods?: readonly LeaderboardPeriod[];
  /** Default `"week"`. */
  initialPeriod?: LeaderboardPeriod;
  /** Default `"units"` for senders, `"gifts"` for receivers. */
  metric?: LeaderboardMetric;
  /** Show the coins / gifts switch. Default false. */
  metricToggle?: boolean;
  /** Rows, 1 to 100. Default 10. */
  limit?: number;
  /** Names (and pictures) for the ids. Fallback: the id. */
  resolveUsers?: ResolveUsers;
  /** The row to highlight. Default: the signed-in person (`me.user`). */
  highlightUser?: string;
  /**
   * Poll every so many ms, at least 5,000 (a smaller number is 5,000). Default 0: no polling (it
   * refreshes on a tab change and `refresh()`).
   */
  refreshIntervalMs?: number;
  /**
   * Draw the inside of each ranked row yourself (web only / pending native port). The board still
   * loads, orders, names, highlights and pins; it keeps the row element, its spoken label and the
   * press. Return a node or a string; nothing draws the default rank, avatar, name and score. The
   * pinned "You: #417" row stays the default.
   */
  renderRow?: (row: LeaderboardRowContext) => RenderResult;
  /** Makes every row a button. */
  onPressUser?: (id: string) => void;
  onError?: (error: GiftingError) => void;
  theme?: Partial<GiftTheme>;
  labels?: GiftLabelsInput;
  /** Name of the currency in spoken labels and the metric switch. Default "coins". */
  coinName?: string;
}

/** How long rows wait for `resolveUsers` before they show with the ids. */
const RESOLVE_WAIT_MS = 2000;

/**
 * Top senders or receivers, by coins or by gifts, for today, this week, this month or all time.
 * Tabs, an optional metric switch, rows with a medal disc for ranks 1 to 3, the viewer's own row
 * highlighted, or pinned under the list ("You: #417") when it is outside the shown rows. A
 * leaderboard is a primary view: a failed first load shows a message and a Try again button.
 */
export class GiftLeaderboard {
  readonly element: HTMLElement;
  /** The pure controller behind the board, for state and tests. */
  readonly controller: LeaderboardController;
  private o: GiftLeaderboardOptions;
  private readonly doc: Document;
  private readonly names = new Map<string, UserInfo>();
  /** Ids asked for and not yet answered: rows wait for them (a short while). */
  private readonly asking = new Set<string>();
  private readonly ids = uniqueId("gs-board");
  private poll: ReturnType<typeof setInterval> | undefined;
  private destroyed = false;
  private readonly unsubscribe: () => void;

  constructor(container: HTMLElement, options: GiftLeaderboardOptions) {
    this.doc = container.ownerDocument;
    this.o = options;
    acquireStyles(this.doc);
    this.element = make(this.doc, "section", "gs-board");
    this.element.setAttribute("data-gs-board", "");
    container.appendChild(this.element);

    this.controller = new LeaderboardController(this.controllerOptions());
    this.unsubscribe = this.controller.subscribe(() => this.onState());
    this.render();
    this.controller.start();
    this.startPolling();
  }

  private controllerOptions() {
    const o = this.o;
    return {
      client: o.client,
      board: o.board,
      periods: o.periods,
      initialPeriod: o.initialPeriod,
      metric: o.metric,
      limit: o.limit,
      onError: (e: GiftingError) => this.o.onError?.(e),
    };
  }

  /**
   * Change options later. `board`, `limit` and callbacks apply to the next request; a new
   * `metric` switches the tab at once. Anything else about the tabs needs a new board.
   */
  update(patch: Partial<GiftLeaderboardOptions>): void {
    if (this.destroyed) return;
    this.o = { ...this.o, ...patch };
    this.controller.setOptions({ ...this.controllerOptions(), metric: undefined });
    if (patch.metric && patch.metric !== this.controller.getState().metric)
      this.controller.setMetric(patch.metric);
    if ("refreshIntervalMs" in patch) this.startPolling();
    this.render();
  }

  /** Fetch the current tab again now. */
  refresh(): void {
    this.controller.refresh();
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    clearInterval(this.poll);
    this.unsubscribe();
    this.controller.dispose();
    this.element.remove();
    releaseStyles();
  }

  private startPolling(): void {
    clearInterval(this.poll);
    const ms = leaderboardPollMs(this.o.refreshIntervalMs);
    if (ms > 0)
      this.poll = setInterval(() => {
        if (this.doc.visibilityState !== "hidden") this.controller.refresh();
      }, ms);
  }

  // ------------------------------------------------------------------ names

  private onState(): void {
    if (this.destroyed) return;
    const data = this.controller.getState().data;
    const resolve = this.o.resolveUsers;
    // The rows, and the viewer (whose own row may be pinned under them).
    const wanted = data
      ? [...data.data.map((r) => r.user), ...(data.me ? [data.me.user] : [])]
      : [];
    const ids = resolve ? missingIds(wanted, this.names) : [];
    const fresh = ids.filter((id) => !this.asking.has(id));
    if (fresh.length && resolve) {
      for (const id of fresh) this.asking.add(id);
      void this.lookUp(resolve, fresh);
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
      // Whatever came back (or did not), these rows may draw now.
      for (const id of ids) this.asking.delete(id);
    }
    if (!this.destroyed) this.render();
  }

  private nameOf(id: string): string {
    return this.names.get(id)?.name ?? id;
  }

  // ------------------------------------------------------------------ drawing

  private labelsNow(): GiftLabels {
    const base = resolveLabels(this.o.labels);
    if (!base.metricUnits) {
      const coin = this.o.coinName ?? "coins";
      base.metricUnits = coin.charAt(0).toUpperCase() + coin.slice(1);
    }
    return base;
  }

  private render(): void {
    if (this.destroyed) return;
    const state = this.controller.getState();
    const labels = this.labelsNow();
    const root = this.element;
    const doc = this.doc;
    applyTheme(root, this.o.theme);
    // A redraw replaces every element: keep the keyboard focus on the same control.
    const active = doc.activeElement;
    const focusKey = active && root.contains(active) ? active.getAttribute("data-gs-focus") : null;
    root.replaceChildren();

    const toggle = this.o.metricToggle === true;
    const tabs = state.periods.length > 1;
    const header = make(doc, "div", "gs-board-head", root);
    if (tabs) this.drawTabs(header, state, labels);
    else make(doc, "span", "gs-board-fill", header);
    if (toggle) this.drawMetric(header, state, labels);
    const spin = make(doc, "span", "gs-spin", header);
    spin.setAttribute("aria-hidden", "true");
    spin.hidden = !state.refreshing;
    if (!tabs && !toggle) header.hidden = !state.refreshing;

    const body = make(doc, "div", "gs-board-body", root);
    body.setAttribute(
      "aria-busy",
      state.status === "loading" || state.refreshing ? "true" : "false",
    );
    if (tabs) {
      body.id = `${this.ids}-panel`;
      body.setAttribute("role", "tabpanel");
      body.setAttribute("aria-labelledby", `${this.ids}-tab-${state.period}`);
    }
    const waiting =
      state.data !== null &&
      (state.data.data.some((r) => this.asking.has(r.user)) ||
        (state.pinned !== null && this.asking.has(state.pinned.user)));

    if (state.status === "loading" || (state.status === "ready" && waiting)) {
      this.drawSkeleton(body, labels);
    } else if (state.status === "error") {
      const box = make(doc, "div", "gs-board-error", body);
      box.setAttribute("role", "alert");
      make(doc, "p", "gs-board-message", box).textContent = labels.error;
      const retry = make(doc, "button", "gs-retry", box);
      retry.type = "button";
      retry.setAttribute("data-gs-focus", "retry");
      retry.textContent = labels.tryAgain;
      retry.addEventListener("click", () => this.controller.refresh());
    } else if (state.status === "empty") {
      make(doc, "p", "gs-board-empty", body).textContent = labels.empty[state.period];
    } else if (state.data) {
      this.drawRows(body, state.data, state.pinned, labels);
    }

    if (focusKey) this.focus(focusKey);
  }

  private focus(key: string): void {
    this.element.querySelector<HTMLElement>(`[data-gs-focus="${key}"]`)?.focus();
  }

  private drawTabs(parent: HTMLElement, state: LeaderboardState, labels: GiftLabels): void {
    const list = make(this.doc, "div", "gs-tabs", parent);
    list.setAttribute("role", "tablist");
    const periods = state.periods;
    for (const p of periods) {
      const selected = p === state.period;
      const tab = make(this.doc, "button", "gs-tab", list);
      tab.type = "button";
      tab.id = `${this.ids}-tab-${p}`;
      tab.setAttribute("role", "tab");
      tab.setAttribute("data-gs-tab", p);
      tab.setAttribute("data-gs-focus", `tab:${p}`);
      tab.setAttribute("aria-selected", String(selected));
      tab.setAttribute("aria-controls", `${this.ids}-panel`);
      tab.tabIndex = selected ? 0 : -1;
      tab.textContent = labels.tabs[p];
      tab.addEventListener("click", () => this.select(p));
      tab.addEventListener("keydown", (e) => {
        const i = periods.indexOf(p);
        const next =
          e.key === "ArrowRight"
            ? periods[(i + 1) % periods.length]
            : e.key === "ArrowLeft"
              ? periods[(i - 1 + periods.length) % periods.length]
              : e.key === "Home"
                ? periods[0]
                : e.key === "End"
                  ? periods[periods.length - 1]
                  : undefined;
        if (!next) return;
        e.preventDefault();
        this.select(next);
      });
    }
  }

  private select(period: LeaderboardPeriod): void {
    this.controller.setPeriod(period);
    this.focus(`tab:${period}`);
  }

  private drawMetric(parent: HTMLElement, state: LeaderboardState, labels: GiftLabels): void {
    const group = make(this.doc, "div", "gs-metric", parent);
    group.setAttribute("role", "group");
    group.setAttribute("aria-label", labels.metricSwitch);
    const options: [LeaderboardMetric, string][] = [
      ["units", labels.metricUnits],
      ["gifts", labels.metricGifts],
    ];
    for (const [metric, text] of options) {
      const b = make(this.doc, "button", "gs-metric-btn", group);
      b.type = "button";
      b.setAttribute("data-gs-metric", metric);
      b.setAttribute("data-gs-focus", `metric:${metric}`);
      b.setAttribute("aria-pressed", String(state.metric === metric));
      b.textContent = text;
      b.addEventListener("click", () => {
        this.controller.setMetric(metric);
        this.focus(`metric:${metric}`);
      });
    }
  }

  private drawSkeleton(body: HTMLElement, labels: GiftLabels): void {
    const rows = this.o.limit ?? 10;
    const list = make(this.doc, "div", "gs-rows", body);
    list.setAttribute("role", "status");
    list.setAttribute("aria-label", labels.loading);
    for (let i = 0; i < rows; i++) {
      const row = make(this.doc, "div", "gs-row gs-row-skeleton", list);
      row.setAttribute("aria-hidden", "true");
      make(this.doc, "span", "gs-skel gs-skel-disc", row);
      make(this.doc, "span", "gs-skel gs-skel-disc", row);
      make(this.doc, "span", "gs-skel gs-skel-bar", row);
      make(this.doc, "span", "gs-skel gs-skel-score", row);
    }
  }

  /** `"54,000 coins"` or `"120 gifts"`: the score as it is spoken. */
  private spokenScore(n: number, metric: LeaderboardMetric, labels: GiftLabels): string {
    if (metric === "gifts") return `${groupThousands(n)} ${labels.giftsWord}`;
    return `${groupThousands(n)} ${this.o.coinName ?? "coins"}`;
  }

  private drawScore(parent: HTMLElement, n: number, metric: LeaderboardMetric, labels: GiftLabels) {
    const score = make(this.doc, "span", "gs-score", parent);
    score.setAttribute("aria-hidden", "true");
    make(this.doc, "span", "gs-score-num", score).textContent = shortCount(n, labels);
    if (metric === "units") make(this.doc, "span", "gs-dot gs-dot-small", score);
    else make(this.doc, "span", "gs-score-unit", score).textContent = labels.giftsWord;
  }

  private drawRows(
    body: HTMLElement,
    board: Leaderboard,
    pinned: LeaderboardMe | null,
    labels: GiftLabels,
  ): void {
    const doc = this.doc;
    const press = this.o.onPressUser;
    const mine = this.o.highlightUser ?? board.me?.user;
    const list = make(doc, "ol", "gs-rows", body);
    list.setAttribute("role", "list");
    for (const entry of board.data) {
      const li = make(doc, "li", "gs-row", list);
      const name = this.nameOf(entry.user);
      const spoken = fill(labels.rowSpoken, {
        rank: entry.rank,
        name,
        score: this.spokenScore(this.scoreOf(entry, board.metric), board.metric, labels),
      });
      if (entry.user === mine) {
        li.setAttribute("data-gs-me", "");
        li.setAttribute("aria-current", "true");
      }
      const main = make(doc, press ? "button" : "div", "gs-row-main", li);
      if (press) {
        (main as HTMLButtonElement).type = "button";
        main.setAttribute("data-gs-focus", `row:${entry.user}`);
        main.setAttribute("aria-label", spoken);
        main.addEventListener("click", () => this.o.onPressUser?.(entry.user));
      } else {
        li.setAttribute("aria-label", spoken);
        // The label says it all; what is drawn is not read a second time.
        main.setAttribute("aria-hidden", "true");
      }
      const info = this.names.get(entry.user);
      const score = this.scoreOf(entry, board.metric);
      const render = this.o.renderRow;
      const custom = render
        ? runRender(
            doc,
            () =>
              render({
                entry,
                rank: entry.rank,
                name,
                avatarUrl: info?.avatarUrl ?? null,
                metric: board.metric,
                score,
                scoreText: shortCount(score, labels),
                isMe: entry.user === mine,
                doc,
              }),
            (err) => this.o.onError?.(asGiftingError(err)),
          )
        : null;
      if (custom) {
        main.append(custom);
        continue;
      }
      const rank = make(doc, "span", "gs-rank", main);
      rank.setAttribute("aria-hidden", "true");
      rank.textContent = String(entry.rank);
      if (entry.rank >= 1 && entry.rank <= 3)
        rank.setAttribute("data-gs-medal", String(entry.rank));
      main.append(avatar(doc, name, info?.avatarUrl, 32));
      const nameEl = make(doc, "span", "gs-row-name", main);
      nameEl.setAttribute("aria-hidden", "true");
      nameEl.textContent = name;
      this.drawScore(main, score, board.metric, labels);
    }
    if (pinned) {
      const score = board.metric === "gifts" ? pinned.gifts : pinned.units;
      const rank = leaderboardRankLabel(pinned.rank, { overflow: labels.rankOverflow });
      const row = make(doc, "div", "gs-row gs-pinned", body);
      row.setAttribute("role", "group");
      row.setAttribute("data-gs-pinned", "");
      row.setAttribute("data-gs-me", "");
      row.setAttribute(
        "aria-label",
        fill(labels.pinnedSpoken, {
          rank: pinned.rank === null ? labels.rankOverflow : groupThousands(pinned.rank),
          score: this.spokenScore(score, board.metric, labels),
        }),
      );
      const main = make(doc, "div", "gs-row-main", row);
      main.setAttribute("aria-hidden", "true");
      make(doc, "span", "gs-pinned-rank", main).textContent = fill(labels.pinned, { rank });
      make(doc, "span", "gs-row-name", main).textContent = this.nameOf(pinned.user);
      this.drawScore(main, score, board.metric, labels);
    }
  }

  private scoreOf(entry: LeaderboardEntry, metric: LeaderboardMetric): number {
    return metric === "gifts" ? entry.gifts : entry.units;
  }
}
