/**
 * Battle scores (SPEC 17.8, 18.6): the fixture `rooms-battle.json`, the session's battle state
 * and the web handle.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  type RoomBattle,
  RoomClient,
  type RoomClientOptions,
  type RoomGiftEvent,
  type RoomSocketHandlers,
  battleView,
  parseRoomFrame,
} from "../src/core";
import { joinRoom } from "../src/web";
import { type Json, fixture, plain } from "./client-runner";
import { FakeWebSocket, welcome } from "./fake-websocket";

const f = fixture("rooms-battle.json");

describe("conformance: rooms-battle.json", () => {
  describe("parse", () => {
    for (const c of f.parse as Json[]) {
      it(c.name, () => {
        expect(plain(parseRoomFrame(JSON.stringify(c.frame)))).toEqual(c.expect);
      });
    }
  });
  describe("view", () => {
    for (const c of f.view as Json[]) {
      it(c.name, () => {
        expect(plain(battleView(c.battle, c.serverNow))).toEqual(c.expect);
      });
    }
  });
});

const battle = (units: [number, number], round = "r1"): RoomBattle => ({
  round,
  started: 1_000,
  ends: 61_000,
  scores: [
    { id: "ava", units: units[0], gifts: units[0] > 0 ? 1 : 0 },
    { id: "mateo", units: units[1], gifts: units[1] > 0 ? 1 : 0 },
  ],
});

/** A RoomClient on a scripted socket and a manual clock. */
function session(extra: Partial<RoomClientOptions> = {}) {
  let now = 0;
  const sockets: RoomSocketHandlers[] = [];
  const onBattle = vi.fn();
  const room = new RoomClient({
    room: "live_1",
    getToken: async () => "tok",
    socket: (_url, _protocols, handlers) => {
      sockets.push(handlers);
      return { send: () => {}, close: () => {} };
    },
    heartbeatMs: 0,
    now: () => now,
    setTimeout: () => 0,
    clearTimeout: () => {},
    onBattle,
    ...extra,
  });
  const socket = () => sockets[sockets.length - 1] as RoomSocketHandlers;
  const send = (frame: unknown) => socket().onMessage(JSON.stringify(frame));
  return {
    room,
    onBattle,
    socket,
    send,
    sockets,
    setNow: (n: number) => (now = n),
  };
}

const flush = async () => {
  for (let i = 0; i < 10; i++) await Promise.resolve();
};

describe("RoomClient battle gifts (SPEC 18.4)", () => {
  const gift = (at: number, to: string) => ({
    t: "gift",
    id: at,
    at,
    tx: `gtx_${at}`,
    gift: { id: "rose", name: "Rose", price: 10 },
    quantity: 1,
    sender: { id: "u1", name: "Ava" },
    receiver: { id: to },
  });

  it("gives a gift of the round the receiver, with the room's names and colours", async () => {
    const events: RoomGiftEvent[] = [];
    const s = session({
      onEvent: (e) => events.push(e),
      resolveName: (id) => (id === "mateo" ? "Mateo" : undefined),
      sideColors: ["#ff3366", "#00aa88"],
    });
    s.room.start();
    await flush();
    s.socket().onOpen();
    s.send(welcome({ now: 5_000, battle: battle([0, 0]) }));
    s.send(gift(5_000, "mateo"));
    s.send(gift(5_001, "ava"));
    s.send(gift(5_002, "viewer"));
    expect(events.map((e) => e.receiver)).toEqual([
      { name: "Mateo", side: 1, color: "#00aa88" },
      { name: "ava", side: 0, color: "#ff3366" },
      undefined,
    ]);
    s.send({ t: "scores", battle: null });
    s.send(gift(5_003, "mateo"));
    expect(events[3]?.receiver).toBeUndefined();
  });

  it("receiverFor names the side of a user now, for the app's own gifts", async () => {
    const s = session({
      resolveName: (id) => (id === "ava" ? "Ava" : undefined),
      sideColors: ["#111", "#222"],
    });
    s.room.start();
    await flush();
    s.socket().onOpen();
    expect(s.room.receiverFor("ava")).toBeUndefined();
    s.send(welcome({ now: 5_000, battle: battle([0, 0]) }));
    expect(s.room.receiverFor("ava")).toEqual({ name: "Ava", side: 0, color: "#111" });
    expect(s.room.receiverFor("mateo")).toEqual({ name: "mateo", side: 1, color: "#222" });
    expect(s.room.receiverFor("viewer")).toBeUndefined();
    s.setNow(70_000); // past the round's end (61,000 on the server clock)
    expect(s.room.receiverFor("ava")).toBeUndefined();
  });
});

describe("RoomClient battle state", () => {
  it("takes the round from welcome, then each scores frame; null when removed", async () => {
    const s = session();
    const changes: (RoomBattle | null)[] = [];
    s.room.subscribeBattle(() => changes.push(s.room.getBattle()));
    s.room.start();
    await flush();
    s.socket().onOpen();
    expect(s.room.getBattle()).toBeNull();
    // Local clock 100, server clock 31,000: offset 30,900.
    s.setNow(100);
    s.send(welcome({ now: 31_000, battle: battle([0, 0]) }));
    expect(s.room.getBattle()).toEqual(battle([0, 0]));
    expect(s.room.serverNow()).toBe(31_000);
    s.send({ t: "scores", battle: battle([300, 100]) });
    s.setNow(10_100);
    expect(s.room.getBattleView()).toMatchObject({
      open: true,
      remainingMs: 20_000,
      total: 400,
      leader: "ava",
    });
    s.send({ t: "scores", battle: null });
    expect(s.room.getBattle()).toBeNull();
    expect(s.room.getBattleView()).toBeNull();
    expect(changes).toEqual([battle([0, 0]), battle([300, 100]), null]);
    expect(s.onBattle.mock.calls.map((c) => c[0])).toEqual(changes);
  });

  it("ignores malformed scores frames and keeps the last round across a reconnect until welcome", async () => {
    const s = session();
    s.room.start();
    await flush();
    s.socket().onOpen();
    s.send(welcome({ battle: battle([5, 0]) }));
    s.send({ t: "scores", battle: { round: "" } });
    s.send({ t: "scores" });
    expect(s.room.getBattle()).toEqual(battle([5, 0]));
    s.socket().onClose(1006, "");
    expect(s.room.getState().status).toBe("reconnecting");
    expect(s.room.getBattle()).toEqual(battle([5, 0]));
    s.room.reconnectNow();
    await flush();
    s.socket().onOpen();
    // The new welcome has no round: it was removed while we were away.
    s.send(welcome());
    expect(s.room.getBattle()).toBeNull();
  });

  it("app callbacks that throw never break the room", async () => {
    const s = session();
    s.room.subscribeBattle(() => {
      throw new Error("app bug");
    });
    s.room.start();
    await flush();
    s.socket().onOpen();
    s.send(welcome({ battle: battle([1, 2]) }));
    expect(s.room.getState().status).toBe("open");
    expect(s.room.getBattle()).toEqual(battle([1, 2]));
  });
});

describe("web joinRoom battle", () => {
  beforeEach(() => FakeWebSocket.reset());
  afterEach(() => vi.useRealTimers());

  it("exposes battle, battleView and onBattle on the handle", async () => {
    const onBattle = vi.fn();
    const room = joinRoom({
      room: "live_1",
      getToken: async () => "tok",
      onBattle,
      WebSocket: FakeWebSocket,
    });
    await flush();
    const ws = FakeWebSocket.last();
    ws.serverOpen();
    const seen: (RoomBattle | null)[] = [];
    const off = room.onBattle((b) => seen.push(b));
    ws.serverSend(welcome({ battle: battle([0, 0], "r9") }));
    ws.serverSend({ t: "scores", battle: battle([10, 30], "r9") });
    expect(room.battle).toEqual(battle([10, 30], "r9"));
    expect(room.battleView()?.sides.map((x) => [x.id, x.share])).toEqual([
      ["ava", 0.25],
      ["mateo", 0.75],
    ]);
    expect(room.battleView()?.leader).toBe("mateo");
    off();
    ws.serverSend({ t: "scores", battle: null });
    expect(seen).toEqual([battle([0, 0], "r9"), battle([10, 30], "r9")]);
    expect(onBattle).toHaveBeenLastCalledWith(null);
    expect(room.battle).toBeNull();
    room.leave();
  });
});
