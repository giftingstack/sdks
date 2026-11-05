/**
 * The 4008 `retry_after` growth and the token-refresh spread (SPEC 18.3, 18.5), at the unit
 * level. The shared fixtures (rooms-reconnect.json, rooms-session.json) pin the same rules on
 * every platform; these tests also exercise `roomRateLimitedDelayMs` and the default of
 * `refreshJitterMs` directly.
 */
import { describe, expect, it } from "vitest";
import {
  ROOM_LIMITED_MAX_MS,
  ROOM_LIMITED_MIN_MS,
  RoomClient,
  type RoomSocketHandlers,
  roomRateLimitedDelayMs,
} from "../src/core";

describe("roomRateLimitedDelayMs", () => {
  it("is at least 30 s and at least retry_after, growing with the waits in a row, capped", () => {
    expect(roomRateLimitedDelayMs(1, 0, () => 0)).toBe(ROOM_LIMITED_MIN_MS);
    expect(roomRateLimitedDelayMs(90, 0, () => 0)).toBe(90_000);
    expect(roomRateLimitedDelayMs(60, 1, () => 0)).toBe(120_000);
    expect(roomRateLimitedDelayMs(60, 2, () => 0)).toBe(240_000);
    expect(roomRateLimitedDelayMs(60, 3, () => 0)).toBe(ROOM_LIMITED_MAX_MS);
    expect(roomRateLimitedDelayMs(60, 50, () => 0.999)).toBe(ROOM_LIMITED_MAX_MS);
  });

  it("adds up to 25 % jitter below the cap", () => {
    expect(roomRateLimitedDelayMs(60, 0, () => 0.5)).toBe(67_500);
    const spread = new Set(
      [0, 0.25, 0.5, 0.75, 0.99].map((r) => roomRateLimitedDelayMs(60, 0, () => r)),
    );
    expect(spread.size).toBe(5);
  });
});

function session(opts: { random?: () => number; refreshJitterMs?: number } = {}) {
  let now = 0;
  let id = 0;
  const timers = new Map<number, { at: number; fn: () => void }>();
  const sockets: RoomSocketHandlers[] = [];
  const room = new RoomClient({
    room: "live_1",
    getToken: async () => "tok",
    socket: (_u, _p, h) => {
      sockets.push(h);
      return { send: () => {}, close: () => {} };
    },
    heartbeatMs: 0,
    now: () => now,
    setTimeout: (fn, ms) => {
      timers.set(++id, { at: now + ms, fn });
      return id;
    },
    clearTimeout: (h) => void timers.delete(h as number),
    random: opts.random ?? (() => 0),
    refreshJitterMs: opts.refreshJitterMs,
  });
  const flush = () => new Promise((r) => setTimeout(r, 0));
  /** Runs the earliest timer; returns the wait it had. */
  const fireNext = async (): Promise<number> => {
    const [h, t] = [...timers.entries()].sort((a, b) => a[1].at - b[1].at)[0]!;
    timers.delete(h);
    const wait = t.at - now;
    now = t.at;
    t.fn();
    await flush();
    return wait;
  };
  const nextAt = () => Math.min(...[...timers.values()].map((t) => t.at)) - now;
  return { room, sockets, fireNext, nextAt, flush, advanceTo: (t: number) => (now = t) };
}

describe("4008 with retry_after", () => {
  it("keeps retrying with growing waits capped at 5 minutes, never gives up", async () => {
    const s = session();
    s.room.start();
    await s.flush();
    const waits: number[] = [];
    for (let i = 0; i < 12; i++) {
      s.sockets[s.sockets.length - 1]!.onClose(4008, '{"retry_after":60}');
      expect(s.room.getState().status).toBe("reconnecting");
      waits.push(await s.fireNext());
    }
    expect(waits.slice(0, 4)).toEqual([60_000, 120_000, 240_000, 300_000]);
    expect(Math.max(...waits)).toBe(ROOM_LIMITED_MAX_MS);
    expect(s.room.getState().status).not.toBe("closed");
  });

  it("without retry_after it still stops after 5 waits (and can be restarted)", async () => {
    const s = session();
    s.room.start();
    await s.flush();
    for (let i = 0; i < 5; i++) {
      s.sockets[s.sockets.length - 1]!.onClose(4008, "slow down");
      await s.fireNext();
    }
    s.sockets[s.sockets.length - 1]!.onClose(4008, "slow down");
    expect(s.room.getState().status).toBe("closed");
  });
});

describe("refresh jitter", () => {
  const welcomeFrame = JSON.stringify({
    t: "welcome",
    v: 1,
    viewers: 1,
    gap: false,
    replay: [],
    ttl: 3600,
    now: 0,
  });
  const refreshAt = async (opts: Parameters<typeof session>[0]) => {
    const s = session(opts);
    s.room.start();
    await s.flush();
    s.sockets[0]!.onOpen();
    s.sockets[0]!.onMessage(welcomeFrame);
    return s.nextAt();
  };

  it("defaults to none: ttl minus 30 s", async () => {
    expect(await refreshAt({ random: () => 0.9 })).toBe(3_570_000);
  });

  it("refreshes earlier by random(0, refreshJitterMs)", async () => {
    expect(await refreshAt({ random: () => 0.5, refreshJitterMs: 120_000 })).toBe(3_510_000);
    expect(await refreshAt({ random: () => 0, refreshJitterMs: 120_000 })).toBe(3_570_000);
  });

  it("never pushes a short ttl below half of what is left", async () => {
    const s = session({ random: () => 0.999, refreshJitterMs: 120_000 });
    s.room.start();
    await s.flush();
    s.sockets[0]!.onOpen();
    s.sockets[0]!.onMessage(
      JSON.stringify({ t: "welcome", v: 1, viewers: 1, gap: false, replay: [], ttl: 90, now: 0 }),
    );
    expect(s.nextAt()).toBeGreaterThanOrEqual(30_000);
  });
});
