/**
 * Runs the five rooms-*.json fixtures (SPEC sections 17-18) against the reference core. Other
 * platforms port this runner; conformance/README.md ("Rooms fixtures") is the contract.
 */
import { describe, expect, it } from "vitest";
import {
  type Gift,
  type RoomBattle,
  RoomClient,
  type RoomClientOptions,
  RoomEventFilter,
  type RoomGiftEvent,
  type RoomGiftMessage,
  type RoomSocketHandlers,
  parseRoomFrame,
  roomGiftToEffect,
  roomHelloFrame,
  roomRetryDecision,
  roomTokenUser,
  roomUrl,
} from "../src/core";
import { type Json, fixture, plain } from "./client-runner";

/** Virtual clock: `advance` fires due timers in due order (ties: set order) at their due time. */
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

async function settle(clock: FakeClock): Promise<void> {
  for (let i = 0; i < 3; i++) {
    for (let j = 0; j < 20; j++) await Promise.resolve();
    clock.runDue();
  }
}

/** A JSON frame object is sent as its JSON text; `text` is sent as is. */
const frameText = (c: Json): string => (c.text !== undefined ? c.text : JSON.stringify(c.frame));

// ================================================================ rooms-protocol.json

describe("conformance: rooms-protocol.json", () => {
  const f = fixture("rooms-protocol.json");
  describe("parse", () => {
    for (const c of f.parse) {
      it(c.name, () => {
        expect(plain(parseRoomFrame(frameText(c)))).toEqual(c.expect);
      });
    }
  });
  it("hello", () => {
    for (const c of f.hello) expect(JSON.parse(roomHelloFrame(c.last))).toEqual(c.expect);
  });
  it("url", () => {
    for (const c of f.url) expect(roomUrl(c.room, c.baseUrl)).toBe(c.expect);
  });
  it("tokenUser", () => {
    for (const c of f.tokenUser) expect(roomTokenUser(c.token), c.token).toBe(c.expect);
  });
});

// ================================================================ rooms-reconnect.json

describe("conformance: rooms-reconnect.json", () => {
  const f = fixture("rooms-reconnect.json");
  for (const c of f.cases) {
    it(c.name, () => {
      let calls = 0;
      const random = () => {
        calls++;
        expect(c.random, "random() called but the case gives none").toBeDefined();
        return c.random as number;
      };
      const d = roomRetryDecision(
        { code: c.code, reason: c.reason, attempt: c.attempt, limited: c.limited },
        random,
      );
      expect(d).toEqual(c.expect);
      expect(calls).toBeLessThanOrEqual(1);
    });
  }
});

// ================================================================ rooms-filter.json

describe("conformance: rooms-filter.json", () => {
  const f = fixture("rooms-filter.json");
  const ev = (name: string): RoomGiftMessage => {
    const m = parseRoomFrame(JSON.stringify(f.events[name]));
    expect(m, name).not.toBeNull();
    return m as RoomGiftMessage;
  };
  for (const s of f.scenarios) {
    it(s.name, () => {
      const filter = new RoomEventFilter(s.options);
      let fills = 0;
      let serverOffset = 0;
      for (const [i, step] of (s.steps as Json[]).entries()) {
        const at = `step ${i + 1}`;
        let r: { events: RoomGiftMessage[]; gap: boolean };
        if (step.welcome) {
          serverOffset = step.welcome.now - step.at;
          r = filter.welcome(
            {
              t: "welcome",
              ...step.welcome,
              replay: (step.welcome.replay as string[]).map(ev),
            },
            step.at,
          );
        } else if (step.live) {
          r = filter.live((step.live as string[]).map(ev), step.at);
        } else if (step.batch) {
          // A wire `batch` frame: parsed, then its gifts go through `live` in order.
          const frame = JSON.stringify({
            t: "batch",
            events: (step.batch as string[]).map((n) => f.events[n]),
          });
          const m = parseRoomFrame(frame);
          expect(m?.t, `${at} batch parsed`).toBe("batch");
          r = filter.live((m as { events: RoomGiftMessage[] }).events, step.at);
        } else if (step.fill !== undefined) {
          const list: RoomGiftMessage[] = [];
          for (let k = 0; k < step.fill; k++) {
            fills++;
            list.push({
              t: "gift",
              id: 1000 + fills,
              at: step.at + serverOffset,
              tx: `gtx_fill_${fills}`,
              gift: { id: "rose", name: "Rose", price: 10, icon_url: null },
              quantity: 1,
              sender: { id: "filler" },
              receiver: { id: "host" },
            });
          }
          r = filter.live(list, step.at);
        } else throw new Error(`${at}: unknown step`);
        const x = step.expect ?? {};
        if (x.passed)
          expect(
            r.events.map((e) => e.tx),
            `${at} passed`,
          ).toEqual(x.passed);
        if ("last" in x) expect(filter.last, `${at} last`).toBe(x.last);
        if ("gap" in x) expect(r.gap, `${at} gap`).toBe(x.gap);
      }
    });
  }
});

// ================================================================ rooms-mapping.json

describe("conformance: rooms-mapping.json", () => {
  const f = fixture("rooms-mapping.json");
  for (const c of f.cases) {
    it(c.name, () => {
      const msg = parseRoomFrame(JSON.stringify(c.event)) as RoomGiftMessage;
      expect(msg).not.toBeNull();
      const names = c.names as Record<string, string> | undefined;
      const out = roomGiftToEffect(msg, {
        catalog: c.catalog ? (f.catalog as Gift[]) : undefined,
        resolveName: names ? (u) => names[u] : undefined,
        replayed: c.replayed,
        battle: (c.battle as RoomBattle | undefined) ?? null,
        sideColors: c.sideColors as [string, string] | undefined,
      });
      expect(plain(out)).toEqual(c.expect);
    });
  }
});

// ================================================================ rooms-session.json

interface FakeSocket {
  url: string;
  protocols: string[];
  sent: unknown[];
  closed: { code: number; reason: string } | null;
  handlers: RoomSocketHandlers;
}

/** Runs one rooms-session.json scenario; exported for the mutation check. */
export async function runSessionScenario(s: Json): Promise<void> {
  const clock = new FakeClock();
  const randoms = s.random as number[] | undefined;
  let r = 0;
  const random = () => {
    if (!randoms) return 0.5;
    expect(r, `random() call ${r + 1} beyond the list`).toBeLessThan(randoms.length);
    return randoms[r++]!;
  };
  const tokens: boolean[] = [];
  const pendingTokens: {
    forceRefresh: boolean;
    resolve: (t: string) => void;
    reject: (e: unknown) => void;
  }[] = [];
  const sockets: FakeSocket[] = [];
  const events: RoomGiftEvent[] = [];
  const viewers: number[] = [];
  let gaps = 0;

  const options: RoomClientOptions = {
    ...s.options,
    getToken: ({ forceRefresh }) =>
      new Promise<string>((resolve, reject) => {
        tokens.push(forceRefresh);
        pendingTokens.push({ forceRefresh, resolve, reject });
      }),
    socket: (url, protocols, handlers) => {
      const sock: FakeSocket = { url, protocols: [...protocols], sent: [], closed: null, handlers };
      sockets.push(sock);
      return {
        send: (data) => {
          let v: unknown = data;
          try {
            v = JSON.parse(data);
          } catch {
            // plain text ("ping")
          }
          sock.sent.push(v);
        },
        close: (code, reason) => {
          sock.closed = { code, reason };
        },
      };
    },
    onEvent: (e) => events.push(e),
    onViewers: (n) => viewers.push(n),
    onGap: () => gaps++,
    now: () => clock.now,
    setTimeout: clock.setTimeout,
    clearTimeout: clock.clearTimeout,
    random,
  };
  const room = new RoomClient(options);
  const newest = (at: string) => {
    const sock = sockets[sockets.length - 1];
    expect(sock, `${at}: no socket`).toBeDefined();
    return sock!;
  };

  for (const [i, step] of (s.steps as Json[]).entries()) {
    const at = `${s.name}: step ${i + 1}`;
    if (step.start) room.start();
    else if (step.leave) room.leave();
    else if (step.pause) room.pause();
    else if (step.resume) room.resume();
    else if (step.reconnectNow) room.reconnectNow();
    else if (step.advance !== undefined) clock.advance(step.advance);
    else if (step.token !== undefined) {
      const p = pendingTokens.shift();
      expect(p, `${at}: no pending getToken`).toBeDefined();
      p!.resolve(step.token);
    } else if (step.tokenFail) {
      const p = pendingTokens.shift();
      expect(p, `${at}: no pending getToken`).toBeDefined();
      p!.reject(new Error("token server down"));
    } else if (step.open) newest(at).handlers.onOpen();
    else if (step.receive !== undefined) {
      const data = typeof step.receive === "string" ? step.receive : JSON.stringify(step.receive);
      newest(at).handlers.onMessage(data);
    } else if (step.close) newest(at).handlers.onClose(step.close.code, step.close.reason);
    else if (!step.expect) throw new Error(`${at}: unknown step ${JSON.stringify(step)}`);
    await settle(clock);

    const x = step.expect;
    if (!x) continue;
    if (x.state) {
      const st = room.getState() as unknown as Record<string, unknown>;
      for (const [k, v] of Object.entries(x.state)) expect(st[k], `${at} state.${k}`).toEqual(v);
    }
    if (x.tokens) expect(tokens, `${at} tokens`).toEqual(x.tokens);
    if (x.sockets) {
      expect(sockets.length, `${at} socket count`).toBe(x.sockets.length);
      (x.sockets as Json[]).forEach((want, k) => {
        const got = sockets[k]! as unknown as Record<string, unknown>;
        for (const [key, v] of Object.entries(want)) {
          expect(plain(got[key]), `${at} sockets[${k}].${key}`).toEqual(v);
        }
      });
    }
    if (x.events) {
      const want = x.events as Json[];
      expect(
        events.map((e, k) => ({
          tx: e.tx,
          sender: e.sender ?? null,
          replayed: e.replayed,
          // `quantity` is compared only where the fixture lists it.
          ...(want[k] && "quantity" in want[k] ? { quantity: e.quantity } : {}),
        })),
        `${at} events`,
      ).toEqual(want);
    }
    if (x.viewers) expect(viewers, `${at} viewers`).toEqual(x.viewers);
    if (x.gaps !== undefined) expect(gaps, `${at} gaps`).toBe(x.gaps);
  }
}

describe("conformance: rooms-session.json", () => {
  const f = fixture("rooms-session.json");
  for (const s of f.scenarios) {
    it(s.name, () => runSessionScenario(s));
  }
});
