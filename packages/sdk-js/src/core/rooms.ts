/**
 * Gift rooms, client side (SPEC section 17 is the wire protocol, section 18 the client rules,
 * docs/design/gift-rooms.md the design). Everything here is pure: the socket, the clock, the
 * timers, the random source and the token are injected, so the fixtures `rooms-*.json` can drive
 * it. Platforms add only a socket transport and app lifecycle hooks.
 *
 * Pieces: `parseRoomFrame`/`roomHelloFrame` (protocol), `roomRetryDecision` (reconnect policy),
 * `RoomEventFilter` (resume point, dedup, staleness, own gifts, tier filter), `roomGiftToEffect`
 * (event -> `GiftEffectEvent`), `battleView` (battle scores, SPEC 17.8 and 18.6) and
 * `RoomClient` (the session state machine).
 */
import { type EffectTier, type TierThresholds, tierFor } from "./recipes";
import type { Gift, GiftEffectEvent, GiftEffectReceiver } from "./types";
import { assertSecureUrl } from "./url";

/** The only subprotocol; the client token rides as the second entry. */
export const ROOM_SUBPROTOCOL = "gs.v1";
export const DEFAULT_ROOMS_URL = "wss://rt.giftingstack.com";
/** Room id rule (SPEC 17.1). */
export const ROOM_ID_PATTERN = /^[A-Za-z0-9_.:-]{1,64}$/;
/** Events older than this (server clock) are dropped instead of played. */
export const DEFAULT_MAX_REPLAY_AGE_MS = 10_000;
/** Recent `tx` ids remembered for dedup. */
export const ROOM_DEDUP_SIZE = 256;
/** Full jitter: `random(0, min(30 s, 0.5 s x 2^attempt))`, never below the floor (SPEC 18.3). */
export const ROOM_BACKOFF_BASE_MS = 500;
export const ROOM_BACKOFF_MAX_MS = 30_000;
/** First retry after a drop (1006) or a server restart (1012): `random(0, 5 s)`. */
export const ROOM_FIRST_DROP_MAX_MS = 5_000;
/** A jittered wait is never shorter than this, so a zero draw cannot start a tight loop. */
export const ROOM_RETRY_FLOOR_MS = 500;
/**
 * Reconnect attempts in a row (no socket that stayed open `ROOM_STABLE_MS` in between) before the
 * client gives up: the state becomes `closed` with reason `ROOM_REASON_EXHAUSTED`, and
 * `reconnectNow()` starts again with a fresh budget. About 3.5 minutes at the longest.
 */
export const ROOM_MAX_ATTEMPTS = 12;
/** `closed` reason after `ROOM_MAX_ATTEMPTS` failed attempts in a row. */
export const ROOM_REASON_EXHAUSTED = "retries_exhausted";
/** `getToken` has this long, from the start of a connection, to answer (SPEC 18.5 step 1). */
export const ROOM_TOKEN_MS = 20_000;
/** Rate limited (4008) or room full (4009): wait at least this, at most 5 times in a row. */
export const ROOM_LIMITED_MIN_MS = 30_000;
export const ROOM_LIMITED_MAX_RETRIES = 5;
/**
 * A 4008 whose reason carries `retry_after` is a platform limit that lifts by itself (a rooms
 * deploy makes every viewer rejoin at once): such a client never gives up. Its wait grows with
 * the waits in a row, up to this cap (SPEC 18.3).
 */
export const ROOM_LIMITED_MAX_MS = 300_000;
/** Spread of the proactive token refresh (the platform entry points set it; SPEC 18.5). */
export const ROOM_REFRESH_JITTER_MS = 120_000;
/** The attempt counters reset after a socket stayed open this long. */
export const ROOM_STABLE_MS = 60_000;
/** App heartbeat (web, React Native): `ping` after this long without any frame. */
export const ROOM_HEARTBEAT_MS = 45_000;
/** No frame within this after `ping`, or no `welcome` this long after opening: the socket is dead. */
export const ROOM_DEAD_MS = 10_000;
/** A socket never lives longer than this (design D8); the server closes it with 4001 anyway. */
export const ROOM_MAX_LIFETIME_MS = 60 * 60 * 1000;
/** Reconnect with a fresh token this long before the server would close the socket. */
export const ROOM_REFRESH_AHEAD_MS = 30_000;

/** Close codes (SPEC 17.6). */
export const ROOM_CLOSE = {
  TOKEN_EXPIRED: 4001,
  FORBIDDEN: 4003,
  BAD_ROOM_ID: 4004,
  RATE_LIMITED: 4008,
  ROOM_FULL: 4009,
  PLAN: 4010,
  SUSPENDED: 4011,
  PROTOCOL: 4400,
} as const;

// ---------------------------------------------------------------- protocol

/** A `gift` event as the server sends it, unknown fields dropped. */
export interface RoomGiftMessage {
  t: "gift";
  id: number;
  at: number;
  tx: string;
  gift: { id: string; name: string; price: number; icon_url: string | null };
  quantity: number;
  sender: { id: string; name?: string };
  receiver: { id: string } | null;
}

/** One receiver's running total in a battle round (SPEC 17.8). Display counters only. */
export interface RoomScoreEntry {
  /** Receiver external id. */
  id: string;
  /** Sum of unit price x quantity of the counted gifts. */
  units: number;
  /** Number of counted gifts. */
  gifts: number;
}

/** A battle round with its scores, in the server's fixed order (the round's receivers first). */
export interface RoomBattle {
  round: string;
  /** Epoch ms (server clock). */
  started: number;
  /** Epoch ms (server clock): gifts from then on no longer count. */
  ends: number;
  scores: RoomScoreEntry[];
}

export interface RoomWelcomeMessage {
  t: "welcome";
  viewers: number;
  gap: boolean;
  replay: RoomGiftMessage[];
  /** Seconds until the server closes the socket with 4001. */
  ttl: number;
  /** Server time, epoch ms. */
  now: number;
  /** The room's battle round; absent when there is none (or it was malformed). */
  battle?: RoomBattle;
}

export type RoomServerMessage =
  | RoomWelcomeMessage
  | RoomGiftMessage
  | { t: "viewers"; n: number }
  | { t: "batch"; events: RoomGiftMessage[] }
  | { t: "scores"; battle: RoomBattle | null }
  | { t: "pong" };

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);
const isCount = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) >= 0;

function parseGift(v: unknown): RoomGiftMessage | null {
  if (!isObj(v) || v.t !== "gift") return null;
  const { gift, sender, receiver } = v;
  if (
    !isCount(v.id) ||
    !isCount(v.at) ||
    typeof v.tx !== "string" ||
    v.tx === "" ||
    !isObj(gift) ||
    typeof gift.id !== "string" ||
    typeof gift.name !== "string" ||
    !isCount(gift.price) ||
    !Number.isSafeInteger(v.quantity) ||
    (v.quantity as number) < 1 ||
    !isObj(sender) ||
    typeof sender.id !== "string"
  ) {
    return null;
  }
  return {
    t: "gift",
    id: v.id,
    at: v.at,
    tx: v.tx,
    gift: {
      id: gift.id,
      name: gift.name,
      price: gift.price,
      icon_url: typeof gift.icon_url === "string" ? gift.icon_url : null,
    },
    quantity: v.quantity as number,
    sender:
      typeof sender.name === "string" && sender.name !== ""
        ? { id: sender.id, name: sender.name }
        : { id: sender.id },
    receiver: isObj(receiver) && typeof receiver.id === "string" ? { id: receiver.id } : null,
  };
}

/** A battle object, or null when malformed. Invalid score entries are dropped alone. */
function parseBattle(v: unknown): RoomBattle | null {
  if (!isObj(v) || typeof v.round !== "string" || v.round === "") return null;
  if (!isCount(v.started) || !isCount(v.ends) || !Array.isArray(v.scores)) return null;
  const scores: RoomScoreEntry[] = [];
  for (const e of v.scores) {
    if (isObj(e) && typeof e.id === "string" && isCount(e.units) && isCount(e.gifts)) {
      scores.push({ id: e.id, units: e.units, gifts: e.gifts });
    }
  }
  return { round: v.round, started: v.started, ends: v.ends, scores };
}

const giftList = (v: unknown): RoomGiftMessage[] | null =>
  Array.isArray(v) ? v.map(parseGift).filter((g): g is RoomGiftMessage => g !== null) : null;

/**
 * One server frame, or `null` for anything to ignore: not JSON, an unknown `t`, a known `t` with
 * a missing or mistyped required field. Unknown fields are dropped; inside `replay` and `events`
 * an invalid gift is dropped alone. The literal text `pong` is `{ t: "pong" }`.
 */
export function parseRoomFrame(data: unknown): RoomServerMessage | null {
  if (typeof data !== "string") return null;
  if (data === "pong") return { t: "pong" };
  let v: unknown;
  try {
    v = JSON.parse(data);
  } catch {
    return null;
  }
  if (!isObj(v)) return null;
  switch (v.t) {
    case "gift":
      return parseGift(v);
    case "welcome": {
      const replay = giftList(v.replay ?? []);
      if (
        !isCount(v.viewers) ||
        typeof v.gap !== "boolean" ||
        replay === null ||
        typeof v.ttl !== "number" ||
        !(v.ttl >= 0) ||
        !isCount(v.now)
      ) {
        return null;
      }
      const welcome: RoomWelcomeMessage = {
        t: "welcome",
        viewers: v.viewers,
        gap: v.gap,
        replay,
        ttl: v.ttl,
        now: v.now,
      };
      const battle = parseBattle(v.battle);
      if (battle) welcome.battle = battle;
      return welcome;
    }
    case "scores": {
      if (v.battle === null) return { t: "scores", battle: null };
      const battle = parseBattle(v.battle);
      return battle ? { t: "scores", battle } : null;
    }
    case "viewers":
      return isCount(v.n) ? { t: "viewers", n: v.n } : null;
    case "batch": {
      const events = giftList(v.events);
      return events === null ? null : { t: "batch", events };
    }
    default:
      return null;
  }
}

/** The first frame after open: `{"t":"hello","v":1,"last":<id|null>}`, keys in this order. */
export function roomHelloFrame(last: number | null): string {
  return JSON.stringify({ t: "hello", v: 1, last });
}

/** `wss://rt.giftingstack.com/v1/rooms/<room>` (trailing slashes of `baseUrl` removed). */
export function roomUrl(room: string, baseUrl: string = DEFAULT_ROOMS_URL): string {
  return `${baseUrl.replace(/\/+$/, "")}/v1/rooms/${encodeURIComponent(room)}`;
}

/**
 * The user a client token was minted for (claim `u`), or `null` when the token is not a
 * GiftingStack client token. Used only to skip the user's own gifts; the token is not verified
 * here (the server does that).
 */
export function roomTokenUser(token: string): string | null {
  const m = /^gs_ct_([A-Za-z0-9_-]+)\./.exec(token);
  if (!m) return null;
  try {
    const claims: unknown = JSON.parse(base64UrlToText(m[1] as string));
    return isObj(claims) && typeof claims.u === "string" ? claims.u : null;
  } catch {
    return null;
  }
}

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/** No `atob`/`TextDecoder` needed (older React Native runtimes lack them). */
function base64UrlToText(s: string): string {
  let bits = 0;
  let acc = 0;
  let pct = "";
  for (const ch of s) {
    const v = B64.indexOf(ch);
    if (v < 0) throw new Error("bad base64url");
    acc = (acc << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      pct += "%" + ((acc >> bits) & 0xff).toString(16).padStart(2, "0");
    }
  }
  return decodeURIComponent(pct);
}

// ---------------------------------------------------------------- reconnect policy

export interface RoomRetryInput {
  code: number;
  reason: string;
  /** Failed connections in a row before this one (0 = the first since a stable socket). */
  attempt: number;
  /** 4008/4009 waits in a row before this one. */
  limited: number;
}

export type RoomRetryDecision =
  | {
      retry: false;
      /**
       * Present (true) when the client stopped by its own rule, not because the server said it is
       * final: `reconnectNow()` may start again (SPEC 18.3). Absent for a final close.
       */
      resumable?: true;
      /** Present (true) after `ROOM_MAX_ATTEMPTS` failed attempts in a row. */
      exhausted?: true;
    }
  | {
      retry: true;
      delayMs: number;
      /** Ask `getToken` with `forceRefresh: true` before reconnecting. */
      refreshToken: boolean;
      /** A rate-limit/room-full wait: counts against the 5 such waits. */
      limited: boolean;
    };

/** `retry_after` of a JSON close reason, in whole seconds; 0 when absent or not a count. */
function retryAfterSeconds(reason: string): number {
  try {
    const v: unknown = JSON.parse(reason);
    return isObj(v) && isCount(v.retry_after) ? v.retry_after : 0;
  } catch {
    return 0;
  }
}

/**
 * Wait after a 4008 that carried `retry_after` (seconds): `max(30 s, retry_after)` doubled per
 * wait already in a row (`limited`), plus up to 25 % jitter, never above 5 minutes. Calls
 * `random` once.
 */
export function roomRateLimitedDelayMs(
  retryAfterS: number,
  limited: number,
  random: () => number,
): number {
  const base = Math.max(ROOM_LIMITED_MIN_MS, retryAfterS * 1000);
  const grown = Math.min(ROOM_LIMITED_MAX_MS, base * 2 ** Math.min(Math.max(0, limited), 16));
  return Math.min(ROOM_LIMITED_MAX_MS, grown + Math.floor(random() * (grown / 4)));
}

/**
 * What to do after a socket closed (SPEC 18.3). `random` returns [0, 1) and is called at most
 * once, only for a jittered delay: `ROOM_RETRY_FLOOR_MS + floor(random() * (cap - floor))`.
 */
export function roomRetryDecision(input: RoomRetryInput, random: () => number): RoomRetryDecision {
  const { code, reason, attempt } = input;
  const jitter = (cap: number) =>
    ROOM_RETRY_FLOOR_MS + Math.floor(random() * Math.max(0, cap - ROOM_RETRY_FLOOR_MS));
  const backoff = () =>
    jitter(Math.min(ROOM_BACKOFF_MAX_MS, ROOM_BACKOFF_BASE_MS * 2 ** Math.max(0, attempt)));
  switch (code) {
    case ROOM_CLOSE.FORBIDDEN:
    case ROOM_CLOSE.BAD_ROOM_ID:
    case ROOM_CLOSE.PLAN:
    case ROOM_CLOSE.PROTOCOL:
      return { retry: false };
    case ROOM_CLOSE.SUSPENDED:
      return { retry: false, resumable: true };
    case ROOM_CLOSE.ROOM_FULL:
    case ROOM_CLOSE.RATE_LIMITED: {
      if (code === ROOM_CLOSE.ROOM_FULL && reason === "replaced") return { retry: false };
      const retryAfter = retryAfterSeconds(reason);
      if (code === ROOM_CLOSE.RATE_LIMITED && retryAfter > 0) {
        // A platform limit that lifts by itself: grows, never gives up (and is not counted
        // against the attempt ceiling).
        return {
          retry: true,
          delayMs: roomRateLimitedDelayMs(retryAfter, input.limited, random),
          refreshToken: false,
          limited: true,
        };
      }
      if (input.limited >= ROOM_LIMITED_MAX_RETRIES) return { retry: false, resumable: true };
      return {
        retry: true,
        delayMs: Math.max(ROOM_LIMITED_MIN_MS, retryAfter * 1000),
        refreshToken: false,
        limited: true,
      };
    }
    default:
      break;
  }
  if (attempt >= ROOM_MAX_ATTEMPTS) return { retry: false, resumable: true, exhausted: true };
  switch (code) {
    case ROOM_CLOSE.TOKEN_EXPIRED:
      return {
        retry: true,
        delayMs: attempt === 0 ? 0 : backoff(),
        refreshToken: true,
        limited: false,
      };
    case 1006:
    case 1012:
      return {
        retry: true,
        delayMs: attempt === 0 ? jitter(ROOM_FIRST_DROP_MAX_MS) : backoff(),
        refreshToken: false,
        limited: false,
      };
    default:
      return { retry: true, delayMs: backoff(), refreshToken: false, limited: false };
  }
}

// ---------------------------------------------------------------- filter

const TIER_RANK: Record<EffectTier, number> = { small: 0, medium: 1, large: 2 };

export interface RoomEventFilterOptions {
  /** The signed-in user (token claim `u`): with `skipOwn`, their gifts are not played again. */
  user?: string | null;
  /** Default true: the sender's own tray already played the effect on tap. */
  skipOwn?: boolean;
  /** Default 10,000. Events at least this old (server clock) are dropped. */
  maxReplayAgeMs?: number;
  /** Viewer-side filter: only gifts of this tier or bigger. Default `"small"` (all). */
  minTier?: EffectTier;
  thresholds?: Partial<TierThresholds>;
}

export interface RoomFilterResult {
  /** The gifts to play, in order. */
  events: RoomGiftMessage[];
  /** `welcome.gap`: events may have been missed. Always false for live frames. */
  gap: boolean;
}

/**
 * Decides which received gifts reach the app (SPEC 18.2). Keeps the resume point `last` (id of
 * the last gift received, played or not) and the last 256 `tx` across reconnects. Each gift, in
 * order: `last = id`; a `tx` seen before is dropped; then (the `tx` is remembered) a gift whose
 * age `serverNow - at` is at least `maxReplayAgeMs` is dropped, then the user's own gift
 * (`skipOwn`), then a gift below `minTier`. `serverNow` is `welcome.now` for the replay and
 * `welcome.now + (localNow - local time of the welcome)` for live gifts.
 */
export class RoomEventFilter {
  private options: RoomEventFilterOptions;
  /** Resume point sent in `hello`. */
  last: number | null = null;
  private readonly seen = new Set<string>();
  private readonly order: string[] = [];
  /** `welcome.now - local time of the welcome`; null before the first welcome. */
  private offset: number | null = null;

  constructor(options: RoomEventFilterOptions = {}) {
    this.options = options;
  }

  setOptions(options: RoomEventFilterOptions): void {
    this.options = options;
  }

  /** Server time for a local time, from the last welcome; null before the first welcome. */
  serverNow(localNow: number): number | null {
    return this.offset === null ? null : localNow + this.offset;
  }

  /** The `tx` ids remembered, oldest first. */
  seenTx(): string[] {
    return [...this.order];
  }

  welcome(msg: RoomWelcomeMessage, localNow: number): RoomFilterResult {
    this.offset = msg.now - localNow;
    return { events: this.pass(msg.replay, msg.now), gap: msg.gap };
  }

  /** A live `gift` or `batch`. Before any welcome nothing passes (the server never does that). */
  live(events: readonly RoomGiftMessage[], localNow: number): RoomFilterResult {
    if (this.offset === null) return { events: [], gap: false };
    return { events: this.pass(events, localNow + this.offset), gap: false };
  }

  private pass(events: readonly RoomGiftMessage[], serverNow: number): RoomGiftMessage[] {
    const o = this.options;
    const maxAge = o.maxReplayAgeMs ?? DEFAULT_MAX_REPLAY_AGE_MS;
    const min = TIER_RANK[o.minTier ?? "small"];
    const out: RoomGiftMessage[] = [];
    for (const e of events) {
      this.last = e.id;
      if (this.seen.has(e.tx)) continue;
      this.remember(e.tx);
      if (serverNow - e.at >= maxAge) continue;
      if ((o.skipOwn ?? true) && o.user != null && e.sender.id === o.user) continue;
      if (TIER_RANK[tierFor(e.gift.price, o.thresholds)] < min) continue;
      out.push(e);
    }
    return out;
  }

  private remember(tx: string): void {
    this.seen.add(tx);
    this.order.push(tx);
    while (this.order.length > ROOM_DEDUP_SIZE) this.seen.delete(this.order.shift() as string);
  }
}

// ---------------------------------------------------------------- mapping

/** A room gift ready for the effect layer: pass it straight to `play`. */
export interface RoomGiftEvent extends GiftEffectEvent {
  gift: GiftEffectEvent["gift"] & { icon: string | null };
  quantity: number;
  /** Event id (the resume point). */
  id: number;
  /** Gift transaction id. */
  tx: string;
  /** Commit time, epoch ms (server clock). */
  at: number;
  /** The sender's external id. */
  senderId: string;
  /** The sender's display name from their token (claim `n`), else null. */
  senderName: string | null;
  receiverId: string | null;
  /** Came in the `welcome` replay after a (re)connect, not live. */
  replayed: boolean;
}

export interface RoomMappingOptions {
  /** The app's gift catalog (`GET /v1/client/gifts`): supplies the big picture. */
  catalog?: readonly Gift[] | null;
  /** Display name of a sender without a name claim. Return undefined for the default. */
  resolveName?: (user: string) => string | null | undefined;
  replayed?: boolean;
  /**
   * The room's current battle (`RoomClient.getBattle()`). With two or more sides and the gift's
   * receiver one of the first two, the event gets a `receiver` (SPEC 18.4). `RoomClient` passes it.
   */
  battle?: RoomBattle | null;
  /** The bar's `sideColors`: the border colour of every side, by side (same list as the bar's). */
  sideColors?: readonly string[];
}

/**
 * Turns a room gift into what the effect layer plays (SPEC 18.4): name and price from the event
 * (the price at send time drives the tier); `image` = the catalog gift's `animation_url`, else
 * its `icon_url`, else the event's `icon_url`; `icon` = the event's `icon_url`, else the
 * catalog's; `sender` = the name claim, else `resolveName(sender id)`, else absent (the effect
 * layer then shows "Someone").
 */
export function roomGiftToEffect(
  msg: RoomGiftMessage,
  options: RoomMappingOptions = {},
): RoomGiftEvent {
  const known = options.catalog?.find((g) => g.id === msg.gift.id);
  const image = known?.animation_url ?? known?.icon_url ?? msg.gift.icon_url;
  const icon = msg.gift.icon_url ?? known?.icon_url ?? null;
  const senderName = msg.sender.name ?? null;
  let sender: string | undefined = senderName ?? undefined;
  if (sender === undefined && options.resolveName) {
    try {
      sender = options.resolveName(msg.sender.id) || undefined;
    } catch {
      sender = undefined;
    }
  }
  const event: RoomGiftEvent = {
    gift: { id: msg.gift.id, name: msg.gift.name, price: msg.gift.price, image, icon },
    quantity: msg.quantity,
    id: msg.id,
    tx: msg.tx,
    at: msg.at,
    senderId: msg.sender.id,
    senderName,
    receiverId: msg.receiver?.id ?? null,
    replayed: options.replayed ?? false,
  };
  if (sender !== undefined) event.sender = sender;
  const receiver = battleReceiver(msg.receiver?.id, msg.at, options);
  if (receiver) event.receiver = receiver;
  return event;
}

/**
 * The receiving side of a gift in a battle (SPEC 18.4), or undefined. Only a gift of the round
 * itself counts: `battle.started <= at < battle.ends` (a replayed gift from before the round, or one
 * at the end or later, is no battle gift), the battle has two or more sides and `receiver` is one of
 * them (any of the up to 8). `RoomClient.receiverFor` is this for "now"; the tray uses it for the user's own gifts.
 */
export function battleReceiver(
  receiver: string | null | undefined,
  at: number,
  options: Pick<RoomMappingOptions, "battle" | "resolveName" | "sideColors">,
): GiftEffectReceiver | undefined {
  const round = options.battle;
  if (!receiver || !round || round.scores.length < 2 || at < round.started || at >= round.ends) {
    return undefined;
  }
  const side = round.scores.findIndex((s) => s.id === receiver);
  if (side < 0) return undefined;
  let name: string | undefined;
  if (options.resolveName) {
    try {
      name = options.resolveName(receiver) || undefined;
    } catch {
      name = undefined;
    }
  }
  return { name: name ?? receiver, side, color: options.sideColors?.[side] ?? null };
}

// ---------------------------------------------------------------- battle scores

/** One side of a battle bar. */
export interface BattleSide extends RoomScoreEntry {
  /** `units / total`, 0..1; an equal split while nobody has scored. */
  share: number;
}

export interface BattleView {
  round: string;
  /** The round still counts: `started <= serverNow < ends`. */
  open: boolean;
  /** `max(0, ends - serverNow)`, ms. */
  remainingMs: number;
  /** Sum of every side's `units`. */
  total: number;
  /** The server's order (the round's receivers first): keep it for a stable left/right bar. */
  sides: BattleSide[];
  /** The receiver with the most units; null while nobody has scored or the top is tied. */
  leader: string | null;
}

/**
 * What a battle bar shows (SPEC 18.6), pure. `serverNow` is the server clock (`RoomClient`
 * keeps the offset from the last welcome); null (no welcome yet) reads as the round's start.
 */
export function battleView(battle: RoomBattle, serverNow: number | null): BattleView {
  const now = serverNow ?? battle.started;
  const total = battle.scores.reduce((sum, e) => sum + e.units, 0);
  const n = battle.scores.length;
  const sides = battle.scores.map((e) => ({
    id: e.id,
    units: e.units,
    gifts: e.gifts,
    share: total > 0 ? e.units / total : 1 / n,
  }));
  let leader: string | null = null;
  let best = 0;
  let tied = false;
  for (const e of battle.scores) {
    if (e.units > best) {
      best = e.units;
      leader = e.id;
      tied = false;
    } else if (e.units === best && best > 0) {
      tied = true;
    }
  }
  return {
    round: battle.round,
    open: now >= battle.started && now < battle.ends,
    remainingMs: Math.max(0, battle.ends - now),
    total,
    sides,
    leader: tied ? null : leader,
  };
}

// ---------------------------------------------------------------- session

/** What a platform transport implements: one WebSocket, text frames only. */
export interface RoomSocket {
  send(data: string): void;
  /** Close the socket. After this the client ignores every callback of this socket. */
  close(code: number, reason: string): void;
}

export interface RoomSocketHandlers {
  onOpen(): void;
  /** Text frames only; a transport drops binary frames. */
  onMessage(data: string): void;
  /** Exactly once per socket (an error before or after open is a close with 1006). */
  onClose(code: number, reason: string): void;
}

/** Opens `url` with the WebSocket protocols `["gs.v1", token]`. */
export type RoomSocketFactory = (
  url: string,
  protocols: string[],
  handlers: RoomSocketHandlers,
) => RoomSocket;

export type RoomStatus = "idle" | "connecting" | "open" | "reconnecting" | "paused" | "closed";

export interface RoomState {
  status: RoomStatus;
  /** Failed connections in a row. */
  attempt: number;
  /** `reconnecting`: the wait before the next attempt, ms. Else null. */
  retryInMs: number | null;
  /** `closed`: the close code (1000 after `leave()`), else the last close code seen or null. */
  code: number | null;
  reason: string | null;
  /** Approximate viewer count from the server; null before the first welcome. */
  viewers: number | null;
}

export interface RoomClientOptions extends RoomEventFilterOptions, RoomMappingOptions {
  room: string;
  /** The same token function as the client's. Mint the token with `rooms` and `name` (SPEC 17.2). */
  getToken: (options: { forceRefresh: boolean }) => Promise<string>;
  socket: RoomSocketFactory;
  /**
   * Default `wss://rt.giftingstack.com`. `ws://` is refused (the constructor throws) unless the
   * host is localhost, 127.0.0.1, ::1 or 10.0.2.2, or `allowInsecure` is true. SPEC 3.1.
   */
  url?: string;
  /** Allow a plain `ws://` URL to any host. Default false. For development only. */
  allowInsecure?: boolean;
  /** The catalog, read at each event (wins over `catalog`). */
  getCatalog?: () => readonly Gift[] | null | undefined;
  onEvent?: (event: RoomGiftEvent) => void;
  onViewers?: (n: number) => void;
  onGap?: () => void;
  onState?: (state: RoomState) => void;
  /** Battle scores changed (SPEC 18.6): a new snapshot, or null when the round was removed. */
  onBattle?: (battle: RoomBattle | null) => void;
  /**
   * App heartbeat interval (web, React Native). 0 turns it off for transports with protocol
   * pings (native). Default 45,000.
   */
  heartbeatMs?: number;
  now?: () => number;
  setTimeout?: (fn: () => void, ms: number) => unknown;
  clearTimeout?: (handle: unknown) => void;
  /** [0, 1). Default `Math.random`. */
  random?: () => number;
  /**
   * The proactive token refresh happens `random(0, refreshJitterMs)` earlier than 30 s before the
   * socket's end, so viewers that joined together do not all reconnect in the same second.
   * Default 0 (exact timing, as in the fixtures); the platform entry points use
   * `ROOM_REFRESH_JITTER_MS`.
   */
  refreshJitterMs?: number;
}

/**
 * One room membership (SPEC 18): connects, says hello, plays what the filter lets through,
 * reconnects with backoff and resume, refreshes the token, keeps a heartbeat. Never throws into
 * the app; app callbacks that throw are ignored.
 *
 * idle -start-> connecting -welcome-> open -drop-> reconnecting -> connecting ...;
 * `pause()` (app in background) -> paused -`resume()`-> connecting; `leave()` or a final close
 * code -> closed (terminal).
 */
export class RoomClient {
  private options: RoomClientOptions;
  private state: RoomState = {
    status: "idle",
    attempt: 0,
    retryInMs: null,
    code: null,
    reason: null,
    viewers: null,
  };
  private readonly listeners = new Set<() => void>();
  private readonly eventListeners = new Set<(event: RoomGiftEvent) => void>();
  private readonly battleListeners = new Set<() => void>();
  private battle: RoomBattle | null = null;
  readonly filter: RoomEventFilter;
  /** Bumped whenever the current socket or token request stops mattering. */
  private gen = 0;
  private socket: RoomSocket | null = null;
  private limited = 0;
  /** The last close was a stop by the client's own rule (SPEC 18.3): `reconnectNow()` may restart. */
  private resumable = false;
  /** The pending retry is a 4008/4009 wait (the platform said when to come back): not skippable. */
  private rateWait = false;
  private refreshNext = false;
  private tokenUser: string | null = null;
  private openedAt: number | null = null;
  private lastFrameAt = 0;
  private timers = new Map<"retry" | "dead" | "beat" | "refresh", unknown>();

  constructor(options: RoomClientOptions) {
    assertSecureUrl(options.url ?? DEFAULT_ROOMS_URL, options.allowInsecure, "url");
    this.options = options;
    this.filter = new RoomEventFilter(options);
  }

  /** Callbacks and filter settings are read when used, so they can change between calls. */
  setOptions(options: RoomClientOptions): void {
    assertSecureUrl(options.url ?? DEFAULT_ROOMS_URL, options.allowInsecure, "url");
    this.options = options;
    this.filter.setOptions(this.filterOptions());
  }

  /** `user` option, else the token's `u` claim. */
  private filterOptions(): RoomEventFilterOptions {
    return { ...this.options, user: this.options.user ?? this.tokenUser };
  }

  getState = (): RoomState => this.state;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  /**
   * The room's battle round as last received (SPEC 18.6): from `welcome`, then each `scores`
   * frame. Kept across reconnects until the next welcome; null when there is none.
   */
  getBattle = (): RoomBattle | null => this.battle;

  /** Battle changes; returns the unsubscribe function. */
  subscribeBattle = (listener: () => void): (() => void) => {
    this.battleListeners.add(listener);
    return () => this.battleListeners.delete(listener);
  };

  /** Server time now (from the last welcome), null before the first welcome. */
  serverNow = (): number | null => this.filter.serverNow(this.now());

  /**
   * The battle side `user` is on right now (SPEC 18.4), for the gifts this app plays itself: give
   * it to the tray as `receiverOf` so the user's own gift says who got it too. Undefined outside a
   * round or when `user` is no side.
   */
  receiverFor = (user: string): GiftEffectReceiver | undefined =>
    battleReceiver(user, this.serverNow() ?? this.now(), {
      battle: this.battle,
      resolveName: this.options.resolveName,
      sideColors: this.options.sideColors,
    });

  /** `battleView` of the current round at the server's time now, null without a round. */
  getBattleView = (): BattleView | null =>
    this.battle ? battleView(this.battle, this.serverNow()) : null;

  /** Every gift that passes the filter, after `onEvent`. */
  onEvent = (listener: (event: RoomGiftEvent) => void): (() => void) => {
    this.eventListeners.add(listener);
    return () => this.eventListeners.delete(listener);
  };

  /** Connect. Only from idle; a bad room id closes at once with 4004 and opens nothing. */
  start = (): void => {
    if (this.state.status !== "idle") return;
    if (!ROOM_ID_PATTERN.test(this.options.room)) {
      this.finish(ROOM_CLOSE.BAD_ROOM_ID, "bad_room_id");
      return;
    }
    this.connect();
  };

  /** Leave the room for good: closes with 1000, no callbacks after this. */
  leave = (): void => {
    if (this.state.status === "closed") return;
    this.finish(1000, "left");
  };

  /** App went to the background: close (1000), keep `last` and the dedup set, no retry. */
  pause = (): void => {
    const s = this.state.status;
    if (s === "idle" || s === "closed" || s === "paused") return;
    this.drop();
    this.set({ status: "paused", retryInMs: null });
  };

  /** Back in the foreground: reconnect now with `last`. Only from paused. */
  resume = (): void => {
    if (this.state.status !== "paused") return;
    this.connect();
  };

  /**
   * The network is back (or the page became visible, or the user asked): skip a pending backoff
   * wait, but never a 4008/4009 wait (rate limited, room full: the platform named the time, and
   * every viewer skipping it would rejoin at once). After a stop by the client's own rule (`retries_exhausted`, 4011, the 4008/4009 limit)
   * it starts again with a fresh attempt budget. Nothing else changes.
   */
  reconnectNow = (): void => {
    if (this.state.status === "closed" && this.resumable) {
      this.resumable = false;
      this.limited = 0;
      this.set({ attempt: 0 });
      this.connect();
      return;
    }
    if (this.state.status !== "reconnecting" || this.rateWait) return;
    this.clear("retry");
    this.connect();
  };

  dispose(): void {
    this.leave();
  }

  // ---------------------------------------------------------------- internals

  private now(): number {
    return (this.options.now ?? Date.now)();
  }

  private set(patch: Partial<RoomState>): void {
    this.state = { ...this.state, ...patch };
    this.safe(() => this.options.onState?.(this.state));
    for (const l of this.listeners) this.safe(l);
  }

  private safe(fn: () => void): void {
    try {
      fn();
    } catch {
      // App callbacks never break the room.
    }
  }

  private later(name: "retry" | "dead" | "beat" | "refresh", ms: number, fn: () => void): void {
    this.clear(name);
    const schedule = this.options.setTimeout ?? ((f: () => void, t: number) => setTimeout(f, t));
    this.timers.set(
      name,
      schedule(() => {
        this.timers.delete(name);
        fn();
      }, ms),
    );
  }

  private clear(name: "retry" | "dead" | "beat" | "refresh"): void {
    const h = this.timers.get(name);
    if (h === undefined) return;
    this.timers.delete(name);
    const cancel =
      this.options.clearTimeout ??
      ((x: unknown) => clearTimeout(x as ReturnType<typeof setTimeout>));
    cancel(h);
  }

  private clearAll(): void {
    for (const name of [...this.timers.keys()]) this.clear(name);
  }

  /** Forget the current socket (closing it with 1000) and any token request in flight. */
  private drop(): void {
    this.gen += 1;
    this.clearAll();
    const s = this.socket;
    this.socket = null;
    this.openedAt = null;
    if (s) this.safe(() => s.close(1000, "client"));
  }

  private finish(code: number, reason: string): void {
    this.drop();
    this.resumable = false;
    this.set({ status: "closed", retryInMs: null, code, reason });
  }

  private connect(): void {
    this.drop();
    const gen = this.gen;
    const refresh = this.refreshNext;
    this.refreshNext = false;
    this.set({ status: "connecting", retryInMs: null });
    // A `getToken` that never answers must not keep the room connecting forever.
    this.later("dead", ROOM_TOKEN_MS, () => this.dead(gen));
    let pending: Promise<string>;
    try {
      pending = this.options.getToken({ forceRefresh: refresh });
    } catch (err) {
      pending = Promise.reject(err);
    }
    pending.then(
      (token) => {
        if (gen !== this.gen) return;
        this.open(token, gen);
      },
      () => {
        if (gen !== this.gen) return;
        // No token (the app's server is down, the user signed out): retry like a network error.
        this.closed(gen, 1006, "token_failed");
      },
    );
  }

  private open(token: string, gen: number): void {
    this.tokenUser = roomTokenUser(token);
    this.filter.setOptions(this.filterOptions());
    const url = roomUrl(this.options.room, this.options.url);
    const handlers: RoomSocketHandlers = {
      onOpen: () => {
        if (gen !== this.gen || !this.socket) return;
        this.lastFrameAt = this.now();
        this.sendFrame(roomHelloFrame(this.filter.last));
      },
      onMessage: (data) => {
        if (gen !== this.gen) return;
        this.message(data, gen);
      },
      onClose: (code, reason) => {
        if (gen !== this.gen) return;
        this.socket = null;
        this.closed(gen, code, reason);
      },
    };
    try {
      this.socket = this.options.socket(url, [ROOM_SUBPROTOCOL, token], handlers);
    } catch {
      this.closed(gen, 1006, "socket_failed");
      return;
    }
    // From creation to `welcome`: the same 10 s as a missing pong.
    this.later("dead", ROOM_DEAD_MS, () => this.dead(gen));
  }

  private sendFrame(data: string): void {
    const s = this.socket;
    if (s) this.safe(() => s.send(data));
  }

  private message(data: string, gen: number): void {
    const now = this.now();
    this.lastFrameAt = now;
    if (this.state.status === "open") this.clear("dead");
    const msg = parseRoomFrame(data);
    if (!msg) return;
    switch (msg.t) {
      case "welcome": {
        this.clear("dead");
        this.openedAt = now;
        const ttlMs = Math.min(msg.ttl * 1000, ROOM_MAX_LIFETIME_MS);
        if (ttlMs > ROOM_REFRESH_AHEAD_MS) {
          const left = ttlMs - ROOM_REFRESH_AHEAD_MS;
          const spread = Math.min(this.options.refreshJitterMs ?? 0, Math.floor(left / 2));
          const early =
            spread > 0 ? Math.floor((this.options.random ?? Math.random)() * spread) : 0;
          this.later("refresh", left - early, () => {
            if (gen !== this.gen) return;
            this.refreshNext = true;
            this.connect();
          });
        }
        this.beat(gen);
        this.set({ status: "open", viewers: msg.viewers, retryInMs: null });
        this.safe(() => this.options.onViewers?.(msg.viewers));
        const r = this.filter.welcome(msg, now);
        this.setBattle(msg.battle ?? null);
        if (r.gap) this.safe(() => this.options.onGap?.());
        this.emit(r.events, true, gen);
        return;
      }
      case "gift":
        this.emit(this.filter.live([msg], now).events, false, gen);
        return;
      case "batch":
        this.emit(this.filter.live(msg.events, now).events, false, gen);
        return;
      case "viewers":
        this.set({ viewers: msg.n });
        this.safe(() => this.options.onViewers?.(msg.n));
        return;
      case "scores":
        if (this.state.status === "open") this.setBattle(msg.battle);
        return;
      default:
        return;
    }
  }

  private setBattle(battle: RoomBattle | null): void {
    if (battle === null && this.battle === null) return;
    this.battle = battle;
    this.safe(() => this.options.onBattle?.(battle));
    for (const l of this.battleListeners) this.safe(l);
  }

  private emit(events: RoomGiftMessage[], replayed: boolean, gen: number): void {
    for (const e of events) {
      if (gen !== this.gen) return;
      const o = this.options;
      const event = roomGiftToEffect(e, {
        catalog: o.getCatalog?.() ?? o.catalog,
        resolveName: o.resolveName,
        replayed,
        battle: this.battle,
        sideColors: o.sideColors,
      });
      this.safe(() => o.onEvent?.(event));
      for (const l of this.eventListeners) this.safe(() => l(event));
    }
  }

  /** Heartbeat: `ping` after `heartbeatMs` without frames; the next frame must come within 10 s. */
  private beat(gen: number): void {
    const every = this.options.heartbeatMs ?? ROOM_HEARTBEAT_MS;
    if (every <= 0) return;
    const wait = Math.max(0, this.lastFrameAt + every - this.now());
    this.later("beat", wait, () => {
      if (gen !== this.gen) return;
      if (this.now() - this.lastFrameAt >= every) {
        this.sendFrame("ping");
        this.later("dead", ROOM_DEAD_MS, () => this.dead(gen));
        this.lastFrameAt = this.now();
      }
      this.beat(gen);
    });
  }

  /**
   * No token, no welcome or no answer to `ping` in time: drop the socket and retry like a 1006
   * (reason `token_timeout` while no socket exists yet, else `timeout`).
   */
  private dead(gen: number): void {
    if (gen !== this.gen) return;
    const s = this.socket;
    this.socket = null;
    if (s) this.safe(() => s.close(1000, "timeout"));
    this.closed(gen, 1006, s ? "timeout" : "token_timeout");
  }

  private closed(gen: number, code: number, reason: string): void {
    if (gen !== this.gen) return;
    const stable = this.openedAt !== null && this.now() - this.openedAt >= ROOM_STABLE_MS;
    this.drop();
    if (stable) this.limited = 0;
    const attempt = stable ? 0 : this.state.attempt;
    const d = roomRetryDecision(
      { code, reason, attempt, limited: this.limited },
      this.options.random ?? Math.random,
    );
    if (!d.retry) {
      this.resumable = d.resumable === true;
      this.set({
        status: "closed",
        retryInMs: null,
        code,
        reason: d.exhausted ? ROOM_REASON_EXHAUSTED : reason,
        attempt,
      });
      return;
    }
    this.limited = d.limited ? this.limited + 1 : 0;
    this.rateWait = d.limited;
    this.refreshNext = d.refreshToken;
    this.set({ status: "reconnecting", attempt: attempt + 1, retryInMs: d.delayMs, code, reason });
    const next = this.gen;
    this.later("retry", d.delayMs, () => {
      if (next === this.gen) this.connect();
    });
  }
}
