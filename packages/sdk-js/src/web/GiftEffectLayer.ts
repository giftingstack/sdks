import {
  EffectScheduler,
  type EffectPlayer,
  type EffectQuality,
  type EffectTier,
  type GiftEffectEvent,
  type ScheduledEffect,
  type TierThresholds,
} from "../core";
import { EffectView } from "./effect";
import { NoticeView } from "./notice";
import { type RecipesLoader, startRemoteRecipes } from "./recipes-loader";
import { acquireStyles, releaseStyles } from "./styles";
import { type GiftTheme, applyTheme } from "./theme";

export interface GiftEffectLayerOptions {
  /** From which price a gift is medium or large. Defaults: 100 and 10,000. */
  thresholds?: Partial<TierThresholds>;
  /** `low` for slow devices: fewer sparks, no coin rain, no rays. */
  quality?: EffectQuality;
  /**
   * Default: follows `prefers-reduced-motion`, live. Reduced motion shows only the notice. A browser
   * without the Web Animations API always behaves like this, whatever the option says.
   */
  reducedMotion?: boolean;
  /** Small and medium effects on screen at once, 1 to 12 (defaults 6 and 2). Large ones stay one at a time. */
  maxConcurrent?: { small?: number; medium?: number };
  /** Same gift from the same person within this time counts as a combo. Default 2500. */
  comboWindowMs?: number;
  /** Where gifts start, as fractions of the layer. Default: bottom centre, `{ x: 0.5, y: 0.86 }`. */
  origin?: { x: number; y: number };
  /**
   * Longest wait for a gift's picture before its effect starts anyway, in ms. Default 300.
   * The effect and its notice start together once the picture is ready.
   */
  pictureWaitMs?: number;
  /** Distance of the notice from the bottom edge, in px. Default 150 (above a gift tray). */
  noticeBottom?: number;
  /** Multiplier for the gift picture size. Default: automatic (bigger in a wide layer, 1 on a phone). */
  pictureScale?: number;
  theme?: Partial<GiftTheme>;
  onEffectEnd?: (event: GiftEffectEvent, tier: EffectTier) => void;
  /** The clock for the combo window, in ms. Default `Date.now`. For tests. */
  now?: () => number;
  /**
   * Fetch the effect numbers from `recipesUrl` (cached, refreshed at most every 6 h; spec section
   * 13). Default true. `false`: no network at all, only the built-in numbers.
   */
  remoteRecipes?: boolean;
  /** Pin a document: fetches `recipes.<version>.json` instead of `recipes.json`. */
  recipesVersion?: string;
  /** Default `https://assets.giftingstack.com/recipes.json`. For self-hosting and tests. */
  recipesUrl?: string;
}

/**
 * Put one of these over your content, once, and call `play` whenever a gift is sent or received.
 * It draws the effect by the gift's price and the "ayla sent X" notice with a combo counter.
 * It never takes pointer events. The container should cover the area you want the effects in
 * (for the whole page: a `position: fixed; inset: 0` element); if it is `position: static` it is
 * made `relative` until `destroy()`.
 */
export class GiftEffectLayer implements EffectPlayer {
  /** The layer's root element, a child of the container. */
  readonly element: HTMLElement;
  /** The pure scheduler this layer draws for. Read-only use; call `play` on the layer. */
  readonly scheduler: EffectScheduler;
  private options: GiftEffectLayerOptions;
  private readonly container: HTMLElement;
  /** Holds the effects; the notice sits after it, on top. */
  private readonly effects: HTMLElement;
  private readonly views = new Map<number, EffectView>();
  private readonly notice: NoticeView;
  private readonly motion: MediaQueryList | null;
  private readonly resizeObserver: ResizeObserver | null;
  private readonly savedPosition: string | null;
  private destroyed = false;
  /** Remote recipes (null when off). Read at each `play`; never awaited. */
  private readonly remote: RecipesLoader | null;

  constructor(container: HTMLElement, options: GiftEffectLayerOptions = {}) {
    const doc = container.ownerDocument;
    const win = doc.defaultView;
    this.container = container;
    this.options = options;
    acquireStyles(doc);

    this.savedPosition = null;
    if (win && win.getComputedStyle(container).position === "static") {
      this.savedPosition = container.style.position;
      container.style.position = "relative";
    }
    this.element = doc.createElement("div");
    this.element.className = "gs-layer";
    this.element.setAttribute("data-gs-layer", "");
    applyTheme(this.element, options.theme);
    container.appendChild(this.element);
    this.effects = doc.createElement("div");
    this.effects.className = "gs-effects";
    this.element.appendChild(this.effects);

    this.motion = win?.matchMedia?.("(prefers-reduced-motion: reduce)") ?? null;
    this.notice = new NoticeView({
      parent: this.element,
      bottom: options.noticeBottom ?? 150,
    });

    // The queue, the caps, the combo and the notice text live in the shared scheduler (core).
    const s = new EffectScheduler({ comboWindowMs: options.comboWindowMs, now: options.now });
    s.listener = {
      enter: (item) => this.enter(item),
      exit: (item) => this.dropView(item.id),
      end: (item) => this.options.onEffectEnd?.(item.event, item.recipe.tier),
      notice: (data, durationMs) => {
        this.notice.show(data, durationMs);
      },
      noticeHide: () => this.notice.hideNewest(),
      clear: () => {
        this.notice.clearAll();
        this.dropAllViews();
      },
    };
    this.scheduler = s;
    this.remote = startRemoteRecipes(options);

    // Effects wait for a size (spec open question 9): start them when the layer gets one.
    this.resizeObserver =
      typeof ResizeObserver === "undefined"
        ? null
        : new ResizeObserver(() => {
            for (const view of this.views.values()) view.tryStart();
          });
    this.resizeObserver?.observe(this.element);
  }

  /** Change settings later. Gifts already on screen keep the settings they started with. */
  setOptions(options: GiftEffectLayerOptions): void {
    this.options = { ...this.options, ...options };
    // A new theme replaces the old one; options without a theme leave it alone.
    if ("theme" in options) applyTheme(this.element, options.theme);
    if (options.noticeBottom !== undefined) this.notice.setBottom(options.noticeBottom);
  }

  /**
   * Show a gift. Large gifts wait their turn; small and medium ones play at once.
   * Returns an id you can pass to `cancel` (0 after `destroy`).
   */
  play(event: GiftEffectEvent): number {
    if (this.destroyed) return 0;
    this.scheduler.setOptions({
      thresholds: this.options.thresholds,
      quality: this.options.quality,
      maxConcurrent: this.options.maxConcurrent,
      reducedMotion: this.reducedMotion(),
      recipes: this.remote?.current() ?? undefined,
    });
    return this.scheduler.play(event);
  }

  /** Take back a gift that was shown too early, for example because its send failed. */
  cancel(id: number): void {
    if (!this.destroyed) this.scheduler.cancel(id);
  }

  /** Stop everything and forget the queue. */
  clear(): void {
    if (!this.destroyed) this.scheduler.clear();
  }

  /** Remove the layer and everything it added to the page. The layer cannot be used again. */
  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.scheduler.listener = {};
    this.resizeObserver?.disconnect();
    this.dropAllViews();
    this.notice.dispose();
    this.element.remove();
    if (this.savedPosition !== null) this.container.style.position = this.savedPosition;
    releaseStyles();
  }

  /**
   * Without the Web Animations API (old browsers) nothing can fly, so the layer shows only the
   * notice, the same as reduced motion. The option cannot turn that off.
   */
  private reducedMotion(): boolean {
    const win = this.container.ownerDocument.defaultView;
    if (typeof win?.Element?.prototype?.animate !== "function") return true;
    return this.options.reducedMotion ?? this.motion?.matches ?? false;
  }

  private enter(item: ScheduledEffect): void {
    const view = new EffectView({
      effect: item,
      parent: this.effects,
      measure: () => ({ width: this.element.clientWidth, height: this.element.clientHeight }),
      pictureScale: this.options.pictureScale,
      origin: this.options.origin ?? { x: 0.5, y: 0.86 },
      pictureWaitMs: this.options.pictureWaitMs ?? 300,
      onStart: () => this.scheduler.started(item.id),
      onDone: () => this.scheduler.finished(item.id),
    });
    this.views.set(item.id, view);
  }

  private dropView(id: number): void {
    this.views.get(id)?.destroy();
    this.views.delete(id);
  }

  private dropAllViews(): void {
    for (const view of this.views.values()) view.destroy();
    this.views.clear();
  }
}
