import {
  AwayController,
  type AwayAckOn,
  type AwayEffectPlayer,
  type AwaySummary,
  type EffectQuality,
  type GiftingClient,
  type GiftingError,
  type TierThresholds,
  asGiftingError,
  groupThousands,
} from "../core";
import { type GiftLabels, type GiftLabelsInput, fill, resolveLabels } from "./labels";
import { acquireStyles, releaseStyles } from "./styles";
import { type GiftTheme, applyTheme } from "./theme";
import {
  type RenderResult,
  type ResolveUsers,
  type UserInfo,
  avatar,
  ensurePositioned,
  giftIcon,
  make,
  missingIds,
  motionOff,
  runRender,
  shortCount,
  withTimeout,
} from "./ui";

/** What `renderSummary` receives: the data the card would show, already computed, and callbacks. */
export interface AwaySummaryContext {
  summary: AwaySummary;
  /** The card title, from the labels. */
  title: string;
  /** `"37 gifts from 12 people"`, as the default card shows it. */
  headline: string;
  /** `"37 gifts"` and `"12 people"` (`2,000+` when the count was capped). */
  gifts: string;
  people: string;
  /** Top senders (the default card shows three), names from `resolveUsers` or the id. */
  senders: { user: string | null; name: string; avatarUrl: string | null; count: number }[];
  /** Close the card. Your own buttons call this: a tap on custom content does not dismiss. */
  dismiss: () => void;
  /** `ackOn: "manual"`: mark the summary as seen. */
  ack: () => Promise<void>;
  /** The document to create elements with. */
  doc: Document;
}

export interface GiftAwaySummaryOptions {
  client: GiftingClient;
  /** The effect layer that replays the gifts (or a function returning it). Absent: card only. */
  effects?: AwayEffectPlayer | (() => AwayEffectPlayer | null | undefined) | null;
  /** External ids are rarely display names: name (and picture) for each id. Fallback: the id. */
  resolveUsers?: ResolveUsers;
  /** Check on mount and when the page becomes visible again (at most once a minute). Default true. */
  autoCheck?: boolean;
  /** When the summary counts as seen: `"shown"` (default), `"finished"` or `"manual"` (`ack()`). */
  ackOn?: AwayAckOn;
  /** Show the card only with at least this many gifts (default 1); fewer: nothing shows, still acknowledged. */
  minGifts?: number;
  /** Gift groups replayed at most. Default 5. */
  maxEffects?: number;
  /** The replay ends by then, ms. Default 8000. */
  budgetMs?: number;
  thresholds?: Partial<TierThresholds>;
  quality?: EffectQuality;
  /** Default: follows `prefers-reduced-motion`. Reduced motion: the card only, no replay, no slide-in. */
  reducedMotion?: boolean;
  /**
   * Draw the body of the card yourself (web only / pending native port). The SDK still checks,
   * names the senders, keeps the card (a non-modal dialog labelled with the title), the screen
   * reader announcement, `focusOnShow`, Escape to close, the slide-in, the effect replay and the
   * acknowledgement. Return a node or a string; nothing draws the default body. With your body a
   * tap does not dismiss: call `dismiss()`.
   */
  renderSummary?: (summary: AwaySummaryContext) => RenderResult;
  /** Move the keyboard focus to the card when it appears. Default false. */
  focusOnShow?: boolean;
  onShow?: (summary: AwaySummary) => void;
  onDone?: () => void;
  onError?: (error: GiftingError) => void;
  theme?: Partial<GiftTheme>;
  labels?: GiftLabelsInput;
}

/** How long the card waits for `resolveUsers` before it shows with the ids. */
const RESOLVE_WAIT_MS = 1500;
const SLIDE_MS = 240;
const FADE_OUT_MS = 160;

/**
 * "While you were away": a card with how many gifts arrived, the top senders and the gifts, and
 * a short replay of the gift groups in the effect layer. The card is centred in `container` (the
 * container becomes `position: relative` if it is static) and takes clicks only on itself. Tap or
 * the Dismiss button closes it; it closes itself when the replay has ended. Non-modal dialog.
 */
export class GiftAwaySummary {
  readonly element: HTMLElement;
  /** The pure controller behind the card, for state and tests. */
  readonly controller: AwayController;
  private o: GiftAwaySummaryOptions;
  private readonly doc: Document;
  private readonly live: HTMLElement;
  private readonly restorePosition: () => void;
  private readonly names = new Map<string, UserInfo>();
  private card: HTMLElement | null = null;
  private fadeTimer: ReturnType<typeof setTimeout> | undefined;
  private destroyed = false;
  private presenting = false;
  private readonly unsubscribe: () => void;
  private readonly onVisible: () => void;

  constructor(container: HTMLElement, options: GiftAwaySummaryOptions) {
    this.doc = container.ownerDocument;
    this.o = options;
    acquireStyles(this.doc);
    this.restorePosition = ensurePositioned(container);
    this.element = make(this.doc, "div", "gs-away");
    this.element.setAttribute("data-gs-away", "");
    applyTheme(this.element, options.theme);
    this.live = make(this.doc, "div", "gs-sr", this.element);
    this.live.setAttribute("role", "status");
    this.live.setAttribute("aria-live", "polite");
    this.live.setAttribute("aria-atomic", "true");
    container.appendChild(this.element);

    this.controller = new AwayController({
      client: options.client,
      effects: () => {
        const e = this.o.effects;
        return typeof e === "function" ? e() : e;
      },
      reducedMotion: () => motionOff(this.doc, this.o.reducedMotion),
      ...this.controllerSettings(),
    });
    this.unsubscribe = this.controller.subscribe(() => this.onState());
    this.onVisible = () => {
      if (this.doc.visibilityState !== "hidden" && this.o.autoCheck !== false)
        void this.controller.foreground();
    };
    this.doc.addEventListener("visibilitychange", this.onVisible);
    if (options.autoCheck !== false) void this.controller.check();
  }

  /** Read at each use by the controller: callbacks and settings change live. */
  private controllerSettings() {
    const o = this.o;
    return {
      ackOn: o.ackOn,
      minGifts: o.minGifts,
      maxEffects: o.maxEffects,
      budgetMs: o.budgetMs,
      thresholds: o.thresholds,
      quality: o.quality,
      labels: { someone: resolveLabels(o.labels).someone },
      resolveName: (id: string) => this.names.get(id)?.name ?? id,
      onShow: (s: AwaySummary) => this.o.onShow?.(s),
      onDone: () => this.o.onDone?.(),
      onError: (e: GiftingError) => this.o.onError?.(e),
    };
  }

  update(patch: Partial<GiftAwaySummaryOptions>): void {
    if (this.destroyed) return;
    this.o = { ...this.o, ...patch };
    this.controller.setOptions({
      client: this.o.client,
      effects: () => {
        const e = this.o.effects;
        return typeof e === "function" ? e() : e;
      },
      reducedMotion: () => motionOff(this.doc, this.o.reducedMotion),
      ...this.controllerSettings(),
    });
    if ("theme" in patch) applyTheme(this.element, this.o.theme);
  }

  /** Ask the server what arrived (ignored while a card is showing). */
  check(): Promise<void> {
    return this.controller.check();
  }
  /** `ackOn: "manual"`: mark the summary on screen as seen. */
  ack(): Promise<void> {
    return this.controller.ack();
  }
  /** Close the card now. */
  dismiss(): void {
    this.controller.dismiss();
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    clearTimeout(this.fadeTimer);
    this.unsubscribe();
    this.doc.removeEventListener("visibilitychange", this.onVisible);
    this.controller.dispose();
    this.element.remove();
    this.restorePosition();
    releaseStyles();
  }

  // ------------------------------------------------------------------ state to DOM

  private onState(): void {
    if (this.destroyed) return;
    const { status, summary } = this.controller.getState();
    if (status === "ready" && summary && !this.presenting) {
      this.presenting = true;
      void this.present(summary);
    } else if (status === "done" || status === "idle" || status === "empty") {
      this.presenting = false;
      this.removeCard();
    }
  }

  /** Names first (briefly), then the card, then the replay. */
  private async present(summary: AwaySummary): Promise<void> {
    const resolve = this.o.resolveUsers;
    if (resolve) {
      const ids = missingIds(
        [
          ...summary.groups.flatMap((g) => g.senders.map((s) => s.user)),
          ...summary.top_senders.map((s) => s.user),
        ],
        this.names,
      );
      if (ids.length) {
        try {
          const found = await withTimeout(resolve(ids), RESOLVE_WAIT_MS);
          for (const [id, info] of Object.entries(found ?? {})) this.names.set(id, info);
        } catch (err) {
          this.o.onError?.(asGiftingError(err));
        }
      }
    }
    // Still this summary, still ready? (The screen may have gone, or the person left.)
    if (this.destroyed || this.controller.getState().status !== "ready") return;
    this.showCard(summary);
    this.controller.start();
  }

  private removeCard(): void {
    const card = this.card;
    if (!card) return;
    this.card = null;
    if (motionOff(this.doc, this.o.reducedMotion)) {
      card.remove();
      return;
    }
    // Fade out, then drop it. A new card may already be there: only this one goes.
    card.style.pointerEvents = "none";
    card.animate([{ opacity: 1 }, { opacity: 0 }], { duration: FADE_OUT_MS, fill: "forwards" });
    setTimeout(() => card.remove(), FADE_OUT_MS);
  }

  private nameOf(id: string | null, labels: GiftLabels): string {
    return id === null ? labels.someone : (this.names.get(id)?.name ?? id);
  }

  private count(n: number, one: string, other: string, plus: boolean): string {
    const text = groupThousands(n) + (plus ? "+" : "");
    return fill(n === 1 && !plus ? one : other, { n: text });
  }

  private showCard(summary: AwaySummary): void {
    const o = this.o;
    const labels = resolveLabels(o.labels);
    const doc = this.doc;
    this.card?.remove();
    const gifts = this.count(
      summary.total_gifts,
      labels.giftOne,
      labels.giftOther,
      summary.truncated,
    );
    const people = this.count(
      summary.sender_count,
      labels.personOne,
      labels.personOther,
      summary.truncated,
    );
    const headline = fill(labels.awaySummary, { gifts, people });

    const card = make(doc, "div", "gs-away-card");
    card.setAttribute("data-gs-away-card", "");
    card.setAttribute("role", "dialog");
    card.setAttribute("aria-modal", "false");
    card.tabIndex = -1;

    const render = o.renderSummary;
    const custom = render
      ? runRender(
          doc,
          () =>
            render({
              summary,
              title: labels.awayTitle,
              headline,
              gifts,
              people,
              senders: summary.top_senders.map((s) => ({
                user: s.user,
                name: this.nameOf(s.user, labels),
                avatarUrl: (s.user === null ? null : this.names.get(s.user)?.avatarUrl) ?? null,
                count: s.count,
              })),
              dismiss: () => this.controller.dismiss(),
              ack: () => this.controller.ack(),
              doc,
            }),
          (err) => o.onError?.(asGiftingError(err)),
        )
      : null;
    if (custom) {
      card.setAttribute("aria-label", labels.awayTitle);
      card.append(custom);
    } else this.drawDefault(card, summary, headline, labels);

    if (!custom) card.addEventListener("click", () => this.controller.dismiss());
    card.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        e.stopPropagation();
        this.controller.dismiss();
      }
    });
    this.element.appendChild(card);
    this.card = card;

    this.live.textContent = fill(labels.awayAnnounce, {
      summary: fill(labels.awaySummary, { gifts, people }),
    });
    if (o.focusOnShow) card.focus();
    if (!motionOff(doc, o.reducedMotion)) {
      card.animate(
        [
          { opacity: 0, transform: "translateY(16px) scale(0.97)" },
          { opacity: 1, transform: "translateY(0) scale(1)" },
        ],
        { duration: SLIDE_MS, easing: "cubic-bezier(0.22, 1, 0.36, 1)" },
      );
    }
  }

  /** The default body: title, headline, close button, top senders, gift chips. */
  private drawDefault(
    card: HTMLElement,
    summary: AwaySummary,
    headline: string,
    labels: GiftLabels,
  ): void {
    const doc = this.doc;
    const head = make(doc, "div", "gs-away-head", card);
    const titles = make(doc, "div", "gs-away-titles", head);
    const title = make(doc, "h2", "gs-away-title", titles);
    title.id = `gs-away-title-${Math.random().toString(36).slice(2, 8)}`;
    title.textContent = labels.awayTitle;
    card.setAttribute("aria-labelledby", title.id);
    make(doc, "p", "gs-away-headline", titles).textContent = headline;
    const close = make(doc, "button", "gs-away-close", head);
    close.type = "button";
    close.setAttribute("aria-label", labels.dismiss);
    close.setAttribute("data-gs-dismiss", "");
    close.innerHTML =
      '<svg viewBox="0 0 12 12" width="12" height="12" aria-hidden="true" focusable="false"><path d="M2 2l8 8M10 2l-8 8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" fill="none"/></svg>';
    close.addEventListener("click", (e) => {
      e.stopPropagation();
      this.controller.dismiss();
    });

    const senders = summary.top_senders.slice(0, 3);
    if (senders.length) {
      const list = make(doc, "ul", "gs-away-senders", card);
      for (const s of senders) {
        const name = this.nameOf(s.user, labels);
        const row = make(doc, "li", "gs-away-sender", list);
        row.append(
          avatar(doc, name, s.user === null ? null : this.names.get(s.user)?.avatarUrl, 28),
        );
        make(doc, "span", "gs-away-name", row).textContent = name;
        make(doc, "span", "gs-away-count", row).textContent = shortCount(s.count, labels);
      }
    }
    if (summary.groups.length) {
      const wrap = make(doc, "div", "gs-away-gifts", card);
      for (const g of summary.groups) {
        const chip = make(doc, "span", "gs-chip", wrap);
        chip.setAttribute("data-gs-gift", g.gift.id);
        chip.title = g.gift.name;
        chip.append(giftIcon(doc, g.gift.icon_url));
        make(doc, "span", "gs-chip-count", chip).textContent = shortCount(g.count, labels);
      }
    }
  }
}
