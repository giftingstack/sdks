/**
 * Runs one client scenario (conformance/README.md, "client.json") against the reference client.
 * Shared by client.json and the `client` sections of wall.json, away.json and leaderboard.json.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { expect } from "vitest";
import { GiftingError, createGiftingClient } from "../src/core";

/* eslint-disable @typescript-eslint/no-explicit-any -- fixtures are untyped JSON */
export type Json = any;

export const fixture = (name: string): Json =>
  JSON.parse(
    readFileSync(join(process.cwd(), "..", "sdk-spec", "conformance", name), "utf8"),
  ) as Json;

/** Drops undefined fields, the way JSON does. */
export const plain = (v: unknown): Json =>
  v === undefined ? undefined : JSON.parse(JSON.stringify(v));

export function errorFields(e: GiftingError) {
  return {
    status: e.status,
    type: e.type,
    message: e.message,
    requestId: e.requestId,
    retryable: e.retryable,
    insufficientBalance: e.insufficientBalance,
  };
}

// ------------------------------------------------------------- wire shapes of 2xx bodies
//
// The JS client passes bodies through, so a fixture body in the wrong shape would pass here and
// break only the typed native clients. Every 2xx `body` of a client scenario is checked against
// the shape the typed models (src/core/types.ts, SPEC 14-16) parse: every key present, no extra
// key, every value of the right type.

type Shape =
  | "string"
  | "string?"
  | "int"
  | "int?"
  | "bool"
  | [Shape]
  | { nullable: Shape }
  | { [key: string]: Shape };
const nullable = (s: Shape): Shape => ({ nullable: s });
const isNullable = (s: Shape): s is { nullable: Shape } =>
  typeof s === "object" && !Array.isArray(s) && Object.keys(s).length === 1 && "nullable" in s;
const giftRef: Shape = { id: "string", name: "string", icon_url: "string?" };
const awaySender: Shape = { user: "string?", count: "int" };
const page = (item: Shape): Shape => ({ data: [item], has_more: "bool" });

/** The 2xx body shape of each call (null: no body is parsed). */
export const RESPONSE_SHAPES: Record<string, Shape | null> = {
  getGifts: page({
    id: "string",
    name: "string",
    description: "string?",
    price: "int",
    icon_url: "string?",
    animation_url: "string?",
    sort_order: "int",
  }),
  getMe: { user: "string", balance: "int" },
  getReceivedGifts: page({ gift: giftRef, count: "int" }),
  sendGift: {
    id: "string",
    sender: "string",
    receiver: "string",
    gift: giftRef,
    quantity: "int",
    unit_price: "int",
    total: "int",
    message: "string?",
    reference: "string?",
    status: "string",
    created_at: "string",
    sender_balance_after: "int",
  },
  queryGiftWalls: {
    data: [{ receiver: "string", reference: "string?", gifts: [{ gift: giftRef, count: "int" }] }],
  },
  getAway: {
    user: "string",
    since: "string",
    until: "string",
    cursor: "string?",
    truncated: "bool",
    total_gifts: "int",
    total_units: "int",
    sender_count: "int",
    groups: [
      {
        gift: {
          id: "string",
          name: "string",
          price: "int",
          icon_url: "string?",
          animation_url: "string?",
        },
        count: "int",
        units: "int",
        sender_count: "int",
        senders: [awaySender],
      },
    ],
    top_senders: [{ user: "string?", count: "int", units: "int" }],
  },
  ackAway: null,
  getInbox: {
    user: "string",
    since: "string",
    until: "string",
    data: [
      {
        id: "string",
        created_at: "string",
        sender: "string?",
        gift: {
          id: "string",
          name: "string",
          price: "int",
          icon_url: "string?",
          animation_url: "string?",
        },
        quantity: "int",
        units: "int",
        status: "string",
      },
    ],
    has_more: "bool",
    next_cursor: "string?",
  },
  getLeaderboard: {
    board: "string",
    period: "string",
    metric: "string",
    label: "string",
    starts_at: "string?",
    ends_at: "string?",
    as_of: "string",
    data: [{ rank: "int", user: "string", gifts: "int", units: "int" }],
    has_more: "bool",
    me: nullable({ user: "string", rank: "int?", gifts: "int", units: "int", hidden: "bool" }),
  },
};
/** Every mismatch between `v` and `shape`, as `path: problem` strings. */
export function shapeProblems(v: unknown, shape: Shape, path = "body"): string[] {
  if (typeof shape === "string") {
    const nullable = shape.endsWith("?");
    if (v === null) return nullable ? [] : [`${path}: null`];
    const base = shape.replace("?", "");
    const ok =
      base === "string"
        ? typeof v === "string"
        : base === "int"
          ? Number.isInteger(v)
          : typeof v === "boolean";
    return ok ? [] : [`${path}: ${JSON.stringify(v)} is not ${base}`];
  }
  if (Array.isArray(shape)) {
    if (!Array.isArray(v)) return [`${path}: ${JSON.stringify(v)} is not an array`];
    return v.flatMap((x, i) => shapeProblems(x, shape[0], `${path}[${i}]`));
  }
  if (isNullable(shape)) return v === null ? [] : shapeProblems(v, shape.nullable, path);
  if (typeof v !== "object" || v === null || Array.isArray(v)) {
    return [`${path}: ${JSON.stringify(v)} is not an object`];
  }
  const o = v as Record<string, unknown>;
  const out: string[] = [];
  for (const k of Object.keys(o)) if (!(k in shape)) out.push(`${path}.${k}: unexpected key`);
  for (const [k, s] of Object.entries(shape)) {
    if (!(k in o)) out.push(`${path}.${k}: missing`);
    else out.push(...shapeProblems(o[k], s, `${path}.${k}`));
  }
  return out;
}

/** The problems of every 2xx `body` in a client scenario (empty when all match the typed models). */
export function scenarioBodyProblems(s: Json): string[] {
  const method = s.call.method as string;
  const shape = RESPONSE_SHAPES[method];
  if (shape === undefined) return [`unknown call ${method}`];
  const out: string[] = [];
  (s.exchanges as Json[]).forEach((ex, i) => {
    const r = ex.response;
    if (!r || r.status < 200 || r.status > 299 || r.body === undefined) return;
    if (shape === null) out.push(`exchange ${i + 1}: ${method} has no body to parse`);
    else out.push(...shapeProblems(r.body, shape, `exchange ${i + 1} body`));
  });
  if (shape !== null && !s.error && s.result !== undefined) {
    // The result is the parsed body (a list for the calls that unwrap `data`).
    const unwrapped =
      typeof shape === "object" &&
      !Array.isArray(shape) &&
      "data" in shape &&
      method !== "getLeaderboard" &&
      method !== "getInbox"
        ? (shape as { data: Shape }).data
        : shape;
    out.push(...shapeProblems(s.result, unwrapped, "result"));
  }
  return out;
}

const UUID_LIKE = /^[0-9A-Fa-f-]{16,255}$/;
/** Statuses whose response must not have a body (the Fetch standard). */
const NULL_BODY = new Set([101, 204, 205, 304]);

export async function runClientScenario(s: Json): Promise<void> {
  // Strict: the fixture's bodies must be what the API sends (README, "client" sections).
  expect(scenarioBodyProblems(s), "fixture bodies vs the typed models").toEqual([]);
  const tokenCalls: boolean[] = [];
  const seenHeaders: Record<string, string>[] = [];
  let n = 0;

  const getToken = async ({ forceRefresh }: { forceRefresh: boolean }) => {
    const next = s.tokens[tokenCalls.length];
    tokenCalls.push(forceRefresh);
    expect(next, `unexpected getToken call #${tokenCalls.length}`).toBeDefined();
    expect(forceRefresh, `getToken #${tokenCalls.length} forceRefresh`).toBe(next.forceRefresh);
    return next.returns as string;
  };

  const fakeFetch = async (url: string, init: RequestInit = {}) => {
    const ex = s.exchanges[n];
    const at = `request ${n + 1}`;
    n++;
    expect(ex, `unexpected ${at}: ${init.method} ${url}`).toBeDefined();
    const want = ex.request;
    expect(init.method ?? "GET", `${at} method`).toBe(want.method);
    expect(url, `${at} url`).toBe(want.url);
    const headers: Record<string, string> = {};
    for (const [k, v] of Object.entries((init.headers ?? {}) as Record<string, string>)) {
      headers[k.toLowerCase()] = v;
    }
    seenHeaders.push(headers);
    for (const [k, v] of Object.entries(want.headers as Record<string, string>)) {
      const got = headers[k.toLowerCase()];
      const same = /^<same-as-request:(\d+)>$/.exec(v);
      if (v === "<any-uuid-like>") expect(got, `${at} ${k}`).toMatch(UUID_LIKE);
      else if (same) {
        expect(got, `${at} ${k}`).toBeDefined();
        expect(got, `${at} ${k}`).toBe(seenHeaders[Number(same[1]) - 1]?.[k.toLowerCase()]);
      } else expect(got, `${at} ${k}`).toBe(v);
    }
    for (const k of want.absentHeaders as string[]) {
      expect(headers[k.toLowerCase()], `${at} ${k} must be absent`).toBeUndefined();
    }
    if (want.body === null) expect(init.body ?? null, `${at} body`).toBeNull();
    else expect(JSON.parse(String(init.body)), `${at} body`).toEqual(want.body);

    if (ex.networkError) throw new TypeError("Network request failed");
    const r = ex.response;
    const text = r.bodyText !== undefined ? r.bodyText : JSON.stringify(r.body);
    return new Response(NULL_BODY.has(r.status) ? null : text, {
      status: r.status,
      headers: r.headers,
    });
  };

  const client = createGiftingClient({
    getToken,
    fetch: fakeFetch as unknown as typeof fetch,
    ...(s.baseUrl !== undefined ? { baseUrl: s.baseUrl } : {}),
  });
  const args = s.call.args ?? {};
  const run = (): Promise<unknown> => {
    switch (s.call.method) {
      case "getGifts":
        return client.getGifts();
      case "getMe":
        return client.getMe();
      case "getReceivedGifts":
        return client.getReceivedGifts(args.user, args.reference);
      case "sendGift":
        return client.sendGift(args.input);
      case "queryGiftWalls":
        return client.queryGiftWalls(args.items);
      case "getAway":
        return client.getAway(args.query);
      case "ackAway":
        return client.ackAway(args.cursor);
      case "getInbox":
        return client.getInbox(args.query);
      case "getLeaderboard":
        return client.getLeaderboard(args.board, args.query);
      default:
        throw new Error(`unknown call ${s.call.method}`);
    }
  };

  let result: unknown;
  let failure: unknown = null;
  try {
    result = await run();
  } catch (e) {
    failure = e;
  }
  if (s.error) {
    expect(failure, "expected an error").toBeInstanceOf(GiftingError);
    expect(errorFields(failure as GiftingError)).toEqual(s.error);
  } else {
    if (failure) throw failure;
    // A call that returns nothing (ackAway) is `null` in the fixture.
    expect(plain(result) ?? null).toEqual(s.result);
  }
  expect(n, "requests made").toBe(s.exchanges.length);
  expect(tokenCalls.length, "getToken calls").toBe(s.tokens.length);
}
