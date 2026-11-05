/**
 * Runs wall.json, away.json and leaderboard.json (SPEC sections 14-16) against the reference
 * core. Other platforms port this runner; conformance/README.md is the contract it implements.
 */
import { describe, expect, it } from "vitest";
import {
  AwayController,
  type AwayGroup,
  type AwaySummary,
  type GiftEffectEvent,
  GiftWallLoader,
  GiftingError,
  type GiftWallQueryItem,
  type Leaderboard,
  LeaderboardController,
  RANK_COLORS,
  type ReceivedGift,
  type WallChip,
  awaySenderLabel,
  contrastRatio,
  darkTheme,
  defaultTheme,
  formatCount,
  LEADERBOARD_MIN_POLL_MS,
  leaderboardPollMs,
  leaderboardRankLabel,
  lightTheme,
  pinnedMe,
  planAwayReplay,
  wallChips,
} from "../src/core";
import {
  type Json,
  fixture,
  plain,
  runClientScenario,
  scenarioBodyProblems,
} from "./client-runner";

/**
 * A virtual clock with timers. `advance(ms)` fires every timer due up to the new time, in due
 * order (ties: the order they were set), with the clock set to each timer's due time.
 */
class FakeClock {
  now = 0;
  private seq = 0;
  private timers: { id: number; due: number; fn: () => void }[] = [];

  setTimeout = (fn: () => void, ms: number): number => {
    const id = ++this.seq;
    this.timers.push({ id, due: this.now + Math.max(0, ms), fn });
    return id;
  };

  clearTimeout = (id: unknown): void => {
    this.timers = this.timers.filter((t) => t.id !== id);
  };

  private next(limit: number) {
    let best: (typeof this.timers)[number] | undefined;
    for (const t of this.timers) {
      if (t.due <= limit && (!best || t.due < best.due || (t.due === best.due && t.id < best.id))) {
        best = t;
      }
    }
    return best;
  }

  /** Fire the timers due now. */
  runDue(): void {
    for (let t = this.next(this.now); t; t = this.next(this.now)) {
      this.clearTimeout(t.id);
      t.fn();
    }
  }

  advance(ms: number): void {
    const target = this.now + ms;
    for (let t = this.next(target); t; t = this.next(target)) {
      this.now = t.due;
      this.clearTimeout(t.id);
      t.fn();
    }
    this.now = target;
  }
}

/** Lets pending promise work run, then fires timers that became due, until nothing changes. */
async function settle(clock: FakeClock): Promise<void> {
  for (let i = 0; i < 3; i++) {
    for (let j = 0; j < 20; j++) await Promise.resolve();
    clock.runDue();
  }
}

const toError = (e: Json) => new GiftingError(e.status, e.type, e.message, e.requestId ?? null);

/** A client whose every call waits until a step settles it (oldest call of a method first). */
function scriptedCalls() {
  const pending: { method: string; resolve: (v: unknown) => void; reject: (e: unknown) => void }[] =
    [];
  const calls: { method: string; args: unknown }[] = [];
  const call = <T>(method: string, args: unknown) =>
    new Promise<T>((resolve, reject) => {
      calls.push({ method, args: plain(args) });
      pending.push({ method, resolve: resolve as (v: unknown) => void, reject });
    });
  const take = (method: string, at: string) => {
    const idx = pending.findIndex((p) => p.method === method);
    expect(idx, `${at}: no pending ${method}`).toBeGreaterThanOrEqual(0);
    return pending.splice(idx, 1)[0]!;
  };
  return { pending, calls, call, take };
}

// ================================================================ wall.json

describe("conformance: wall.json", () => {
  const f = fixture("wall.json");
  const received = (items: Json[]): ReceivedGift[] =>
    items.map((i) => ({ gift: { ...f.gifts[i.gift] }, count: i.count }));
  const compact = (list: ReceivedGift[]) => list.map((r) => ({ gift: r.gift.id, count: r.count }));
  const chipJson = (c: WallChip) =>
    c.type === "gift"
      ? { gift: c.gift.id, count: c.count }
      : { overflow: c.count, hidden: c.hidden };

  describe("chips", () => {
    for (const c of f.chips) {
      it(c.name, () => {
        expect(wallChips(received(c.items), c.options).map(chipJson)).toEqual(c.expect);
      });
    }
  });

  describe("formatCount", () => {
    for (const c of f.formatCount) {
      it(`${c.n} ${JSON.stringify(c.labels ?? {})} -> ${c.expect}`, () => {
        expect(formatCount(c.n, c.labels)).toBe(c.expect);
      });
    }
  });

  describe("loader", () => {
    for (const s of f.loader) {
      it(s.name, async () => {
        const clock = new FakeClock();
        const batches: {
          items: GiftWallQueryItem[];
          resolve: (v: unknown) => void;
          reject: (e: unknown) => void;
        }[] = [];
        const loader = new GiftWallLoader({
          now: () => clock.now,
          setTimeout: clock.setTimeout,
          query: (items) =>
            new Promise((resolve, reject) => {
              batches.push({
                items: plain(items),
                resolve: resolve as (v: unknown) => void,
                reject,
              });
            }),
        });
        const settled: Record<string, { ok: boolean; value: unknown }> = {};
        const order: string[] = [];
        for (const [i, step] of (s.steps as Json[]).entries()) {
          const at = `step ${i + 1}`;
          if (step.load) {
            const id = step.id as string;
            order.push(id);
            loader.load(step.load[0], step.load[1]).then(
              (v) => (settled[id] = { ok: true, value: compact(v) }),
              (e: GiftingError) => (settled[id] = { ok: false, value: e.type }),
            );
          } else if (step.advance !== undefined) clock.advance(step.advance);
          else if (step.invalidate) loader.invalidate(step.invalidate[0], step.invalidate[1]);
          else if (step.respond) {
            const b = batches[step.respond.batch - 1];
            expect(b, `${at}: batch ${step.respond.batch}`).toBeDefined();
            b!.resolve(
              b!.items.map((item, k) => ({
                receiver: item.receiver,
                reference: item.reference ?? null,
                gifts: received(step.respond.walls[k]),
              })),
            );
          } else if (step.fail) {
            batches[step.fail.batch - 1]!.reject(toError(step.fail.error));
          } else if (step.expect) {
            const x = step.expect;
            if (x.batches)
              expect(
                batches.map((b) => b.items),
                `${at} batches`,
              ).toEqual(x.batches);
            if (x.waiting)
              expect(
                order.filter((id) => !settled[id]),
                `${at} waiting`,
              ).toEqual(x.waiting);
            for (const [id, v] of Object.entries(x.resolved ?? {})) {
              expect(settled[id], `${at} resolved ${id}`).toEqual({ ok: true, value: v });
            }
            for (const [id, v] of Object.entries(x.rejected ?? {})) {
              expect(settled[id], `${at} rejected ${id}`).toEqual({ ok: false, value: v });
            }
          } else throw new Error(`${at}: unknown step ${JSON.stringify(step)}`);
          await settle(clock);
        }
      });
    }
  });

  describe("client", () => {
    for (const s of f.client) it(s.name, () => runClientScenario(s));
  });
});

// ================================================================ away.json

describe("conformance: away.json", () => {
  const f = fixture("away.json");
  const groups = (list: Json[]): AwayGroup[] =>
    list.map((g) => ({ ...g, gift: { ...f.gifts[g.gift] } }));
  const summary = (key: string): AwaySummary => {
    const s = f.summaries[key];
    return { ...s, groups: groups(s.groups) };
  };

  describe("plan", () => {
    for (const c of f.plan) {
      it(c.name, () => {
        const names = (c.names ?? {}) as Record<string, string>;
        const plan = planAwayReplay(groups(c.groups), {
          ...c.options,
          resolveName: (u) => names[u] ?? u,
        });
        expect(plan.endMs, "endMs").toBe(c.expect.endMs);
        expect(plan.items.length, "items").toBe(c.expect.items.length);
        plan.items.forEach((item, i) => {
          const actual = {
            gift: item.event.gift.id,
            name: item.event.gift.name,
            price: item.event.gift.price,
            image: item.event.gift.image,
            icon: item.event.gift.icon,
            atMs: item.atMs,
            durationMs: item.durationMs,
            tier: item.tier,
            quantity: item.event.quantity,
            sender: item.event.sender,
          };
          for (const [k, v] of Object.entries(c.expect.items[i] as Record<string, unknown>)) {
            expect((actual as Record<string, unknown>)[k], `item ${i + 1}.${k}`).toEqual(v);
          }
        });
      });
    }
  });

  describe("senderLabel", () => {
    for (const c of f.senderLabel) {
      it(`${JSON.stringify(c.names)} x${c.senderCount} ${JSON.stringify(c.labels ?? {})} -> ${c.expect}`, () => {
        expect(awaySenderLabel(c.names, c.senderCount, c.labels)).toBe(c.expect);
      });
    }
  });

  describe("controller", () => {
    for (const s of f.controller) {
      it(s.name, async () => {
        const clock = new FakeClock();
        const { pending, calls, call, take } = scriptedCalls();
        const played: Json[] = [];
        const errors: string[] = [];
        let shown = 0;
        let done = 0;
        const o = s.options ?? {};
        const player = {
          play: (event: GiftEffectEvent) => {
            played.push({
              atMs: clock.now,
              gift: event.gift.id,
              quantity: event.quantity,
              sender: event.sender,
            });
            return played.length;
          },
        };
        const controller = new AwayController({
          client: {
            getAway: (query) => call<AwaySummary>("getAway", query ?? {}),
            ackAway: (cursor) => call<void>("ackAway", { cursor }),
          },
          effects: o.effects === false ? undefined : () => player,
          reducedMotion: o.reducedMotion ? () => true : undefined,
          ackOn: o.ackOn,
          maxGroups: o.maxGroups,
          maxEffects: o.maxEffects,
          budgetMs: o.budgetMs,
          onShow: () => shown++,
          onDone: () => done++,
          onError: (e) => errors.push(e.type),
          now: () => clock.now,
          setTimeout: clock.setTimeout,
          clearTimeout: clock.clearTimeout,
        });
        for (const [i, step] of (s.steps as Json[]).entries()) {
          const at = `step ${i + 1}`;
          if (step.check) void controller.check();
          else if (step.foreground) void controller.foreground();
          else if (step.start) controller.start();
          else if (step.dismiss) controller.dismiss();
          else if (step.ack) void controller.ack();
          else if (step.dispose) controller.dispose();
          else if (step.advance !== undefined) clock.advance(step.advance);
          else if (step.resolve) {
            const { method, value } = step.resolve;
            take(method, at).resolve(method === "getAway" ? summary(value) : undefined);
          } else if (step.reject) take(step.reject.method, at).reject(toError(step.reject.error));
          else if (step.expect) {
            const x = step.expect;
            const st = controller.getState();
            if ("status" in x) expect(st.status, `${at} status`).toBe(x.status);
            if ("summaryCursor" in x)
              expect(st.summary?.cursor ?? null, `${at} summaryCursor`).toBe(x.summaryCursor);
            if ("planEndMs" in x) expect(st.plan?.endMs, `${at} planEndMs`).toBe(x.planEndMs);
            if (x.played) expect(played, `${at} played`).toEqual(x.played);
            if (x.calls) expect(calls, `${at} calls`).toEqual(x.calls);
            if (x.pending)
              expect(
                pending.map((p) => p.method),
                `${at} pending`,
              ).toEqual(x.pending);
            if ("shown" in x) expect(shown, `${at} shown`).toBe(x.shown);
            if ("done" in x) expect(done, `${at} done`).toBe(x.done);
            if (x.errors) expect(errors, `${at} errors`).toEqual(x.errors);
          } else throw new Error(`${at}: unknown step ${JSON.stringify(step)}`);
          await settle(clock);
        }
      });
    }
  });

  describe("client", () => {
    for (const s of f.client) it(s.name, () => runClientScenario(s));

    it("the body check rejects a gift id where the API sends the gift object (SPEC 15.1)", () => {
      const s = structuredClone(
        f.client.find((c: Json) => c.call.method === "getAway" && c.result.groups.length > 0),
      );
      expect(scenarioBodyProblems(s)).toEqual([]);
      s.exchanges[0].response.body.groups[0].gift = s.exchanges[0].response.body.groups[0].gift.id;
      expect(scenarioBodyProblems(s)).toEqual([
        `exchange 1 body.groups[0].gift: ${JSON.stringify(s.result.groups[0].gift.id)} is not an object`,
      ]);
    });
  });
});

// ================================================================ leaderboard.json

describe("conformance: leaderboard.json", () => {
  const f = fixture("leaderboard.json");

  describe("pollMs", () => {
    it("minPollMs", () => expect(LEADERBOARD_MIN_POLL_MS).toBe(f.pollMs.minPollMs));
    for (const c of f.pollMs.cases) {
      it(`${c.refreshIntervalMs} -> ${c.expect}`, () => {
        expect(leaderboardPollMs(c.refreshIntervalMs)).toBe(c.expect);
      });
    }
  });

  describe("rankLabel", () => {
    for (const c of f.rankLabel) {
      it(`${c.rank} ${JSON.stringify(c.labels ?? {})} -> ${c.expect}`, () => {
        expect(leaderboardRankLabel(c.rank, c.labels)).toBe(c.expect);
      });
    }
  });

  describe("pin", () => {
    for (const c of f.pin) {
      it(c.name, () => {
        const board = {
          board: "senders",
          period: "week",
          metric: c.metric,
          label: "2026-W41",
          starts_at: null,
          ends_at: null,
          as_of: "2026-10-11T07:30:00.000Z",
          data: c.data,
          has_more: false,
          me: c.me,
        } as Leaderboard;
        expect(pinnedMe(board, c.limit) !== null).toBe(c.expect);
        if (c.expect) expect(pinnedMe(board, c.limit)).toEqual(c.me);
      });
    }
  });

  it("rankColors: the medal tokens and their contrast with noticeBigText", () => {
    const rc = f.rankColors;
    expect({ ...RANK_COLORS }).toEqual(rc.tokens);
    const themes = { defaultTheme, darkTheme, lightTheme } as const;
    for (const name of rc.themes as (keyof typeof themes)[]) {
      const text = themes[name][rc.text as "noticeBigText"];
      for (const [token, color] of Object.entries(rc.tokens as Record<string, string>)) {
        expect(contrastRatio(color, text), `${name}.${rc.text} on ${token}`).toBeGreaterThanOrEqual(
          rc.min,
        );
      }
    }
  });

  describe("controller", () => {
    for (const s of f.controller) {
      it(s.name, async () => {
        const clock = new FakeClock();
        const { pending, calls, call, take } = scriptedCalls();
        const errors: string[] = [];
        const o = s.options ?? {};
        const controller = new LeaderboardController({
          client: {
            getLeaderboard: (board, query) => call<Leaderboard>("getLeaderboard", { board, query }),
          },
          board: o.board,
          periods: o.periods,
          initialPeriod: o.initialPeriod,
          metric: o.metric,
          limit: o.limit,
          includeMe: o.includeMe,
          now: () => clock.now,
          onError: (e) => errors.push(e.type),
        });
        for (const [i, step] of (s.steps as Json[]).entries()) {
          const at = `step ${i + 1}`;
          if (step.start) controller.start();
          else if (step.setPeriod) controller.setPeriod(step.setPeriod);
          else if (step.setMetric) controller.setMetric(step.setMetric);
          else if (step.refresh) controller.refresh();
          else if (step.dispose) controller.dispose();
          else if (step.advance !== undefined) clock.advance(step.advance);
          else if (step.resolve)
            take(step.resolve.method, at).resolve(structuredClone(f.boards[step.resolve.value]));
          else if (step.reject) take(step.reject.method, at).reject(toError(step.reject.error));
          else if (step.expect) {
            const x = step.expect;
            const st = controller.getState();
            if ("status" in x) expect(st.status, `${at} status`).toBe(x.status);
            if ("period" in x) expect(st.period, `${at} period`).toBe(x.period);
            if ("periods" in x) expect(st.periods, `${at} periods`).toEqual(x.periods);
            if ("metric" in x) expect(st.metric, `${at} metric`).toBe(x.metric);
            if ("rows" in x)
              expect(st.data?.data.map((r) => r.user) ?? null, `${at} rows`).toEqual(x.rows);
            if ("asOf" in x) expect(st.data?.as_of ?? null, `${at} asOf`).toBe(x.asOf);
            if ("refreshing" in x) expect(st.refreshing, `${at} refreshing`).toBe(x.refreshing);
            if ("error" in x) expect(st.error?.type ?? null, `${at} error`).toBe(x.error);
            if ("pinned" in x) expect(st.pinned?.user ?? null, `${at} pinned`).toBe(x.pinned);
            if (x.calls) expect(calls, `${at} calls`).toEqual(x.calls);
            if ("pending" in x) expect(pending.length, `${at} pending`).toBe(x.pending);
            if (x.errors) expect(errors, `${at} errors`).toEqual(x.errors);
          } else throw new Error(`${at}: unknown step ${JSON.stringify(step)}`);
          await settle(clock);
        }
      });
    }
  });

  describe("client", () => {
    for (const s of f.client) it(s.name, () => runClientScenario(s));
  });
});
