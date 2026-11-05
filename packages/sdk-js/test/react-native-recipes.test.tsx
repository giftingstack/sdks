/**
 * Remote recipes on React Native (spec section 13): the layer's props, with a fake fetch, a fake
 * async storage and fake timers. The loader's own rules (timeout, backoff, 6 h) are tested once,
 * in remote-recipes.test.ts, because the web and React Native share that code.
 */
import { act, cleanup, render, screen } from "@testing-library/react";
import { createRef } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { RECIPES_REFRESH_MS } from "../src/shared/recipes-loader";
import { GiftEffectLayer, type GiftEffectLayerHandle } from "../src/react-native";
import { resetSharedRecipesLoaders } from "../src/react-native/recipes-loader";
import { installPhoneLayout } from "./setup";

const DEFAULT_URL = "https://assets.giftingstack.com/recipes.json";
const URL_ = "https://recipes.test/fx/recipes.json";
const cacheKey = (url: string) => "giftingstack:recipes:" + url;
// Price 50 is small by default (under 100); with these thresholds it is medium.
const LOW_THRESHOLDS = { specVersion: "1.0.0", thresholds: { mediumFrom: 10, largeFrom: 500 } };

const ev = (id: string, price: number, sender = "ayla") => ({
  gift: { id, name: id, price, image: null },
  sender,
});

let restoreLayout = () => {};
let calls: string[];
let replies: Array<{ body?: string; status?: number; error?: boolean }>;
const savedFetch = globalThis.fetch;

beforeEach(() => {
  restoreLayout = installPhoneLayout();
  vi.useFakeTimers({
    toFake: [
      "setTimeout",
      "clearTimeout",
      "requestAnimationFrame",
      "cancelAnimationFrame",
      "performance",
      "Date",
    ],
  });
  resetSharedRecipesLoaders();
  calls = [];
  replies = [];
  globalThis.fetch = ((url: string) => {
    calls.push(url);
    const r = replies.shift() ?? { error: true };
    if (r.error) return Promise.reject(new Error("offline"));
    return Promise.resolve({
      ok: (r.status ?? 200) < 300,
      text: () => Promise.resolve(r.body ?? JSON.stringify(LOW_THRESHOLDS)),
    });
  }) as unknown as typeof fetch;
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  restoreLayout();
  globalThis.fetch = savedFetch;
  resetSharedRecipesLoaders();
});

async function mount(props: Partial<React.ComponentProps<typeof GiftEffectLayer>> = {}) {
  const ref = createRef<GiftEffectLayerHandle>();
  render(<GiftEffectLayer ref={ref} reducedMotion={false} pictureWaitMs={0} {...props} />);
  await act(async () => {
    await vi.advanceTimersByTimeAsync(0);
  });
  return ref;
}
async function play(ref: React.RefObject<GiftEffectLayerHandle | null>, e: ReturnType<typeof ev>) {
  act(() => {
    ref.current!.play(e);
  });
  await act(async () => {
    await vi.advanceTimersByTimeAsync(10);
  });
}
const count = (tier: "small" | "medium") => screen.queryAllByTestId(`gift-effect-${tier}`).length;

/** Async storage in the style of AsyncStorage: every call returns a promise. */
function asyncStorage(initial: Record<string, string> = {}) {
  const data = { ...initial };
  return {
    data,
    getItem: (k: string) => Promise.resolve(k in data ? data[k]! : null),
    setItem: (k: string, v: string) => {
      data[k] = v;
      return Promise.resolve();
    },
  };
}

describe("React Native GiftEffectLayer: remote recipes", () => {
  it("remoteRecipes: false makes no request at all", async () => {
    const ref = await mount({ remoteRecipes: false });
    await mount({ remoteRecipes: false, recipesVersion: "1.0.0", recipesUrl: URL_ });
    await play(ref, ev("rose", 50));
    expect(count("small")).toBe(1); // built-in numbers
    await act(async () => {
      await vi.advanceTimersByTimeAsync(10_000);
    });
    expect(calls).toEqual([]);
  });

  it("by default asks the hosted address once for any number of layers", async () => {
    await mount();
    await mount();
    expect(calls).toEqual([DEFAULT_URL]);
  });

  it("recipesVersion requests recipes.<version>.json; recipesUrl replaces the address", async () => {
    await mount({ recipesVersion: "1.0.0" });
    await mount({ recipesUrl: URL_, recipesVersion: "b7" });
    expect(calls).toEqual([
      "https://assets.giftingstack.com/recipes.1.0.0.json",
      "https://recipes.test/fx/recipes.b7.json",
    ]);
  });

  it("a version that cannot be pinned means no network", async () => {
    await mount({ recipesVersion: "../x" });
    expect(calls).toEqual([]);
  });

  it("uses the cached copy for the first gift, and a fresh cache means no request", async () => {
    const storage = asyncStorage({
      [cacheKey(URL_)]: JSON.stringify({ fetchedAt: Date.now() - 1000, doc: LOW_THRESHOLDS }),
    });
    const ref = await mount({ recipesUrl: URL_, recipesStorage: storage });
    await play(ref, ev("rose", 50));
    expect(count("medium")).toBe(1); // the cached thresholds, with no wait for the network
    expect(count("small")).toBe(0);
    expect(calls).toEqual([]);
  });

  it("a stale cache is used now and refreshed in the background", async () => {
    const storage = asyncStorage({
      [cacheKey(URL_)]: JSON.stringify({
        fetchedAt: Date.now() - RECIPES_REFRESH_MS,
        doc: LOW_THRESHOLDS,
      }),
    });
    replies.push({
      body: JSON.stringify({
        specVersion: "1.0.0",
        thresholds: { mediumFrom: 20, largeFrom: 500 },
      }),
    });
    const ref = await mount({ recipesUrl: URL_, recipesStorage: storage });
    expect(calls).toEqual([URL_]);
    await play(ref, ev("rose", 15)); // 15 is medium under 10, small under 20
    expect(count("small")).toBe(1);
    expect(JSON.parse(storage.data[cacheKey(URL_)]!).doc.thresholds.mediumFrom).toBe(20);
  });

  it("a recipe change applies to the next gift only", async () => {
    // The network answers after the first gift has started.
    let answer: (v: unknown) => void = () => {};
    globalThis.fetch = ((url: string) => {
      calls.push(url);
      return new Promise((resolve) => (answer = resolve));
    }) as unknown as typeof fetch;
    const ref = await mount({ recipesUrl: URL_ });
    await play(ref, ev("rose", 50, "a"));
    expect(count("small")).toBe(1); // built-in numbers: nothing waited
    await act(async () => {
      answer({ ok: true, text: () => Promise.resolve(JSON.stringify(LOW_THRESHOLDS)) });
      await vi.advanceTimersByTimeAsync(0);
    });
    expect(count("small")).toBe(1); // the running effect keeps its recipe
    expect(count("medium")).toBe(0);
    await play(ref, ev("rose", 50, "b"));
    expect(count("medium")).toBe(1); // the next gift uses the new numbers
    expect(count("small")).toBe(1);
  });

  it("a failed fetch never surfaces: the built-in numbers play", async () => {
    replies.push({ error: true });
    const ref = await mount({ recipesUrl: URL_ });
    await expect(play(ref, ev("rose", 50))).resolves.toBeUndefined();
    expect(count("small")).toBe(1);
  });
});
