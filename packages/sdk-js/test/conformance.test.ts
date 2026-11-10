/**
 * Runs every fixture in packages/sdk-spec/conformance against this (reference) SDK. Other
 * platforms port this runner; conformance/README.md is the contract it implements.
 */
import { act, cleanup, render, screen } from "@testing-library/react";
import { createElement, createRef } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  EffectScheduler,
  type EffectQuality,
  type EffectTier,
  type Gift,
  type GiftEffectEvent,
  type GiftTransaction,
  type GiftingClient,
  GiftingError,
  GiftTrayController,
  PICTURE_FAILURE_MEMORY_MS,
  PICTURE_MAX_BYTES,
  PictureFailures,
  isPictureUrl,
  type SheetLayout,
  type SheetSnap,
  TraySheetController,
  TrayOpenState,
  SCRIM_FADE_MS,
  SCRIM_OPACITY,
  scrimFadeMs,
  scrimTapOutcome,
  scrimTakesTouches,
  scrimVisible,
  resolveSheetHeights,
  type PlacementInput,
  type PopoverInput,
  positionPopover,
  resolveTrayPlacement,
  contrastRatio,
  darkTheme,
  lightTheme,
  themeFromAccent,
  type GiftTheme,
  type TierThresholds,
  createComboTracker,
  recipeFor,
  sendButtonState,
  tierFor,
} from "../src/core";
import { GiftEffectLayer, type GiftEffectLayerHandle } from "../src/react-native";
import { installPhoneLayout } from "./setup";
import { componentCallStubs } from "./stub-client";
import { type Json, errorFields, fixture, plain, runClientScenario } from "./client-runner";

/** Compares only the keys the fixture names. */
function expectSubset(
  actual: Record<string, unknown>,
  expected: Record<string, unknown>,
  at: string,
) {
  for (const [k, v] of Object.entries(expected)) expect(actual[k], `${at}.${k}`).toEqual(v);
}

// ---------------------------------------------------------------- tiers and recipes

describe("conformance: tiers.json", () => {
  const f = fixture("tiers.json");
  for (const c of f.cases) {
    it(`price ${c.price} ${JSON.stringify(c.thresholds ?? {})} -> ${c.tier}`, () => {
      expect(tierFor(c.price, c.thresholds as Partial<TierThresholds> | undefined)).toBe(c.tier);
    });
  }
  for (const c of f.recipes) {
    it(`recipe ${c.tier}/${c.quality}`, () => {
      const r = recipeFor(c.tier as EffectTier, c.quality as EffectQuality);
      expectSubset(r as unknown as Record<string, unknown>, c.expect, `${c.tier}/${c.quality}`);
    });
  }
});

// ---------------------------------------------------------------- combo

describe("conformance: combo.json", () => {
  for (const s of fixture("combo.json").scenarios) {
    it(s.name, () => {
      const t = createComboTracker(s.windowMs);
      s.steps.forEach((step: Json, i: number) => {
        if (step.reset) return t.reset();
        const [sender, giftId, atMs] = step.hit;
        expect(t.hit(sender, giftId, atMs), `step ${i + 1}`).toBe(step.count);
      });
    });
  }
});

// ---------------------------------------------------------------- client

describe("conformance: client.json", () => {
  for (const s of fixture("client.json").scenarios) {
    it(s.name, () => runClientScenario(s));
  }
});

// ---------------------------------------------------------------- effect scheduler

describe("conformance: effects.json scheduler", () => {
  const f = fixture("effects.json");
  for (const s of f.scenarios) {
    it(s.name, () => {
      let clock = 0;
      const scheduler = new EffectScheduler({
        comboWindowMs: s.options?.comboWindowMs,
        now: () => clock,
      });
      scheduler.setOptions({
        thresholds: s.options?.thresholds,
        quality: s.options?.quality,
        reducedMotion: s.options?.reducedMotion ?? false,
      });
      let events: string[] = [];
      const ended: number[] = [];
      let noticeDurationMs: number | null = null;
      scheduler.listener = {
        enter: (e) => events.push(`enter:${e.id}`),
        exit: (e) => events.push(`exit:${e.id}`),
        end: (e) => {
          events.push(`end:${e.id}`);
          ended.push(e.id);
        },
        notice: (d, ms) => {
          events.push(`notice:${d.id}`);
          noticeDurationMs = ms;
        },
        noticeHide: () => events.push("noticeHide"),
        clear: () => events.push("clear"),
      };

      s.steps.forEach((step: Json, i: number) => {
        const at = `step ${i + 1}`;
        if (step.play) {
          clock = step.atMs ?? clock;
          const event: GiftEffectEvent = { gift: f.gifts[step.play.gift] };
          if (step.play.sender !== undefined) event.sender = step.play.sender;
          if (step.play.quantity !== undefined) event.quantity = step.play.quantity;
          if (step.play.receiver !== undefined) event.receiver = step.play.receiver;
          const id = scheduler.play(event);
          if (step.returns !== undefined) expect(id, `${at} play() id`).toBe(step.returns);
        } else if (step.started !== undefined) scheduler.started(step.started);
        else if (step.finished !== undefined) scheduler.finished(step.finished);
        else if (step.cancel !== undefined) scheduler.cancel(step.cancel);
        else if (step.clear) scheduler.clear();
        else if (step.noticeExpired) scheduler.noticeExpired();
        else if (step.expect) {
          const x = step.expect;
          const notice = scheduler.notice();
          if (x.events) expect(events, `${at} events`).toEqual(x.events);
          if (x.active)
            expect(
              scheduler.active().map((e) => e.id),
              `${at} active`,
            ).toEqual(x.active);
          if (x.activeTiers) {
            expect(
              scheduler.active().map((e) => e.recipe.tier),
              `${at} activeTiers`,
            ).toEqual(x.activeTiers);
          }
          if (x.queued)
            expect(
              scheduler.queued().map((e) => e.id),
              `${at} queued`,
            ).toEqual(x.queued);
          if (x.ended) expect(ended, `${at} ended`).toEqual(x.ended);
          if ("notice" in x) expect(plain(notice.data), `${at} notice`).toEqual(x.notice);
          if ("noticeVisible" in x)
            expect(notice.visible, `${at} noticeVisible`).toBe(x.noticeVisible);
          if ("noticeOwner" in x) expect(notice.owner, `${at} noticeOwner`).toBe(x.noticeOwner);
          if ("noticeDurationMs" in x) {
            expect(noticeDurationMs, `${at} noticeDurationMs`).toBe(x.noticeDurationMs);
          }
          events = [];
        } else throw new Error(`${at}: unknown step ${JSON.stringify(step)}`);
      });
    });
  }
});

// ---------------------------------------------------------------- picture gate (rendered)

describe("conformance: effects.json pictureGate", () => {
  /** Pictures load or fail when the fixture says, on the fake clock. */
  const plans = new Map<string, { loadAtMs: number | null; errorAtMs: number | null }>();
  class FakeImage {
    onload: ((e: unknown) => void) | null = null;
    onerror: ((e: unknown) => void) | null = null;
    naturalWidth = 512;
    naturalHeight = 512;
    set src(uri: string) {
      const plan = plans.get(uri);
      if (plan?.loadAtMs != null) setTimeout(() => this.onload?.({}), plan.loadAtMs);
      if (plan?.errorAtMs != null) setTimeout(() => this.onerror?.({}), plan.errorAtMs);
    }
  }

  let restore = () => {};
  beforeEach(() => {
    restore = installPhoneLayout();
    vi.stubGlobal("Image", FakeImage);
    vi.useFakeTimers({
      toFake: [
        "setTimeout",
        "clearTimeout",
        "requestAnimationFrame",
        "cancelAnimationFrame",
        "performance",
        "Date",
      ],
    });
  });
  afterEach(() => {
    cleanup();
    vi.useRealTimers();
    restore();
  });
  const advance = (ms: number) =>
    act(async () => {
      await vi.advanceTimersByTimeAsync(ms);
    });
  const started = () => screen.queryByTestId("gift-notice") !== null;

  const gate = fixture("effects.json").pictureGate;
  gate.cases.forEach((c: Json, i: number) => {
    it(`${c.name}: starts at ${c.startsAtMs} ms`, async () => {
      const url = `https://assets.test/gate/${i}.webp`;
      plans.set(url, { loadAtMs: c.loadAtMs, errorAtMs: c.errorAtMs });
      const ref = createRef<GiftEffectLayerHandle>();
      render(
        createElement(GiftEffectLayer, {
          ref,
          reducedMotion: false,
          pictureWaitMs: c.pictureWaitMs,
        }),
      );
      await advance(10);
      act(() => {
        ref.current!.play({
          gift: {
            id: "gate",
            name: "Gate",
            price: 50_000,
            image: c.image ? url : null,
            icon: null,
          },
        });
      });
      if (c.startsAtMs === 0) {
        await advance(0);
        expect(started()).toBe(true);
        return;
      }
      await advance(c.startsAtMs - 1);
      expect(started(), "not yet").toBe(false);
      await advance(1 + gate.toleranceMs);
      expect(started(), "started").toBe(true);
    });
  });
});

// ---------------------------------------------------------------- tray controller

describe("conformance: tray.json controller", () => {
  const f = fixture("tray.json");
  const flush = async () => {
    for (let i = 0; i < 3; i++) await new Promise((r) => setTimeout(r, 0));
  };

  for (const s of f.scenarios) {
    it(s.name, async () => {
      const pending: {
        method: string;
        resolve: (v: unknown) => void;
        reject: (e: unknown) => void;
      }[] = [];
      const calls: { method: string; args: unknown }[] = [];
      const call = <T>(method: string, args?: unknown) =>
        new Promise<T>((resolve, reject) => {
          calls.push({ method, args: plain(args) });
          pending.push({ method, resolve: resolve as (v: unknown) => void, reject });
        });
      const client: GiftingClient = {
        getGifts: () => call<Gift[]>("getGifts"),
        getMe: () => call("getMe"),
        getReceivedGifts: (user) => call("getReceivedGifts", { user }),
        ...componentCallStubs,
        sendGift: (input) => call<GiftTransaction>("sendGift", input),
      };
      const played: { id: number; event: unknown }[] = [];
      const cancelled: number[] = [];
      const prefetched: string[] = [];
      const sent: string[] = [];
      const errors: string[] = [];
      const player = {
        play: (event: GiftEffectEvent) => {
          const id = played.length + 1;
          played.push({ id, event: plain(event) });
          return id;
        },
        cancel: (id: number) => cancelled.push(id),
      };
      const o = s.options ?? {};
      const controller = new GiftTrayController({
        client,
        receiver: o.receiver,
        reference: o.reference,
        playOn: o.playOn,
        effects: o.effects === false ? undefined : () => player,
        prefetch: (url) => prefetched.push(url),
        onSent: (tx) => sent.push(tx.id),
        onError: (e) => errors.push(e.type),
      });

      const take = (method: string, at: string) => {
        const idx = pending.findIndex((p) => p.method === method);
        expect(idx, `${at}: no pending ${method}`).toBeGreaterThanOrEqual(0);
        return pending.splice(idx, 1)[0]!;
      };
      const value = (method: string, v: Json) => {
        if (method === "getGifts") return (v as string[]).map((k) => ({ ...f.gifts[k] }));
        if (method === "sendGift" && typeof v === "string") return f.transactions[v];
        return v;
      };
      const toError = (e: Json) =>
        e.plain !== undefined
          ? new Error(e.plain)
          : new GiftingError(e.status, e.type, e.message, e.requestId ?? null);

      for (const [i, step] of (s.steps as Json[]).entries()) {
        const at = `step ${i + 1}`;
        if (step.mount) void controller.refresh();
        else if (step.refresh) void controller.refresh();
        else if (step.dispose) controller.dispose();
        else if (step.send) void controller.send({ ...f.gifts[step.send] });
        else if (step.resolve)
          take(step.resolve.method, at).resolve(value(step.resolve.method, step.resolve.value));
        else if (step.reject) take(step.reject.method, at).reject(toError(step.reject.error));
        else if (step.expect) {
          const x = step.expect;
          const st = controller.getState();
          if ("balance" in x) expect(st.balance, `${at} balance`).toBe(x.balance);
          if ("user" in x) expect(st.user, `${at} user`).toBe(x.user);
          if ("loading" in x) expect(st.loading, `${at} loading`).toBe(x.loading);
          if ("testMode" in x) expect(st.testMode, `${at} testMode`).toBe(x.testMode);
          if (x.gifts)
            expect(
              st.gifts.map((g) => g.id),
              `${at} gifts`,
            ).toEqual(x.gifts);
          if ("error" in x) {
            if (x.error === null) expect(st.error, `${at} error`).toBeNull();
            else expectSubset(errorFields(st.error!), x.error, `${at} error`);
          }
          if (x.played) expect(played, `${at} played`).toEqual(x.played);
          if ("playedCount" in x) expect(played.length, `${at} playedCount`).toBe(x.playedCount);
          if (x.cancelled) expect(cancelled, `${at} cancelled`).toEqual(x.cancelled);
          if (x.sent) expect(sent, `${at} sent`).toEqual(x.sent);
          if (x.errors) expect(errors, `${at} errors`).toEqual(x.errors);
          if (x.prefetched) expect(prefetched, `${at} prefetched`).toEqual(x.prefetched);
          if (x.pending)
            expect(
              pending.map((p) => p.method),
              `${at} pending`,
            ).toEqual(x.pending);
          if (x.lastCall) expect(calls[calls.length - 1], `${at} lastCall`).toEqual(x.lastCall);
          if (x.callCount) {
            const counts: Record<string, number> = {};
            for (const c of calls) counts[c.method] = (counts[c.method] ?? 0) + 1;
            expect(counts, `${at} callCount`).toEqual(x.callCount);
          }
        } else throw new Error(`${at}: unknown step ${JSON.stringify(step)}`);
        await flush();
      }
    });
  }
});

describe("conformance: tray.json sendButton", () => {
  for (const c of fixture("tray.json").sendButton.cases) {
    it(c.name, () => {
      expect(sendButtonState(c.input)).toEqual(c.expect);
    });
  }
});

// ---------------------------------------------------------------- tray sheet

describe("conformance: sheet.json heights", () => {
  for (const c of fixture("sheet.json").heights) {
    it(c.name, () => {
      expect(resolveSheetHeights(c.layout as SheetLayout)).toEqual(c.expect);
    });
  }
});

describe("conformance: sheet.json controller", () => {
  const f = fixture("sheet.json");
  const layoutOf = (v: Json): SheetLayout => (typeof v === "string" ? f.layouts[v] : v);

  for (const s of f.scenarios) {
    it(s.name, () => {
      const snapChanges: string[] = [];
      const sheet = new TraySheetController({
        initialSnap: s.initialSnap as SheetSnap | undefined,
        layout: layoutOf(s.layout),
        onSnapChange: (snap) => snapChanges.push(snap),
      });
      for (const [i, step] of (s.steps as Json[]).entries()) {
        const at = `${s.name}, step ${i + 1}`;
        let returned: unknown;
        if (step.dragStart) sheet.dragStart();
        else if ("drag" in step) sheet.drag(step.drag);
        else if ("release" in step) returned = sheet.release(step.release);
        else if (step.cancel) sheet.cancel();
        else if (step.snapTo) sheet.snapTo(step.snapTo);
        else if (step.toggle) returned = sheet.toggle();
        else if ("step" in step) returned = sheet.step(step.step);
        else if (step.layout) sheet.setLayout(layoutOf(step.layout));
        else if (step.scrollOwner)
          returned = sheet.scrollOwner(step.scrollOwner.dy, step.scrollOwner.gridScrollTop);
        else if (step.expect) {
          const { snapChanges: changes, ...rest } = step.expect;
          expectSubset(sheet.getState() as unknown as Record<string, unknown>, rest, at);
          if (changes) expect(snapChanges, `${at} snapChanges`).toEqual(changes);
        } else throw new Error(`${at}: unknown step ${JSON.stringify(step)}`);
        if ("returns" in step) expect(returned, `${at} returns`).toBe(step.returns);
      }
    });
  }
});

// ---------------------------------------------------------------- tray scrim and open state

describe("conformance: tray-scrim.json", () => {
  const f = fixture("tray-scrim.json");
  it("constants", () => {
    expect(SCRIM_FADE_MS).toBe(f.constants.fadeMs);
    expect(SCRIM_OPACITY).toBe(f.constants.opacity);
  });
  for (const [i, c] of (f.visible as Json[]).entries()) {
    it(`visible #${i + 1}: ${JSON.stringify(c)}`, () => {
      const { expect: want, ...state } = c;
      expect(scrimVisible(state as Parameters<typeof scrimVisible>[0])).toBe(want);
    });
  }
  for (const [i, c] of (f.takesTouches as Json[]).entries()) {
    it(`takesTouches #${i + 1}: ${JSON.stringify(c)}`, () => {
      const { expect: want, ...state } = c;
      expect(scrimTakesTouches(state as Parameters<typeof scrimTakesTouches>[0])).toBe(want);
    });
  }
  for (const c of f.fade as Json[]) {
    it(`fade: ${c.name}`, () => expect(scrimFadeMs(c.reducedMotion)).toBe(c.ms));
  }
  for (const [i, c] of (f.tap as Json[]).entries()) {
    it(`tap #${i + 1}: ${JSON.stringify(c)}`, () => {
      const { expect: want, ...state } = c;
      expect(scrimTapOutcome(state as Parameters<typeof scrimTapOutcome>[0])).toBe(want);
    });
  }
  for (const s of f.open as Json[]) {
    it(`open: ${s.name}`, () => {
      const changes: boolean[] = [];
      const o = new TrayOpenState({ open: s.open, onChange: (v) => changes.push(v) });
      for (const [i, step] of (s.steps as Json[]).entries()) {
        const at = `${s.name}, step ${i + 1}`;
        if (step.call) {
          const returned = o[step.call as "open" | "close" | "toggle"]();
          expect(returned, `${at} returns`).toBe(step.returns);
        } else if (step.expect) {
          expect(o.isOpen(), `${at} open`).toBe(step.expect.open);
          expect(changes, `${at} changes`).toEqual(step.expect.changes);
        } else throw new Error(`${at}: unknown step`);
      }
    });
  }
});

// ---------------------------------------------------------------- theming

describe("conformance: theme.json", () => {
  const f = fixture("theme.json");
  for (const c of f.contrast) {
    it(`contrast ${c.a} on ${c.b} = ${c.ratio}`, () => {
      expect(Math.round(contrastRatio(c.a, c.b) * 100) / 100).toBe(c.ratio);
    });
  }
  const check = (t: GiftTheme, at: string) => {
    for (const r of f.rules) {
      const ratio = contrastRatio(t[r.fg as keyof GiftTheme], t[r.bg as keyof GiftTheme]);
      expect(ratio, `${at}: ${r.fg} on ${r.bg}`).toBeGreaterThanOrEqual(r.min);
    }
  };
  const presets: Record<string, GiftTheme> = { darkTheme, lightTheme };
  for (const name of f.presets) {
    it(`preset ${name} meets every rule`, () => check(presets[name]!, name));
  }
  for (const a of f.accents) {
    for (const mode of f.modes) {
      it(`themeFromAccent(${a.accent}, ${mode}) keeps the accent and meets every rule`, () => {
        const t = themeFromAccent(a.accent, mode);
        expect(t.accent).toBe(a.normalized);
        check(t, `${a.accent}/${mode}`);
      });
    }
  }
  for (const bad of f.invalid) {
    it(`themeFromAccent rejects ${JSON.stringify(bad)}`, () => {
      expect(() => themeFromAccent(bad, "dark")).toThrow();
    });
  }
});

// ---------------------------------------------------------------- placement (web only)

describe("conformance: placement.json", () => {
  const f = fixture("placement.json");
  for (const c of f.resolve) {
    it(`resolve: ${c.name}`, () => {
      expect(resolveTrayPlacement(c.input as PlacementInput)).toBe(c.expect);
    });
  }
  for (const c of f.popover) {
    it(`popover: ${c.name}`, () => {
      expect(positionPopover(c.input as PopoverInput)).toEqual(c.expect);
    });
  }
});

// ---------------------------------------------------------------- pictures

describe("conformance: pictures.json", () => {
  const f = fixture("pictures.json");
  it("constants", () => {
    expect(PICTURE_MAX_BYTES).toBe(f.maxBytes);
    expect(PICTURE_FAILURE_MEMORY_MS).toBe(f.failureMemoryMs);
  });
  for (const c of f.urls) {
    it(`isPictureUrl(${JSON.stringify(c.url)}) = ${c.allowed}`, () => {
      expect(isPictureUrl(c.url)).toBe(c.allowed);
    });
  }
  for (const c of f.dataUrlSize.cases) {
    it(`a data:image URL of ${c.totalChars} characters: allowed ${c.allowed}`, () => {
      const prefix = "data:image/png;base64,";
      expect(isPictureUrl(prefix + "A".repeat(c.totalChars - prefix.length))).toBe(c.allowed);
    });
  }
  for (const s of f.failures) {
    it(s.name, () => {
      const memory = new PictureFailures(() => 0);
      for (const [i, step] of (s.steps as Json[]).entries()) {
        const at = `${s.name} step ${i + 1}`;
        if (step.fail) memory.mark(step.fail, step.atMs);
        else if (step.failMany) {
          for (let n = 0; n < step.failMany.count; n++)
            memory.mark(`${step.failMany.prefix}${n}`, step.atMs);
        } else if (step.failed) {
          for (const [url, want] of Object.entries(step.failed))
            expect(memory.has(url, step.atMs), `${at} ${url}`).toBe(want);
        } else throw new Error(`${at}: unknown step ${JSON.stringify(step)}`);
      }
    });
  }
});
