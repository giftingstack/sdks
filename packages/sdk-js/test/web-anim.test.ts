import { describe, expect, it } from "vitest";
import { recipeFor } from "../src/core";
import {
  coinFrames,
  effectDurationMs,
  glowFrames,
  outBack,
  outCubic,
  pictureAt,
  pictureFrames,
  pictureScale,
  sampleTimes,
  sparkFrames,
  springScale,
} from "../src/web/anim";

const geo = { width: 390, height: 780, origin: { x: 195, y: 670.8 }, stage: { x: 195, y: 296.4 } };

describe("web timeline maths", () => {
  it("effect durations are the ones in the spec", () => {
    expect(effectDurationMs(recipeFor("small"))).toBe(1600);
    expect(effectDurationMs(recipeFor("medium"))).toBe(2100);
    expect(effectDurationMs(recipeFor("large", "high"))).toBe(3850);
    expect(effectDurationMs(recipeFor("large", "low"))).toBe(3050);
  });

  it("easings start at 0 and end at 1; back overshoots", () => {
    expect(outBack(1.3)(0)).toBeCloseTo(0);
    expect(outBack(1.3)(1)).toBeCloseTo(1);
    const peak = Math.max(...Array.from({ length: 50 }, (_, i) => outBack(1.3)(i / 49)));
    expect(peak).toBeGreaterThan(1.05);
    expect(outCubic(0.5)).toBeCloseTo(0.875);
  });

  it("the picture flies from the start point to the stage, holds, then leaves", () => {
    const r = recipeFor("medium");
    const at = (t: number) => pictureAt(r, geo, t);
    // t = 0: at the start point (centre of the 100 px box), scale 0.3, invisible.
    expect(at(0)).toMatchObject({ transform: "translate(145px, 620.8px) scale(0.3)", opacity: 0 });
    // End of the fly-in and the whole hold: on the stage at peak scale.
    expect(at(r.flyInMs)).toMatchObject({
      transform: "translate(145px, 246.4px) scale(1.5)",
      opacity: 1,
    });
    expect(at(r.flyInMs + r.holdMs)).toEqual(at(r.flyInMs));
    // End: lifted by 7 % of the height, scale 1.5 x 0.55, gone.
    expect(at(r.flyInMs + r.holdMs + r.flyOutMs)).toMatchObject({
      transform: "translate(145px, 191.8px) scale(0.825)",
      opacity: 0,
    });
  });

  it("keyframe offsets are sorted and within 0..1", () => {
    for (const frames of [
      pictureFrames(recipeFor("large"), geo),
      sparkFrames({ x: 0, y: 0 }, 10, 10),
      coinFrames(780, 0.2, 0.5),
      coinFrames(780, 0.35, 0.65),
      glowFrames(recipeFor("large")),
    ]) {
      const offsets = frames.map((f) => f.offset as number);
      expect(offsets[0]).toBe(0);
      expect(offsets.at(-1)).toBe(1);
      expect(offsets).toEqual([...offsets].sort((a, b) => a - b));
    }
  });

  it("a coin waits, appears and falls past the bottom edge", () => {
    const frames = coinFrames(780, 0.2, 0.5);
    expect(frames[0]).toMatchObject({ offset: 0, opacity: 0, transform: "translate(0px, 0px)" });
    expect(frames.at(-1)).toMatchObject({ opacity: 1, transform: "translate(0px, 828px)" });
  });

  it("the counter pop starts at 1.9, swings below 1 and settles at 1", () => {
    expect(springScale(1.9, 0)).toBeCloseTo(1.9);
    const samples = Array.from({ length: 70 }, (_, i) => springScale(1.9, i * 0.016));
    expect(Math.min(...samples)).toBeLessThan(1);
    expect(springScale(1.9, 1.1)).toBeCloseTo(1, 2);
  });

  it("sampleTimes keeps the ends and the kinks", () => {
    expect(sampleTimes(100, [30], 40)).toEqual([0, 30, 40, 80, 100]);
  });
});

describe("pictureScale", () => {
  it("is 1 on a phone layer, grows in a wide layer and stops at 2", () => {
    expect(pictureScale(390, 700, 2.8)).toBe(1);
    expect(pictureScale(877, 493, 1.5)).toBeGreaterThan(1.2);
    expect(pictureScale(877, 493, 1.5)).toBeLessThan(1.4);
    expect(pictureScale(3000, 2000, 1.5)).toBe(2);
  });

  it("never lets the picture pass 90 percent of the short side", () => {
    // Large gift (2.8 x 100 px) in a 600 x 300 layer: room is 0.9 * 300 / 280.
    expect(pictureScale(600, 300, 2.8)).toBeCloseTo(0.9643, 3);
    expect(pictureScale(600, 300, 2.8, 5)).toBeCloseTo(0.9643, 3);
  });

  it("takes a manual multiplier instead of the automatic one", () => {
    expect(pictureScale(390, 700, 0.9, 1.5)).toBe(1.5);
    expect(pictureScale(1200, 800, 0.9, 1)).toBe(1);
  });
});
