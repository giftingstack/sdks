/** The demo's pretend rooms server (demo/fakeRoom.ts): the SDK's real joinRoom must work against it. */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Gift, RoomGiftEvent } from "../src/core";
import { joinRoom } from "../src/web";
import { demoRoomToken, fakeRoomSocket } from "../demo/fakeRoom";

const gift = (id: string, price: number): Gift => ({
  id,
  name: id,
  description: null,
  price,
  icon_url: null,
  animation_url: null,
  sort_order: 0,
});

describe("demo fake room", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("joins, gets a welcome with viewers, then gifts from others", async () => {
    const events: RoomGiftEvent[] = [];
    const room = joinRoom({
      room: "pixel-live",
      getToken: async () => demoRoomToken("ava"),
      WebSocket: fakeRoomSocket({
        gifts: [gift("rose", 10)],
        senders: ["mateo"],
        nameOf: (id) => id.toUpperCase(),
        random: () => 0.5,
      }),
      onEvent: (e) => events.push(e),
    });
    await vi.advanceTimersByTimeAsync(200);
    expect(room.getState().status).toBe("open");
    expect(room.viewers).toBeGreaterThan(0);
    await vi.advanceTimersByTimeAsync(13_000);
    expect(events.length).toBeGreaterThan(0);
    expect(events[0]).toMatchObject({ sender: "MATEO", gift: { id: "rose" } });
    room.leave();
    const n = events.length;
    await vi.advanceTimersByTimeAsync(30_000);
    expect(events.length).toBe(n);
  });

  it("runs battle rounds: welcome.battle, scores for counted gifts, a new round after the break", async () => {
    const Socket = fakeRoomSocket({
      gifts: [gift("rose", 10)],
      senders: ["mateo"],
      nameOf: (id) => id,
      random: () => 0.99, // no combos, the last receiver, the longest delay
      minDelayMs: 60_000,
      maxDelayMs: 60_000,
      battle: { receivers: ["mia", "theo"], roundMs: 10_000, breakMs: 2_000 },
    });
    let battleCalls = 0;
    const room = joinRoom({
      room: "pixel-live",
      getToken: async () => demoRoomToken("ava"),
      WebSocket: Socket,
      onBattle: () => battleCalls++,
    });
    await vi.advanceTimersByTimeAsync(500);
    const first = room.battleView();
    expect(first).toMatchObject({ round: "demo_r1", open: true, total: 0, leader: null });
    expect(first!.sides.map((s) => s.id)).toEqual(["mia", "theo"]);

    // Own sends (the app's publish) count; three in a burst give one scores frame, not three.
    const before = battleCalls;
    Socket.publish("ava", gift("rose", 10), 2, "mia");
    Socket.publish("ava", gift("rose", 10), 1, "theo");
    Socket.publish("ava", gift("rose", 10), 1, "mia");
    Socket.publish("ava", gift("rose", 10), 5, "nobody"); // not in the round
    await vi.advanceTimersByTimeAsync(300);
    expect(battleCalls - before).toBe(1);
    expect(room.battleView()).toMatchObject({ total: 40, leader: "mia" });
    expect(room.battleView()!.sides.map((s) => [s.units, s.gifts])).toEqual([
      [30, 3],
      [10, 1],
    ]);

    // After `ends` nothing counts and no frame comes; the client sees the round closed.
    await vi.advanceTimersByTimeAsync(10_000);
    Socket.publish("ava", gift("rose", 10), 9, "theo");
    await vi.advanceTimersByTimeAsync(300);
    expect(room.battleView()).toMatchObject({ round: "demo_r1", open: false, total: 40 });

    // After the break a fresh round starts at 0.
    await vi.advanceTimersByTimeAsync(2_000);
    expect(room.battleView()).toMatchObject({ round: "demo_r2", open: true, total: 0 });
    room.leave();
  });
});
