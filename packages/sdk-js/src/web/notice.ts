/**
 * "ayla sent Rose x3", bottom-left (spec 7.4). Up to three lines stack, newest at the bottom.
 * A line slides in from the left, stays, and slides out on its own timer; the combo number pops
 * each time it grows. The region is a polite live region, so a screen reader says it. A pill is
 * created for a line and removed after it has slid out.
 */
import { BATTLE_EXTRA_COLORS, type NoticeData, pictureSrc } from "../core";
import { setPicture } from "./images";
import { type Easing, inQuad, lerp, outBack, run, sample, sampleTimes, springScale } from "./anim";

/** Up to this many lines at once, newest at the bottom (same on every SDK). */
export const MAX_NOTICE_LINES = 3;

const SLIDE_IN_MS = 380;
const SLIDE_OUT_MS = 260;
const SLIDE_DISTANCE = 260;
const POP_FROM = 1.9;
const POP_MS = 1100;
const round = (n: number): number => Math.round(n * 100) / 100;

interface Line {
  pill: HTMLElement;
  image: HTMLImageElement | null;
  combo: HTMLElement | null;
  lastId: number;
  lastCount: number;
  visible: boolean;
  /** Expiry timer, restarted by each update of this line. */
  expiry: ReturnType<typeof setTimeout> | undefined;
  /** Removes the pill after its slide out. */
  removal: ReturnType<typeof setTimeout> | undefined;
  animations: Animation[];
  /** Slide progress, 0 (out) to 1 (in), and the move in progress, so a new move starts from here. */
  progress: number;
  move: { from: number; to: number; at: number; ms: number; ease: Easing } | null;
}

export interface NoticeViewOptions {
  parent: HTMLElement;
  /** Distance from the bottom edge of the layer, px. */
  bottom: number;
}

/** Whether the browser reads `color` as a CSS colour (it drops what it cannot parse). */
function readable(el: HTMLElement, color: string): boolean {
  const probe = el.ownerDocument.createElement("span");
  probe.style.color = color;
  return probe.style.color !== "";
}

export class NoticeView {
  readonly region: HTMLElement;
  private readonly doc: Document;
  /** Oldest first; the last one is the newest (bottom). */
  private lines: Line[] = [];

  constructor(private readonly o: NoticeViewOptions) {
    this.doc = o.parent.ownerDocument;
    this.region = this.doc.createElement("div");
    this.region.className = "gs-notice-region";
    this.region.setAttribute("role", "alert");
    this.region.setAttribute("aria-live", "polite");
    this.region.setAttribute("aria-atomic", "true");
    this.setBottom(o.bottom);
    o.parent.appendChild(this.region);
  }

  setBottom(px: number): void {
    this.region.style.bottom = `${px}px`;
  }

  /**
   * Shows the notice: a line with the same id is updated in place, any other id adds a line at
   * the bottom (the oldest goes at once when that would make four). The line's own timer hides it.
   */
  show(data: NoticeData, durationMs: number): void {
    let line = this.lines.find((l) => l.visible && l.lastId === data.id);
    const sameNotice = !!line;
    if (!line) {
      while (this.lines.filter((l) => l.visible).length >= MAX_NOTICE_LINES) {
        const oldest = this.lines.find((l) => l.visible);
        if (!oldest) break;
        this.hideLine(oldest);
      }
      line = this.createLine();
    }
    clearTimeout(line.expiry);
    this.render(line, data);
    if (sameNotice && data.count > line.lastCount && data.count > 1 && line.combo) this.pop(line);
    if (!sameNotice) this.slideTo(line, 1, SLIDE_IN_MS, outBack(1.2));
    line.visible = true;
    line.lastId = data.id;
    line.lastCount = data.count;
    const l = line;
    l.expiry = setTimeout(() => this.hideLine(l), durationMs);
  }

  /** Slides the newest line out. */
  hideNewest(): void {
    for (let i = this.lines.length - 1; i >= 0; i--) {
      const l = this.lines[i];
      if (l && l.visible) {
        this.hideLine(l);
        return;
      }
    }
  }

  /** Removes every line at once. */
  clearAll(): void {
    for (const l of this.lines) this.destroyLine(l);
    this.lines = [];
  }

  /** Removes everything at once. */
  dispose(): void {
    this.clearAll();
    this.region.remove();
  }

  private hideLine(line: Line): void {
    if (!line.visible) return;
    line.visible = false;
    clearTimeout(line.expiry);
    line.pill.setAttribute("data-gs-visible", "false");
    this.slideTo(line, 0, SLIDE_OUT_MS, inQuad);
    line.removal = setTimeout(() => {
      this.destroyLine(line);
      this.lines = this.lines.filter((l) => l !== line);
    }, SLIDE_OUT_MS);
  }

  private destroyLine(line: Line): void {
    clearTimeout(line.expiry);
    clearTimeout(line.removal);
    this.cancelAnimations(line);
    line.pill.remove();
  }

  private createLine(): Line {
    const pill = this.doc.createElement("div");
    pill.className = "gs-notice";
    pill.setAttribute("data-gs-notice", "");
    pill.innerHTML =
      '<span class="gs-avatar" aria-hidden="true"></span>' +
      '<span class="gs-notice-text"><span class="gs-notice-name"></span><span class="gs-notice-what"></span></span>';
    this.region.appendChild(pill);
    const line: Line = {
      pill,
      image: null,
      combo: null,
      lastId: -1,
      lastCount: 0,
      visible: false,
      expiry: undefined,
      removal: undefined,
      animations: [],
      progress: 0,
      move: null,
    };
    this.lines.push(line);
    this.paint(pill, 0);
    return line;
  }

  private render(line: Line, data: NoticeData): void {
    const pill = line.pill;
    pill.classList.toggle("gs-big", data.big);
    pill.setAttribute("data-gs-visible", "true");
    const q = (sel: string) => pill.querySelector(sel) as HTMLElement;
    q(".gs-avatar").textContent = (Array.from(data.senderName)[0] ?? "").toUpperCase();
    q(".gs-notice-name").textContent = data.senderName;
    const r = data.receiver;
    q(".gs-notice-what").textContent = r
      ? `sent ${data.giftName} to ${r.name}`
      : `sent ${data.giftName}`;
    // A battle gift: a 2 px ring in the side colour inside the pill's edge, then a 1 px line in
    // the pill's text colour inside it, so the ring shows even when the side colour is the pill's
    // own (the default accent on the default notice). The text keeps its colour, the pill its
    // size. An unreadable colour counts as none (SPEC 7.4).
    pill.style.boxShadow = "";
    if (r) {
      const text = data.big ? "var(--gs-notice-big-text)" : "var(--gs-notice-text)";
      const line = `inset 0 0 0 3px ${text}`;
      const own = r.color && readable(pill, r.color) ? r.color : null;
      // The default palette (SPEC 7.4, 18.7): accent, coin, teal, pink, then over again.
      const palette = ["var(--gs-accent)", "var(--gs-coin)", ...BATTLE_EXTRA_COLORS];
      const side = own ?? palette[(r.side ?? 0) % palette.length]!;
      pill.style.boxShadow = `inset 0 0 0 2px ${side}, ${line}`;
    }

    // A fresh <img> for each picture: one reused element shows the previous gift until the new one loads.
    if (data.image !== (line.image?.getAttribute("src") ?? null)) {
      line.image?.remove();
      line.image = null;
      if (pictureSrc(data.image)) {
        const img = this.doc.createElement("img");
        img.className = "gs-notice-img";
        img.alt = "";
        img.decoding = "async";
        setPicture(img, data.image);
        pill.insertBefore(img, line.combo);
        line.image = img;
      }
    }
    if (data.count > 1) {
      if (!line.combo) {
        line.combo = this.doc.createElement("span");
        line.combo.className = "gs-combo";
        line.combo.setAttribute("data-gs-combo", "");
        pill.appendChild(line.combo);
      }
      line.combo.textContent = `x${data.count}`;
    } else if (line.combo) {
      line.combo.remove();
      line.combo = null;
    }
  }

  /** Slide progress 0..1 as transform and opacity (translateX -260 to 0 px). */
  private paint(pill: HTMLElement, p: number): void {
    const q = Math.min(1, Math.max(0, p));
    pill.style.transform = `translateX(${round(lerp(-SLIDE_DISTANCE, 0, p))}px)`;
    pill.style.opacity = String(q);
  }

  private progressNow(line: Line): number {
    const m = line.move;
    if (!m) return line.progress;
    const t = Math.min(1, (performance.now() - m.at) / m.ms);
    return lerp(m.from, m.to, m.ease(t));
  }

  private slideTo(line: Line, to: number, ms: number, ease: Easing): void {
    const pill = line.pill;
    const from = this.progressNow(line);
    this.cancelAnimations(line);
    line.progress = to;
    // Reduced motion keeps the slide too (spec 7.5): it is the only motion left, and it is short.
    line.move = { from, to, at: performance.now(), ms, ease };
    // The end state is the inline style; the animation only covers the way there.
    this.paint(pill, to);
    const frames = sample(ms, sampleTimes(ms, [], 20), (t) => {
      const p = lerp(from, to, ease(t / ms));
      return {
        transform: `translateX(${round(lerp(-SLIDE_DISTANCE, 0, p))}px)`,
        opacity: Math.min(1, Math.max(0, p)),
      };
    });
    const a = run(pill, frames, ms);
    if (a) line.animations.push(a);
  }

  /** The counter jumps to 1.9 and springs back to 1. */
  private pop(line: Line): void {
    const el = line.combo;
    if (!el) return;
    const frames = sample(POP_MS, sampleTimes(POP_MS, [], 16), (t) => ({
      transform: `scale(${Math.round(springScale(POP_FROM, t / 1000) * 1000) / 1000})`,
    }));
    const a = run(el, frames, POP_MS);
    if (a) line.animations.push(a);
  }

  private cancelAnimations(line: Line): void {
    for (const a of line.animations) a.cancel();
    line.animations = [];
  }
}
