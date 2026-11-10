import {
  type RefObject,
  useCallback,
  useEffect,
  useReducer,
  useRef,
  useSyncExternalStore,
} from "react";
import { AppState } from "react-native";
import {
  type BattleView,
  type EffectTier,
  type Gift,
  type GiftingClient,
  type RoomBattle,
  ROOM_REFRESH_JITTER_MS,
  RoomClient,
  type RoomClientOptions,
  type RoomGiftEvent,
  type RoomState,
  type TierThresholds,
} from "../core";
import { type WebSocketConstructor, webSocketRoomFactory } from "../shared/room-socket";
import type { GiftEffectLayerHandle } from "./GiftEffectLayer";
import { useDisposable } from "./use-disposable";

export interface UseGiftRoomOptions {
  /** Room id, `^[A-Za-z0-9_.:-]{1,64}$`. `null`: not in a room (nothing connects). */
  room: string | null;
  /**
   * The same token function you give `createGiftingClient`. Your server mints the token with
   * `rooms` and `name` (SPEC 17.2).
   */
  getToken: (options: { forceRefresh: boolean }) => Promise<string>;
  /** Loads the catalog once so room gifts show the big picture. */
  client?: Pick<GiftingClient, "getGifts">;
  /** Room gifts play here automatically. */
  effects?: RefObject<GiftEffectLayerHandle | null>;
  onEvent?: (event: RoomGiftEvent) => void;
  onGap?: () => void;
  /** Battle scores changed (a versus round, SPEC 18.6). Or read `battle` / `useBattleScore`. */
  onBattle?: (battle: RoomBattle | null) => void;
  /** Default true: your own gifts already played on tap. */
  skipOwn?: boolean;
  /** Default 10,000. */
  maxReplayAgeMs?: number;
  minTier?: EffectTier;
  thresholds?: Partial<TierThresholds>;
  resolveName?: (user: string) => string | null | undefined;
  /** Border colours of the two battle sides in the gift notice; pass the bar's `sideColors` (SPEC 7.4). */
  sideColors?: readonly string[];
  /** Default `wss://rt.giftingstack.com`. `ws://` only to localhost, 127.0.0.1, ::1, 10.0.2.2. */
  url?: string;
  /** Allow a plain `ws://` `url` to any host. Default false. For development only. */
  allowInsecure?: boolean;
  /** For tests. Default: React Native's global `WebSocket`. */
  WebSocket?: WebSocketConstructor;
}

export interface UseGiftRoom {
  state: RoomState;
  /** Approximate viewer count, null before the first `welcome`. */
  viewers: number | null;
  /** The battle round and its scores as last received; null when the room has none. */
  battle: RoomBattle | null;
  controller: RoomClient;
  /** Leave before unmounting (unmounting leaves too). */
  leave: () => void;
}

const NO_ROOM = "\u0000";

/**
 * Keeps the screen in a gift room while mounted (SPEC 18): room gifts play in `effects`. The
 * socket closes when the app goes to the background and reconnects, with resume, when it comes
 * back. A new `room` leaves the old one. Send with `useGiftTray({ roomId })`.
 */
export function useGiftRoom(options: UseGiftRoomOptions): UseGiftRoom {
  const latest = useRef(options);
  latest.current = options;
  const catalog = useRef<Gift[] | null>(null);
  const room = options.room ?? NO_ROOM;

  const controller = useDisposable(
    () => new RoomClient(roomOptions(room, latest, catalog)),
    [room],
    (c) => {
      // Mounted in the background: connect when the app becomes active.
      if (room !== NO_ROOM && AppState.currentState !== "background") c.start();
    },
  );
  controller.setOptions(roomOptions(room, latest, catalog));
  const state = useSyncExternalStore(controller.subscribe, controller.getState);
  const battle = useSyncExternalStore(controller.subscribeBattle, controller.getBattle);

  const client = options.client;
  useEffect(() => {
    if (!client || room === NO_ROOM) return;
    let alive = true;
    client.getGifts().then(
      (gifts) => {
        if (alive) catalog.current = gifts;
      },
      () => {},
    );
    return () => {
      alive = false;
    };
  }, [client, room]);

  useEffect(() => {
    if (room === NO_ROOM) return;
    const sub = AppState.addEventListener("change", (s) => {
      if (s === "background") controller.pause();
      else if (s === "active") {
        if (controller.getState().status === "idle") controller.start();
        controller.resume();
        // Like the web page becoming visible: skip a pending wait, or start again after a stop
        // the app can retry (SPEC 18.3).
        controller.reconnectNow();
      }
    });
    return () => sub?.remove();
  }, [controller, room]);

  return { state, viewers: state.viewers, battle, controller, leave: controller.leave };
}

/**
 * A battle bar (SPEC 18.6): `battleView` of the room's round, re-rendered on every scores
 * frame and every `tickMs` (default 1,000; 0 = off) while the round is open, so a countdown
 * from `remainingMs` keeps moving. Null without a round. Pass `useGiftRoom(...).controller`.
 */
export function useBattleScore(
  controller: RoomClient | null,
  options: { tickMs?: number } = {},
): BattleView | null {
  const subscribe = useCallback(
    (l: () => void) => controller?.subscribeBattle(l) ?? (() => {}),
    [controller],
  );
  const battle = useSyncExternalStore(subscribe, () => controller?.getBattle() ?? null);
  const [, tick] = useReducer((n: number) => n + 1, 0);
  const view = controller && battle ? controller.getBattleView() : null;
  const open = view?.open ?? false;
  const every = options.tickMs ?? 1_000;
  useEffect(() => {
    if (!open || every <= 0) return;
    const timer = setInterval(tick, every);
    return () => clearInterval(timer);
  }, [open, every]);
  return view;
}

function roomOptions(
  room: string,
  latest: { current: UseGiftRoomOptions },
  catalog: { current: Gift[] | null },
): RoomClientOptions {
  const o = latest.current;
  return {
    room,
    getToken: (x) => latest.current.getToken(x),
    socket: webSocketRoomFactory(o.WebSocket),
    url: o.url,
    allowInsecure: o.allowInsecure,
    getCatalog: () => catalog.current,
    skipOwn: o.skipOwn,
    maxReplayAgeMs: o.maxReplayAgeMs,
    minTier: o.minTier,
    thresholds: o.thresholds,
    resolveName: o.resolveName,
    sideColors: o.sideColors,
    onEvent: (event) => {
      latest.current.effects?.current?.play(event);
      latest.current.onEvent?.(event);
    },
    onGap: () => latest.current.onGap?.(),
    onBattle: (battle) => latest.current.onBattle?.(battle),
    refreshJitterMs: ROOM_REFRESH_JITTER_MS,
  };
}
