/**
 * Draws one gift effect (spec 7.2 and 7.3) and tells the layer when it starts and when it ends.
 * It waits for its picture first, so the dim, the notice and the gift appear together. Every
 * animation is a Web Animation on `transform` or `opacity`.
 */
import { type ScheduledEffect, pictureFailed, pictureSrc } from "../core";
import {
  type Geometry,
  type Point,
  PICTURE_SIZE,
  pictureScale,
  coinFrames,
  dimFrames,
  effectDurationMs,
  glowFrames,
  pictureFrames,
  raysFrames,
  run,
  sparkFrames,
} from "./anim";

export interface EffectViewOptions {
  effect: ScheduledEffect;
  parent: HTMLElement;
  /** The layer's size now; 0 while it is hidden or not laid out. */
  measure: () => { width: number; height: number };
  /** Where gifts start, as fractions of the layer. */
  origin: Point;
  pictureWaitMs: number;
  /** Multiplier for the picture size. Default: automatic, bigger in a wide layer. */
  pictureScale?: number;
  /** The picture is ready (or the wait ran out): the effect really starts now. */
  onStart: () => void;
  /** The animation ran to its end. */
  onDone: () => void;
}

const SVG = "http://www.w3.org/2000/svg";

/** One set of thin triangles from the centre to the edge, like a stage light. */
function raysSet(
  doc: Document,
  R: number,
  count: number,
  halfWidth: number,
  opacity: number,
): SVGElement {
  const svg = doc.createElementNS(SVG, "svg");
  svg.setAttribute("width", String(R));
  svg.setAttribute("height", String(R));
  svg.setAttribute("viewBox", `0 0 ${R} ${R}`);
  svg.setAttribute("aria-hidden", "true");
  const c = R / 2;
  for (let i = 0; i < count; i++) {
    const tri = doc.createElementNS(SVG, "polygon");
    tri.setAttribute("points", `${c - halfWidth},0 ${c + halfWidth},0 ${c},${c}`);
    tri.setAttribute("transform", `rotate(${(i * 360) / count} ${c} ${c})`);
    tri.setAttribute("fill", "var(--gs-glow)");
    tri.setAttribute("fill-opacity", String(opacity));
    svg.appendChild(tri);
  }
  return svg;
}

export class EffectView {
  readonly root: HTMLElement;
  private readonly doc: Document;
  private readonly picture: HTMLElement;
  private readonly animations: Animation[] = [];
  private waitTimer: ReturnType<typeof setTimeout> | undefined;
  private doneTimer: ReturnType<typeof setTimeout> | undefined;
  private pictureReady = false;
  private started = false;
  private dead = false;

  constructor(private readonly o: EffectViewOptions) {
    const { effect, parent } = o;
    this.doc = parent.ownerDocument;
    this.root = this.doc.createElement("div");
    this.root.className = "gs-effect";
    this.root.setAttribute("data-gs-effect", effect.recipe.tier);
    this.root.setAttribute("data-gs-effect-id", String(effect.id));
    this.root.setAttribute("aria-hidden", "true");
    this.picture = this.doc.createElement("div");
    this.picture.className = "gs-abs gs-picture";
    this.root.appendChild(this.picture);
    parent.appendChild(this.root);
    this.loadPicture();
  }

  /** Called when the layer may have gained a size. */
  tryStart(): void {
    if (this.dead || this.started || !this.pictureReady) return;
    const { width, height } = this.o.measure();
    if (width <= 0 || height <= 0) return;
    this.started = true;
    this.begin(width, height);
  }

  destroy(): void {
    this.dead = true;
    clearTimeout(this.waitTimer);
    clearTimeout(this.doneTimer);
    for (const a of this.animations) a.cancel();
    this.animations.length = 0;
    this.root.remove();
  }

  /** Waits for the picture up to `pictureWaitMs`; starts exactly once. */
  private loadPicture(): void {
    // A URL the SDK refuses, or one that failed a moment ago, is the same as no picture (7.6).
    const url = pictureSrc(this.o.effect.event.gift.image);
    if (!url || this.o.pictureWaitMs <= 0) {
      if (url) this.addPicture(url);
      else this.addFallback();
      // After the listener returns, so `started` never runs inside `enter`.
      queueMicrotask(() => this.ready());
      return;
    }
    const img = this.addPicture(url);
    img.addEventListener("load", () => {
      // Decode before the first frame, so the picture does not pop in half-drawn.
      if (typeof img.decode === "function") {
        void img.decode().then(
          () => this.ready(),
          () => this.ready(),
        );
      } else {
        this.ready();
      }
    });
    img.addEventListener("error", () => {
      pictureFailed(url);
      this.ready();
    });
    this.waitTimer = setTimeout(() => this.ready(), this.o.pictureWaitMs);
    // A picture from the cache may be complete already.
    if (img.complete && img.naturalWidth > 0) queueMicrotask(() => this.ready());
  }

  private addPicture(url: string): HTMLImageElement {
    const img = this.doc.createElement("img");
    img.alt = "";
    img.decoding = "async";
    img.draggable = false;
    img.src = url;
    this.picture.appendChild(img);
    return img;
  }

  private addFallback(): void {
    const disc = this.doc.createElement("div");
    disc.className = "gs-picture-fallback";
    this.picture.appendChild(disc);
  }

  private ready(): void {
    if (this.dead || this.pictureReady) return;
    this.pictureReady = true;
    clearTimeout(this.waitTimer);
    this.tryStart();
  }

  /** An absolutely positioned box behind the picture. */
  private spot(className: string, x: number, y: number, w: number, h = w): HTMLElement {
    const el = this.doc.createElement("div");
    el.className = `gs-abs ${className}`;
    el.style.left = `${x}px`;
    el.style.top = `${y}px`;
    el.style.width = `${w}px`;
    el.style.height = `${h}px`;
    this.root.insertBefore(el, this.picture);
    return el;
  }

  private play(el: Element, frames: Keyframe[], durationMs: number, delayMs = 0): void {
    const a = run(el, frames, durationMs, delayMs);
    if (a) this.animations.push(a);
  }

  /** Builds the layout of the effect (random, fixed from here on) and starts every animation. */
  private begin(W: number, H: number): void {
    const { effect, origin } = this.o;
    const k = pictureScale(W, H, effect.recipe.peakScale, this.o.pictureScale);
    // The picture, the burst and the glow grow together; times and counts stay the same.
    const recipe =
      k === 1
        ? effect.recipe
        : {
            ...effect.recipe,
            peakScale: effect.recipe.peakScale * k,
            sparkSpread: effect.recipe.sparkSpread * k,
          };
    const O: Point = { x: origin.x * W, y: origin.y * H };
    const S: Point =
      recipe.stage === "center"
        ? { x: W / 2, y: 0.38 * H }
        : { x: O.x + (Math.random() - 0.5) * 0.2 * W, y: O.y - 0.32 * H };
    const geo: Geometry = { width: W, height: H, origin: O, stage: S };
    const tail = recipe.holdMs + recipe.flyOutMs;
    const runMs = recipe.flyInMs + tail;

    this.o.onStart();
    if (this.dead) return; // the start led to a cancel

    // Drawing order, back to front: dim, rays, glow, sparks, coins, picture.
    if (recipe.dim) this.play(this.spot("gs-dim", 0, 0, W, H), dimFrames(recipe), runMs);
    if (recipe.rays) {
      const R = Math.min(W, H) * 1.6;
      const sets = [
        { halfWidth: R * 0.075, opacity: 0.34, from: 0, to: 60 },
        { halfWidth: R * 0.028, opacity: 0.42, from: 15, to: -35 },
      ];
      for (const s of sets) {
        const el = this.spot("gs-rays", S.x - R / 2, S.y - R / 2, R);
        el.appendChild(raysSet(this.doc, R, 12, s.halfWidth, s.opacity));
        this.play(el, raysFrames(s.from, s.to), runMs);
      }
      // A soft round glow: five discs, brighter towards the middle.
      const G = PICTURE_SIZE * 3.4 * k;
      const glow = this.spot("gs-glow", S.x - G / 2, S.y - G / 2, G);
      for (const k of [1, 0.78, 0.58, 0.4, 0.24]) {
        const disc = this.doc.createElement("div");
        const d = G * k;
        disc.style.cssText = `left:${(G - d) / 2}px;top:${(G - d) / 2}px;width:${d}px;height:${d}px`;
        glow.appendChild(disc);
      }
      this.play(glow, glowFrames(recipe), runMs);
    }
    for (let i = 0; i < recipe.sparks; i++) {
      const angle = (i / Math.max(1, recipe.sparks)) * Math.PI * 2 + Math.random() * 0.6;
      const dist = recipe.sparkSpread * (0.4 + Math.random() * 0.8);
      const size = 5 + Math.random() * 6;
      const from = { x: S.x - size / 2, y: S.y - size / 2 };
      const el = this.spot("gs-spark", 0, 0, size);
      el.style.background = i % 3 === 0 ? "var(--gs-accent)" : "var(--gs-glow)";
      const dx = Math.cos(angle) * dist;
      const dy = Math.sin(angle) * dist;
      this.play(el, sparkFrames(from, dx, dy), 900, recipe.flyInMs);
    }
    for (let i = 0; i < recipe.coins; i++) {
      const size = 10 + Math.random() * 8;
      const el = this.spot("gs-coin-rain", Math.random() * W, -24, size);
      el.style.background = "var(--gs-coin)";
      const frames = coinFrames(H, Math.random() * 0.35, 0.45 + Math.random() * 0.2);
      this.play(el, frames, tail + 800, recipe.flyInMs);
    }
    this.play(this.picture, pictureFrames(recipe, geo), runMs);

    this.doneTimer = setTimeout(() => this.o.onDone(), effectDurationMs(recipe));
  }
}
