import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Gift, GiftEffectEvent, RoomGiftEvent } from "../src/core";
import { HIDDEN_PAUSE_MS, joinRoom } from "../src/web";
import { FakeWebSocket, giftFrame, welcome } from "./fake-websocket";

const TOKEN = "tok_room";
const CATALOG: Gift[] = [
  {
    id: "rose",
    name: "Rose",
    description: null,
    price: 10,
    icon_url: "https://assets.test/rose/256.webp",
    animation_url: "https://assets.test/rose/512.webp",
    sort_order: 1,
  },
];

const flush = async () => {
  for (let i = 0; i < 10; i++) await Promise.resolve();
};

function setHidden(hidden: boolean) {
  Object.defineProperty(document, "hidden", { configurable: true, get: () => hidden });
  document.dispatchEvent(new Event("visibilitychange"));
}

describe("web joinRoom", () => {
  beforeEach(() => FakeWebSocket.reset());
  afterEach(() => {
    vi.useRealTimers();
    setHidden(false);
  });

  it("connects with gs.v1 + token, says hello, plays room gifts in the layer with the catalog picture", async () => {
    const played: GiftEffectEvent[] = [];
    const getToken = vi.fn(async () => TOKEN);
    const onViewers = vi.fn();
    const room = joinRoom({
      room: "live_1",
      getToken,
      client: { getGifts: async () => CATALOG },
      effects: { play: (e) => played.push(e) },
      onViewers,
      WebSocket: FakeWebSocket,
    });
    await flush();
    expect(getToken).toHaveBeenCalledWith({ forceRefresh: false });
    const ws = FakeWebSocket.last();
    expect(ws.url).toBe("wss://rt.giftingstack.com/v1/rooms/live_1");
    expect(ws.protocols).toEqual(["gs.v1", TOKEN]);

    ws.serverOpen();
    expect(ws.sent.map((s) => JSON.parse(s))).toEqual([{ t: "hello", v: 1, last: null }]);
    ws.serverSend(welcome({ viewers: 7 }));
    expect(room.getState().status).toBe("open");
    expect(room.viewers).toBe(7);
    expect(onViewers).toHaveBeenCalledWith(7);

    const seen: RoomGiftEvent[] = [];
    const off = room.onEvent((e) => seen.push(e));
    ws.serverSend(giftFrame(11, "gtx_1", "ayla", "Ayla"));
    expect(played).toHaveLength(1);
    expect(played[0]).toMatchObject({
      gift: {
        id: "rose",
        image: "https://assets.test/rose/512.webp",
        icon: "https://assets.test/rose/256.webp",
      },
      sender: "Ayla",
      quantity: 2,
    });
    expect(seen.map((e) => e.tx)).toEqual(["gtx_1"]);
    off();
    // The same tx again (a re-publish): not played twice.
    ws.serverSend(giftFrame(12, "gtx_1"));
    expect(played).toHaveLength(1);
    // Binary frames are dropped by the transport.
    ws.onmessage?.({ data: new ArrayBuffer(4) });
    room.leave();
  });

  it("leave closes the socket with 1000 and ignores later frames", async () => {
    const play = vi.fn();
    const room = joinRoom({
      room: "live_1",
      getToken: async () => TOKEN,
      effects: () => ({ play }),
      WebSocket: FakeWebSocket,
    });
    await flush();
    const ws = FakeWebSocket.last();
    ws.serverOpen();
    ws.serverSend(welcome());
    room.leave();
    room.leave();
    expect(ws.closedWith).toEqual({ code: 1000, reason: "client" });
    expect(ws.onmessage).toBeNull();
    expect(room.getState()).toMatchObject({ status: "closed", code: 1000, reason: "left" });
    expect(play).not.toHaveBeenCalled();
  });

  it("an error followed by a close is handled once and reconnects with backoff and resume", async () => {
    vi.useFakeTimers();
    const room = joinRoom({
      room: "live_1",
      getToken: async () => TOKEN,
      WebSocket: FakeWebSocket,
      pauseWhenHidden: false,
    });
    await flush();
    const ws = FakeWebSocket.last();
    ws.serverOpen();
    ws.serverSend(welcome());
    ws.serverSend(giftFrame(41, "gtx_41"));
    ws.serverError();
    ws.serverClose(1006);
    ws.serverClose(1006);
    expect(room.getState().status).toBe("reconnecting");
    expect(room.getState().attempt).toBe(1);
    await vi.advanceTimersByTimeAsync(5_000);
    await flush();
    expect(FakeWebSocket.all).toHaveLength(2);
    const ws2 = FakeWebSocket.last();
    ws2.serverOpen();
    expect(JSON.parse(ws2.sent[0]!)).toEqual({ t: "hello", v: 1, last: 41 });
    room.leave();
  });

  it("the online event skips the backoff wait", async () => {
    const room = joinRoom({
      room: "live_1",
      getToken: async () => TOKEN,
      WebSocket: FakeWebSocket,
    });
    await flush();
    FakeWebSocket.last().serverClose(1011);
    expect(room.getState().status).toBe("reconnecting");
    window.dispatchEvent(new Event("online"));
    await flush();
    expect(FakeWebSocket.all).toHaveLength(2);
    room.leave();
  });

  it("online and visible never skip a 4008 or 4009 wait", async () => {
    const room = joinRoom({
      room: "live_1",
      getToken: async () => TOKEN,
      WebSocket: FakeWebSocket,
    });
    await flush();
    FakeWebSocket.last().serverClose(4008, JSON.stringify({ retry_after: 60 }));
    expect(room.getState().status).toBe("reconnecting");
    window.dispatchEvent(new Event("online"));
    setHidden(false);
    await flush();
    expect(room.getState().status).toBe("reconnecting");
    expect(FakeWebSocket.all).toHaveLength(1);
    room.leave();
  });

  it("setOptions(pauseWhenHidden: false) stops the hidden-page pause", async () => {
    vi.useFakeTimers();
    const room = joinRoom({
      room: "live_1",
      getToken: async () => TOKEN,
      WebSocket: FakeWebSocket,
    });
    await flush();
    const ws = FakeWebSocket.last();
    ws.serverOpen();
    ws.serverSend(welcome());
    room.setOptions({ pauseWhenHidden: false });
    setHidden(true);
    await vi.advanceTimersByTimeAsync(HIDDEN_PAUSE_MS + 1_000);
    // (The heartbeat may have dropped the silent fake socket meanwhile; it was not paused.)
    expect(room.getState().status).not.toBe("paused");
    room.leave();
  });

  it("a page hidden for 60 s disconnects; visible again reconnects", async () => {
    vi.useFakeTimers();
    const room = joinRoom({
      room: "live_1",
      getToken: async () => TOKEN,
      WebSocket: FakeWebSocket,
    });
    await flush();
    const ws = FakeWebSocket.last();
    ws.serverOpen();
    ws.serverSend(welcome());
    setHidden(true);
    await vi.advanceTimersByTimeAsync(50_000);
    // The heartbeat ping went out at 45 s: answer it.
    ws.serverSend("pong");
    await vi.advanceTimersByTimeAsync(HIDDEN_PAUSE_MS - 50_001);
    expect(room.getState().status).toBe("open");
    await vi.advanceTimersByTimeAsync(1);
    expect(room.getState().status).toBe("paused");
    expect(ws.closedWith?.code).toBe(1000);
    setHidden(false);
    await flush();
    expect(room.getState().status).toBe("connecting");
    expect(FakeWebSocket.all).toHaveLength(2);
    room.leave();
    // Listeners are gone after leave: nothing reconnects.
    setHidden(true);
    setHidden(false);
    expect(FakeWebSocket.all).toHaveLength(2);
  });

  it("a bad room id never opens a socket", async () => {
    const getToken = vi.fn(async () => TOKEN);
    const room = joinRoom({ room: "no spaces", getToken, WebSocket: FakeWebSocket });
    await flush();
    expect(getToken).not.toHaveBeenCalled();
    expect(FakeWebSocket.all).toHaveLength(0);
    expect(room.getState()).toMatchObject({ status: "closed", code: 4004 });
  });
});
