import {
  type Gift,
  type InputSwapEvent,
  KEYBOARD_MIN_HEIGHT,
  SEND_TO_LABEL,
  type TrayReceiver,
  battleSidePalette,
  resolveReceiver,
  revealOffset,
  PLACEMENT_COLUMNS,
  inputSwapStep,
  keyboardPlaceSnap,
  type ScrimTap,
  type SheetLayout,
  type SheetSnap,
  TrayOpenState,
  type TrayPlacement,
  type TrayPlacementOption,
  type TraySheetState,
  resolveTrayPlacement,
  scrimFadeMs,
  scrimTapOutcome,
  scrimTakesTouches,
  scrimVisible,
  sendButtonState,
} from "../core";
import { outCubic } from "./anim";
import { avatar } from "./ui";
import { prefetch, setPicture } from "./images";
import { PopoverView } from "./popover";
import { SheetView } from "./sheet";
import { acquireStyles, releaseStyles } from "./styles";
import { type GiftTheme, applyTheme } from "./theme";

export interface GiftTrayOptions {
  gifts?: Gift[];
  balance?: number;
  /** Called when the person presses Send. Press again for a combo. */
  onSend?: (gift: Gift) => void | Promise<void>;
  /** Shows "+ Coins" and, when the balance is too low, a "Get coins" button. Open your store here. */
  onTopUp?: () => void;
  title?: string;
  /** Name of your currency, used in labels for screen readers. Default "coins". */
  coinName?: string;
  sendLabel?: string;
  notEnoughLabel?: string;
  getCoinsLabel?: string;
  /** Cells per row. Default: 4 in the sheet, 5 in the popover, as many as fit inline (tiles of 84 px or more). */
  columns?: number;
  /** Fixed tray only (`sheet: false`): the grid scrolls when taller than this, in px. Default 230. */
  gridMaxHeight?: number;
  /**
   * Default `true`: the tray is a bottom sheet the person drags between peek, default and
   * expanded. It is absolutely positioned at the bottom of the container, so the container should
   * be the screen area (a `position: static` container is made `relative` until `destroy()`).
   * `false`: the old fixed-height tray in the normal page flow. Read once, at construction.
   */
  sheet?: boolean;
  /**
   * Where the tray sits (spec 9.3, web only; read once; ignored with `sheet: false`). `"sheet"`:
   * the bottom sheet. `"popover"`: a 380 px panel next to `anchor`, opened and closed by it (no
   * `anchor`: inline). `"inline"`: fills the container. `"auto"` (default): from the container's
   * width, now and on every resize: below 600 px the sheet, else a popover with an `anchor`, else
   * inline.
   */
  placement?: TrayPlacementOption;
  /** Popover: the app's gift button. Its clicks open and close the tray. Read once. */
  anchor?: HTMLElement | null;
  /**
   * The app's own text field in its message bar (spec 20, read once). The tray then takes the
   * keyboard's place: the `anchor` (your `GiftButton`) closes the keyboard and opens the tray, a
   * focus on the field closes the tray, the button again brings the keyboard back. The sheet
   * starts closed (unless `open` is given) and opens about as tall as the keyboard was.
   */
  input?: HTMLInputElement | HTMLTextAreaElement | null;
  /**
   * It opened or closed. Popover: Escape, a click outside, the anchor, `open()`/`close()`.
   * Sheet: `open()`, `close()`, `toggle()` and a dismissed scrim tap (spec 9.4).
   */
  onOpenChange?: (open: boolean) => void;
  /**
   * Sheet only: the sheet starts open (default) or closed (`false`: hidden until `open()` or
   * `toggle()`). Read once. The popover always starts closed, the inline tray is always shown.
   */
  open?: boolean;
  /**
   * Sheet only (spec 9.4): draw a dim behind the sheet over the whole container. It fades in over
   * 200 ms (at once with reduced motion) when the sheet is placed, is hidden while the sheet is at
   * peek (the page stays in sight) and takes the touches above the sheet while it shows. Default
   * `false`: no dim, touches above the sheet reach the page.
   */
  scrim?: boolean;
  /**
   * What a tap on the scrim does. `"lower"` (default): lowers the sheet to peek (the dim goes
   * away), and from peek dismisses. `"dismiss"`: dismisses from every state. A dismissal closes
   * the tray (`onOpenChange(false)`) and calls `onDismiss`.
   */
  scrimTap?: ScrimTap;
  /** Sheet only: a scrim tap asked to close. The tray is already closed when this runs. */
  onDismiss?: () => void;
  /** The resolved placement changed (`auto` on a resize). Not called for the first one. */
  onPlacementChange?: (placement: TrayPlacement) => void;
  /** Sheet only: the state it opens in. Default `"default"`. */
  initialSnap?: SheetSnap;
  /** Sheet only: snap heights as fractions of the container height (0 = fit the content). */
  snaps?: SheetLayout["snaps"];
  /** Sheet only: the settled state changed (after a release, tap, arrow key or `snapTo`). */
  onSnapChange?: (snap: SheetSnap) => void;
  /**
   * Picking a gift in the grid makes the tray small (the picked gift and Send), so what is behind
   * it stays in sight, for example a live stream. The sheet lowers to peek (the handle brings the
   * grid back). The popover and the inline tray hide the grid (the "All gifts" button brings it
   * back); a press outside the popover still closes it. Default `false`.
   */
  collapseOnSelect?: boolean;
  /**
   * Sheet only: the sheet's top edge, in px from the container's bottom, whenever it moves (live
   * during a drag, the target when it snaps). Use it to keep the notice above the tray:
   * `effects.setOptions({ noticeBottom: px + 16 })`. When the placement leaves the sheet it
   * reports 0 once; the popover and the inline tray report nothing.
   */
  onInsetChange?: (px: number) => void;
  /**
   * A battle (spec 21): the sides the viewer can send to. Two or more show a "Send to" row under
   * the header; the send goes to the picked side (default: the side this tray last sent to, else
   * the first). Without it the tray sends to `receiver` as before.
   */
  receivers?: TrayReceiver[];
  /** The receiver without `receivers`, and the fallback when it is one of them. */
  receiver?: string;
  /** The picked side changed (a tap, `selectReceiver`, a new list). */
  onReceiverChange?: (id: string | null) => void;
  /** Default "Send to". */
  sendToLabel?: string;
  /** Id of the gift selected first. Default: the first gift. */
  defaultSelectedId?: string;
  /** Turn off sending, for example while a request is running. */
  disabled?: boolean;
  /**
   * Shows a "Test mode" badge next to the title. `createGiftTray` sets it when the server says
   * the token was made with a test key, so end users of an app on a test key can see it.
   */
  testMode?: boolean;
  /** Default "Test mode". */
  testModeLabel?: string;
  theme?: Partial<GiftTheme>;
  /** Starts downloading a picture. Default: a hidden `Image`. */
  prefetch?: (url: string) => void;
}

const COUNT_UP_MS = 600;
const fmt = (n: number): string => n.toLocaleString("en-US");

/**
 * A tray of gifts with the balance and a Send button. Presentational: you pass gifts, balance and
 * callbacks (`createGiftTray` wires them to the core controller). Call `update` when they change.
 * Keyboard: Tab to the grid, arrow keys select, Enter or Space presses a button.
 */
export class GiftTray {
  /** The tray's root element: a child of the container (of `document.body` as a popover). */
  readonly element: HTMLElement;
  private o: Required<Pick<GiftTrayOptions, "gifts" | "balance">> & GiftTrayOptions;
  private readonly doc: Document;
  private readonly container: HTMLElement;
  private readonly title: HTMLElement;
  private readonly testBadge: HTMLElement;
  private readonly balanceNum: HTMLElement;
  private readonly balanceLabel: HTMLElement;
  private readonly topUp: HTMLButtonElement;
  private readonly grid: HTMLElement;
  /** The "Send to" row of a battle (spec 21.3). */
  private readonly pickRow: HTMLElement;
  private pickedId: string | null = null;
  private lastSentTo: string | null = null;
  /** The receiver last reported to `onReceiverChange` (undefined: nothing reported yet). */
  private shownReceiver: string | null | undefined = undefined;
  private builtReceivers: { list: TrayReceiver[]; theme: unknown; label: string } | null = null;
  private readonly send: HTMLButtonElement;
  private readonly picked: HTMLElement | null = null;
  /** Popover and inline, `collapseOnSelect`: shows the grid again after a pick made the tray small. */
  private readonly more: HTMLButtonElement | null = null;
  private compact = false;
  /** Placed trays (every placement): body (handle, header, grid) and footer (picked gift, Send). */
  private readonly parts: {
    body: HTMLElement;
    handle: HTMLButtonElement;
    head: HTMLElement;
    footer: HTMLElement;
  } | null = null;
  private readonly anchor: HTMLElement | null;
  private readonly input: HTMLInputElement | HTMLTextAreaElement | null;
  /** The bound field's listeners and the keyboard watch (spec 20). */
  private readonly inputListeners = new AbortController();
  /** The last keyboard height seen (0: none yet). */
  private keyboard = 0;
  private savedExpanded: string | null = null;
  private placement: TrayPlacement | null = null;
  private sheet: SheetView | null = null;
  private popover: PopoverView | null = null;
  private scrimEl: HTMLElement | null = null;
  private scrimShown = false;
  private readonly openState: TrayOpenState;
  private readonly motion: MediaQueryList | null;
  private resizeObserver: ResizeObserver | null = null;
  private warmup: HTMLImageElement | null = null;
  private selectedId: string | undefined;
  private builtFor: { gifts: Gift[]; columns: number; coinName: string } | null = null;
  private shown: number;
  private target: number;
  private raf = 0;
  private destroyed = false;
  private bigPicture: string | null | undefined;

  constructor(container: HTMLElement, options: GiftTrayOptions = {}) {
    this.doc = container.ownerDocument;
    this.container = container;
    this.anchor = options.anchor ?? null;
    this.input = options.input ?? null;
    this.savedExpanded = this.anchor?.getAttribute("aria-expanded") ?? null;
    this.motion = this.doc.defaultView?.matchMedia?.("(prefers-reduced-motion: reduce)") ?? null;
    this.openState = new TrayOpenState({
      // A bound text field: the tray waits for the gift button (spec 20.3).
      open: options.open ?? (this.input ? false : undefined),
      onChange: (open) => {
        this.sheet?.setOpen(open);
        this.paintScrim();
        this.paintExpanded();
        // Opened again: the picked side in sight (the row may have been measured while hidden).
        if (open) requestAnimationFrame(() => this.revealPicked());
        this.o.onOpenChange?.(open);
      },
    });
    this.o = { ...options, gifts: options.gifts ?? [], balance: options.balance ?? 0 };
    this.selectedId = options.defaultSelectedId ?? this.o.gifts[0]?.id;
    this.shown = this.target = this.o.balance;
    acquireStyles(this.doc);

    const el = (tag: string, cls: string, parent?: HTMLElement) => {
      const e = this.doc.createElement(tag);
      e.className = cls;
      parent?.appendChild(e);
      return e;
    };
    const placed = options.sheet ?? true;
    this.element = el("section", "gs-tray");
    this.element.setAttribute("data-gs-tray", "");
    const body = placed ? el("div", "", this.element) : this.element;
    let handle: HTMLButtonElement | null = null;
    if (placed) {
      handle = el("button", "gs-handle", body) as HTMLButtonElement;
      handle.type = "button";
      handle.setAttribute("data-gs-handle", "");
      handle.setAttribute("aria-label", "Gift tray");
      handle.setAttribute("aria-keyshortcuts", "ArrowUp ArrowDown");
      el("span", "gs-handle-pill", handle).setAttribute("aria-hidden", "true");
    }
    const head = el("div", "gs-head", body);
    this.title = el("h2", "gs-title", head);
    this.testBadge = el("span", "gs-test-badge", head);
    this.testBadge.setAttribute("data-gs-test-mode", "");
    const balance = el("div", "gs-balance", head);
    balance.setAttribute("data-gs-balance", "");
    balance.setAttribute("role", "status");
    balance.setAttribute("aria-live", "polite");
    el("span", "gs-dot", balance).setAttribute("aria-hidden", "true");
    this.balanceNum = el("span", "", balance);
    this.balanceNum.setAttribute("aria-hidden", "true");
    // Screen readers get the target value at once, not the numbers counting up.
    this.balanceLabel = el("span", "gs-sr", balance);
    this.topUp = el("button", "gs-topup", head) as HTMLButtonElement;
    this.topUp.type = "button";
    this.topUp.textContent = "+ Coins";
    this.topUp.addEventListener("click", () => this.o.onTopUp?.());
    this.pickRow = el("div", "gs-receivers", body);
    this.pickRow.setAttribute("role", "radiogroup");
    this.pickRow.setAttribute("data-gs-receivers", "");
    this.pickRow.hidden = true;
    this.pickRow.addEventListener("keydown", (e) => this.onPickKey(e));
    this.grid = el("div", "gs-grid", body);
    this.grid.setAttribute("role", "radiogroup");
    this.grid.addEventListener("keydown", (e) => this.onKey(e));
    const footer = placed ? el("div", "gs-footer", this.element) : this.element;
    if (placed) {
      footer.setAttribute("data-gs-footer", "");
      this.more = el("button", "gs-more", footer) as HTMLButtonElement;
      this.more.type = "button";
      this.more.hidden = true;
      this.more.setAttribute("data-gs-more", "");
      this.more.setAttribute("aria-expanded", "false");
      this.more.textContent = "All gifts";
      this.more.addEventListener("click", () => {
        this.setCompact(false);
        this.grid.querySelector<HTMLElement>('[tabindex="0"]')?.focus();
      });
      // The selected gift stays in sight in every state, also in peek where the grid is hidden.
      this.picked = el("div", "gs-picked", footer);
      this.picked.setAttribute("data-gs-picked", "");
      this.picked.setAttribute("aria-hidden", "true");
    }
    this.send = el("button", "gs-send", footer) as HTMLButtonElement;
    this.send.type = "button";
    this.send.setAttribute("data-gs-send", "");
    this.send.addEventListener("click", () => this.press());
    container.appendChild(this.element);

    if (!placed || !handle) {
      this.render();
      return;
    }
    this.parts = { body, handle, head, footer };
    this.placement = this.resolve();
    this.render();
    this.mount();
    this.bindInput();
    if ((options.placement ?? "auto") === "auto" || !isPlacement(options.placement)) {
      const RO = this.doc.defaultView?.ResizeObserver;
      this.resizeObserver = RO ? new RO(() => this.checkPlacement()) : null;
      this.resizeObserver?.observe(container);
    }
  }

  /** The placement in use, or `null` for the fixed tray (`sheet: false`). */
  getPlacement(): TrayPlacement | null {
    return this.placement;
  }

  /** Popover: open it (focus moves into it). Sheet: show it again at `initialSnap`. Inline: nothing. */
  open(): void {
    // The keyboard and the tray are never up together (spec 20.3).
    if (this.input && !this.isOpen() && this.swaps()) this.input.blur();
    this.openNow();
  }

  /** Popover: close it (focus goes back to the anchor when it was inside). Sheet: hide it. */
  close(): void {
    if (this.popover) this.popover.close();
    else if (this.sheet) this.openState.close();
  }

  /**
   * Open if closed, close if open: the host's Gift button is `tray.toggle()`. With a bound text
   * field it is the keyboard swap (spec 20.2): closing it puts the focus back on the field.
   */
  toggle(): void {
    if (this.input && this.swaps()) this.swap("button");
    else if (this.popover) this.popover.toggle();
    else if (this.sheet) this.openState.toggle();
  }

  /** A text field is bound (the `input` option, spec 20). */
  hasInput(): boolean {
    return this.input !== null;
  }

  private openNow(): void {
    if (this.popover) this.popover.open();
    else if (this.sheet) this.openState.open();
  }

  /** The placement takes part in the keyboard swap: the sheet and the popover (not inline). */
  private swaps(): boolean {
    return !!this.sheet || !!this.popover;
  }

  /** One step of the keyboard swap (spec 20.2): blur before open, close before focus. */
  private swap(event: InputSwapEvent): void {
    const input = this.input;
    if (!input || this.destroyed || !this.swaps()) return;
    const step = inputSwapStep(this.isOpen(), event);
    if (step.input === "blur") input.blur();
    if (step.tray === "open") this.openNow();
    else if (step.tray === "close") this.close();
    if (step.input === "focus" && input.isConnected) input.focus();
  }

  /** The bound field's focus, the anchor's clicks and the keyboard's height (spec 20.3). */
  private bindInput(): void {
    const input = this.input;
    if (!input) return;
    const signal = this.inputListeners.signal;
    input.addEventListener("focus", () => this.swap("inputFocus"), { signal });
    this.anchor?.addEventListener("click", () => this.toggle(), { signal });
    this.paintExpanded();
    const win = this.doc.defaultView;
    const vv = win?.visualViewport;
    const vk = (win?.navigator as { virtualKeyboard?: VirtualKeyboardLike } | undefined)
      ?.virtualKeyboard;
    const note = (): void => {
      if (!win) return;
      const fromViewport = vv ? win.innerHeight - vv.height - vv.offsetTop : 0;
      const k = Math.max(fromViewport, vk?.boundingRect?.height ?? 0);
      if (k >= KEYBOARD_MIN_HEIGHT) this.keyboard = k;
    };
    vv?.addEventListener("resize", note, { signal });
    vk?.addEventListener?.("geometrychange", note, { signal });
  }

  /** Sheet with a bound field: the anchor says whether the tray is open (the popover does its own). */
  private paintExpanded(): void {
    if (!this.input || !this.anchor || this.popover || this.destroyed) return;
    this.anchor.setAttribute("aria-expanded", String(!!this.sheet && this.openState.isOpen()));
  }

  /** Popover and sheet: whether it is open. The inline tray is always shown: `true`. */
  isOpen(): boolean {
    if (this.popover) return this.popover.isOpen();
    return this.sheet ? this.openState.isOpen() : true;
  }

  /** Sheet only: the current snap state, offset and visible height. `null` otherwise. */
  getSheetState(): TraySheetState | null {
    return this.sheet?.getState() ?? null;
  }

  /** Sheet only: move to a state (animated unless reduced motion). */
  snapTo(snap: SheetSnap): void {
    this.sheet?.controller.snapTo(snap);
  }

  /** Measure again (the tray does it by itself on resize and when the gifts change). */
  measure(): void {
    this.sheet?.measure();
    this.popover?.measure();
  }

  /** Change anything: gifts, balance, labels, callbacks, theme. The balance counts to its new value. */
  update(patch: GiftTrayOptions): void {
    this.o = { ...this.o, ...patch };
    if (patch.theme) applyTheme(this.element, patch.theme);
    this.render();
    if (patch.snaps !== undefined) this.sheet?.setSnaps(patch.snaps);
  }

  /** Battle (spec 21): pick the side the next gift goes to. An id not in `receivers` is ignored. */
  selectReceiver(id: string): void {
    if (!this.o.receivers?.some((r) => r.id === id)) return;
    this.pickedId = id;
    this.renderReceivers();
  }

  /** The receiver the next gift goes to: the picked side, else the plain `receiver`. */
  getReceiver(): string | null {
    const ids = (this.o.receivers ?? []).map((r) => r.id);
    return resolveReceiver(ids, {
      selected: this.pickedId,
      last: this.lastSentTo,
      fallback: this.o.receiver,
    });
  }

  /** A send to `receiver` succeeded: it becomes the default side (spec 21.2). */
  noteSent(receiver: string): void {
    this.lastSentTo = receiver;
    this.renderReceivers();
  }

  /** The gift shown as selected, or undefined for an empty tray. */
  getSelected(): Gift | undefined {
    return this.o.gifts.find((g) => g.id === this.selectedId) ?? this.o.gifts[0];
  }

  /** Remove the tray and everything it added to the page. */
  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.inputListeners.abort();
    if (this.input && this.anchor && !this.popover) {
      if (this.savedExpanded === null) this.anchor.removeAttribute("aria-expanded");
      else this.anchor.setAttribute("aria-expanded", this.savedExpanded);
    }
    cancelAnimationFrame(this.raf);
    this.resizeObserver?.disconnect();
    this.sheet?.destroy();
    this.popover?.destroy();
    this.sheet = this.popover = null;
    this.paintScrim();
    this.element.remove();
    releaseStyles();
  }

  private resolve(): TrayPlacement {
    return resolveTrayPlacement({
      placement: this.o.placement,
      containerWidth: this.container.clientWidth,
      hasAnchor: !!this.anchor,
    });
  }

  /** `auto`: the container was resized. */
  private checkPlacement(): void {
    if (this.destroyed) return;
    const next = this.resolve();
    if (next === this.placement) return;
    const was = this.placement;
    this.popover?.close(false);
    this.sheet?.destroy();
    this.popover?.destroy();
    this.sheet = this.popover = null;
    this.paintScrim();
    this.placement = next;
    this.render();
    this.mount();
    if (was === "sheet") this.o.onInsetChange?.(0);
    this.o.onPlacementChange?.(next);
  }

  /** Classes, parent and the view (sheet or popover) for `this.placement`. */
  private mount(): void {
    const parts = this.parts;
    const p = this.placement;
    if (!parts || !p) return;
    const { body, handle, head, footer } = parts;
    this.setCompact(false);
    this.element.className = `gs-tray gs-${p}`;
    this.element.setAttribute("data-gs-placement", p);
    body.className = p === "sheet" ? "gs-sheet-body" : "gs-body";
    body.toggleAttribute("data-gs-sheet-body", p === "sheet");
    handle.hidden = p !== "sheet";
    // A popover lives in the body, so no ancestor's overflow or transform clips or moves it.
    const parent = p === "popover" ? this.doc.body : this.container;
    if (this.element.parentNode !== parent) parent.appendChild(this.element);
    if (p === "sheet") {
      this.sheet = new SheetView(
        { root: this.element, body, handle, head, grid: this.grid, footer },
        {
          container: this.container,
          initialSnap: this.o.initialSnap,
          snaps: this.o.snaps,
          // A bound text field: `default` is the keyboard's place (the host's own snaps win).
          snapsFor: this.input
            ? (containerHeight) => ({
                default: keyboardPlaceSnap({ keyboardHeight: this.keyboard, containerHeight }),
              })
            : undefined,
          columns: () => this.columns(),
          onSnapChange: (snap) => this.o.onSnapChange?.(snap),
          onInsetChange: (px) => this.o.onInsetChange?.(px),
          open: this.openState.isOpen(),
          onPaint: () => this.paintScrim(),
        },
      );
      this.paintScrim();
    } else if (p === "popover" && this.anchor) {
      this.popover = new PopoverView({
        anchor: this.anchor,
        root: this.element,
        grid: this.grid,
        label: () => this.title.textContent ?? "",
        anchorClicks: !this.input,
        onOpenChange: (open) => {
          // Opened again: the whole tray.
          if (!open) this.setCompact(false);
          this.o.onOpenChange?.(open);
        },
      });
    }
    this.paintExpanded();
  }

  /** A tap on the scrim (spec 9.4). */
  private tapScrim(): void {
    const sheet = this.sheet;
    if (!sheet) return;
    const outcome = scrimTapOutcome({
      scrim: !!this.o.scrim,
      scrimTap: this.o.scrimTap,
      open: this.openState.isOpen(),
      snap: sheet.getState().snap,
    });
    if (outcome === "lower") sheet.controller.snapTo("peek");
    else if (outcome === "dismiss") {
      this.openState.close();
      this.o.onDismiss?.();
    }
  }

  /** Creates, shows, hides or removes the scrim to match the sheet (spec 9.4). */
  private paintScrim(): void {
    const sheet = this.sheet;
    if (!sheet || !this.o.scrim) {
      this.scrimEl?.remove();
      this.scrimEl = null;
      this.scrimShown = false;
      return;
    }
    let el = this.scrimEl;
    if (!el) {
      el = this.doc.createElement("div");
      el.className = "gs-scrim";
      el.setAttribute("data-gs-scrim", "");
      el.setAttribute("aria-hidden", "true");
      el.addEventListener("click", () => this.tapScrim());
      this.container.insertBefore(el, this.element);
      this.scrimEl = el;
    }
    const open = this.openState.isOpen();
    const placed = sheet.isPlaced();
    const on = scrimVisible({ scrim: true, open, snap: sheet.getState().snap, placed });
    // Touches are taken in every state, peek included (the dim stays hidden there).
    el.toggleAttribute("data-gs-active", scrimTakesTouches({ scrim: true, open, placed }));
    if (on === this.scrimShown && el.style.transitionDuration) return;
    this.scrimShown = on;
    el.style.transitionDuration = `${scrimFadeMs(this.motion?.matches ?? false)}ms`;
    el.toggleAttribute("data-gs-visible", on);
  }

  /**
   * Popover and inline (`collapseOnSelect`: small (the grid hidden, the picked gift and Send
   * shown) or full. The sheet has peek for this instead.
   */
  private setCompact(on: boolean): void {
    const can = this.placement === "popover" || this.placement === "inline";
    const next = on && can;
    if (next === this.compact) return;
    this.compact = next;
    this.element.toggleAttribute("data-gs-compact", next);
    if (this.more) {
      this.more.hidden = !next;
      this.more.setAttribute("aria-expanded", String(!next));
    }
    this.popover?.measure();
  }

  /** Cells per row for the sheet's measurements and the grid. Inline: 0 = as many as fit. */
  private columns(): number {
    if (this.o.columns) return this.o.columns;
    if (this.placement === "popover") return PLACEMENT_COLUMNS.popover;
    if (this.placement === "inline") return 0;
    return PLACEMENT_COLUMNS.sheet;
  }

  private render(): void {
    const { gifts, balance, coinName = "coins" } = this.o;
    const columns = this.columns();
    applyTheme(this.element, this.o.theme);
    this.title.textContent = this.o.title ?? "Send a gift";
    this.grid.setAttribute("aria-label", this.title.textContent);
    this.testBadge.hidden = !this.o.testMode;
    this.testBadge.textContent = this.o.testModeLabel ?? "Test mode";
    if (this.placement === null) this.grid.style.maxHeight = `${this.o.gridMaxHeight ?? 230}px`;
    if (columns > 0) this.grid.style.setProperty("--gs-columns", String(columns));
    else this.grid.style.removeProperty("--gs-columns");
    this.grid.toggleAttribute("data-gs-fill", columns === 0);
    this.topUp.hidden = !this.o.onTopUp;
    this.topUp.setAttribute("aria-label", `Get more ${coinName}`);

    const built = this.builtFor;
    if (
      !built ||
      built.gifts !== gifts ||
      built.columns !== columns ||
      built.coinName !== coinName
    ) {
      this.builtFor = { gifts, columns, coinName };
      this.buildGrid();
      // Warm up the pictures: small icons for the whole tray.
      for (const g of gifts) if (g.icon_url) (this.o.prefetch ?? prefetch)(g.icon_url);
      // New rows: the snap heights (or the popover's height) change.
      this.sheet?.measure();
      this.popover?.measure();
    }
    this.renderReceivers();
    this.renderSelection();
    this.renderBalance(balance, coinName);
  }

  private buildGrid(): void {
    this.grid.replaceChildren();
    const { coinName = "coins" } = this.o;
    for (const g of this.o.gifts) {
      const cell = this.doc.createElement("button");
      cell.type = "button";
      cell.className = "gs-cell";
      cell.setAttribute("role", "radio");
      cell.setAttribute("data-gs-gift", g.id);
      const label = `${g.name}, ${fmt(g.price)} ${coinName}`;
      cell.setAttribute("aria-label", label);
      // Desktop: the name and price as a tooltip on hover.
      cell.title = label;
      const icon = this.doc.createElement("img");
      icon.className = "gs-icon";
      icon.alt = "";
      icon.draggable = false;
      if (setPicture(icon, g.icon_url)) {
        cell.appendChild(icon);
      } else {
        const empty = this.doc.createElement("div");
        empty.className = "gs-icon gs-icon-empty";
        cell.appendChild(empty);
      }
      const price = this.doc.createElement("div");
      price.className = "gs-price";
      price.innerHTML = '<span class="gs-dot gs-dot-small" aria-hidden="true"></span>';
      price.append(fmt(g.price));
      cell.appendChild(price);
      cell.addEventListener("click", () => {
        this.selectedId = g.id;
        this.renderSelection();
        if (!this.o.collapseOnSelect) return;
        if (this.sheet) this.sheet.controller.snapTo("peek");
        else this.setCompact(true);
      });
      this.grid.appendChild(cell);
    }
  }

  /** Selected cell, send button state and the big picture's warm-up. */
  private renderSelection(): void {
    const selected = this.getSelected();
    for (const cell of this.grid.children) {
      const on = cell.getAttribute("data-gs-gift") === selected?.id;
      cell.setAttribute("aria-checked", String(on));
      // One tab stop for the group: the selected cell (arrow keys move inside).
      cell.setAttribute("tabindex", on ? "0" : "-1");
    }

    const { gifts, balance, disabled = false } = this.o;
    const state = sendButtonState({
      gifts,
      selectedId: this.selectedId,
      balance,
      disabled,
      canTopUp: !!this.o.onTopUp,
    });
    const label = {
      send: this.o.sendLabel ?? "Send",
      getCoins: this.o.getCoinsLabel ?? "Get coins",
      notEnough: this.o.notEnoughLabel ?? "Not enough coins",
    }[state.label];
    this.send.textContent = label;
    this.send.setAttribute("aria-label", selected ? `${label}: ${selected.name}` : label);
    this.send.setAttribute("aria-disabled", String(!state.pressable));
    this.send.setAttribute("data-gs-action", state.action);
    this.send.classList.toggle("gs-coin-state", state.broke && state.pressable);
    this.renderPicked(selected);

    // The big picture is downloaded now and drawn invisibly at the effect's size, so the browser
    // has it decoded when the person presses Send.
    const big = selected?.animation_url ?? selected?.icon_url ?? null;
    if (big !== this.bigPicture) {
      this.bigPicture = big;
      this.warmup?.remove();
      this.warmup = null;
      if (big) {
        (this.o.prefetch ?? prefetch)(big);
        const img = this.doc.createElement("img");
        img.className = "gs-warmup";
        img.setAttribute("data-gs-warmup", "");
        img.alt = "";
        img.setAttribute("aria-hidden", "true");
        setPicture(img, big);
        this.element.prepend(img);
        this.warmup = img;
      }
    }
  }

  /** Footer: the selected gift's icon, name and price. */
  private renderPicked(selected: Gift | undefined): void {
    const box = this.picked;
    if (!box) return;
    const key = selected ? `${selected.id}|${selected.icon_url ?? ""}|${selected.price}` : "";
    if (box.getAttribute("data-gs-picked") === key) return;
    box.setAttribute("data-gs-picked", key);
    box.replaceChildren();
    if (!selected) return;
    const pickedImg = this.doc.createElement("img");
    pickedImg.className = "gs-picked-icon";
    pickedImg.alt = "";
    pickedImg.draggable = false;
    if (setPicture(pickedImg, selected.icon_url)) {
      box.appendChild(pickedImg);
    } else {
      const empty = this.doc.createElement("div");
      empty.className = "gs-picked-icon gs-icon-empty";
      box.appendChild(empty);
    }
    const text = this.doc.createElement("div");
    text.className = "gs-picked-text";
    const name = this.doc.createElement("span");
    name.className = "gs-picked-name";
    name.textContent = selected.name;
    const price = this.doc.createElement("span");
    price.className = "gs-price";
    price.innerHTML = '<span class="gs-dot gs-dot-small" aria-hidden="true"></span>';
    price.append(fmt(selected.price));
    text.append(name, price);
    box.appendChild(text);
  }

  /** The "Send to" row (spec 21.3): only with two or more receivers. */
  private renderReceivers(): void {
    const list = this.o.receivers;
    const row = this.pickRow;
    const many = !!list && list.length >= 2;
    const wasHidden = row.hidden;
    row.hidden = !many;
    const current = this.getReceiver();
    if (list && many) {
      const label = this.o.sendToLabel ?? SEND_TO_LABEL;
      const built = this.builtReceivers;
      if (!built || built.list !== list || built.theme !== this.o.theme || built.label !== label) {
        this.builtReceivers = { list, theme: this.o.theme, label };
        const palette = battleSidePalette(this.o.theme, list.length);
        row.replaceChildren();
        const caption = this.doc.createElement("span");
        caption.className = "gs-receivers-label";
        caption.setAttribute("aria-hidden", "true");
        caption.textContent = label;
        row.appendChild(caption);
        row.setAttribute("aria-label", label);
        list.forEach((r, i) => {
          const b = this.doc.createElement("button");
          b.type = "button";
          b.className = "gs-receiver";
          b.setAttribute("role", "radio");
          b.setAttribute("data-gs-receiver", r.id);
          b.setAttribute("aria-label", r.name);
          b.title = r.name;
          b.style.setProperty("--gs-side", r.color ?? palette[i]!.color);
          b.style.setProperty("--gs-side-text", palette[i]!.text);
          const av = avatar(this.doc, r.name, r.avatarUrl, 30);
          av.classList.add("gs-receiver-avatar");
          const name = this.doc.createElement("span");
          name.className = "gs-receiver-name";
          name.setAttribute("aria-hidden", "true");
          name.textContent = r.name;
          b.append(av, name);
          b.addEventListener("click", () => this.selectReceiver(r.id));
          row.appendChild(b);
        });
      }
      for (const b of row.querySelectorAll<HTMLElement>("[data-gs-receiver]")) {
        const on = b.getAttribute("data-gs-receiver") === current;
        b.setAttribute("aria-checked", String(on));
        b.setAttribute("tabindex", on ? "0" : "-1");
      }
    } else if (row.childElementCount) {
      row.replaceChildren();
      this.builtReceivers = null;
    }
    // The row is part of the block above the grid: the peek height changes with it.
    if (wasHidden !== row.hidden) {
      this.sheet?.measure();
      this.popover?.measure();
    }
    const revealKey = `${current}|${this.builtReceivers ? list?.length : ""}`;
    if (many && revealKey !== this.revealed) {
      this.revealed = revealKey;
      this.revealPicked();
    }
    if (current !== this.shownReceiver) {
      const first = this.shownReceiver === undefined;
      this.shownReceiver = current;
      if (!first) this.o.onReceiverChange?.(current);
    }
  }

  /** What the row last scrolled to (the pick and the list), so it scrolls only on a change. */
  private revealed = "";

  /**
   * The selected side is always in sight (spec 21.3): the ROW scrolls by the least distance so the
   * whole chip shows. Only the row's own offset: never `scrollIntoView` (that would move the page).
   */
  private revealPicked(): void {
    const row = this.pickRow;
    if (row.hidden || row.scrollWidth <= row.clientWidth) return;
    const chip = row.querySelector<HTMLElement>('[aria-checked="true"]');
    if (!chip) return;
    const left = revealOffset({
      scroll: row.scrollLeft,
      viewport: row.clientWidth,
      start: chip.offsetLeft,
      end: chip.offsetLeft + chip.offsetWidth,
    });
    if (left === row.scrollLeft) return;
    const smooth = !(this.motion?.matches ?? false);
    if (typeof row.scrollTo === "function")
      row.scrollTo({ left, behavior: smooth ? "smooth" : "auto" });
    else row.scrollLeft = left;
  }

  /** Arrow keys move the pick inside the "Send to" row, like the gift grid. */
  private onPickKey(e: KeyboardEvent): void {
    const list = this.o.receivers ?? [];
    const at = list.findIndex((r) => r.id === this.getReceiver());
    const last = list.length - 1;
    const forward = e.key === "ArrowRight" || e.key === "ArrowDown";
    const back = e.key === "ArrowLeft" || e.key === "ArrowUp";
    if (!forward && !back) return;
    const next = forward ? (at >= last ? 0 : at + 1) : at <= 0 ? last : at - 1;
    const r = list[next];
    if (!r) return;
    e.preventDefault();
    this.selectReceiver(r.id);
    this.pickRow.querySelector<HTMLElement>(`[data-gs-receiver="${CSS.escape(r.id)}"]`)?.focus();
  }

  private renderBalance(balance: number, coinName: string): void {
    this.balanceLabel.textContent = `Balance: ${fmt(balance)} ${coinName}`;
    if (balance === this.target) {
      if (!this.raf) this.balanceNum.textContent = fmt(this.shown);
      return;
    }
    this.target = balance;
    cancelAnimationFrame(this.raf);
    const from = this.shown;
    const startedAt = performance.now();
    const step = (): void => {
      const t = Math.min(1, (performance.now() - startedAt) / COUNT_UP_MS);
      this.shown = Math.round(from + (balance - from) * outCubic(t));
      this.balanceNum.textContent = fmt(this.shown);
      this.raf = t < 1 ? requestAnimationFrame(step) : 0;
    };
    this.balanceNum.textContent = fmt(this.shown);
    this.raf = requestAnimationFrame(step);
  }

  private press(): void {
    const selected = this.getSelected();
    if (!selected) return;
    const { gifts, balance, disabled = false } = this.o;
    const { action } = sendButtonState({
      gifts,
      selectedId: this.selectedId,
      balance,
      disabled,
      canTopUp: !!this.o.onTopUp,
    });
    if (action === "topUp") this.o.onTopUp?.();
    else if (action === "send") void this.o.onSend?.(selected);
  }

  /** Arrow keys move the selection like a radio group (and wrap round). */
  private onKey(e: KeyboardEvent): void {
    const { gifts } = this.o;
    const at = gifts.findIndex((g) => g.id === this.getSelected()?.id);
    const last = gifts.length - 1;
    const next =
      e.key === "ArrowRight" || e.key === "ArrowDown"
        ? at >= last
          ? 0
          : at + 1
        : e.key === "ArrowLeft" || e.key === "ArrowUp"
          ? at <= 0
            ? last
            : at - 1
          : e.key === "Home"
            ? 0
            : e.key === "End"
              ? last
              : -1;
    if (next < 0 || !gifts[next]) return;
    e.preventDefault();
    const cell = this.grid.children[next] as HTMLElement;
    this.selectedId = gifts[next].id;
    this.renderSelection();
    cell.focus();
    // Keep the newly selected cell in sight in a scrolling grid (popover, inline, expanded sheet).
    if (this.placement === "popover" || this.placement === "inline")
      cell.scrollIntoView?.({ block: "nearest" });
  }
}

/** `navigator.virtualKeyboard` (Chromium), where present. */
interface VirtualKeyboardLike {
  boundingRect?: { height: number };
  addEventListener?: (type: string, cb: () => void, options?: AddEventListenerOptions) => void;
}

const isPlacement = (v: unknown): v is TrayPlacementOption =>
  v === "sheet" || v === "popover" || v === "inline" || v === "auto";
