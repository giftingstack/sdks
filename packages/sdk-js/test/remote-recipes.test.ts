/**
 * Remote recipes (spec section 13): the conformance fixture for the pure parser, merge and URL
 * rules, the scheduler with a recipe set, and the web loader with a fake fetch and fake storage.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  EffectScheduler,
  type GiftEffectEvent,
  REMOTE_RECIPE_LIMITS,
  type RemoteRecipeSet,
  embeddedRecipeSet,
  mergeRecipeSet,
  parseRemoteRecipes,
  remoteRecipesUrl,
  specData,
} from "../src/core";
import { GiftEffectLayer } from "../src/web";
import {
  type FetchLike,
  RECIPES_BACKOFF_MS,
  RECIPES_FETCH_TIMEOUT_MS,
  RECIPES_REFRESH_MS,
  type StorageLike,
  createRecipesLoader,
  resetSharedRecipesLoaders,
} from "../src/web/recipes-loader";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";

/* eslint-disable @typescript-eslint/no-explicit-any -- fixtures are untyped JSON */
type Json = any;

const specDir = join(process.cwd(), "..", "sdk-spec");
const embeddedDoc = JSON.parse(readFileSync(join(specDir, "recipes.json"), "utf8")) as Json;
const fixture = JSON.parse(
  readFileSync(join(specDir, "conformance", "remote-recipes.json"), "utf8"),
) as Json;

const isObj = (v: unknown): v is Record<string, Json> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
/** The embedded set with the fixture's patch laid over it, key by key. */
function patched(base: Json, patch: Json): Json {
  if (!isObj(base) || !isObj(patch)) return patch;
  const out: Json = { ...base };
  for (const [k, v] of Object.entries(patch)) out[k] = patched(base[k], v);
  return out;
}
const embeddedSetJson = (): Json => ({
  thresholds: embeddedDoc.thresholds,
  comboWindowMs: embeddedDoc.comboWindowMs,
  recipes: embeddedDoc.recipes,
});

// ---------------------------------------------------------------- conformance

describe("conformance: remote-recipes.json parse", () => {
  for (const c of fixture.parse) {
    it(c.name, () => {
      const input = c.input === "@embedded" ? embeddedDoc : c.input;
      const got = parseRemoteRecipes(input);
      if (c.expect === null) {
        expect(got).toBeNull();
        return;
      }
      expect(got).toEqual({
        specVersion: input.specVersion,
        ...patched(embeddedSetJson(), c.expect),
      });
    });
  }
});

describe("conformance: remote-recipes.json merge", () => {
  for (const c of fixture.merge) {
    it(c.name, () => {
      const remote = c.remote === null ? null : parseRemoteRecipes(c.remote);
      const got = mergeRecipeSet(embeddedRecipeSet(), remote, c.app);
      const recipes =
        c.expect.recipes === "remote" ? remote!.recipes : (embeddedDoc.recipes as Json);
      expect(got).toEqual({ ...c.expect, recipes });
    });
  }
});

describe("conformance: remote-recipes.json urls", () => {
  for (const c of fixture.urls) {
    it(c.name, () => {
      expect(remoteRecipesUrl(c.url, c.version)).toBe(c.expect);
    });
  }
});

describe("remote recipes: code and spec agree", () => {
  it("the embedded set equals recipes.json", () => {
    expect(embeddedRecipeSet()).toEqual(embeddedSetJson());
    expect(parseRemoteRecipes(specData())).toEqual({ specVersion: "1.0.0", ...embeddedSetJson() });
  });

  it("the clamp table in SPEC.md section 13.3 equals REMOTE_RECIPE_LIMITS", () => {
    const spec = readFileSync(join(specDir, "SPEC.md"), "utf8");
    const section = spec.slice(spec.indexOf("### 13.3"), spec.indexOf("### 13.4"));
    const rows = new Map<string, { min: number; max: number; integer: boolean }>();
    for (const m of section.matchAll(
      /^\|\s*`(\w+)`\s*\|\s*([\d.,_]+)\s*\|\s*([\d.,_]+)\s*\|\s*(yes|no)\s*\|/gm,
    )) {
      const num = (s: string) => Number(s.replace(/[,_]/g, ""));
      rows.set(m[1]!, { min: num(m[2]!), max: num(m[3]!), integer: m[4] === "yes" });
    }
    expect(Object.fromEntries(rows)).toEqual(REMOTE_RECIPE_LIMITS);
  });

  it("every embedded number lies inside its limits (the embedded set survives a round trip)", () => {
    const set = embeddedRecipeSet();
    for (const q of ["high", "low"] as const) {
      for (const t of ["small", "medium", "large"] as const) {
        const r = set.recipes[q][t];
        for (const k of [
          "peakScale",
          "flyInMs",
          "holdMs",
          "flyOutMs",
          "sparks",
          "sparkSpread",
          "coins",
          "noticeMs",
        ] as const) {
          const { min, max } = REMOTE_RECIPE_LIMITS[k];
          expect(r[k], `${q}.${t}.${k}`).toBeGreaterThanOrEqual(min);
          expect(r[k], `${q}.${t}.${k}`).toBeLessThanOrEqual(max);
        }
      }
    }
  });

  it("non-finite numbers count as the wrong type", () => {
    const got = parseRemoteRecipes({
      specVersion: "1.0.0",
      comboWindowMs: Infinity,
      recipes: { high: { large: { sparks: NaN, coins: -Infinity } } },
    });
    expect(got?.comboWindowMs).toBe(2500);
    expect(got?.recipes.high.large.sparks).toBe(50);
    expect(got?.recipes.high.large.coins).toBe(34);
  });
});

// ---------------------------------------------------------------- scheduler

const gift = (id: string, price: number) => ({ id, name: id, price, image: null });
const play = (s: EffectScheduler, price: number, sender = "ayla"): number =>
  s.play({ gift: gift(`g${price}`, price), sender } as GiftEffectEvent);

const remote = (patch: Json): RemoteRecipeSet =>
  parseRemoteRecipes({ specVersion: "1.0.0", ...patch })!;

describe("EffectScheduler with a recipe set", () => {
  it("without one it uses the embedded recipes (unchanged behaviour)", () => {
    const s = new EffectScheduler({ now: () => 0 });
    play(s, 40_000);
    expect(s.active()[0]!.recipe).toEqual(embeddedDoc.recipes.high.large);
  });

  it("uses the remote recipes, thresholds and quality table", () => {
    const set = remote({
      thresholds: { mediumFrom: 10, largeFrom: 500 },
      recipes: { high: { large: { sparks: 77 } }, low: { large: { sparks: 3 } } },
    });
    const s = new EffectScheduler({ now: () => 0 });
    s.setOptions({ recipes: set });
    play(s, 600);
    expect(s.active()[0]!.recipe.tier).toBe("large");
    expect(s.active()[0]!.recipe.sparks).toBe(77);
    s.clear();
    s.setOptions({ recipes: set, quality: "low" });
    play(s, 600);
    expect(s.active()[0]!.recipe.sparks).toBe(3);
  });

  it("app thresholds beat remote thresholds", () => {
    const s = new EffectScheduler({ now: () => 0 });
    s.setOptions({
      recipes: remote({ thresholds: { mediumFrom: 10, largeFrom: 500 } }),
      thresholds: { largeFrom: 1000 },
    });
    play(s, 600);
    expect(s.active()[0]!.recipe.tier).toBe("medium");
  });

  it("the remote combo window applies unless the app gave one", () => {
    let clock = 0;
    const s = new EffectScheduler({ now: () => clock });
    // Reduced motion: the notice (with the combo count) shows at play.
    s.setOptions({ recipes: remote({ comboWindowMs: 5000 }), reducedMotion: true });
    play(s, 10);
    clock = 4000; // beyond the embedded 2500, inside the remote 5000
    play(s, 10);
    expect(s.notice().data?.count).toBe(2);

    let clock2 = 0;
    const app = new EffectScheduler({ comboWindowMs: 1000, now: () => clock2 });
    app.setOptions({ recipes: remote({ comboWindowMs: 5000 }), reducedMotion: true });
    play(app, 10);
    clock2 = 2000;
    play(app, 10);
    expect(app.notice().data?.count).toBe(1);
  });

  it("effects already running or queued keep their recipe when a new set arrives", () => {
    const s = new EffectScheduler({ now: () => 0 });
    s.setOptions({ recipes: remote({ recipes: { high: { large: { holdMs: 1000 } } } }) });
    const first = play(s, 40_000, "a");
    const waiting = play(s, 40_000, "b");
    s.setOptions({ recipes: remote({ recipes: { high: { large: { holdMs: 3000 } } } }) });
    const later = play(s, 40_000, "c");
    expect(s.active()[0]!.recipe.holdMs).toBe(1000);
    expect(s.queued().map((e) => [e.id, e.recipe.holdMs])).toEqual([
      [waiting, 1000],
      [later, 3000],
    ]);
    s.finished(first);
    expect(s.active()[0]!.recipe.holdMs).toBe(1000);
  });
});

// ---------------------------------------------------------------- web loader

const URL_ = "https://recipes.test/recipes.json";
const goodDoc = { specVersion: "1.0.0", comboWindowMs: 4000 };

function fakeStorage(
  initial: Record<string, string> = {},
): StorageLike & { data: Record<string, string> } {
  const data = { ...initial };
  return {
    data,
    getItem: (k) => (k in data ? data[k]! : null),
    setItem: (k, v) => {
      data[k] = v;
    },
  };
}
type Reply = {
  status?: number;
  body?: string;
  error?: boolean;
  never?: boolean;
  /** Never answers and ignores the abort signal (old browsers, odd fetch polyfills). */
  deaf?: boolean;
};
function fakeFetch(replies: Reply[]) {
  const calls: string[] = [];
  const signals: (AbortSignal | undefined)[] = [];
  const fn: FetchLike = (url, init) => {
    calls.push(url);
    signals.push(init.signal);
    const r = replies.shift() ?? { error: true };
    if (r.deaf) return new Promise(() => {});
    if (r.never) {
      return new Promise((_, reject) =>
        init.signal?.addEventListener("abort", () => reject(new Error("aborted"))),
      );
    }
    if (r.error) return Promise.reject(new Error("offline"));
    return Promise.resolve({
      ok: (r.status ?? 200) < 300,
      text: () => Promise.resolve(r.body ?? JSON.stringify(goodDoc)),
    });
  };
  return { fn, calls, signals };
}
const cacheKey = "giftingstack:recipes:" + URL_;

describe("web recipes loader", () => {
  let clock: number;
  beforeEach(() => {
    clock = 1_000_000;
  });

  it("uses the cached copy at once, without waiting for the network", () => {
    const storage = fakeStorage({
      [cacheKey]: JSON.stringify({
        fetchedAt: clock - 1000,
        doc: { specVersion: "1.0.0", comboWindowMs: 3333 },
      }),
    });
    const f = fakeFetch([]);
    const loader = createRecipesLoader({ url: URL_, fetch: f.fn, storage, now: () => clock });
    expect(loader.current()?.comboWindowMs).toBe(3333);
    void loader.refresh(); // fresh cache: no request
    expect(f.calls).toEqual([]);
  });

  it("re-validates the cached copy (clamps apply; an unusable copy is ignored)", () => {
    const clamped = createRecipesLoader({
      url: URL_,
      fetch: null,
      storage: fakeStorage({
        [cacheKey]: JSON.stringify({
          fetchedAt: clock,
          doc: { specVersion: "1.0.0", comboWindowMs: 1 },
        }),
      }),
    });
    expect(clamped.current()?.comboWindowMs).toBe(500);
    for (const raw of [
      "{not json",
      JSON.stringify({ fetchedAt: clock, doc: { specVersion: "9.0.0" } }),
      JSON.stringify({ doc: goodDoc }),
    ]) {
      const l = createRecipesLoader({
        url: URL_,
        fetch: null,
        storage: fakeStorage({ [cacheKey]: raw }),
      });
      expect(l.current()).toBeNull();
    }
  });

  it("fetches, applies and caches a good document; concurrent refreshes share one request", async () => {
    const storage = fakeStorage();
    const f = fakeFetch([{}]);
    const loader = createRecipesLoader({ url: URL_, fetch: f.fn, storage, now: () => clock });
    expect(loader.current()).toBeNull();
    const a = loader.refresh();
    const b = loader.refresh();
    expect(a).toBe(b);
    await a;
    expect(f.calls).toEqual([URL_]);
    expect(loader.current()?.comboWindowMs).toBe(4000);
    expect(JSON.parse(storage.data[cacheKey]!)).toEqual({ fetchedAt: clock, doc: goodDoc });
  });

  it("refreshes at most once per 6 hours", async () => {
    const f = fakeFetch([{}, {}]);
    const loader = createRecipesLoader({
      url: URL_,
      fetch: f.fn,
      storage: fakeStorage(),
      now: () => clock,
    });
    await loader.refresh();
    clock += RECIPES_REFRESH_MS - 1;
    await loader.refresh();
    expect(f.calls).toHaveLength(1);
    clock += 1;
    await loader.refresh();
    expect(f.calls).toHaveLength(2);
  });

  it("a cached copy older than 6 hours is used now and refreshed in the background", async () => {
    const storage = fakeStorage({
      [cacheKey]: JSON.stringify({
        fetchedAt: clock - RECIPES_REFRESH_MS,
        doc: { specVersion: "1.0.0", comboWindowMs: 3333 },
      }),
    });
    const f = fakeFetch([{}]);
    const loader = createRecipesLoader({ url: URL_, fetch: f.fn, storage, now: () => clock });
    const pending = loader.refresh();
    expect(loader.current()?.comboWindowMs).toBe(3333);
    await pending;
    expect(f.calls).toHaveLength(1);
    expect(loader.current()?.comboWindowMs).toBe(4000);
  });

  it("bad JSON, an HTTP error and a wrong major keep the old copy and back off", async () => {
    for (const reply of [
      { body: "{oops" },
      { status: 404 },
      { body: JSON.stringify({ specVersion: "2.0.0", comboWindowMs: 9000 }) },
      { error: true },
    ]) {
      const storage = fakeStorage({
        [cacheKey]: JSON.stringify({
          fetchedAt: clock - RECIPES_REFRESH_MS,
          doc: { specVersion: "1.0.0", comboWindowMs: 3333 },
        }),
      });
      const f = fakeFetch([reply]);
      const loader = createRecipesLoader({ url: URL_, fetch: f.fn, storage, now: () => clock });
      await expect(loader.refresh()).resolves.toBeUndefined();
      expect(loader.current()?.comboWindowMs, JSON.stringify(reply)).toBe(3333);
      expect(JSON.parse(storage.data[cacheKey]!).doc.comboWindowMs).toBe(3333);
    }
  });

  it("backs off after failures: 1 min, 2 min, 4 min ... capped at 6 hours", async () => {
    const f = fakeFetch(Array.from({ length: 20 }, () => ({ error: true })));
    const loader = createRecipesLoader({ url: URL_, fetch: f.fn, storage: null, now: () => clock });
    await loader.refresh();
    expect(f.calls).toHaveLength(1);
    await loader.refresh(); // no retry storm
    clock += RECIPES_BACKOFF_MS - 1;
    await loader.refresh();
    expect(f.calls).toHaveLength(1);
    clock += 1;
    await loader.refresh();
    expect(f.calls).toHaveLength(2);
    clock += 2 * RECIPES_BACKOFF_MS - 1;
    await loader.refresh();
    expect(f.calls).toHaveLength(2);
    clock += 1;
    await loader.refresh();
    expect(f.calls).toHaveLength(3);
    for (let i = 0; i < 12; i++) {
      clock += RECIPES_REFRESH_MS;
      await loader.refresh();
    }
    expect(f.calls).toHaveLength(15);
    clock += RECIPES_REFRESH_MS - 1; // the wait never grows beyond 6 hours
    await loader.refresh();
    expect(f.calls).toHaveLength(15);
    clock += 1;
    await loader.refresh();
    expect(f.calls).toHaveLength(16);
  });

  it.each([
    ["a fetch that honours abort", { never: true }],
    ["a fetch that ignores abort", { deaf: true }],
  ])("gives up after 3 s and aborts the request (%s)", async (_, reply: Reply) => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    try {
      const f = fakeFetch([reply]);
      const loader = createRecipesLoader({
        url: URL_,
        fetch: f.fn,
        storage: null,
        now: () => clock,
      });
      let done = false;
      void loader.refresh().then(() => (done = true));
      await vi.advanceTimersByTimeAsync(RECIPES_FETCH_TIMEOUT_MS - 1);
      expect(done).toBe(false);
      await vi.advanceTimersByTimeAsync(1);
      expect(done).toBe(true);
      expect(f.signals[0]?.aborted).toBe(true);
      expect(loader.current()).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });

  it("works without storage, and when storage throws", async () => {
    const throwing: StorageLike = {
      getItem: () => {
        throw new Error("SecurityError");
      },
      setItem: () => {
        throw new Error("QuotaExceeded");
      },
    };
    for (const storage of [null, throwing]) {
      const loader = createRecipesLoader({
        url: URL_,
        fetch: fakeFetch([{}]).fn,
        storage,
        now: () => clock,
      });
      expect(loader.current()).toBeNull();
      await loader.refresh();
      expect(loader.current()?.comboWindowMs).toBe(4000);
    }
  });
});

// ---------------------------------------------------------------- web layer

describe("web GiftEffectLayer: remote recipes", () => {
  let env: ReturnType<typeof installWebEnv>;
  let container: HTMLElement;
  let layers: GiftEffectLayer[];
  let calls: string[];
  let replies: Reply[];
  const savedFetch = globalThis.fetch;

  beforeEach(() => {
    env = installWebEnv();
    vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
    resetSharedRecipesLoaders();
    localStorage.clear();
    container = document.createElement("div");
    document.body.appendChild(container);
    layers = [];
    calls = [];
    replies = [];
    const { fn } = (() => {
      const f = fakeFetch(replies);
      return { fn: ((url: string, init: Json) => (calls.push(url), f.fn(url, init))) as FetchLike };
    })();
    globalThis.fetch = fn as unknown as typeof fetch;
  });
  afterEach(() => {
    for (const l of layers) l.destroy();
    container.remove();
    vi.useRealTimers();
    env.restore();
    globalThis.fetch = savedFetch;
    resetSharedRecipesLoaders();
    localStorage.clear();
  });
  const make = (options: ConstructorParameters<typeof GiftEffectLayer>[1] = {}) => {
    const l = new GiftEffectLayer(container, { pictureWaitMs: 0, ...options });
    layers.push(l);
    return l;
  };
  const dragon = (sender = "ayla"): GiftEffectEvent => ({ gift: gift("dragon", 40_000), sender });

  it("remoteRecipes: false makes no request at all", async () => {
    make({ remoteRecipes: false }).play(dragon());
    make({ remoteRecipes: false, recipesVersion: "1.0.0" }).play(dragon());
    await vi.advanceTimersByTimeAsync(10_000);
    expect(calls).toEqual([]);
  });

  it("all layers share one request to the default URL; the first effect does not wait", async () => {
    replies.push({
      body: JSON.stringify({ specVersion: "1.0.0", recipes: { high: { large: { sparks: 99 } } } }),
    });
    const a = make();
    make();
    a.play(dragon());
    expect(a.scheduler.active()[0]!.recipe.sparks).toBe(50); // embedded: nothing waited
    await vi.advanceTimersByTimeAsync(0);
    expect(calls).toEqual(["https://assets.giftingstack.com/recipes.json"]);
    a.play(dragon("b"));
    expect(a.scheduler.active()[0]!.recipe.sparks).toBe(50); // the running effect keeps its recipe
    expect(a.scheduler.queued()[0]!.recipe.sparks).toBe(99); // a new one uses the remote recipe
  });

  it("recipesVersion requests recipes.<version>.json; recipesUrl replaces the address", async () => {
    make({ recipesVersion: "1.0.0" });
    make({ recipesUrl: "https://self.test/fx/recipes.json", recipesVersion: "b7" });
    await vi.advanceTimersByTimeAsync(0);
    expect(calls).toEqual([
      "https://assets.giftingstack.com/recipes.1.0.0.json",
      "https://self.test/fx/recipes.b7.json",
    ]);
  });

  it("a failed fetch never surfaces: effects play with the embedded numbers", async () => {
    replies.push({ error: true });
    const l = make();
    await vi.advanceTimersByTimeAsync(0);
    expect(() => l.play(dragon())).not.toThrow();
    expect(l.scheduler.active()[0]!.recipe).toEqual(embeddedDoc.recipes.high.large);
  });
});
