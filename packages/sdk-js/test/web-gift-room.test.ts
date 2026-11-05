import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { GiftEffectEvent, RoomGiftEvent } from "../src/core";
import { GiftRoomElement, defineGiftElements } from "../src/web";
import { FakeWebSocket, giftFrame, welcome } from "./fake-websocket";

const flush = async () => {
  for (let i = 0; i < 10; i++) await Promise.resolve();
};

describe("<gift-room>", () => {
  beforeEach(() => {
    FakeWebSocket.reset();
    vi.stubGlobal("WebSocket", FakeWebSocket);
    defineGiftElements();
    document.body.innerHTML = "";
  });
  afterEach(() => vi.unstubAllGlobals());

  function mount(attrs = 'room="live_1"') {
    document.body.innerHTML = `<div id="fx"></div><gift-room ${attrs}></gift-room>`;
    const el = document.querySelector("gift-room") as GiftRoomElement;
    const played: GiftEffectEvent[] = [];
    el.effectPlayer = { play: (e) => played.push(e) };
    el.getToken = async () => "tok";
    return { el, played };
  }

  it("is hidden, joins when it has a room and a getToken, plays and emits", async () => {
    const { el, played } = mount();
    const seen: RoomGiftEvent[] = [];
    const viewers: number[] = [];
    el.addEventListener("gift-room-event", (e) => seen.push((e as CustomEvent).detail));
    el.addEventListener("gift-room-viewers", (e) => viewers.push((e as CustomEvent).detail));
    await flush();
    expect(el.style.display).toBe("none");
    const ws = FakeWebSocket.last();
    expect(ws.url).toBe("wss://rt.giftingstack.com/v1/rooms/live_1");
    ws.serverOpen();
    ws.serverSend(welcome({ viewers: 4 }));
    ws.serverSend(giftFrame(1, "gtx_1", "ayla", "Ayla"));
    expect(played).toHaveLength(1);
    expect(seen.map((e) => e.tx)).toEqual(["gtx_1"]);
    expect(viewers).toContain(4);
    expect(el.handle?.getState().status).toBe("open");
  });

  it("plays in the gift-effect-layer the selector names when no player is set", async () => {
    document.body.innerHTML = `<gift-room room="r1" effects="#mine"></gift-room>`;
    const el = document.querySelector("gift-room") as GiftRoomElement;
    const played: GiftEffectEvent[] = [];
    const layer = Object.assign(document.createElement("div"), {
      id: "mine",
      play: (e: GiftEffectEvent) => played.push(e),
    });
    document.body.appendChild(layer);
    el.getToken = async () => "tok";
    await flush();
    const ws = FakeWebSocket.last();
    ws.serverOpen();
    ws.serverSend(welcome());
    ws.serverSend(giftFrame(1, "gtx_1"));
    expect(played).toHaveLength(1);
  });

  it("waits for getToken, rejoins when room changes, leaves when removed", async () => {
    document.body.innerHTML = `<gift-room room="a"></gift-room>`;
    const el = document.querySelector("gift-room") as GiftRoomElement;
    await flush();
    expect(FakeWebSocket.all).toHaveLength(0);
    el.getToken = async () => "tok";
    await flush();
    expect(FakeWebSocket.all).toHaveLength(1);
    el.setAttribute("room", "b");
    await flush();
    expect(FakeWebSocket.all).toHaveLength(2);
    expect(FakeWebSocket.all[0]?.closedWith?.code).toBe(1000);
    expect(FakeWebSocket.last().url).toMatch(/\/v1\/rooms\/b$/);
    el.remove();
    await flush();
    expect(FakeWebSocket.last().closedWith?.code).toBe(1000);
    expect(el.handle).toBeNull();
  });

  it("changing min-tier, skip-own or max-replay-age-ms updates in place: same socket, no gift lost", async () => {
    const { el, played } = mount('room="r1" min-tier="large"');
    await flush();
    const ws = FakeWebSocket.last();
    ws.serverOpen();
    ws.serverSend(welcome());
    ws.serverSend(giftFrame(1, "gtx_1")); // small: filtered out by min-tier="large"
    expect(played).toHaveLength(0);
    el.setAttribute("min-tier", "small");
    el.setAttribute("skip-own", "false");
    el.setAttribute("max-replay-age-ms", "5000");
    el.setAttribute("effects", "#fx");
    await flush();
    expect(FakeWebSocket.all).toHaveLength(1);
    expect(ws.closedWith ?? null).toBeNull();
    expect(el.handle?.getState().status).toBe("open");
    ws.serverSend(giftFrame(2, "gtx_2"));
    expect(played.map((e) => e.gift.id)).toHaveLength(1);
    el.removeAttribute("min-tier"); // back to the default (all gifts)
    await flush();
    expect(FakeWebSocket.all).toHaveLength(1);
  });

  it("properties getToken, resolveName and thresholds also change in place", async () => {
    const { el } = mount();
    await flush();
    const first = el.handle;
    el.resolveName = () => "Someone";
    el.thresholds = { mediumFrom: 5 };
    el.getToken = async () => "tok2";
    await flush();
    expect(el.handle).toBe(first);
    expect(FakeWebSocket.all).toHaveLength(1);
  });

  it("changing url or allow-insecure joins again (a new socket)", async () => {
    const { el } = mount();
    await flush();
    el.setAttribute("url", "ws://localhost:8788");
    await flush();
    expect(FakeWebSocket.all).toHaveLength(2);
    expect(FakeWebSocket.last().url).toBe("ws://localhost:8788/v1/rooms/live_1");
    expect(FakeWebSocket.all[0]?.closedWith?.code).toBe(1000);
  });

  it("reads skip-own and min-tier from attributes", async () => {
    const { el, played } = mount('room="r1" min-tier="large" skip-own="false"');
    await flush();
    const ws = FakeWebSocket.last();
    ws.serverOpen();
    ws.serverSend(welcome());
    ws.serverSend(giftFrame(1, "gtx_1")); // 10 coins: small, below the large filter
    expect(played).toHaveLength(0);
    expect(el.getAttribute("min-tier")).toBe("large");
  });
});
