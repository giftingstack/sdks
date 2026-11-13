import {
  type BattleBarLabelsInput,
  type BattleBarModel,
  type BattleView,
  asGiftingError,
  battleBarModel,
  battleGains,
  battleSidePalette,
  PRESS_SIDE_LABEL,
} from "../core";
import { acquireStyles, releaseStyles } from "./styles";
import { type GiftTheme, applyTheme } from "./theme";
import { type ResolveUsers, type UserInfo, avatar, make, missingIds, motionOff } from "./ui";
import type { RoomHandle } from "./joinRoom";

export interface GiftBattleBarOptions {
  /**
   * The room you joined: the bar follows its battle by itself (scores frames and a clock tick).
   * Or leave it out and call `setView(view)` yourself, for example from `joinRoom({ onBattle })`.
   */
  room?: Pick<RoomHandle, "battleView" | "onBattle">;
  /** Names and pictures of the receivers (the ids are your user ids). Fallback: the id. */
  resolveUsers?: ResolveUsers;
  /**
   * Override the side colours, one per side in order (default: the theme's accent, its coin
   * colour, then teal and pink, then the same again). A shorter list keeps the default for the
   * sides it does not name. Give the room the same list (`joinRoom({ sideColors })`).
   */
  sideColors?: readonly string[];
  /** Default: follows `prefers-reduced-motion`. Reduced motion: no sliding, counting or pulse. */
  reducedMotion?: boolean;
  /** How often the clock refreshes while a round is open, ms. Default 1,000; 0 = never. */
  tickMs?: number;
  /** Called when `resolveUsers` fails. The bar still draws, with the ids. */
  onError?: (error: ReturnType<typeof asGiftingError>) => void;
  theme?: Partial<GiftTheme>;
  labels?: BattleBarLabelsInput;
  /**
   * Makes every side's avatar a button (spec 21.4): open your tray with that side picked,
   * `tray.selectReceiver(id); tray.open()`. Without it the bar is read-only, as before.
   */
  onPressSide?: (id: string) => void;
  /** The button's label; `{name}` is replaced. Default "Send {name} a gift". */
  pressSideLabel?: string;
}

const CROWN =
  '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M3 8l4.5 4L12 5l4.5 7L21 8l-2 11H5z"/></svg>';
const COUNT_MS = 650;

/** Replays a CSS animation class. */
function restart(el: HTMLElement, cls: string): void {
  el.classList.remove(cls);
  void el.offsetWidth;
  el.classList.add(cls);
}

/**
 * The battle bar of a round (SPEC 18.6, 18.7): the receivers with their scores, a countdown,
 * and a split bar whose boundary slides as gifts arrive. Two sides are the classic versus; three
 * or more (up to 8) are a free-for-all: the clock, a row of cells, a bar of proportional
 * segments. Draws `battleView` data only; the SDK decides nothing about the round (your server
 * starts and ends it). Hidden while the room has no round with two sides. A screen reader hears
 * the scores and the result.
 */
export class GiftBattleBar {
  readonly element: HTMLElement;
  private o: GiftBattleBarOptions;
  private readonly doc: Document;
  private view: BattleView | null = null;
  private readonly names = new Map<string, UserInfo>();
  private key = "";
  private last: number[] | null = null;
  private shown: number[] = [0, 0];
  private frames: number[] = [0, 0];
  private wasFinal = false;
  private destroyed = false;
  private timer: ReturnType<typeof setInterval> | undefined;
  private unsubscribe: (() => void) | undefined;
  private lookups = 0;

  constructor(container: HTMLElement, options: GiftBattleBarOptions = {}) {
    this.doc = container.ownerDocument;
    this.o = options;
    acquireStyles(this.doc);
    this.element = make(this.doc, "div", "gs-battle");
    this.element.setAttribute("data-gs-battle", "");
    this.element.hidden = true;
    applyTheme(this.element, options.theme);
    container.appendChild(this.element);
    this.follow();
  }

  update(patch: Partial<GiftBattleBarOptions>): void {
    if (this.destroyed) return;
    const roomChanged = "room" in patch && patch.room !== this.o.room;
    this.o = { ...this.o, ...patch };
    if ("theme" in patch) applyTheme(this.element, this.o.theme);
    if (roomChanged) this.follow();
    this.key = ""; // colours, labels and names may have changed: draw again
    this.draw();
  }

  /** Show this round (null hides the bar). Use it when you did not pass `room`. */
  setView(view: BattleView | null): void {
    if (this.destroyed) return;
    this.view = view;
    this.draw();
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.unsubscribe?.();
    clearInterval(this.timer);
    this.frames.forEach((f) => this.cancelFrame(f));
    this.element.remove();
    releaseStyles();
  }

  // ------------------------------------------------------------------ following a room

  private follow(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    clearInterval(this.timer);
    const room = this.o.room;
    if (!room) return;
    const refresh = () => this.setView(room.battleView());
    this.unsubscribe = room.onBattle(refresh);
    const every = this.o.tickMs ?? 1_000;
    if (every > 0)
      this.timer = setInterval(() => {
        // The clock only needs a frame while a round is open.
        if (this.view?.open) refresh();
      }, every);
    refresh();
  }

  // ------------------------------------------------------------------ drawing

  private calm(): boolean {
    return motionOff(this.doc, this.o.reducedMotion);
  }

  private nameOf = (id: string): string => this.names.get(id)?.name ?? id;

  private lookUp(ids: string[]): void {
    const resolve = this.o.resolveUsers;
    const missing = resolve ? missingIds(ids, this.names) : [];
    if (!resolve || !missing.length) return;
    const ticket = ++this.lookups;
    resolve(missing).then(
      (found) => {
        if (this.destroyed || ticket !== this.lookups) return;
        for (const [id, info] of Object.entries(found)) this.names.set(id, info);
        this.key = "";
        this.draw();
      },
      (err: unknown) => this.o.onError?.(asGiftingError(err)),
    );
  }

  /** With `onPressSide`, the avatar inside a button (spec 21.4). */
  private pickable(av: HTMLElement, id: string): HTMLElement {
    if (!this.o.onPressSide) return av;
    const b = make(this.doc, "button", "gs-vs-pick") as HTMLButtonElement;
    b.type = "button";
    b.setAttribute("data-gs-side", id);
    b.addEventListener("click", () => this.o.onPressSide?.(id));
    b.append(av);
    return b;
  }

  private draw(): void {
    const model = battleBarModel(this.view, { nameOf: this.nameOf, labels: this.o.labels });
    const view = this.view;
    if (!model || !view) {
      this.element.hidden = true;
      this.key = "";
      this.last = null;
      return;
    }
    this.element.hidden = false;
    this.element.toggleAttribute("data-calm", this.calm());
    const ids = view.sides.map((s) => s.id);
    const key = `${view.round}|${ids.join("|")}|${this.o.onPressSide ? "p" : ""}`;
    if (key !== this.key) {
      if (!this.key.startsWith(`${view.round}|`)) this.last = null; // a new round: nothing pulses
      this.build(model, key);
      this.lookUp(ids);
    }
    this.apply(model, view);
    const label = this.o.pressSideLabel ?? PRESS_SIDE_LABEL;
    for (const b of this.element.querySelectorAll<HTMLElement>(".gs-vs-pick")) {
      const side = model.sides.find((x) => x.id === b.getAttribute("data-gs-side"));
      if (side) b.setAttribute("aria-label", label.replace("{name}", side.name));
    }
  }

  private build(model: BattleBarModel, key: string): void {
    this.key = key;
    this.frames.forEach((f) => this.cancelFrame(f));
    const n = model.sides.length;
    this.shown =
      this.last && this.shown.length === n ? [...this.shown] : new Array<number>(n).fill(0);
    this.frames = new Array<number>(n).fill(0);
    const palette = battleSidePalette(this.o.theme, n, this.o.sideColors);
    if (n > 2) return this.buildMulti(model, palette);
    const [colA, colB] = [palette[0]!, palette[1]!];
    const doc = this.doc;
    const root = make(doc, "div", "gs-vs");
    root.style.setProperty("--gs-side-a", colA.color);
    root.style.setProperty("--gs-side-a-text", colA.text);
    root.style.setProperty("--gs-side-b", colB.color);
    root.style.setProperty("--gs-side-b-text", colB.text);
    const top = make(doc, "div", "gs-vs-top", root);
    const sides = model.sides.map((s, i) => {
      const side = make(doc, "div", `gs-vs-side gs-vs-s${i}`);
      const av = avatar(doc, s.name, this.names.get(s.id)?.avatarUrl, 44);
      av.classList.add("gs-vs-avatar");
      side.append(this.pickable(av, s.id));
      const crown = make(doc, "span", "gs-vs-crown", side);
      crown.setAttribute("aria-hidden", "true");
      crown.innerHTML = CROWN;
      const who = make(doc, "div", "gs-vs-who", side);
      make(doc, "b", "gs-vs-name", who).textContent = s.name;
      make(doc, "span", "gs-vs-score", who).textContent = "0";
      return side;
    });
    const mid = make(doc, "div", "gs-vs-mid");
    make(doc, "span", "gs-vs-tag", mid).textContent = resolveVs(this.o.labels);
    make(doc, "span", "gs-vs-clock", mid);
    top.append(sides[0]!, mid, sides[1]!);
    const bar = make(doc, "div", "gs-vs-bar", root);
    bar.setAttribute("role", "img");
    make(doc, "i", "gs-vs-a", bar);
    make(doc, "i", "gs-vs-b", bar);
    make(doc, "i", "gs-vs-spark", bar);
    const banner = make(doc, "p", "gs-vs-banner", root);
    banner.setAttribute("role", "status");
    this.element.replaceChildren(root);
  }

  /** Three or more sides (SPEC 18.7): the clock, a row of N cells, a bar of N segments. */
  private buildMulti(model: BattleBarModel, palette: { color: string; text: string }[]): void {
    const doc = this.doc;
    const n = model.sides.length;
    const root = make(doc, "div", "gs-vs gs-vs-multi");
    palette.forEach((c, i) => {
      root.style.setProperty(`--gs-side-${i}`, c.color);
      root.style.setProperty(`--gs-side-${i}-text`, c.text);
    });
    root.style.setProperty("--gs-vs-n", String(n));
    root.dataset.gsSides = n > 4 ? "many" : "few";
    const mid = make(doc, "div", "gs-vs-mid", root);
    make(doc, "span", "gs-vs-tag", mid).textContent = resolveVs(this.o.labels);
    make(doc, "span", "gs-vs-clock", mid);
    const cells = make(doc, "div", "gs-vs-cells", root);
    model.sides.forEach((s, i) => {
      const side = make(doc, "div", `gs-vs-side gs-vs-s${i}`, cells);
      side.style.setProperty("--gs-side", `var(--gs-side-${i})`);
      side.style.setProperty("--gs-side-text", `var(--gs-side-${i}-text)`);
      const av = avatar(doc, s.name, this.names.get(s.id)?.avatarUrl, n > 4 ? 30 : 36);
      av.classList.add("gs-vs-avatar");
      side.append(this.pickable(av, s.id));
      const crown = make(doc, "span", "gs-vs-crown", side);
      crown.setAttribute("aria-hidden", "true");
      crown.innerHTML = CROWN;
      const who = make(doc, "div", "gs-vs-who", side);
      make(doc, "b", "gs-vs-name", who).textContent = s.name;
      make(doc, "span", "gs-vs-score", who).textContent = "0";
    });
    const bar = make(doc, "div", "gs-vs-bar", root);
    bar.setAttribute("role", "img");
    model.sides.forEach((_, i) => {
      const seg = make(doc, "i", `gs-vs-seg gs-vs-seg${i}`, bar);
      seg.style.setProperty("--gs-side", `var(--gs-side-${i})`);
    });
    const banner = make(doc, "p", "gs-vs-banner", root);
    banner.setAttribute("role", "status");
    this.element.replaceChildren(root);
  }

  private apply(model: BattleBarModel, view: BattleView): void {
    const el = this.element;
    const q = (sel: string): HTMLElement => el.querySelector<HTMLElement>(sel)!;
    const root = q(".gs-vs");
    const multi = model.sides.length > 2;
    const units = view.sides.map((s) => s.units);
    const gains = battleGains(this.last, units);
    const calm = this.calm();
    model.sides.forEach((s, i) => {
      const side = q(`.gs-vs-s${i}`);
      if (gains[i] && !calm) {
        restart(side, "gs-pulse");
        restart(q(multi ? `.gs-vs-seg${i}` : i ? ".gs-vs-b" : ".gs-vs-a"), "gs-pulse");
      }
      side.classList.toggle("gs-win", s.won);
      side.classList.toggle("gs-lose", s.lost);
      this.count(i, q(`.gs-vs-s${i} .gs-vs-score`), s.units, s.score, calm);
    });
    this.last = units;
    if (multi) {
      model.pcts.forEach((p, i) => (q(`.gs-vs-seg${i}`).style.width = `${p}%`));
    } else {
      q(".gs-vs-a").style.width = `${model.pct}%`;
      q(".gs-vs-b").style.width = `${100 - model.pct}%`;
      q(".gs-vs-spark").style.left = `${model.pct}%`;
    }
    const clock = q(".gs-vs-clock");
    clock.textContent = model.clock;
    clock.classList.toggle("gs-urgent", model.urgent);
    root.classList.toggle("gs-done", model.final);
    q(".gs-vs-bar").setAttribute("aria-label", model.spoken);
    const banner = q(".gs-vs-banner");
    if (banner.textContent !== model.banner) banner.textContent = model.banner;
    if (model.final && !this.wasFinal && !calm) restart(root, "gs-finish");
    this.wasFinal = model.final;
  }

  /** Counts a score up to its value; calm: straight to it. */
  private count(i: number, el: HTMLElement, to: number, text: string, calm: boolean): void {
    this.cancelFrame(this.frames[i]!);
    const from = this.shown[i]!;
    const win = this.doc.defaultView;
    if (calm || from === to || !win) {
      this.shown[i] = to;
      el.textContent = text;
      return;
    }
    const model = (n: number) => battleBarModel(this.fake(i, n), { labels: this.o.labels });
    const t0 = win.performance.now();
    const step = (now: number): void => {
      const k = Math.min(1, (now - t0) / COUNT_MS);
      const v = Math.round(from + (to - from) * (1 - (1 - k) ** 3));
      this.shown[i] = v;
      el.textContent = k < 1 ? (model(v)?.sides[i]?.score ?? String(v)) : text;
      if (k < 1 && !this.destroyed) this.frames[i] = win.requestAnimationFrame(step);
    };
    this.frames[i] = win.requestAnimationFrame(step);
  }

  /** The current view with side `i` showing `n`, so the counter uses the same short form. */
  private fake(i: number, n: number): BattleView {
    const v = this.view!;
    return { ...v, sides: v.sides.map((s, j) => (j === i ? { ...s, units: n } : s)) };
  }

  private cancelFrame(id: number): void {
    if (id) this.doc.defaultView?.cancelAnimationFrame(id);
  }
}

const resolveVs = (labels?: BattleBarLabelsInput): string => labels?.vs ?? "VS";
