import { describe, expect, it, vi } from "vitest";
import {
  setDetectedOs,
  GiftingError,
  allRecipes,
  createComboTracker,
  createGiftingClient,
  detectPlatform,
  recipeFor,
  tierFor,
} from "../src/core";

describe("tierFor", () => {
  it("splits gifts by price with the default thresholds", () => {
    expect(tierFor(1)).toBe("small");
    expect(tierFor(99)).toBe("small");
    expect(tierFor(100)).toBe("medium");
    expect(tierFor(9_999)).toBe("medium");
    expect(tierFor(10_000)).toBe("large");
    expect(tierFor(1_000_000)).toBe("large");
  });

  it("uses your own thresholds, filling in the missing one", () => {
    expect(tierFor(500, { mediumFrom: 1000 })).toBe("small");
    expect(tierFor(500, { largeFrom: 400 })).toBe("large");
    expect(tierFor(5, { mediumFrom: 5, largeFrom: 50 })).toBe("medium");
  });
});

describe("recipes", () => {
  it("grow with the tier", () => {
    const [s, m, l] = [recipeFor("small"), recipeFor("medium"), recipeFor("large")];
    expect(s.sparks).toBeLessThan(m.sparks);
    expect(m.sparks).toBeLessThan(l.sparks);
    expect(s.peakScale).toBeLessThan(m.peakScale);
    expect(m.peakScale).toBeLessThan(l.peakScale);
    expect([s.dim, m.dim, l.dim]).toEqual([false, false, true]);
    expect([s.rays, m.rays, l.rays]).toEqual([false, false, true]);
    expect([s.coins, m.coins]).toEqual([0, 0]);
    expect(l.coins).toBeGreaterThan(0);
    expect(s.stage).toBe("float-up");
    expect(l.stage).toBe("center");
  });

  it("low quality keeps the gift and the notice but drops the heavy parts", () => {
    const high = recipeFor("large", "high");
    const low = recipeFor("large", "low");
    expect(low.sparks).toBeLessThan(high.sparks);
    expect(low.sparks).toBeGreaterThan(0);
    expect(low.coins).toBe(0);
    expect(low.rays).toBe(false);
    expect(low.noticeMs).toBe(high.noticeMs);
    expect(low.flyInMs).toBe(high.flyInMs);
  });

  it("returns copies, so editing one does not change the next", () => {
    const a = recipeFor("small");
    a.sparks = 999;
    expect(recipeFor("small").sparks).toBe(0);
  });

  it("exports all three as plain JSON for other platforms", () => {
    const all = allRecipes();
    expect(Object.keys(all)).toEqual(["small", "medium", "large"]);
    expect(JSON.parse(JSON.stringify(all))).toEqual(all);
  });
});

describe("combo tracker", () => {
  it("counts the same gift from the same sender inside the window", () => {
    const t = createComboTracker(2000);
    expect(t.hit("ayla", "rose", 0)).toBe(1);
    expect(t.hit("ayla", "rose", 500)).toBe(2);
    expect(t.hit("ayla", "rose", 1900)).toBe(3);
  });

  it("starts over after a pause, another gift or another sender", () => {
    const t = createComboTracker(2000);
    t.hit("ayla", "rose", 0);
    t.hit("ayla", "rose", 100);
    expect(t.hit("ayla", "rose", 2100 + 100)).toBe(1); // 2000 ms gap: window is exclusive
    expect(t.hit("ayla", "crown", 2300)).toBe(1);
    expect(t.hit("mert", "crown", 2400)).toBe(1);
    expect(t.hit("mert", "crown", 2500)).toBe(2);
  });

  it("keeps ids with separators apart", () => {
    const t = createComboTracker();
    t.hit("a:b", "c", 0);
    expect(t.hit("a", "b:c", 1)).toBe(1);
  });

  it("reset forgets the run", () => {
    const t = createComboTracker();
    t.hit("a", "b", 0);
    t.reset();
    expect(t.hit("a", "b", 1)).toBe(1);
  });
});

function jsonResponse(status: number, body: unknown, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), { status, headers });
}

const SENT = {
  id: "gtx_1",
  sender: "alice",
  receiver: "bob",
  gift: { id: "rose", name: "Rose", icon_url: null },
  quantity: 1,
  unit_price: 100,
  total: 100,
  message: null,
  reference: null,
  status: "completed",
  created_at: "2026-10-10T00:00:00.000Z",
  sender_balance_after: 900,
};

describe("client", () => {
  const getToken = vi.fn(async ({ forceRefresh }: { forceRefresh: boolean }) =>
    forceRefresh ? "gs_ct_fresh" : "gs_ct_first",
  );

  it("reads the catalog with the token", async () => {
    const calls: { url: string; init: RequestInit }[] = [];
    const client = createGiftingClient({
      getToken,
      baseUrl: "https://api.example.test/",
      fetch: (async (url: string, init: RequestInit) => {
        calls.push({ url, init });
        return jsonResponse(200, {
          data: [{ id: "rose", name: "Rose", price: 100 }],
          has_more: false,
        });
      }) as typeof fetch,
    });
    expect(await client.getGifts()).toEqual([{ id: "rose", name: "Rose", price: 100 }]);
    expect(calls[0]?.url).toBe("https://api.example.test/v1/client/gifts");
    expect((calls[0]?.init.headers as Record<string, string>).Authorization).toBe(
      "Bearer gs_ct_first",
    );
  });

  it("says where it runs: web by default, react-native in React Native, or the option", async () => {
    const seen: string[] = [];
    const make = (platform?: "flutter") =>
      createGiftingClient({
        getToken,
        ...(platform ? { platform } : {}),
        fetch: (async (_u: string, init: RequestInit) => {
          seen.push((init.headers as Record<string, string>)["X-GiftingStack-Platform"] ?? "");
          return jsonResponse(201, SENT);
        }) as typeof fetch,
      });
    await make().sendGift({ receiver: "bob", giftId: "rose" });
    vi.stubGlobal("navigator", { product: "ReactNative" });
    try {
      expect(detectPlatform()).toBe("react-native");
      await make().sendGift({ receiver: "bob", giftId: "rose" });
    } finally {
      vi.unstubAllGlobals();
    }
    await make("flutter").sendGift({ receiver: "bob", giftId: "rose" });
    expect(seen).toEqual(["web", "react-native", "flutter"]);
  });

  it("sends the phone OS in React Native and when given, never on the web", async () => {
    const seen: (string | undefined)[] = [];
    const make = (o: { os?: "ios" | "android"; platform?: "flutter" } = {}) =>
      createGiftingClient({
        getToken,
        ...o,
        fetch: (async (_u: string, init: RequestInit) => {
          seen.push((init.headers as Record<string, string>)["X-GiftingStack-OS"]);
          return jsonResponse(201, SENT);
        }) as typeof fetch,
      });
    setDetectedOs("android");
    try {
      await make().sendGift({ receiver: "bob", giftId: "rose" });
      vi.stubGlobal("navigator", { product: "ReactNative" });
      await make().sendGift({ receiver: "bob", giftId: "rose" });
    } finally {
      vi.unstubAllGlobals();
      setDetectedOs(undefined);
    }
    await make({ platform: "flutter", os: "ios" }).sendGift({ receiver: "bob", giftId: "rose" });
    expect(seen).toEqual([undefined, "android", "ios"]);
  });

  it("sends with an idempotency key and the right body", async () => {
    let seen: RequestInit | undefined;
    const client = createGiftingClient({
      getToken,
      fetch: (async (_u: string, init: RequestInit) => {
        seen = init;
        return jsonResponse(201, SENT);
      }) as typeof fetch,
    });
    const result = await client.sendGift({ receiver: "bob", giftId: "rose", message: "hi" });
    expect(result.sender_balance_after).toBe(900);
    const headers = seen?.headers as Record<string, string>;
    expect(headers["Idempotency-Key"]).toMatch(/^[0-9a-f-]{16,}$/);
    expect(JSON.parse(String(seen?.body))).toEqual({
      receiver: "bob",
      gift_id: "rose",
      message: "hi",
    });
  });

  it("asks for a fresh token once when the first is rejected", async () => {
    const used: string[] = [];
    const client = createGiftingClient({
      getToken,
      fetch: (async (_u: string, init: RequestInit) => {
        const bearer = (init.headers as Record<string, string>).Authorization ?? "";
        used.push(bearer);
        return bearer.endsWith("first")
          ? jsonResponse(401, {
              error: { type: "invalid_client_token", message: "expired", request_id: "r1" },
            })
          : jsonResponse(200, { user: "alice", balance: 5 });
      }) as typeof fetch,
    });
    expect(await client.getMe()).toEqual({ user: "alice", balance: 5 });
    expect(used).toEqual(["Bearer gs_ct_first", "Bearer gs_ct_fresh"]);
  });

  it("gives up after one refresh and reports the error", async () => {
    const client = createGiftingClient({
      getToken,
      fetch: (async () =>
        jsonResponse(401, {
          error: { type: "invalid_client_token", message: "no", request_id: "r2" },
        })) as typeof fetch,
    });
    await expect(client.getMe()).rejects.toMatchObject({
      status: 401,
      type: "invalid_client_token",
      requestId: "r2",
    });
  });

  it("retries a send after a 500 with the SAME idempotency key", async () => {
    const keys: string[] = [];
    let n = 0;
    const client = createGiftingClient({
      getToken,
      fetch: (async (_u: string, init: RequestInit) => {
        keys.push((init.headers as Record<string, string>)["Idempotency-Key"] ?? "");
        return ++n === 1 ? jsonResponse(503, {}) : jsonResponse(201, SENT);
      }) as typeof fetch,
    });
    await client.sendGift({ receiver: "bob", giftId: "rose" });
    expect(keys).toHaveLength(2);
    expect(keys[0]).toBe(keys[1]);
  });

  it("never retries a 4xx, and reports the API error type", async () => {
    let n = 0;
    const client = createGiftingClient({
      getToken,
      fetch: (async () => {
        n++;
        return jsonResponse(422, {
          error: { type: "insufficient_balance", message: "no coins", request_id: "r3" },
        });
      }) as typeof fetch,
    });
    const err = await client.sendGift({ receiver: "bob", giftId: "rose" }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(GiftingError);
    expect((err as GiftingError).insufficientBalance).toBe(true);
    expect((err as GiftingError).retryable).toBe(false);
    expect(n).toBe(1);
  });

  it("uses the idempotency key you pass, so a retry after an app restart is safe", async () => {
    const keys: string[] = [];
    const client = createGiftingClient({
      getToken,
      fetch: (async (_u: string, init: RequestInit) => {
        keys.push((init.headers as Record<string, string>)["Idempotency-Key"] ?? "");
        return jsonResponse(201, SENT);
      }) as typeof fetch,
    });
    await client.sendGift({ receiver: "bob", giftId: "rose", idempotencyKey: "my-own-key-1" });
    await client.sendGift({ receiver: "bob", giftId: "rose" });
    expect(keys[0]).toBe("my-own-key-1");
    expect(keys[1]).not.toBe("my-own-key-1");
  });

  it("turns a network failure into a retryable error", async () => {
    const client = createGiftingClient({
      getToken,
      fetch: (async () => {
        throw new TypeError("Network request failed");
      }) as typeof fetch,
    });
    const err = (await client.getGifts().catch((e: unknown) => e)) as GiftingError;
    expect(err.status).toBe(0);
    expect(err.type).toBe("network_error");
    expect(err.retryable).toBe(true);
  });

  describe("request timeout (SPEC 3.4)", () => {
    /** A fetch that never answers; rejects when its signal aborts, like the real one. */
    const hanging = (seen: { signals: (AbortSignal | undefined)[] }) =>
      ((_u: string, init: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          seen.signals.push(init.signal ?? undefined);
          init.signal?.addEventListener("abort", () => reject(new DOMException("x", "AbortError")));
        })) as unknown as typeof fetch;

    it("ends a hanging attempt after 20 s with the network error, without a retry", async () => {
      vi.useFakeTimers();
      try {
        const seen = { signals: [] as (AbortSignal | undefined)[] };
        const client = createGiftingClient({ getToken, fetch: hanging(seen) });
        const result = client.getMe().catch((e: unknown) => e);
        await vi.advanceTimersByTimeAsync(19_999);
        expect(seen.signals).toHaveLength(1);
        expect(seen.signals[0]?.aborted).toBe(false);
        await vi.advanceTimersByTimeAsync(1);
        const err = (await result) as GiftingError;
        expect(err).toBeInstanceOf(GiftingError);
        expect([err.status, err.type, err.retryable]).toEqual([0, "network_error", true]);
        expect(seen.signals).toHaveLength(1);
      } finally {
        vi.useRealTimers();
      }
    });

    it("a timed-out send is not repeated (only a lost connection is)", async () => {
      vi.useFakeTimers();
      try {
        const seen = { signals: [] as (AbortSignal | undefined)[] };
        const client = createGiftingClient({ getToken, fetch: hanging(seen), timeoutMs: 500 });
        const result = client
          .sendGift({ receiver: "bob", giftId: "rose" })
          .catch((e: unknown) => e);
        await vi.advanceTimersByTimeAsync(500);
        expect(((await result) as GiftingError).type).toBe("network_error");
        expect(seen.signals).toHaveLength(1);
      } finally {
        vi.useRealTimers();
      }
    });

    it("uses timeoutMs, and 0 turns it off", async () => {
      vi.useFakeTimers();
      try {
        const seen = { signals: [] as (AbortSignal | undefined)[] };
        const short = createGiftingClient({ getToken, fetch: hanging(seen), timeoutMs: 500 });
        const result = short.getMe().catch((e: unknown) => e);
        await vi.advanceTimersByTimeAsync(500);
        expect(((await result) as GiftingError).type).toBe("network_error");

        const off = createGiftingClient({ getToken, fetch: hanging(seen), timeoutMs: 0 });
        void off.getMe().catch(() => undefined);
        await vi.advanceTimersByTimeAsync(600_000);
        expect(seen.signals[1]).toBeUndefined();
      } finally {
        vi.useRealTimers();
      }
    });

    it("also covers reading the body", async () => {
      vi.useFakeTimers();
      try {
        const client = createGiftingClient({
          getToken,
          timeoutMs: 1000,
          fetch: ((_u: string, init: RequestInit) =>
            Promise.resolve({
              ok: true,
              status: 200,
              headers: new Headers(),
              json: () =>
                new Promise((_r, reject) =>
                  init.signal?.addEventListener("abort", () => reject(new Error("aborted"))),
                ),
            })) as unknown as typeof fetch,
        });
        const result = client.getMe().catch((e: unknown) => e);
        await vi.advanceTimersByTimeAsync(1000);
        expect(((await result) as GiftingError).type).toBe("network_error");
      } finally {
        vi.useRealTimers();
      }
    });
  });

  it("wraps a 2xx that is not JSON as invalid_response, without its text", async () => {
    const client = createGiftingClient({
      getToken,
      fetch: (async () =>
        new Response("<html>Captive portal secret-text</html>", {
          status: 200,
          headers: { "X-Request-Id": "req_9" },
        })) as typeof fetch,
    });
    const err = (await client.getMe().catch((e: unknown) => e)) as GiftingError;
    expect(err).toBeInstanceOf(GiftingError);
    expect([err.status, err.type, err.message, err.requestId, err.retryable]).toEqual([
      200,
      "invalid_response",
      "Invalid response (200).",
      "req_9",
      false,
    ]);
    expect(JSON.stringify(err)).not.toContain("secret-text");
    expect(err.message).not.toContain("secret-text");
  });

  it("encodes the user id in the received-gifts path", async () => {
    let url = "";
    const client = createGiftingClient({
      getToken,
      fetch: (async (u: string) => {
        url = u;
        return jsonResponse(200, { data: [], has_more: false });
      }) as typeof fetch,
    });
    await client.getReceivedGifts("a/b c");
    expect(url).toBe("https://api.giftingstack.com/v1/client/users/a%2Fb%20c/received-gifts");
  });
});
