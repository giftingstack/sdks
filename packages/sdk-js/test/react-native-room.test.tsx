import { act, cleanup, render } from "@testing-library/react";
import { type RefObject, createRef } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { GiftEffectEvent } from "../src/core";
import { type GiftEffectLayerHandle, type UseGiftRoom, useGiftRoom } from "../src/react-native";
import { FakeWebSocket, giftFrame, welcome } from "./fake-websocket";

const TOKEN = "tok_room";

const flush = async () => {
  await act(async () => {
    for (let i = 0; i < 10; i++) await Promise.resolve();
  });
};

function setAppState(state: "active" | "background") {
  Object.defineProperty(document, "visibilityState", {
    configurable: true,
    get: () => (state === "active" ? "visible" : "hidden"),
  });
  act(() => {
    document.dispatchEvent(new Event("visibilitychange"));
  });
}

function layerRef(played: GiftEffectEvent[]): RefObject<GiftEffectLayerHandle | null> {
  const ref = createRef<GiftEffectLayerHandle | null>() as {
    current: GiftEffectLayerHandle | null;
  };
  ref.current = {
    play: (e: GiftEffectEvent) => {
      played.push(e);
      return played.length;
    },
    cancel: () => {},
    clear: () => {},
  } as unknown as GiftEffectLayerHandle;
  return ref;
}

let latest: UseGiftRoom | null = null;
function Room(props: { room: string | null; effects?: RefObject<GiftEffectLayerHandle | null> }) {
  latest = useGiftRoom({
    room: props.room,
    getToken: async () => TOKEN,
    effects: props.effects,
    WebSocket: FakeWebSocket,
  });
  return null;
}

describe("React Native useGiftRoom", () => {
  beforeEach(() => {
    FakeWebSocket.reset();
    latest = null;
  });
  afterEach(() => {
    cleanup();
    setAppState("active");
  });

  it("joins while mounted, plays room gifts in the layer, reports viewers", async () => {
    const played: GiftEffectEvent[] = [];
    render(<Room room="live_1" effects={layerRef(played)} />);
    await flush();
    const ws = FakeWebSocket.last();
    expect(ws.url).toBe("wss://rt.giftingstack.com/v1/rooms/live_1");
    expect(ws.protocols).toEqual(["gs.v1", TOKEN]);
    act(() => {
      ws.serverOpen();
      ws.serverSend(welcome({ viewers: 12 }));
      ws.serverSend(giftFrame(5, "gtx_5", "ayla", "Ayla"));
    });
    expect(latest!.state.status).toBe("open");
    expect(latest!.viewers).toBe(12);
    expect(played).toHaveLength(1);
    expect(played[0]).toMatchObject({ gift: { id: "rose" }, sender: "Ayla", quantity: 2 });
    act(() => ws.serverSend({ t: "viewers", n: 13 }));
    expect(latest!.viewers).toBe(13);
  });

  it("background closes the socket; foreground rejoins with the resume point", async () => {
    render(<Room room="live_1" />);
    await flush();
    const ws = FakeWebSocket.last();
    act(() => {
      ws.serverOpen();
      ws.serverSend(welcome());
      ws.serverSend(giftFrame(77, "gtx_77"));
    });
    setAppState("background");
    expect(ws.closedWith).toEqual({ code: 1000, reason: "client" });
    expect(latest!.state.status).toBe("paused");
    setAppState("active");
    await flush();
    expect(FakeWebSocket.all).toHaveLength(2);
    const ws2 = FakeWebSocket.last();
    act(() => ws2.serverOpen());
    expect(JSON.parse(ws2.sent[0]!)).toEqual({ t: "hello", v: 1, last: 77 });
  });

  it("mounted in the background: connects only when the app becomes active", async () => {
    setAppState("background");
    render(<Room room="live_1" />);
    await flush();
    expect(FakeWebSocket.all).toHaveLength(0);
    setAppState("active");
    await flush();
    expect(FakeWebSocket.all).toHaveLength(1);
  });

  it("unmount leaves; a new room leaves the old one; no room connects nothing", async () => {
    const { rerender, unmount } = render(<Room room="live_1" />);
    await flush();
    const first = FakeWebSocket.last();
    rerender(<Room room="live_2" />);
    await flush();
    expect(first.closedWith).toEqual({ code: 1000, reason: "client" });
    const second = FakeWebSocket.last();
    expect(second.url).toBe("wss://rt.giftingstack.com/v1/rooms/live_2");
    rerender(<Room room={null} />);
    await flush();
    expect(second.closedWith?.code).toBe(1000);
    expect(FakeWebSocket.all).toHaveLength(2);
    expect(latest!.state.status).toBe("idle");
    rerender(<Room room="live_3" />);
    await flush();
    const third = FakeWebSocket.last();
    unmount();
    expect(third.closedWith?.code).toBe(1000);
  });

  it("an effect layer that throws does not break the room", async () => {
    const ref = {
      current: {
        play: vi.fn(() => {
          throw new Error("boom");
        }),
      },
    } as unknown as RefObject<GiftEffectLayerHandle | null>;
    render(<Room room="live_1" effects={ref} />);
    await flush();
    const ws = FakeWebSocket.last();
    act(() => {
      ws.serverOpen();
      ws.serverSend(welcome());
      ws.serverSend(giftFrame(1, "gtx_1"));
      ws.serverSend(giftFrame(2, "gtx_2"));
    });
    expect(ref.current!.play).toHaveBeenCalledTimes(2);
    expect(latest!.state.status).toBe("open");
  });
});
