import {
  type GiftEffectReceiver,
  type BattleView,
  type EffectTier,
  type Gift,
  type GiftEffectEvent,
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

/** Anything with `play`: a `GiftEffectLayer`, or your own player. */
export interface RoomEffectPlayer {
  play(event: GiftEffectEvent): unknown;
}

export interface JoinRoomOptions {
  /** Room id, `^[A-Za-z0-9_.:-]{1,64}$` (your stream, audio room or chat id). */
  room: string;
  /**
   * The same token function you give `createGiftingClient`. Your server mints the token with
   * `POST /v1/client-tokens` and, for rooms, `rooms` (allowed room ids or `prefix*`) and `name`
   * (the display name viewers see).
   */
  getToken: (options: { forceRefresh: boolean }) => Promise<string>;
  /** Loads the catalog once (`getGifts`) so events show the big picture, not only the icon. */
  client?: Pick<GiftingClient, "getGifts">;
  /** Every room gift plays here automatically. */
  effects?: RoomEffectPlayer | (() => RoomEffectPlayer | null | undefined);
  onEvent?: (event: RoomGiftEvent) => void;
  onViewers?: (n: number) => void;
  onGap?: () => void;
  onState?: (state: RoomState) => void;
  /** Battle scores changed (a versus round, SPEC 18.6): a new snapshot, or null when removed. */
  onBattle?: (battle: RoomBattle | null) => void;
  /** Default true: your own gifts already played on tap and are not played again. */
  skipOwn?: boolean;
  /** Default 10,000: older events (after a reconnect) are dropped. */
  maxReplayAgeMs?: number;
  /** Only gifts of this tier or bigger. Default `"small"` (all). */
  minTier?: EffectTier;
  thresholds?: Partial<TierThresholds>;
  /** Display name of a sender whose token has no `name`. Default: the effect layer's "Someone". */
  resolveName?: (user: string) => string | null | undefined;
  /**
   * The border colours of the two battle sides in the gift notice (SPEC 7.4), the same pair you
   * give the battle bar. Default: the theme's accent and coin colour.
   */
  sideColors?: readonly string[];
  /** Default true: disconnect after the page is hidden for 60 s, reconnect when it is visible. */
  pauseWhenHidden?: boolean;
  /** Default `wss://rt.giftingstack.com`. `ws://` only to localhost, 127.0.0.1, ::1, 10.0.2.2. */
  url?: string;
  /** Allow a plain `ws://` `url` to any host. Default false. For development only. */
  allowInsecure?: boolean;
  /** For tests: a `WebSocket` constructor. Default: the browser's. */
  WebSocket?: WebSocketConstructor;
}

export interface RoomHandle {
  readonly controller: RoomClient;
  getState(): RoomState;
  /** Approximate viewer count, null before the first `welcome`. */
  readonly viewers: number | null;
  /** State changes; returns the unsubscribe function. */
  subscribe(listener: () => void): () => void;
  /** Every gift that passes the filters; returns the unsubscribe function. */
  onEvent(listener: (event: RoomGiftEvent) => void): () => void;
  /** The battle round and its scores as last received; null when the room has none. */
  readonly battle: RoomBattle | null;
  /** `battleView` now (shares, leader, time left), null without a round. */
  battleView(): BattleView | null;
  /**
   * The battle side a user is on now (SPEC 18.4): pass it to the tray as `receiverOf` so your own
   * gift says who got it too. Undefined outside a round.
   */
  receiverFor(user: string): GiftEffectReceiver | undefined;
  /** Battle changes; returns the unsubscribe function. */
  onBattle(listener: (battle: RoomBattle | null) => void): () => void;
  /**
   * Changes settings without a new socket: `getToken`, `client` (the catalog is fetched again),
   * the filters (`minTier`, `skipOwn`, `maxReplayAgeMs`, `thresholds`, `resolveName`),
   * `effects` and `pauseWhenHidden`. A key given as `undefined` goes back to its default.
   * `room`, `url` and `allowInsecure` need a new `joinRoom`.
   */
  setOptions(patch: RoomLiveOptions): void;
  /** Leave for good (closes the socket, removes the page listeners). Safe to call twice. */
  leave(): void;
}

/** The settings of a joined room that can change while it stays connected. */
export type RoomLiveOptions = Partial<
  Pick<
    JoinRoomOptions,
    | "getToken"
    | "client"
    | "effects"
    | "minTier"
    | "skipOwn"
    | "maxReplayAgeMs"
    | "thresholds"
    | "resolveName"
    | "sideColors"
    | "pauseWhenHidden"
  >
>;

/** A page hidden this long disconnects (design 5.2). */
export const HIDDEN_PAUSE_MS = 60_000;

/**
 * Joins a gift room: everyone in it sees every gift sent with this `roomId` (SPEC 17-18). Pass
 * the effect layer as `effects` and room gifts play by themselves; send with
 * `createGiftTray({ roomId })` so your own gifts reach the others. Reconnects, resumes and
 * refreshes the token by itself.
 */
export function joinRoom(options: JoinRoomOptions): RoomHandle {
  let catalog: Gift[] | null = null;
  // The settings that may change while connected (`setOptions`); read at each use.
  const live: JoinRoomOptions = { ...options };
  const play = (event: RoomGiftEvent) => {
    const fx = live.effects;
    const player = typeof fx === "function" ? fx() : fx;
    player?.play(event);
  };
  const socket = webSocketRoomFactory(options.WebSocket);
  const buildOptions = (): RoomClientOptions => ({
    room: options.room,
    getToken: (o) => live.getToken(o),
    socket,
    url: options.url,
    allowInsecure: options.allowInsecure,
    getCatalog: () => catalog,
    skipOwn: live.skipOwn,
    maxReplayAgeMs: live.maxReplayAgeMs,
    minTier: live.minTier,
    thresholds: live.thresholds,
    resolveName: live.resolveName,
    sideColors: live.sideColors,
    onEvent: (event) => {
      play(event);
      options.onEvent?.(event);
    },
    onViewers: options.onViewers,
    onGap: options.onGap,
    onState: options.onState,
    onBattle: options.onBattle,
    refreshJitterMs: ROOM_REFRESH_JITTER_MS,
  });
  const room = new RoomClient(buildOptions());

  const loadCatalog = () =>
    live.client?.getGifts().then(
      (gifts) => (catalog = gifts),
      () => {
        // Only the icon then: the event carries it.
      },
    );
  void loadCatalog();

  const cleanups: (() => void)[] = [];
  const doc = typeof document === "undefined" ? null : document;
  if (doc) {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const onVisibility = () => {
      clearTimeout(timer);
      if (!(live.pauseWhenHidden ?? true)) return;
      if (doc.hidden) timer = setTimeout(room.pause, HIDDEN_PAUSE_MS);
      else {
        room.resume();
        room.reconnectNow();
      }
    };
    doc.addEventListener("visibilitychange", onVisibility);
    cleanups.push(() => {
      clearTimeout(timer);
      doc.removeEventListener("visibilitychange", onVisibility);
    });
  }
  if (typeof window !== "undefined") {
    const onOnline = () => room.reconnectNow();
    window.addEventListener("online", onOnline);
    cleanups.push(() => window.removeEventListener("online", onOnline));
  }

  room.start();
  return {
    controller: room,
    getState: room.getState,
    get viewers() {
      return room.getState().viewers;
    },
    subscribe: room.subscribe,
    onEvent: room.onEvent,
    get battle() {
      return room.getBattle();
    },
    battleView: room.getBattleView,
    receiverFor: room.receiverFor,
    onBattle: (listener) => room.subscribeBattle(() => listener(room.getBattle())),
    setOptions(patch) {
      const clientChanged = "client" in patch && patch.client !== live.client;
      Object.assign(live, patch);
      room.setOptions(buildOptions());
      if (clientChanged) void loadCatalog();
    },
    leave() {
      for (const c of cleanups.splice(0)) c();
      room.leave();
    },
  };
}
