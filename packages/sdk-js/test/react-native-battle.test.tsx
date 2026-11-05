import { act, cleanup, render } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { BattleView, RoomBattle } from "../src/core";
import { type UseGiftRoom, useBattleScore, useGiftRoom } from "../src/react-native";
import { FakeWebSocket, welcome } from "./fake-websocket";

const flush = async () => {
  await act(async () => {
    for (let i = 0; i < 10; i++) await Promise.resolve();
  });
};

const battle = (ava: number, mateo: number, ends: number): RoomBattle => ({
  round: "r1",
  started: 0,
  ends,
  scores: [
    { id: "ava", units: ava, gifts: ava ? 1 : 0 },
    { id: "mateo", units: mateo, gifts: mateo ? 1 : 0 },
  ],
});

let room: UseGiftRoom | null = null;
let view: BattleView | null = null;
let renders = 0;
function Battle(props: { tickMs?: number }) {
  room = useGiftRoom({ room: "live_1", getToken: async () => "tok", WebSocket: FakeWebSocket });
  view = useBattleScore(room.controller, { tickMs: props.tickMs });
  renders += 1;
  return null;
}

describe("React Native useBattleScore", () => {
  beforeEach(() => {
    FakeWebSocket.reset();
    room = null;
    view = null;
    renders = 0;
  });
  afterEach(() => {
    cleanup();
    vi.useRealTimers();
  });

  it("re-renders on scores frames, exposes battle on useGiftRoom, null after removal", async () => {
    render(<Battle tickMs={0} />);
    await flush();
    const ws = FakeWebSocket.last();
    expect(view).toBeNull();
    const now = Date.now();
    act(() => {
      ws.serverOpen();
      ws.serverSend(welcome({ now, battle: battle(0, 0, now + 60_000) }));
    });
    expect(room!.battle).toEqual(battle(0, 0, now + 60_000));
    expect(view!.sides.map((s) => s.share)).toEqual([0.5, 0.5]);
    act(() => ws.serverSend({ t: "scores", battle: battle(100, 300, now + 60_000) }));
    expect(view!.leader).toBe("mateo");
    expect(view!.total).toBe(400);
    expect(view!.open).toBe(true);
    act(() => ws.serverSend({ t: "scores", battle: null }));
    expect(view).toBeNull();
    expect(room!.battle).toBeNull();
  });

  it("ticks while the round is open so the countdown moves", async () => {
    vi.useFakeTimers({ toFake: ["setInterval", "clearInterval", "Date"] });
    render(<Battle tickMs={1_000} />);
    await flush();
    const ws = FakeWebSocket.last();
    const now = Date.now();
    act(() => {
      ws.serverOpen();
      ws.serverSend(welcome({ now, battle: battle(1, 0, now + 5_000) }));
    });
    expect(view!.remainingMs).toBe(5_000);
    const before = renders;
    act(() => vi.advanceTimersByTime(2_000));
    expect(renders).toBeGreaterThan(before);
    expect(view!.remainingMs).toBe(3_000);
    act(() => vi.advanceTimersByTime(5_000));
    expect(view!.open).toBe(false);
    expect(view!.remainingMs).toBe(0);
    const ended = renders;
    act(() => vi.advanceTimersByTime(5_000));
    expect(renders).toBe(ended);
  });
});
