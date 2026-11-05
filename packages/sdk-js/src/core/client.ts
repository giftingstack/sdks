import type {
  AwayQuery,
  AwaySummary,
  Gift,
  GiftTransaction,
  GiftWall,
  GiftWallQueryItem,
  Inbox,
  InboxQuery,
  Leaderboard,
  LeaderboardBoard,
  LeaderboardQuery,
  Me,
  ReceivedGift,
  SendGiftInput,
} from "./types";
import { assertSecureUrl } from "./url";

export const DEFAULT_BASE_URL = "https://api.giftingstack.com";

/** Any error from the API, or a network failure (`status` 0). */
export class GiftingError extends Error {
  constructor(
    public readonly status: number,
    public readonly type: string,
    message: string,
    public readonly requestId: string | null = null,
  ) {
    super(message);
    this.name = "GiftingError";
  }

  /** Worth showing as "try again" rather than as a hard failure. */
  get retryable(): boolean {
    return this.status === 0 || this.status === 429 || this.status >= 500;
  }

  /** `insufficient_balance`: show your coin store. */
  get insufficientBalance(): boolean {
    return this.type === "insufficient_balance";
  }
}

export interface GiftingClientOptions {
  /**
   * Returns a client token for the signed-in user. Your own server creates it with
   * `POST /v1/client-tokens`. Called again, with `forceRefresh`, when a token is rejected.
   */
  getToken: (options: { forceRefresh: boolean }) => Promise<string>;
  /**
   * Default `https://api.giftingstack.com`. `http://` is refused unless the host is
   * localhost, 127.0.0.1, ::1 or 10.0.2.2 (the Android emulator), or `allowInsecure` is true.
   */
  baseUrl?: string;
  /** Allow a plain `http://` base URL to any host. Default false. For development only. SPEC 3.1. */
  allowInsecure?: boolean;
  /** Default: the global `fetch`. */
  fetch?: typeof fetch;
  /**
   * Where your app runs, sent as `X-GiftingStack-Platform` so your dashboard shows which
   * platforms gifts are sent from. Default: `react-native` in React Native, else `web`.
   */
  platform?: GiftingPlatform;
  /**
   * The phone's operating system, sent as `X-GiftingStack-OS` with the platform. Default: in
   * React Native, the OS the `@giftingstack/sdk/react-native` entry reads from `Platform.OS`;
   * none elsewhere. Informational only.
   */
  os?: GiftingOs;
  /**
   * Time allowed for one HTTP attempt, from sending the request to reading the whole response
   * body, in milliseconds. A slower attempt ends the call with the same `network_error` as a
   * lost connection (never retried). Default 20,000; `0` turns the timeout off. SPEC 3.4.
   */
  timeoutMs?: number;
}

/** Default `timeoutMs` (SPEC 3.1). */
export const DEFAULT_TIMEOUT_MS = 20_000;

export type GiftingPlatform = "web" | "ios" | "android" | "flutter" | "react-native";
export type GiftingOs = "ios" | "android";

/** The header the app-facing API reads the phone OS from (informational only). */
export const OS_HEADER = "X-GiftingStack-OS";

/** Set by the React Native entry when it loads (`Platform.OS`); read at each request. */
let detectedOs: GiftingOs | undefined;
export function setDetectedOs(os: string | undefined): void {
  detectedOs = os === "ios" || os === "android" ? os : undefined;
}

/** The header the app-facing API reads the platform from (informational only). */
export const PLATFORM_HEADER = "X-GiftingStack-Platform";

/** `react-native` when React Native runs this (its `navigator.product`), else `web`. */
export function detectPlatform(): GiftingPlatform {
  const nav = (globalThis as { navigator?: { product?: string } }).navigator;
  return nav?.product === "ReactNative" ? "react-native" : "web";
}

export interface GiftingClient {
  getGifts(): Promise<Gift[]>;
  getMe(): Promise<Me>;
  /** A user's gift counters: the profile wall, or with `reference` one post's wall. */
  getReceivedGifts(user: string, reference?: string): Promise<ReceivedGift[]>;
  sendGift(input: SendGiftInput): Promise<GiftTransaction>;
  /** Up to 25 walls in one call, answered in the same order. An empty list makes no request. */
  queryGiftWalls(items: GiftWallQueryItem[]): Promise<GiftWall[]>;
  /** Gifts the signed-in user received since they last looked (SPEC section 15). */
  getAway(query?: AwayQuery): Promise<AwaySummary>;
  /** Marks a summary as seen: send its `cursor` once it was shown. The server never moves back. */
  ackAway(cursor: string): Promise<void>;
  /** Gifts the signed-in user received over the last 24 hours, newest first (SPEC section 19). */
  getInbox(query?: InboxQuery): Promise<Inbox>;
  /** Top senders or receivers (SPEC section 16). `me` is the signed-in user. */
  getLeaderboard(board: LeaderboardBoard, query?: LeaderboardQuery): Promise<Leaderboard>;
}

/**
 * `?a=1&b=2` from the pairs whose value is given, in the order given, values encoded like
 * `encodeURIComponent`. Empty when nothing is given.
 */
export function queryString(pairs: [string, string | number | undefined | null][]): string {
  const parts = pairs
    .filter(([, v]) => v !== undefined && v !== null)
    .map(([k, v]) => `${k}=${encodeURIComponent(String(v))}`);
  return parts.length ? `?${parts.join("&")}` : "";
}

/**
 * `crypto.randomUUID` is missing in some React Native runtimes: fall back to 128 bits from
 * `crypto.getRandomValues`, and only without any crypto to `Math.random` (SPEC 3.3).
 */
export function newIdempotencyKey(): string {
  const c = (
    globalThis as {
      crypto?: { randomUUID?: () => string; getRandomValues?: (a: Uint32Array) => Uint32Array };
    }
  ).crypto;
  if (c?.randomUUID) return c.randomUUID();
  const hexOf = (n: number) => (n >>> 0).toString(16).padStart(8, "0");
  if (c?.getRandomValues) {
    try {
      const words = c.getRandomValues(new Uint32Array(4));
      return `${hexOf(words[0]!)}-${hexOf(words[1]!)}-${hexOf(words[2]!)}-${hexOf(words[3]!)}`;
    } catch {
      // fall through to Math.random
    }
  }
  const hex = () => hexOf(Math.floor(Math.random() * 0x100000000));
  return `${hex()}-${hex()}-${hex()}-${hex()}`;
}

const networkError = () =>
  new GiftingError(0, "network_error", "Could not reach GiftingStack. Check your connection.");

interface ErrorBody {
  error?: { type?: string; message?: string; request_id?: string };
}

export function createGiftingClient(options: GiftingClientOptions): GiftingClient {
  assertSecureUrl(options.baseUrl ?? DEFAULT_BASE_URL, options.allowInsecure, "baseUrl");
  const base = (options.baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, "");
  const doFetch = options.fetch ?? ((...args: Parameters<typeof fetch>) => fetch(...args));
  const platform = options.platform ?? detectPlatform();
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  async function once(
    method: string,
    path: string,
    token: string,
    body: unknown,
    idempotencyKey: string | null,
    signal: AbortSignal | undefined,
  ): Promise<Response> {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${token}`,
      [PLATFORM_HEADER]: platform,
    };
    const os = options.os ?? (platform === "react-native" ? detectedOs : undefined);
    if (os) headers[OS_HEADER] = os;
    if (body !== undefined) headers["Content-Type"] = "application/json";
    if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
    try {
      return await doFetch(`${base}${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        ...(signal ? { signal } : {}),
      });
    } catch {
      throw networkError();
    }
  }

  async function request<T>(
    method: string,
    path: string,
    body?: unknown,
    idempotencyKey: string | null = null,
  ): Promise<T> {
    // One timer per attempt; it stays armed until that attempt's body is read.
    let timer: ReturnType<typeof setTimeout> | undefined;
    let signal: AbortSignal | undefined;
    // A send (the only call with an idempotency key) that gets no answer at all is repeated once
    // with the same key: if the first one did arrive, the server replays it instead of charging
    // again (SPEC 3.4). A timeout is not repeated.
    let transportRetried = false;
    const attempt = async (token: string): Promise<Response> => {
      clearTimeout(timer);
      signal = undefined;
      if (timeoutMs > 0 && typeof AbortController !== "undefined") {
        const ctl = new AbortController();
        timer = setTimeout(() => ctl.abort(), timeoutMs);
        signal = ctl.signal;
      }
      try {
        return await once(method, path, token, body, idempotencyKey, signal);
      } catch (e) {
        if (idempotencyKey === null || transportRetried || signal?.aborted) throw e;
        transportRetried = true;
        return attempt(token);
      }
    };
    try {
      let token = await options.getToken({ forceRefresh: false });
      let res = await attempt(token);
      // A rejected token is usually just an expired one: get a fresh one and try once more.
      if (res.status === 401) {
        token = await options.getToken({ forceRefresh: true });
        res = await attempt(token);
      }
      // One quiet retry for a server hiccup. Reads are harmless to repeat and every write
      // carries an idempotency key, so repeating one never charges twice.
      if (res.status >= 500) {
        res = await attempt(token);
      }
      if (!res.ok) {
        const parsed = (await res.json().catch(() => null)) as ErrorBody | null;
        throw new GiftingError(
          res.status,
          parsed?.error?.type ?? "unknown_error",
          parsed?.error?.message ?? `Request failed (${res.status}).`,
          parsed?.error?.request_id ?? res.headers.get("X-Request-Id"),
        );
      }
      // 204 No Content (the away cursor PUT): there is nothing to parse.
      if (res.status === 204) return undefined as T;
      try {
        return (await res.json()) as T;
      } catch {
        // The time ran out while reading the body: a lost connection, not a bad answer.
        if (signal?.aborted) throw networkError();
        // A 2xx that is not JSON (a proxy's HTML page, a cut-off body): never show its text.
        throw new GiftingError(
          res.status,
          "invalid_response",
          `Invalid response (${res.status}).`,
          res.headers.get("X-Request-Id"),
        );
      }
    } finally {
      clearTimeout(timer);
    }
  }

  return {
    async getGifts() {
      return (await request<{ data: Gift[] }>("GET", "/v1/client/gifts")).data;
    },
    getMe() {
      return request<Me>("GET", "/v1/client/me");
    },
    async getReceivedGifts(user, reference) {
      const path =
        `/v1/client/users/${encodeURIComponent(user)}/received-gifts` +
        queryString([["reference", reference]]);
      return (await request<{ data: ReceivedGift[] }>("GET", path)).data;
    },
    async queryGiftWalls(items) {
      if (items.length === 0) return [];
      const body = {
        items: items.map((i) =>
          i.reference === undefined || i.reference === null
            ? { receiver: i.receiver }
            : { receiver: i.receiver, reference: i.reference },
        ),
      };
      return (await request<{ data: GiftWall[] }>("POST", "/v1/client/gift-walls/query", body))
        .data;
    },
    getAway(query = {}) {
      const path =
        "/v1/client/me/away" +
        queryString([
          ["since", query.since],
          ["max_groups", query.maxGroups],
        ]);
      return request<AwaySummary>("GET", path);
    },
    async ackAway(cursor) {
      await request<void>("PUT", "/v1/client/me/away/cursor", { cursor });
    },
    getInbox(query = {}) {
      const path =
        "/v1/client/me/inbox" +
        queryString([
          ["cursor", query.cursor],
          ["limit", query.limit],
        ]);
      return request<Inbox>("GET", path);
    },
    getLeaderboard(board, query = {}) {
      const path =
        `/v1/client/leaderboards/${encodeURIComponent(board)}` +
        queryString([
          ["period", query.period],
          ["metric", query.metric],
          ["at", query.at],
          ["limit", query.limit],
          ["include_me", query.includeMe === false ? "false" : undefined],
        ]);
      return request<Leaderboard>("GET", path);
    },
    sendGift(input) {
      return request<GiftTransaction>(
        "POST",
        "/v1/client/gift-transactions",
        {
          receiver: input.receiver,
          gift_id: input.giftId,
          quantity: input.quantity,
          message: input.message,
          reference: input.reference,
          room_id: input.roomId,
        },
        input.idempotencyKey ?? newIdempotencyKey(),
      );
    },
  };
}
