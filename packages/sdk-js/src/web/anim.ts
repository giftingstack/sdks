/**
 * Easing curves, keyframe sampling and the timeline maths of one effect (spec section 7.3).
 * Pure functions, no DOM except `run`. Only `transform` and `opacity` are ever animated, so the
 * browser runs the animations on the compositor and nothing re-lays-out per frame.
 */
import type { EffectRecipe } from "../core";

export type Easing = (t: number) => number;

export const clamp01 = (t: number): number => Math.min(1, Math.max(0, t));
export const lerp = (a: number, b: number, t: number): number => a + (b - a) * t;

export const outCubic: Easing = (t) => 1 - (1 - t) ** 3;
export const inQuad: Easing = (t) => t * t;
/** Ease-out with overshoot, like React Native's `Easing.out(Easing.back(s))`. */
export const outBack =
  (s: number): Easing =>
  (t) => {
    const u = 1 - t;
    return 1 - u * u * ((s + 1) * u - s);
  };

/**
 * The counter pop (spec 7.4): React Native's `Animated.spring` with friction 4 and tension 160 is
 * an underdamped spring with stiffness 664.6, damping 13 and mass 1. This is its closed form,
 * going from `from` to 1 at `seconds` after the start.
 */
export function springScale(from: number, seconds: number): number {
  const stiffness = 3.62 * (160 - 30) + 194;
  const damping = (4 - 8) * 3 + 25;
  const w0 = Math.sqrt(stiffness);
  const zeta = damping / (2 * w0);
  const wd = w0 * Math.sqrt(1 - zeta * zeta);
  const decay = Math.exp(-zeta * w0 * seconds);
  const swing = Math.cos(wd * seconds) + ((zeta * w0) / wd) * Math.sin(wd * seconds);
  return 1 + (from - 1) * decay * swing;
}

/** `n + 1` evenly spaced values from `a` to `b`. */
export function linspace(a: number, b: number, n: number): number[] {
  return Array.from({ length: n + 1 }, (_, i) => lerp(a, b, i / n));
}

/** Sorted, unique sample times: the ends, every kink and, between them, a point each `stepMs`. */
export function sampleTimes(total: number, kinks: number[] = [], stepMs = Infinity): number[] {
  const times = new Set<number>([0, total, ...kinks.filter((k) => k > 0 && k < total)]);
  for (let t = stepMs; t < total; t += stepMs) times.add(t);
  return [...times].sort((a, b) => a - b);
}

export interface Look {
  transform?: string;
  opacity?: number;
}

/** Keyframes for a function of time (ms), sampled at `times`, over `total` ms. */
export function sample(total: number, times: number[], at: (t: number) => Look): Keyframe[] {
  return times.map((t) => ({ offset: total === 0 ? 0 : t / total, ...at(t) }));
}

const r = (n: number): number => Math.round(n * 100) / 100;
export const translate = (x: number, y: number): string => `translate(${r(x)}px, ${r(y)}px)`;

/** Runs keyframes with WAAPI. Browsers without it show the end state only (returns null). */
export function run(
  el: Element,
  frames: Keyframe[],
  durationMs: number,
  delayMs = 0,
): Animation | null {
  if (typeof el.animate !== "function") return null;
  return el.animate(frames, {
    duration: durationMs,
    delay: delayMs,
    fill: "both",
    easing: "linear",
  });
}

export interface Point {
  x: number;
  y: number;
}

/** What is fixed when an effect starts (spec 7.3): the layer size, start point and stage point. */
export interface Geometry {
  width: number;
  height: number;
  origin: Point;
  stage: Point;
}

/** The picture is a box this many px wide at scale 1; the recipe's `peakScale` is relative to it. */
export const PICTURE_SIZE = 100;

/**
 * How much bigger than the phone layout the gift picture is drawn in a wide layer. A phone layer
 * (about 390 x 700) gives 1; the picture grows with the layer's area up to 2, and never beyond
 * 90 percent of the layer's short side at its biggest. `manual` replaces the automatic value.
 */
export function pictureScale(
  width: number,
  height: number,
  peakScale: number,
  manual?: number,
): number {
  const room = (0.9 * Math.min(width, height)) / (PICTURE_SIZE * peakScale);
  const wanted = manual ?? Math.min(2, Math.max(1, Math.sqrt(width * height) / 530));
  return Math.min(wanted, Math.max(room, 0.5));
}

/** Total run time of an effect: when every phase has ended (spec 7.3). */
export function effectDurationMs(recipe: EffectRecipe): number {
  const tail = recipe.holdMs + recipe.flyOutMs;
  return recipe.flyInMs + Math.max(900, tail, recipe.coins > 0 ? tail + 800 : 0);
}

/** Where the picture is, how big and how visible, `t` ms after the effect started. */
export function pictureAt(recipe: EffectRecipe, geo: Geometry, t: number): Look {
  const fly = outBack(1.3)(clamp01(t / recipe.flyInMs));
  const leave = inQuad(clamp01((t - recipe.flyInMs - recipe.holdMs) / recipe.flyOutMs));
  const x = lerp(geo.origin.x, geo.stage.x, fly) - PICTURE_SIZE / 2;
  const y = lerp(geo.origin.y, geo.stage.y, fly) - PICTURE_SIZE / 2 - 0.07 * geo.height * leave;
  const scale = lerp(0.3, recipe.peakScale, fly) * lerp(1, 0.55, leave);
  return {
    transform: `${translate(x, y)} scale(${r(scale * 1000) / 1000})`,
    opacity: r(clamp01(fly / 0.06) * (1 - leave)),
  };
}

export function pictureFrames(recipe: EffectRecipe, geo: Geometry): Keyframe[] {
  const { flyInMs, holdMs, flyOutMs } = recipe;
  const total = flyInMs + holdMs + flyOutMs;
  const leaveAt = flyInMs + holdMs;
  const times = [
    ...linspace(0, flyInMs, 18),
    ...(holdMs > 0 ? [leaveAt] : []),
    ...linspace(leaveAt, total, 12),
  ];
  return sample(total, sampleTimes(total, times), (t) => pictureAt(recipe, geo, t));
}

/** The dark layer behind a large gift: 0 to 0.62 in 300 ms, back to 0 as the gift leaves. */
export function dimFrames(recipe: EffectRecipe): Keyframe[] {
  const total = recipe.flyInMs + recipe.holdMs + recipe.flyOutMs;
  const leaveAt = recipe.flyInMs + recipe.holdMs;
  const at = (t: number): Look => ({
    opacity:
      t < 300
        ? (t / 300) * 0.62
        : t < leaveAt
          ? 0.62
          : (1 - (t - leaveAt) / recipe.flyOutMs) * 0.62,
  });
  return sample(total, sampleTimes(total, [300, leaveAt]), at);
}

/** Position of a spark's burst: `(dx, dy)` away, shrinking, fading in fast and out slowly. */
export function sparkFrames(start: Point, dx: number, dy: number): Keyframe[] {
  const total = 900;
  return sample(total, sampleTimes(total, [40], 75), (t) => {
    const e = outCubic(t / total);
    return {
      transform: `${translate(start.x + dx * e, start.y + dy * e)} scale(${r(lerp(1, 0.2, e) * 1000) / 1000})`,
      opacity: r(e < 0.12 ? e / 0.12 : 1 - (e - 0.12) / 0.88),
    };
  });
}

/** A coin: waits, appears, falls from above the layer to below it. `p` is 0 to 1 of the rain. */
export function coinFrames(height: number, start: number, fall: number): Keyframe[] {
  const end = Math.min(1, start + fall);
  const y = (p: number): number =>
    p <= start ? 0 : p >= end ? height + 48 : lerp(0, height + 48, (p - start) / (end - start));
  const opacity = (p: number): number =>
    p <= start ? 0 : p >= start + 0.02 ? 1 : (p - start) / 0.02;
  const offsets = [...new Set([0, start, start + 0.02, end, 1])].sort((a, b) => a - b);
  return offsets.map((offset) => ({
    offset,
    transform: translate(0, y(offset)),
    opacity: r(opacity(offset)),
  }));
}

/** Both sets of rays fade in over the first 10 % of the run and out over the last 15 %. */
const raysFade = (p: number): number => (p < 0.1 ? p / 0.1 : p < 0.85 ? 1 : (1 - p) / 0.15);

export function raysFrames(fromDeg: number, toDeg: number): Keyframe[] {
  return [0, 0.1, 0.85, 1].map((offset) => ({
    offset,
    transform: `rotate(${r(lerp(fromDeg, toDeg, offset))}deg)`,
    opacity: raysFade(offset),
  }));
}

/** The glow grows with the fly-in and fades with the rays. `opacity` here is the group's. */
export function glowFrames(recipe: EffectRecipe): Keyframe[] {
  const total = recipe.flyInMs + recipe.holdMs + recipe.flyOutMs;
  const times = sampleTimes(total, [...linspace(0, recipe.flyInMs, 14), total * 0.1, total * 0.85]);
  return sample(total, times, (t) => ({
    transform: `scale(${r(lerp(0.4, 1, outBack(1.3)(clamp01(t / recipe.flyInMs))) * 1000) / 1000})`,
    opacity: r(raysFade(t / total)),
  }));
}
