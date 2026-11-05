/**
 * `<gift-effect-layer>`, `<gift-tray>`, `<gift-wall>`, `<gift-away-summary>`,
 * `<gift-leaderboard>`, `<gift-battle-bar>` and `<gift-room>`: the web SDK as plain HTML elements, for pages that are
 * not built with a framework (or are, and just want a few tags). They are thin: every rule lives in
 * `GiftEffectLayer`, `GiftTray` and `createGiftTray`; this file only reads attributes, sets up and
 * tears down, and turns callbacks into DOM events. Light DOM, no shadow root, so your CSS and the
 * `--gs-*` variables reach the tray as usual.
 *
 * Nothing is registered on import. Call `defineGiftElements()`, or import
 * `@giftingstack/sdk/elements`, which does it. Importing this file on a server is safe.
 */
import type {
  AwayEffectPlayer,
  BattleBarLabelsInput,
  BattleView,
  EffectPlayer,
  EffectQuality,
  GiftEffectEvent,
  GiftTransaction,
  GiftingClient,
  GiftingError,
  GiftTrayState,
  LeaderboardPeriod,
  ReceivedGift,
  SheetSnap,
  TrayPlacement,
} from "../core";
import { GiftEffectLayer, type GiftEffectLayerOptions } from "./GiftEffectLayer";
import { type CreateGiftTrayOptions, type GiftTrayHandle, createGiftTray } from "./createGiftTray";
import { GiftAwaySummary, type GiftAwaySummaryOptions } from "./GiftAwaySummary";
import { GiftBattleBar, type GiftBattleBarOptions } from "./GiftBattleBar";
import { GiftLeaderboard, type GiftLeaderboardOptions } from "./GiftLeaderboard";
import type { GiftTray } from "./GiftTray";
import {
  type JoinRoomOptions,
  type RoomEffectPlayer,
  type RoomHandle,
  type RoomLiveOptions,
  joinRoom,
} from "./joinRoom";
import { GiftWall, type GiftWallOptions } from "./GiftWall";
import type { GiftLabelsInput } from "./labels";
import type { ResolveUsers } from "./ui";
import { type InstalledCss, installCss } from "./styles";
import type { GiftTheme } from "./theme";

/** On a server there is no `HTMLElement`; the classes still have to exist so the module loads. */
const Base = (typeof HTMLElement === "undefined" ? class {} : HTMLElement) as typeof HTMLElement;

const HOST_STYLE_ATTR = "data-gs-elements";
/** `:where` keeps the specificity at zero: any rule of the page wins. */
const HOST_CSS = `
:where(gift-effect-layer) { display: block; position: absolute; inset: 0; pointer-events: none; }
:where(gift-tray, gift-wall, gift-leaderboard, gift-battle-bar) { display: block; }
:where(gift-room) { display: none; }
:where(gift-away-summary) { display: block; position: absolute; inset: 0; pointer-events: none; }
gift-tray[data-gs-placement="sheet"] { pointer-events: none; }
`;

const hostStyles = new WeakMap<Document, InstalledCss>();

function ensureHostStyle(doc: Document): void {
  if (hostStyles.get(doc)?.alive() || doc.head.querySelector(`style[${HOST_STYLE_ATTR}]`)) return;
  hostStyles.set(doc, installCss(doc, HOST_CSS, HOST_STYLE_ATTR));
}

/** A boolean attribute: present means true, except the text `false`. */
const flag = (el: Element, name: string): boolean | undefined =>
  el.hasAttribute(name) ? el.getAttribute(name) !== "false" : undefined;

const text = (el: Element, name: string): string | undefined => el.getAttribute(name) ?? undefined;

function number(el: Element, name: string): number | undefined {
  const raw = el.getAttribute(name);
  if (raw === null || raw.trim() === "") return undefined;
  const n = Number(raw);
  return Number.isFinite(n) ? n : undefined;
}

function oneOf<T extends string>(el: Element, name: string, allowed: readonly T[]): T | undefined {
  const raw = el.getAttribute(name);
  return raw !== null && (allowed as readonly string[]).includes(raw) ? (raw as T) : undefined;
}

/** Drops keys whose value is `undefined`, so a missing attribute never overrides a default. */
function defined<T extends object>(o: T): Partial<T> {
  return Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined)) as Partial<T>;
}

function emit<T>(el: Element, name: string, detail: T): void {
  el.dispatchEvent(new CustomEvent<T>(name, { detail, bubbles: true, composed: true }));
}

// ---------------------------------------------------------------------------------------------

/**
 * `<gift-effect-layer>`: put one over the area where gifts should fly. It covers its nearest
 * positioned ancestor (override with your own CSS) and never takes clicks.
 *
 * Attributes: `quality` (`high` | `low`), `reduced-motion` (`true` | `false`; default follows the
 * system), `picture-scale`, `notice-bottom` (px), `combo-window-ms`, `remote-recipes` (`false` = no network), `recipes-version`,
 * `recipes-url` (the last four are read once, when the element is added). Properties: `layer`
 * (the `GiftEffectLayer`), `options` (what attributes cannot say: `thresholds`, `theme`, `origin`,
 * `pictureWaitMs`). Methods: `play(event)`, `cancel(id)`, `clear()`. Event: `gift-effect-end`
 * (`detail: { event, tier }`).
 */
export class GiftEffectLayerElement extends Base {
  static readonly observedAttributes = [
    "quality",
    "reduced-motion",
    "picture-scale",
    "notice-bottom",
  ];

  /** The layer inside, while the element is on the page. */
  layer: GiftEffectLayer | null = null;
  private extra: GiftEffectLayerOptions = {};

  connectedCallback(): void {
    if (this.layer) return;
    ensureHostStyle(this.ownerDocument);
    this.layer = new GiftEffectLayer(this, {
      ...this.extra,
      ...this.fromAttributes(),
      comboWindowMs: number(this, "combo-window-ms"),
      remoteRecipes: flag(this, "remote-recipes"),
      recipesVersion: text(this, "recipes-version"),
      recipesUrl: text(this, "recipes-url"),
      onEffectEnd: (event, tier) => emit(this, "gift-effect-end", { event, tier }),
    });
  }

  disconnectedCallback(): void {
    this.layer?.destroy();
    this.layer = null;
  }

  attributeChangedCallback(): void {
    this.layer?.setOptions(this.fromAttributes());
  }

  /** Settings the attributes cannot carry. Attributes win where both say something. */
  get options(): GiftEffectLayerOptions {
    return this.extra;
  }
  set options(value: GiftEffectLayerOptions) {
    this.extra = value;
    this.layer?.setOptions({ ...value, ...this.fromAttributes() });
  }

  play(event: GiftEffectEvent): number {
    return this.layer?.play(event) ?? 0;
  }
  cancel(id: number): void {
    this.layer?.cancel(id);
  }
  clear(): void {
    this.layer?.clear();
  }

  /** A removed attribute falls back to `options`, then to the default. */
  private fromAttributes(): GiftEffectLayerOptions {
    return {
      quality: oneOf<EffectQuality>(this, "quality", ["high", "low"]) ?? this.extra.quality,
      reducedMotion: flag(this, "reduced-motion") ?? this.extra.reducedMotion,
      pictureScale: number(this, "picture-scale") ?? this.extra.pictureScale,
      noticeBottom: number(this, "notice-bottom") ?? this.extra.noticeBottom,
    };
  }
}

// ---------------------------------------------------------------------------------------------

const SNAPS: readonly SheetSnap[] = ["peek", "default", "expanded"];
const PLACEMENTS = ["auto", "sheet", "popover", "inline"] as const;
const PLAY_ON = ["tap", "success"] as const;

/**
 * `<gift-tray>`: the gift tray, loaded and wired. It stays empty until it is on the page, has a
 * `client` and a `receiver`. Give it the size of the area it belongs to (as the container of
 * `GiftTray`): the sheet sits at the bottom of that area.
 *
 * ```html
 * <gift-effect-layer id="fx"></gift-effect-layer>
 * <gift-tray receiver="mert" reference="post-42" effects="#fx" top-up></gift-tray>
 * <script type="module">
 *   document.querySelector("gift-tray").client = createGiftingClient({ getToken });
 * </script>
 * ```
 *
 * Attributes: `receiver` (required), `reference`, `effects` (CSS selector of the
 * `<gift-effect-layer>` that plays the gifts; default: the first one on the page), `play-on`
 * (`tap` | `success`), `tray-title`, `coin-name`, `send-label`, `not-enough-label`,
 * `get-coins-label`, `columns`, `grid-max-height`, `default-selected-id`, `disabled`, `sheet`
 * (`false` = fixed tray), `placement` (`auto` | `sheet` | `popover` | `inline`), `anchor` (CSS
 * selector of your gift button, for the popover), `initial-snap` (`peek` | `default` | `expanded`),
 * `top-up` (shows the coin button and fires `gift-topup`). Changing one rebuilds the tray, except
 * `disabled`, which updates it in place.
 *
 * Properties: `client` (a `GiftingClient`, required), `theme`, `player` (any `EffectPlayer`, instead of
 * `effects`), `options` (what attributes cannot say: `snaps`, `onSent`...), `tray`, `controller`.
 * Methods: `refresh()`, `open()`, `close()`, `toggle()`.
 *
 * Events, all bubbling: `gift-sent` (`detail`: the transaction), `gift-error` (`detail`: the
 * `GiftingError`; `insufficientBalance` means: open your coin store), `gift-state`, `gift-topup`,
 * `gift-open-change`, `gift-snap-change`, `gift-placement-change`, `gift-inset-change` (px).
 * When the tray is a sheet, it keeps the notice of the linked layer above it (unless that layer has
 * its own `notice-bottom`).
 */
export class GiftTrayElement extends Base {
  static readonly observedAttributes = [
    "receiver",
    "reference",
    "effects",
    "play-on",
    "tray-title",
    "coin-name",
    "send-label",
    "not-enough-label",
    "get-coins-label",
    "columns",
    "grid-max-height",
    "default-selected-id",
    "disabled",
    "sheet",
    "placement",
    "anchor",
    "initial-snap",
    "top-up",
  ];

  private handle: GiftTrayHandle | null = null;
  private clientValue: GiftingClient | null = null;
  private themeValue: Partial<GiftTheme> | undefined;
  private playerValue: EffectPlayer | null = null;
  private extra: Partial<CreateGiftTrayOptions> = {};
  private queued = false;
  private generation = 0;

  get client(): GiftingClient | null {
    return this.clientValue;
  }
  set client(value: GiftingClient | null) {
    this.clientValue = value;
    this.rebuildSoon();
  }

  get receiver(): string {
    return this.getAttribute("receiver") ?? "";
  }
  set receiver(value: string) {
    this.setAttribute("receiver", value);
  }

  get reference(): string {
    return this.getAttribute("reference") ?? "";
  }
  set reference(value: string) {
    this.setAttribute("reference", value);
  }

  get theme(): Partial<GiftTheme> | undefined {
    return this.themeValue;
  }
  set theme(value: Partial<GiftTheme> | undefined) {
    this.themeValue = value;
    this.handle?.tray.update({ theme: value });
  }

  /** Plays the gifts instead of the `<gift-effect-layer>` that `effects` names. */
  get player(): EffectPlayer | null {
    return this.playerValue;
  }
  set player(value: EffectPlayer | null) {
    this.playerValue = value;
  }

  get options(): Partial<CreateGiftTrayOptions> {
    return this.extra;
  }
  set options(value: Partial<CreateGiftTrayOptions>) {
    this.extra = value;
    this.rebuildSoon();
  }

  get tray(): GiftTray | null {
    return this.handle?.tray ?? null;
  }
  get controller(): GiftTrayHandle["controller"] | null {
    return this.handle?.controller ?? null;
  }

  refresh(): Promise<void> {
    return this.handle?.refresh() ?? Promise.resolve();
  }
  open(): void {
    this.handle?.tray.open();
  }
  close(): void {
    this.handle?.tray.close();
  }
  toggle(): void {
    this.handle?.tray.toggle();
  }

  connectedCallback(): void {
    ensureHostStyle(this.ownerDocument);
    this.rebuildSoon();
  }

  disconnectedCallback(): void {
    this.generation++;
    this.teardown();
  }

  attributeChangedCallback(name: string): void {
    if (name === "disabled" && this.handle) {
      this.handle.tray.update({ disabled: flag(this, "disabled") ?? false });
      return;
    }
    this.rebuildSoon();
  }

  /** Several attributes usually change together (and the client arrives later): build once. */
  private rebuildSoon(): void {
    if (this.queued) return;
    this.queued = true;
    const generation = this.generation;
    queueMicrotask(() => {
      this.queued = false;
      if (generation !== this.generation) return;
      this.rebuild();
    });
  }

  private rebuild(): void {
    this.teardown();
    const client = this.clientValue;
    const receiver = this.getAttribute("receiver");
    if (!this.isConnected || !client || !receiver) return;
    const doc = this.ownerDocument;

    this.handle = createGiftTray({
      ...this.extra,
      ...defined({
        title: text(this, "tray-title"),
        coinName: text(this, "coin-name"),
        sendLabel: text(this, "send-label"),
        notEnoughLabel: text(this, "not-enough-label"),
        getCoinsLabel: text(this, "get-coins-label"),
        columns: number(this, "columns"),
        gridMaxHeight: number(this, "grid-max-height"),
        defaultSelectedId: text(this, "default-selected-id"),
        disabled: flag(this, "disabled"),
        sheet: flag(this, "sheet"),
        placement: oneOf(this, "placement", PLACEMENTS),
        initialSnap: oneOf<SheetSnap>(this, "initial-snap", SNAPS),
        playOn: oneOf(this, "play-on", PLAY_ON),
        reference: text(this, "reference"),
      }),
      theme: this.themeValue ?? this.extra.theme,
      anchor: this.resolve<HTMLElement>(doc, text(this, "anchor")) ?? this.extra.anchor,
      container: this,
      client,
      receiver,
      effects: () => this.playerValue ?? this.effectLayer()?.layer,
      onTopUp: flag(this, "top-up") ? () => emit(this, "gift-topup", null) : this.extra.onTopUp,
      onSent: (transaction: GiftTransaction) => {
        this.extra.onSent?.(transaction);
        emit(this, "gift-sent", transaction);
      },
      onError: (error: GiftingError) => {
        this.extra.onError?.(error);
        emit(this, "gift-error", error);
      },
      onState: (state: GiftTrayState) => {
        this.extra.onState?.(state);
        emit(this, "gift-state", state);
      },
      onOpenChange: (open: boolean) => {
        this.extra.onOpenChange?.(open);
        emit(this, "gift-open-change", open);
      },
      onSnapChange: (snap: SheetSnap) => {
        this.extra.onSnapChange?.(snap);
        emit(this, "gift-snap-change", snap);
      },
      onPlacementChange: (placement: TrayPlacement) => {
        this.setPlacementMark(placement);
        this.extra.onPlacementChange?.(placement);
        emit(this, "gift-placement-change", placement);
      },
      onInsetChange: (px: number) => {
        const fx = this.effectLayer();
        if (fx && !fx.hasAttribute("notice-bottom"))
          fx.layer?.setOptions({ noticeBottom: px + 16 });
        this.extra.onInsetChange?.(px);
        emit(this, "gift-inset-change", px);
      },
    });
    this.setPlacementMark(this.handle.tray.getPlacement());
  }

  private teardown(): void {
    this.handle?.destroy();
    this.handle = null;
    this.removeAttribute("data-gs-placement");
  }

  /** The host mirrors the placement so CSS can tell a sheet (clicks pass through) from the rest. */
  private setPlacementMark(placement: TrayPlacement | null): void {
    if (placement) this.setAttribute("data-gs-placement", placement);
    else this.removeAttribute("data-gs-placement");
  }

  private effectLayer(): GiftEffectLayerElement | null {
    const selector = text(this, "effects") ?? "gift-effect-layer";
    const found = this.resolve<GiftEffectLayerElement>(this.ownerDocument, selector);
    return found && "layer" in found ? found : null;
  }

  private resolve<T extends Element>(doc: Document, selector: string | undefined): T | null {
    if (!selector) return null;
    const root = this.getRootNode() as Document | ShadowRoot;
    try {
      return (root.querySelector?.(selector) ?? doc.querySelector(selector)) as T | null;
    } catch {
      return null; // an invalid selector must not break the page
    }
  }
}

// ---------------------------------------------------------------------------------------------

const WALL_ORDERS = ["count", "catalog"] as const;
const WALL_SIZES = ["sm", "md"] as const;

/**
 * `<gift-wall>`: gift chips under a post or on a profile. Stays empty until it is on the page and
 * has a `client` and a `user`. Walls of one screen share their requests (one batch call).
 *
 * Attributes: `user` (required), `reference`, `max`, `order` (`count` | `catalog`), `size` (`sm` |
 * `md`), `refresh-key` (change it to refetch), `pressable` (chips become buttons and fire
 * `gift-chip-press`). Properties: `client`, `data` (preloaded counters: no request), `theme`,
 * `labels`, `options` (what attributes cannot say, e.g. `onPressChip`), `wall`. Events (they
 * bubble): `gift-chip-press` (`detail`: the gift), `gift-error` (`detail`: the `GiftingError`; a wall
 * never shows an error).
 */
export class GiftWallElement extends Base {
  static readonly observedAttributes = [
    "user",
    "reference",
    "max",
    "order",
    "size",
    "refresh-key",
    "pressable",
  ];

  private instance: GiftWall | null = null;
  private builtFor: GiftingClient | null = null;
  private clientValue: GiftingClient | null = null;
  private dataValue: ReceivedGift[] | undefined;
  private themeValue: Partial<GiftTheme> | undefined;
  private labelsValue: GiftLabelsInput | undefined;
  private extra: Partial<GiftWallOptions> = {};

  get client(): GiftingClient | null {
    return this.clientValue;
  }
  set client(value: GiftingClient | null) {
    this.clientValue = value;
    this.sync();
  }
  get data(): ReceivedGift[] | undefined {
    return this.dataValue;
  }
  set data(value: ReceivedGift[] | undefined) {
    this.dataValue = value;
    this.sync();
  }
  get theme(): Partial<GiftTheme> | undefined {
    return this.themeValue;
  }
  set theme(value: Partial<GiftTheme> | undefined) {
    this.themeValue = value;
    this.sync();
  }
  get labels(): GiftLabelsInput | undefined {
    return this.labelsValue;
  }
  set labels(value: GiftLabelsInput | undefined) {
    this.labelsValue = value;
    this.sync();
  }
  get options(): Partial<GiftWallOptions> {
    return this.extra;
  }
  set options(value: Partial<GiftWallOptions>) {
    this.extra = value;
    this.sync();
  }
  get wall(): GiftWall | null {
    return this.instance;
  }

  connectedCallback(): void {
    ensureHostStyle(this.ownerDocument);
    this.sync();
  }
  disconnectedCallback(): void {
    this.instance?.destroy();
    this.instance = null;
  }
  attributeChangedCallback(): void {
    this.sync();
  }

  /** Builds, updates or removes the wall to match the attributes and properties. */
  private sync(): void {
    const user = this.getAttribute("user");
    const client = this.clientValue;
    if (!this.isConnected || !client || !user) {
      this.instance?.destroy();
      this.instance = null;
      return;
    }
    const pressable = flag(this, "pressable");
    const options: GiftWallOptions = {
      ...this.extra,
      ...defined({
        reference: text(this, "reference"),
        max: number(this, "max"),
        order: oneOf(this, "order", WALL_ORDERS),
        size: oneOf(this, "size", WALL_SIZES),
        refreshKey: text(this, "refresh-key"),
        data: this.dataValue,
        theme: this.themeValue ?? this.extra.theme,
        labels: this.labelsValue ?? this.extra.labels,
      }),
      client,
      user,
      onPressChip:
        pressable || this.extra.onPressChip
          ? (gift) => {
              this.extra.onPressChip?.(gift);
              emit(this, "gift-chip-press", gift);
            }
          : undefined,
      onError: (error) => {
        this.extra.onError?.(error);
        emit(this, "gift-error", error);
      },
    };
    if (this.instance && this.builtFor === client) {
      // An attribute that went away must not leave its old value behind.
      this.instance.update({
        reference: undefined,
        max: undefined,
        order: undefined,
        size: undefined,
        refreshKey: undefined,
        data: undefined,
        ...options,
      });
    } else {
      this.instance?.destroy();
      this.instance = new GiftWall(this, options);
      this.builtFor = client;
    }
  }
}

// ---------------------------------------------------------------------------------------------

const ACK_ON = ["shown", "finished", "manual"] as const;

/**
 * `<gift-away-summary>`: the "while you were away" card. Put it inside the screen area (it covers
 * its nearest positioned ancestor, like `<gift-effect-layer>`, and takes clicks only on the card).
 * It checks when it is added and when the page becomes visible again, then replays the gifts in
 * the effect layer.
 *
 * Attributes: `effects` (CSS selector of the `<gift-effect-layer>`; default the first one; `none` =
 * card only), `auto-check` (`false` = call `check()` yourself), `ack-on` (`shown` | `finished` |
 * `manual`), `max-effects`, `budget-ms`, `quality` (`high` | `low`), `reduced-motion`,
 * `focus-on-show`. Properties: `client` (required), `resolveUsers`, `player` (any effect player
 * instead of the layer), `theme`, `labels`, `options` (what attributes cannot say, e.g.
 * `thresholds`), `away`. Methods: `check()`, `ack()`, `dismiss()`. Events (they bubble):
 * `gift-away-show` (`detail`: the summary), `gift-away-done`, `gift-error`.
 */
export class GiftAwaySummaryElement extends Base {
  static readonly observedAttributes = [
    "effects",
    "auto-check",
    "ack-on",
    "max-effects",
    "min-gifts",
    "budget-ms",
    "quality",
    "reduced-motion",
    "focus-on-show",
  ];

  private instance: GiftAwaySummary | null = null;
  private clientValue: GiftingClient | null = null;
  private resolveValue: ResolveUsers | undefined;
  private playerValue: AwayEffectPlayer | null = null;
  private themeValue: Partial<GiftTheme> | undefined;
  private labelsValue: GiftLabelsInput | undefined;
  private extra: Partial<GiftAwaySummaryOptions> = {};
  private queued = false;
  private generation = 0;

  get client(): GiftingClient | null {
    return this.clientValue;
  }
  set client(value: GiftingClient | null) {
    this.clientValue = value;
    this.rebuildSoon();
  }
  get resolveUsers(): ResolveUsers | undefined {
    return this.resolveValue;
  }
  set resolveUsers(value: ResolveUsers | undefined) {
    this.resolveValue = value;
    this.instance?.update({ resolveUsers: value });
  }
  get player(): AwayEffectPlayer | null {
    return this.playerValue;
  }
  set player(value: AwayEffectPlayer | null) {
    this.playerValue = value;
  }
  get theme(): Partial<GiftTheme> | undefined {
    return this.themeValue;
  }
  set theme(value: Partial<GiftTheme> | undefined) {
    this.themeValue = value;
    this.instance?.update({ theme: value });
  }
  get labels(): GiftLabelsInput | undefined {
    return this.labelsValue;
  }
  set labels(value: GiftLabelsInput | undefined) {
    this.labelsValue = value;
    this.instance?.update({ labels: value });
  }
  get options(): Partial<GiftAwaySummaryOptions> {
    return this.extra;
  }
  set options(value: Partial<GiftAwaySummaryOptions>) {
    this.extra = value;
    this.rebuildSoon();
  }
  get away(): GiftAwaySummary | null {
    return this.instance;
  }

  check(): Promise<void> {
    return this.instance?.check() ?? Promise.resolve();
  }
  ack(): Promise<void> {
    return this.instance?.ack() ?? Promise.resolve();
  }
  dismiss(): void {
    this.instance?.dismiss();
  }

  connectedCallback(): void {
    ensureHostStyle(this.ownerDocument);
    this.rebuildSoon();
  }
  disconnectedCallback(): void {
    this.generation++;
    this.teardown();
  }
  attributeChangedCallback(): void {
    this.rebuildSoon();
  }

  private rebuildSoon(): void {
    if (this.queued) return;
    this.queued = true;
    const generation = this.generation;
    queueMicrotask(() => {
      this.queued = false;
      if (generation !== this.generation) return;
      this.rebuild();
    });
  }

  private teardown(): void {
    this.instance?.destroy();
    this.instance = null;
  }

  private rebuild(): void {
    this.teardown();
    const client = this.clientValue;
    if (!this.isConnected || !client) return;
    const selector = text(this, "effects");
    this.instance = new GiftAwaySummary(this, {
      ...this.extra,
      ...defined({
        autoCheck: flag(this, "auto-check"),
        ackOn: oneOf(this, "ack-on", ACK_ON),
        minGifts: number(this, "min-gifts"),
        maxEffects: number(this, "max-effects"),
        budgetMs: number(this, "budget-ms"),
        quality: oneOf<EffectQuality>(this, "quality", ["high", "low"]),
        reducedMotion: flag(this, "reduced-motion"),
        focusOnShow: flag(this, "focus-on-show"),
        resolveUsers: this.resolveValue ?? this.extra.resolveUsers,
        theme: this.themeValue ?? this.extra.theme,
        labels: this.labelsValue ?? this.extra.labels,
      }),
      client,
      effects: () => {
        if (this.playerValue) return this.playerValue;
        if (selector === "none") return null;
        return this.findLayer(selector)?.layer ?? null;
      },
      onShow: (summary) => {
        this.extra.onShow?.(summary);
        emit(this, "gift-away-show", summary);
      },
      onDone: () => {
        this.extra.onDone?.();
        emit(this, "gift-away-done", null);
      },
      onError: (error) => {
        this.extra.onError?.(error);
        emit(this, "gift-error", error);
      },
    });
  }

  private findLayer(selector: string | undefined): GiftEffectLayerElement | null {
    const root = this.getRootNode() as Document | ShadowRoot;
    const doc = this.ownerDocument;
    const query = selector ?? "gift-effect-layer";
    try {
      const found = (root.querySelector?.(query) ??
        doc.querySelector(query)) as GiftEffectLayerElement | null;
      return found && "layer" in found ? found : null;
    } catch {
      return null; // an invalid selector must not break the page
    }
  }
}

// ---------------------------------------------------------------------------------------------

const BOARDS = ["senders", "receivers"] as const;
const PERIODS = ["day", "week", "month", "all"] as const;
const METRICS = ["units", "gifts"] as const;

/**
 * `<gift-leaderboard>`: top senders or receivers with period tabs. Stays empty until it is on the
 * page and has a `client`. A change of an attribute rebuilds the board (several at once: once).
 *
 * Attributes: `board` (`senders` | `receivers`), `periods` (comma list: `day,week,all`),
 * `initial-period`, `metric` (`units` | `gifts`), `metric-toggle`, `limit`, `highlight-user`,
 * `refresh-interval-ms`, `coin-name`, `pressable` (rows become buttons and fire `gift-user-press`).
 * Properties: `client` (required), `resolveUsers`, `theme`, `labels`, `options` (what attributes
 * cannot say), `leaderboard`. Method: `refresh()`. Events (they bubble): `gift-user-press`
 * (`detail`: the user id), `gift-error`.
 */
export class GiftLeaderboardElement extends Base {
  static readonly observedAttributes = [
    "board",
    "periods",
    "initial-period",
    "metric",
    "metric-toggle",
    "limit",
    "highlight-user",
    "refresh-interval-ms",
    "coin-name",
    "pressable",
  ];

  private instance: GiftLeaderboard | null = null;
  private clientValue: GiftingClient | null = null;
  private resolveValue: ResolveUsers | undefined;
  private themeValue: Partial<GiftTheme> | undefined;
  private labelsValue: GiftLabelsInput | undefined;
  private extra: Partial<GiftLeaderboardOptions> = {};
  private queued = false;
  private generation = 0;

  get client(): GiftingClient | null {
    return this.clientValue;
  }
  set client(value: GiftingClient | null) {
    this.clientValue = value;
    this.rebuildSoon();
  }
  get resolveUsers(): ResolveUsers | undefined {
    return this.resolveValue;
  }
  set resolveUsers(value: ResolveUsers | undefined) {
    this.resolveValue = value;
    this.instance?.update({ resolveUsers: value });
  }
  get theme(): Partial<GiftTheme> | undefined {
    return this.themeValue;
  }
  set theme(value: Partial<GiftTheme> | undefined) {
    this.themeValue = value;
    this.instance?.update({ theme: value });
  }
  get labels(): GiftLabelsInput | undefined {
    return this.labelsValue;
  }
  set labels(value: GiftLabelsInput | undefined) {
    this.labelsValue = value;
    this.instance?.update({ labels: value });
  }
  get options(): Partial<GiftLeaderboardOptions> {
    return this.extra;
  }
  set options(value: Partial<GiftLeaderboardOptions>) {
    this.extra = value;
    this.rebuildSoon();
  }
  get leaderboard(): GiftLeaderboard | null {
    return this.instance;
  }

  refresh(): void {
    this.instance?.refresh();
  }

  connectedCallback(): void {
    ensureHostStyle(this.ownerDocument);
    this.rebuildSoon();
  }
  disconnectedCallback(): void {
    this.generation++;
    this.teardown();
  }
  attributeChangedCallback(): void {
    this.rebuildSoon();
  }

  private rebuildSoon(): void {
    if (this.queued) return;
    this.queued = true;
    const generation = this.generation;
    queueMicrotask(() => {
      this.queued = false;
      if (generation !== this.generation) return;
      this.rebuild();
    });
  }

  private teardown(): void {
    this.instance?.destroy();
    this.instance = null;
  }

  private rebuild(): void {
    this.teardown();
    const client = this.clientValue;
    if (!this.isConnected || !client) return;
    const periods = this.getAttribute("periods")
      ?.split(",")
      .map((p) => p.trim())
      .filter((p): p is LeaderboardPeriod => (PERIODS as readonly string[]).includes(p));
    const pressable = flag(this, "pressable");
    this.instance = new GiftLeaderboard(this, {
      ...this.extra,
      ...defined({
        board: oneOf(this, "board", BOARDS),
        periods: periods?.length ? periods : undefined,
        initialPeriod: oneOf(this, "initial-period", PERIODS),
        metric: oneOf(this, "metric", METRICS),
        metricToggle: flag(this, "metric-toggle"),
        limit: number(this, "limit"),
        highlightUser: text(this, "highlight-user"),
        refreshIntervalMs: number(this, "refresh-interval-ms"),
        coinName: text(this, "coin-name"),
        resolveUsers: this.resolveValue ?? this.extra.resolveUsers,
        theme: this.themeValue ?? this.extra.theme,
        labels: this.labelsValue ?? this.extra.labels,
      }),
      client,
      onPressUser:
        pressable || this.extra.onPressUser
          ? (id) => {
              this.extra.onPressUser?.(id);
              emit(this, "gift-user-press", id);
            }
          : undefined,
      onError: (error) => {
        this.extra.onError?.(error);
        emit(this, "gift-error", error);
      },
    });
  }
}

/**
 * `<gift-battle-bar>`: the score bar of a versus round (SPEC 18.6). Give it the room you joined
 * (`el.room = roomEl.handle`) and it follows the battle by itself; it stays hidden while the room
 * has no round with two sides.
 *
 * Attributes: `reduced-motion` (`true` | `false`; default follows the system), `tick-ms`,
 * `side-colors` (two colours, `"#6d5cf0,#ffd27a"`; default: the theme accent and coin colour).
 * Properties: `room` (a `RoomHandle`), `view` (a `BattleView`, when you drive it yourself),
 * `resolveUsers`, `theme`, `labels`, `options` (what attributes cannot say), `bar`.
 */
export class GiftBattleBarElement extends Base {
  static readonly observedAttributes = ["reduced-motion", "tick-ms", "side-colors"];

  private instance: GiftBattleBar | null = null;
  private extra: Partial<GiftBattleBarOptions> = {};
  private roomValue: GiftBattleBarOptions["room"];
  private viewValue: BattleView | null = null;
  private resolveValue: ResolveUsers | undefined;
  private themeValue: Partial<GiftTheme> | undefined;
  private labelsValue: BattleBarLabelsInput | undefined;

  get bar(): GiftBattleBar | null {
    return this.instance;
  }
  get room(): GiftBattleBarOptions["room"] {
    return this.roomValue;
  }
  set room(value: GiftBattleBarOptions["room"]) {
    this.roomValue = value;
    this.instance?.update({ room: value });
  }
  get view(): BattleView | null {
    return this.viewValue;
  }
  set view(value: BattleView | null) {
    this.viewValue = value;
    this.instance?.setView(value);
  }
  get resolveUsers(): ResolveUsers | undefined {
    return this.resolveValue;
  }
  set resolveUsers(value: ResolveUsers | undefined) {
    this.resolveValue = value;
    this.instance?.update({ resolveUsers: value });
  }
  get theme(): Partial<GiftTheme> | undefined {
    return this.themeValue;
  }
  set theme(value: Partial<GiftTheme> | undefined) {
    this.themeValue = value;
    this.instance?.update({ theme: value });
  }
  get labels(): BattleBarLabelsInput | undefined {
    return this.labelsValue;
  }
  set labels(value: BattleBarLabelsInput | undefined) {
    this.labelsValue = value;
    this.instance?.update({ labels: value });
  }
  get options(): Partial<GiftBattleBarOptions> {
    return this.extra;
  }
  set options(value: Partial<GiftBattleBarOptions>) {
    this.extra = value;
    this.instance?.update(this.settings());
  }

  connectedCallback(): void {
    if (this.instance) return;
    ensureHostStyle(this.ownerDocument);
    this.instance = new GiftBattleBar(this, {
      ...this.settings(),
      onError: (error) => emit(this, "gift-error", error),
    });
    if (this.viewValue) this.instance.setView(this.viewValue);
  }
  disconnectedCallback(): void {
    this.instance?.destroy();
    this.instance = null;
  }
  attributeChangedCallback(): void {
    this.instance?.update(this.settings());
  }

  private settings(): Partial<GiftBattleBarOptions> {
    const colors = this.getAttribute("side-colors")
      ?.split(",")
      .map((c) => c.trim())
      .filter(Boolean);
    return {
      ...this.extra,
      ...defined({
        room: this.roomValue,
        resolveUsers: this.resolveValue,
        theme: this.themeValue,
        labels: this.labelsValue,
        reducedMotion: flag(this, "reduced-motion"),
        tickMs: number(this, "tick-ms"),
        sideColors:
          colors?.length === 2 ? ([colors[0]!, colors[1]!] as [string, string]) : undefined,
      }),
    };
  }
}

/**
 * `<gift-room room="live-123">`: joins a gift room (SPEC 17-18) and plays what arrives. It has no
 * picture of its own (`display: none`); put it anywhere. Connects when added, leaves when removed,
 * and changes of `room` rejoin.
 *
 * Attributes: `room` (required), `effects` (a CSS selector of a `<gift-effect-layer>`; default the
 * first one in the document), `min-tier` (`small` | `medium` | `large`), `skip-own` (default true;
 * `skip-own="false"` plays your own gifts again), `max-replay-age-ms`, `pause-when-hidden`, `url`,
 * `allow-insecure` (a plain `ws://` url to any host). Changing `room`, `url` or `allow-insecure`
 * joins again; every other attribute and the `getToken`, `client`, `resolveName` and `thresholds`
 * properties change in place, on the open socket.
 * Properties: `getToken` (required, the function you give `createGiftingClient`), `client` (to
 * prefetch the catalog), `resolveName`, `thresholds`, `effectPlayer` (your own player instead of
 * `effects`), `handle` (the `RoomHandle`, null until it has joined). Events (they bubble):
 * `gift-room-event` (`detail`: the gift event), `gift-room-viewers` (`detail`: the count),
 * `gift-room-gap`, `gift-room-state` (`detail`: the `RoomState`).
 */
export class GiftRoomElement extends Base {
  static readonly observedAttributes = [
    "room",
    "effects",
    "min-tier",
    "skip-own",
    "max-replay-age-ms",
    "pause-when-hidden",
    "url",
    "allow-insecure",
  ];

  private instance: RoomHandle | null = null;
  private getTokenValue: JoinRoomOptions["getToken"] | null = null;
  private clientValue: JoinRoomOptions["client"];
  private resolveNameValue: JoinRoomOptions["resolveName"];
  private thresholdsValue: JoinRoomOptions["thresholds"];
  private playerValue: RoomEffectPlayer | undefined;
  private queued = false;
  private generation = 0;

  get getToken(): JoinRoomOptions["getToken"] | null {
    return this.getTokenValue;
  }
  set getToken(value: JoinRoomOptions["getToken"] | null) {
    this.getTokenValue = value;
    // A joined room keeps its socket and uses the new function at its next token request.
    if (this.instance && value) this.instance.setOptions({ getToken: value });
    else this.rebuildSoon();
  }
  get client(): JoinRoomOptions["client"] {
    return this.clientValue;
  }
  set client(value: JoinRoomOptions["client"]) {
    this.clientValue = value;
    this.update();
  }
  get resolveName(): JoinRoomOptions["resolveName"] {
    return this.resolveNameValue;
  }
  set resolveName(value: JoinRoomOptions["resolveName"]) {
    this.resolveNameValue = value;
    this.update();
  }
  get thresholds(): JoinRoomOptions["thresholds"] {
    return this.thresholdsValue;
  }
  set thresholds(value: JoinRoomOptions["thresholds"]) {
    this.thresholdsValue = value;
    this.update();
  }
  get effectPlayer(): RoomEffectPlayer | undefined {
    return this.playerValue;
  }
  set effectPlayer(value: RoomEffectPlayer | undefined) {
    this.playerValue = value;
  }
  get handle(): RoomHandle | null {
    return this.instance;
  }

  connectedCallback(): void {
    this.style.display = "none";
    this.rebuildSoon();
  }
  disconnectedCallback(): void {
    this.generation++;
    this.teardown();
  }
  attributeChangedCallback(name: string): void {
    // A new room, address or security setting is a new socket. Everything else (filters, effects,
    // pause-when-hidden) changes in place: the viewer stays connected and loses no gift.
    if (name === "room" || name === "url" || name === "allow-insecure") this.rebuildSoon();
    else this.update();
  }

  /** The settings that do not need a new socket, from the attributes and properties. */
  private liveOptions(): RoomLiveOptions {
    return {
      minTier: oneOf(this, "min-tier", ["small", "medium", "large"] as const),
      skipOwn: flag(this, "skip-own"),
      maxReplayAgeMs: number(this, "max-replay-age-ms"),
      pauseWhenHidden: flag(this, "pause-when-hidden"),
      client: this.clientValue,
      resolveName: this.resolveNameValue,
      thresholds: this.thresholdsValue,
    };
  }

  /** Applies a changed setting to the joined room, or joins when there is none yet. */
  private update(): void {
    if (this.instance) this.instance.setOptions(this.liveOptions());
    else this.rebuildSoon();
  }

  private rebuildSoon(): void {
    if (this.queued) return;
    this.queued = true;
    const generation = this.generation;
    queueMicrotask(() => {
      this.queued = false;
      if (generation !== this.generation) return;
      this.rebuild();
    });
  }

  private teardown(): void {
    this.instance?.leave();
    this.instance = null;
  }

  /** The player: your own, else the layer the `effects` selector names, else the first one. */
  private player(): RoomEffectPlayer | null {
    if (this.playerValue) return this.playerValue;
    const selector = this.getAttribute("effects");
    let target: Element | null;
    try {
      target = this.ownerDocument.querySelector(selector || "gift-effect-layer");
    } catch {
      target = null; // a bad selector plays nothing; the events still fire
    }
    const player = target as unknown as Partial<RoomEffectPlayer> | null;
    return typeof player?.play === "function" ? (player as RoomEffectPlayer) : null;
  }

  private rebuild(): void {
    this.teardown();
    const room = this.getAttribute("room");
    const getToken = this.getTokenValue;
    if (!this.isConnected || !room || !getToken) return;
    this.instance = joinRoom({
      ...defined({
        ...this.liveOptions(),
        url: text(this, "url"),
        allowInsecure: flag(this, "allow-insecure"),
      }),
      room,
      getToken,
      effects: () => this.player(),
      onEvent: (event) => emit(this, "gift-room-event", event),
      onViewers: (n) => emit(this, "gift-room-viewers", n),
      onGap: () => emit(this, "gift-room-gap", null),
      onState: (state) => emit(this, "gift-room-state", state),
    });
  }
}

/** Registers all the elements. Safe to call twice, and a no-op where there are no custom elements. */
export function defineGiftElements(registry?: CustomElementRegistry): void {
  const reg = registry ?? (typeof customElements === "undefined" ? undefined : customElements);
  if (!reg) return;
  if (!reg.get("gift-effect-layer")) reg.define("gift-effect-layer", GiftEffectLayerElement);
  if (!reg.get("gift-tray")) reg.define("gift-tray", GiftTrayElement);
  if (!reg.get("gift-wall")) reg.define("gift-wall", GiftWallElement);
  if (!reg.get("gift-away-summary")) reg.define("gift-away-summary", GiftAwaySummaryElement);
  if (!reg.get("gift-leaderboard")) reg.define("gift-leaderboard", GiftLeaderboardElement);
  if (!reg.get("gift-battle-bar")) reg.define("gift-battle-bar", GiftBattleBarElement);
  if (!reg.get("gift-room")) reg.define("gift-room", GiftRoomElement);
}

declare global {
  interface HTMLElementTagNameMap {
    "gift-effect-layer": GiftEffectLayerElement;
    "gift-tray": GiftTrayElement;
    "gift-wall": GiftWallElement;
    "gift-away-summary": GiftAwaySummaryElement;
    "gift-leaderboard": GiftLeaderboardElement;
    "gift-battle-bar": GiftBattleBarElement;
    "gift-room": GiftRoomElement;
  }
}
