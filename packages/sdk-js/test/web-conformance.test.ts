/**
 * The web layer drives the SAME EffectScheduler as every other platform, so the shared fixtures
 * (packages/sdk-spec/conformance/effects.json) must hold through it: the trace scenarios, with the
 * DOM checked against the scheduler after every step, and the picture gate with a fake clock.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { GiftEffectEvent } from "../src/core";
import { GiftEffectLayer } from "../src/web";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";

/* eslint-disable @typescript-eslint/no-explicit-any -- fixtures are untyped JSON */
type Json = any;
const fixture: Json = JSON.parse(
  readFileSync(join(process.cwd(), "..", "sdk-spec", "conformance", "effects.json"), "utf8"),
);
const plain = (v: unknown): Json => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

let env: ReturnType<typeof installWebEnv>;
let container: HTMLElement;
beforeEach(() => {
  env = installWebEnv();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
  container = document.createElement("div");
  document.body.appendChild(container);
});
afterEach(() => {
  container.remove();
  vi.useRealTimers();
  env.restore();
});

const effectIds = () =>
  [...container.querySelectorAll("[data-gs-effect]")].map((e) =>
    Number(e.getAttribute("data-gs-effect-id")),
  );
/** The line of the notice the scheduler wrote last: a combo updates its own line in place, which
 * is not always the newest one. */
const whatOf = (d: { giftName: string; receiver?: { name: string } }) =>
  d.receiver ? `sent ${d.giftName} to ${d.receiver.name}` : `sent ${d.giftName}`;
const pill = (of?: { senderName: string; giftName: string; receiver?: { name: string } }) => {
  const all = [...container.querySelectorAll("[data-gs-notice]")] as HTMLElement[];
  if (of !== undefined) {
    const same = all.filter(
      (p) =>
        p.querySelector(".gs-notice-name")?.textContent === of.senderName &&
        p.querySelector(".gs-notice-what")?.textContent === whatOf(of),
    );
    return same[same.length - 1] ?? null;
  }
  return all[all.length - 1] ?? null;
};

describe("web layer: effects.json scheduler scenarios", () => {
  for (const s of fixture.scenarios) {
    it(s.name, () => {
      let clock = 0;
      // The picture gate never fires here (huge wait, no load): the fixture drives started().
      const layer = new GiftEffectLayer(container, {
        pictureWaitMs: 2_000_000_000,
        comboWindowMs: s.options?.comboWindowMs,
        thresholds: s.options?.thresholds,
        quality: s.options?.quality,
        reducedMotion: s.options?.reducedMotion ?? false,
        now: () => clock,
        // The fixtures pin the embedded numbers (spec 13); no background fetch or its timer.
        remoteRecipes: false,
      });
      const scheduler = layer.scheduler;
      let events: string[] = [];
      const ended: number[] = [];
      let noticeDurationMs: number | null = null;
      // Record what the scheduler tells the layer, then pass it on to the layer's own listener.
      const ui = scheduler.listener;
      scheduler.listener = {
        enter: (e) => {
          events.push(`enter:${e.id}`);
          ui.enter?.(e);
        },
        exit: (e) => {
          events.push(`exit:${e.id}`);
          ui.exit?.(e);
        },
        end: (e) => {
          events.push(`end:${e.id}`);
          ended.push(e.id);
          ui.end?.(e);
        },
        notice: (d, ms) => {
          events.push(`notice:${d.id}`);
          noticeDurationMs = ms;
          ui.notice?.(d, ms);
        },
        noticeHide: () => {
          events.push("noticeHide");
          ui.noticeHide?.();
        },
        clear: () => {
          events.push("clear");
          ui.clear?.();
        },
      };

      try {
        s.steps.forEach((step: Json, i: number) => {
          const at = `step ${i + 1}`;
          if (step.play) {
            clock = step.atMs ?? clock;
            const event: GiftEffectEvent = { gift: fixture.gifts[step.play.gift] };
            if (step.play.sender !== undefined) event.sender = step.play.sender;
            if (step.play.quantity !== undefined) event.quantity = step.play.quantity;
            if (step.play.receiver !== undefined) event.receiver = step.play.receiver;
            const id = layer.play(event);
            if (step.returns !== undefined) expect(id, `${at} play() id`).toBe(step.returns);
          } else if (step.started !== undefined) scheduler.started(step.started);
          else if (step.finished !== undefined) scheduler.finished(step.finished);
          else if (step.cancel !== undefined) layer.cancel(step.cancel);
          else if (step.clear) layer.clear();
          else if (step.noticeExpired) scheduler.noticeExpired();
          else if (step.expect) {
            const x = step.expect;
            const notice = scheduler.notice();
            if (x.events) expect(events, `${at} events`).toEqual(x.events);
            if (x.active) {
              expect(
                scheduler.active().map((e) => e.id),
                `${at} active`,
              ).toEqual(x.active);
            }
            if (x.activeTiers) {
              expect(
                scheduler.active().map((e) => e.recipe.tier),
                `${at} tiers`,
              ).toEqual(x.activeTiers);
            }
            if (x.queued) {
              expect(
                scheduler.queued().map((e) => e.id),
                `${at} queued`,
              ).toEqual(x.queued);
            }
            if (x.ended) expect(ended, `${at} ended`).toEqual(x.ended);
            if ("notice" in x) expect(plain(notice.data), `${at} notice`).toEqual(x.notice);
            if ("noticeVisible" in x) {
              expect(notice.visible, `${at} noticeVisible`).toBe(x.noticeVisible);
            }
            if ("noticeOwner" in x) expect(notice.owner, `${at} noticeOwner`).toBe(x.noticeOwner);
            if ("noticeDurationMs" in x) {
              expect(noticeDurationMs, `${at} duration`).toBe(x.noticeDurationMs);
            }
            events = [];

            // What the web layer adds: the page shows exactly what the scheduler says.
            expect(effectIds(), `${at} DOM effects`).toEqual(scheduler.active().map((e) => e.id));
            const p = pill(notice.visible ? notice.data! : undefined);
            if (notice.visible) {
              expect(p?.getAttribute("data-gs-visible"), `${at} DOM notice shown`).toBe("true");
              const d = notice.data!;
              expect(p!.querySelector(".gs-notice-name")!.textContent).toBe(d.senderName);
              expect(p!.querySelector(".gs-notice-what")!.textContent).toBe(whatOf(d));
              expect(p!.querySelector("[data-gs-combo]")?.textContent ?? null).toBe(
                d.count > 1 ? `x${d.count}` : null,
              );
              expect(p!.querySelector("img")?.getAttribute("src") ?? null).toBe(d.image);
              expect(p!.classList.contains("gs-big")).toBe(d.big);
            } else {
              const hidden = p === null || p.getAttribute("data-gs-visible") === "false";
              expect(hidden, `${at} DOM notice hidden`).toBe(true);
            }
          } else throw new Error(`${at}: unknown step ${JSON.stringify(step)}`);
        });
      } finally {
        layer.destroy();
      }
      expect(container.children).toHaveLength(0);
      expect(vi.getTimerCount()).toBe(0);
    });
  }
});

describe("web layer: effects.json pictureGate", () => {
  const gate = fixture.pictureGate;
  gate.cases.forEach((c: Json, i: number) => {
    it(`${c.name}: starts at ${c.startsAtMs} ms`, async () => {
      const layer = new GiftEffectLayer(container, {
        reducedMotion: false,
        pictureWaitMs: c.pictureWaitMs,
      });
      layer.play({
        gift: {
          id: "gate",
          name: "Gate",
          price: 50_000,
          image: c.image ? `https://assets.test/gate/${i}.webp` : null,
          icon: null,
        },
      });
      // The picture loads or fails when the fixture says, on the fake clock.
      const img = container.querySelector("[data-gs-effect] img");
      if (img && c.loadAtMs != null) {
        setTimeout(() => img.dispatchEvent(new Event("load")), c.loadAtMs);
      }
      if (img && c.errorAtMs != null) {
        setTimeout(() => img.dispatchEvent(new Event("error")), c.errorAtMs);
      }
      const started = () => pill() !== null && env.animations.length > 0;
      if (c.startsAtMs === 0) {
        await vi.advanceTimersByTimeAsync(0);
        expect(started()).toBe(true);
      } else {
        await vi.advanceTimersByTimeAsync(c.startsAtMs - 1);
        expect(started(), "not yet").toBe(false);
        await vi.advanceTimersByTimeAsync(1 + gate.toleranceMs);
        expect(started(), "started").toBe(true);
      }
      layer.destroy();
    });
  });
});
