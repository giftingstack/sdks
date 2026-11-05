import { describe, expect, it } from "vitest";
import { EffectScheduler, type GiftEffectEvent } from "../src/core";

const play = (s: EffectScheduler, price: number): number =>
  s.play({
    gift: { id: `g${price}`, name: `g${price}`, price, image: null, icon: null },
    sender: "ayla",
  } as GiftEffectEvent);
const medium = 350;
const small = 10;

/** How many effects are drawn after `n` quick gifts of one price. */
function drawn(price: number, n: number, options: Record<string, unknown> = {}) {
  const s = new EffectScheduler({ now: () => 0 });
  s.setOptions(options as never);
  for (let i = 0; i < n; i++) play(s, price);
  return s.active().length;
}

describe("maxConcurrent (an app option)", () => {
  it("defaults stay 2 medium and 6 small", () => {
    expect(drawn(medium, 6)).toBe(2);
    expect(drawn(small, 9)).toBe(6);
  });

  it("raises the medium cap: six medium gifts draw four", () => {
    expect(drawn(medium, 6, { maxConcurrent: { medium: 4 } })).toBe(4);
  });

  it("changes the small cap too, and leaves the other tier alone", () => {
    expect(drawn(small, 9, { maxConcurrent: { small: 8 } })).toBe(8);
    expect(drawn(medium, 6, { maxConcurrent: { small: 8 } })).toBe(2);
  });

  it("ignores values that are not whole numbers from 1 to 12", () => {
    for (const bad of [0, -1, 2.5, 13, NaN, Infinity, "4" as unknown as number]) {
      expect(drawn(medium, 6, { maxConcurrent: { medium: bad } }), String(bad)).toBe(2);
    }
    expect(drawn(medium, 20, { maxConcurrent: { medium: 12 } })).toBe(12);
  });

  it("the gifts beyond the cap still count in the notice (combo)", () => {
    const s = new EffectScheduler({ now: () => 0 });
    s.setOptions({ maxConcurrent: { medium: 4 } });
    for (let i = 0; i < 6; i++) play(s, medium);
    expect(s.notice().data?.count).toBe(6);
  });
});
