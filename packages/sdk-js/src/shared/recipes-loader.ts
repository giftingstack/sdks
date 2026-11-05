/**
 * Platform-neutral remote recipes loader (spec section 13): fetch with timeout, cache, single
 * flight, refresh interval and backoff. Fetch, storage and clock are injected; the web and React
 * Native wrappers supply the platform defaults. Nothing here ever throws to the app or delays an
 * effect: on any failure the layer keeps the cached or embedded numbers.
 */
import { type RemoteRecipeSet, parseRemoteRecipes } from "../core";

/** Fetch timeout, in ms (spec 13.5). */
export const RECIPES_FETCH_TIMEOUT_MS = 3_000;
/** A successful fetch is reused this long before the next one, in ms. */
export const RECIPES_REFRESH_MS = 6 * 60 * 60 * 1000;
/** First wait after a failure; doubles per failure, capped at `RECIPES_REFRESH_MS`. */
export const RECIPES_BACKOFF_MS = 60_000;
export const RECIPES_STORAGE_PREFIX = "giftingstack:recipes:";

export type FetchLike = (
  url: string,
  init: { signal?: AbortSignal; credentials?: RequestCredentials },
) => Promise<{ ok: boolean; text(): Promise<string> }>;

/** Synchronous storage (web `localStorage`). */
export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

/** Storage whose calls may return a promise (React Native `AsyncStorage`). */
export interface AsyncStorageLike {
  getItem(key: string): string | null | Promise<string | null>;
  setItem(key: string, value: string): void | Promise<void>;
}

export interface RecipesLoader {
  /** The best document known right now (cached or fetched), or null: use the embedded set. */
  current(): RemoteRecipeSet | null;
  /**
   * Fetches a fresh document when one is due and no attempt is backing off. Concurrent callers
   * share one request. Never rejects.
   */
  refresh(): Promise<void>;
}

export interface RecipesLoaderCoreDeps {
  url: string;
  /** Looked up on every refresh, so a replaced `fetch` is respected. null = no network. */
  getFetch: () => FetchLike | null;
  storage: AsyncStorageLike | null;
  now?: () => number;
}

interface CacheEntry {
  fetchedAt: number;
  doc: unknown;
}

const isThenable = (v: unknown): v is PromiseLike<unknown> =>
  typeof v === "object" && v !== null && typeof (v as { then?: unknown }).then === "function";

export function createRecipesLoaderCore(deps: RecipesLoaderCoreDeps): RecipesLoader {
  const { storage } = deps;
  const now = deps.now ?? (() => Date.now());
  const key = RECIPES_STORAGE_PREFIX + deps.url;

  let loaded = false;
  let value: RemoteRecipeSet | null = null;
  let fetchedAt: number | null = null;
  let failures = 0;
  let backoffUntil = 0;
  let inflight: Promise<void> | null = null;
  /** Set while an asynchronous storage read is pending. */
  let hydrating: Promise<void> | null = null;

  /** The document is parsed again, so new clamps apply to old copies. */
  function apply(raw: unknown): void {
    try {
      if (typeof raw !== "string" || !raw) return;
      // A fetch that finished first is newer than whatever the cache says.
      if (fetchedAt !== null) return;
      const entry = JSON.parse(raw) as CacheEntry;
      const parsed = parseRemoteRecipes(entry?.doc);
      if (parsed && typeof entry.fetchedAt === "number") {
        value = parsed;
        fetchedAt = entry.fetchedAt;
      }
    } catch {
      // A broken cache entry is the same as none.
    }
  }

  /** Reads the cache once (a synchronous store is applied at once). */
  function load(): void {
    if (loaded) return;
    loaded = true;
    try {
      const raw = storage?.getItem(key);
      if (isThenable(raw)) {
        const pending: Promise<void> = Promise.resolve(raw).then(
          (r) => apply(r),
          () => {},
        );
        hydrating = pending.then(() => {
          hydrating = null;
        });
      } else {
        apply(raw);
      }
    } catch {
      // A throwing store is the same as none.
    }
  }

  function due(t: number): boolean {
    if (t < backoffUntil) return false;
    if (fetchedAt === null) return true;
    // A clock that went back counts as due, so a wrong clock cannot pin an old copy forever.
    return t < fetchedAt || t - fetchedAt >= RECIPES_REFRESH_MS;
  }

  async function attempt(fetcher: FetchLike): Promise<void> {
    const controller = typeof AbortController === "function" ? new AbortController() : null;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => {
        controller?.abort();
        reject(new Error("recipes: timeout"));
      }, RECIPES_FETCH_TIMEOUT_MS);
    });
    try {
      const work = (async () => {
        const res = await fetcher(deps.url, {
          signal: controller?.signal,
          credentials: "omit",
        });
        if (!res.ok) throw new Error("recipes: http");
        return JSON.parse(await res.text()) as unknown;
      })();
      work.catch(() => {}); // a late failure after the timeout must not be unhandled
      const doc = await Promise.race([work, timeout]);
      const parsed = parseRemoteRecipes(doc);
      if (!parsed) throw new Error("recipes: unusable document");
      const t = now();
      value = parsed;
      fetchedAt = t;
      failures = 0;
      backoffUntil = 0;
      try {
        const saved = storage?.setItem(
          key,
          JSON.stringify({ fetchedAt: t, doc } satisfies CacheEntry),
        );
        if (isThenable(saved)) Promise.resolve(saved).catch(() => {});
      } catch {
        // Full or blocked storage: keep the copy in memory only.
      }
    } catch {
      failures++;
      backoffUntil = now() + Math.min(RECIPES_REFRESH_MS, RECIPES_BACKOFF_MS * 2 ** (failures - 1));
    } finally {
      clearTimeout(timer);
    }
  }

  function start(): Promise<void> {
    // Looked up per call, so a page (or test) that replaces `fetch` later is respected.
    const fetchFn = deps.getFetch();
    if (!fetchFn || !due(now())) return Promise.resolve();
    inflight = attempt(fetchFn).finally(() => {
      inflight = null;
    });
    return inflight;
  }

  return {
    current() {
      load();
      return value;
    },
    refresh() {
      load();
      if (inflight) return inflight;
      if (hydrating) {
        // Wait for the asynchronous cache read, so a fresh cache means no request.
        inflight = hydrating.then(() => {
          inflight = null;
          return start();
        });
        return inflight;
      }
      return start();
    },
  };
}
