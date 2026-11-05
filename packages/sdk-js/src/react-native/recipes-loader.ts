/**
 * Remote recipes (spec section 13) for the React Native layer. The loader itself is shared with
 * the web (`../shared/recipes-loader`); here only the defaults differ: the global `fetch`, and a
 * cache that lives in memory unless the app passes a `storage` (for example AsyncStorage).
 */
import { remoteRecipesUrl } from "../core";
import {
  type AsyncStorageLike,
  type FetchLike,
  type RecipesLoader,
  createRecipesLoaderCore,
} from "../shared/recipes-loader";

export type { AsyncStorageLike, FetchLike, RecipesLoader };

/** What `recipesStorage` needs: `getItem` and `setItem` on strings, sync or async. */
export type RecipesStorage = AsyncStorageLike;

export interface RnRecipesLoaderDeps {
  url: string;
  fetch?: FetchLike | null;
  /** Default: no cache beyond the loader's own memory. */
  storage?: RecipesStorage | null;
  now?: () => number;
}

function defaultFetch(): FetchLike | null {
  return typeof fetch === "function" ? (fetch.bind(globalThis) as FetchLike) : null;
}

export function createRecipesLoader(deps: RnRecipesLoaderDeps): RecipesLoader {
  return createRecipesLoaderCore({
    url: deps.url,
    storage: deps.storage ?? null,
    getFetch: () => (deps.fetch === undefined ? defaultFetch() : deps.fetch),
    now: deps.now,
  });
}

/** One loader per (storage, URL): every layer shares one request at a time. */
const NO_STORAGE = {};
let shared = new WeakMap<object, Map<string, RecipesLoader>>();

export function sharedRecipesLoader(url: string, storage?: RecipesStorage | null): RecipesLoader {
  const owner: object = storage ?? NO_STORAGE;
  let byUrl = shared.get(owner);
  if (!byUrl) shared.set(owner, (byUrl = new Map()));
  let loader = byUrl.get(url);
  if (!loader) {
    loader = createRecipesLoader({ url, storage });
    byUrl.set(url, loader);
  }
  return loader;
}

export interface RemoteRecipesOptions {
  remoteRecipes?: boolean;
  recipesVersion?: string;
  recipesUrl?: string;
  recipesStorage?: RecipesStorage | null;
}

/** The shared loader for these options, or null when remote recipes are off: no network. */
export function remoteRecipesLoader(options: RemoteRecipesOptions): RecipesLoader | null {
  if (options.remoteRecipes === false) return null;
  const url = remoteRecipesUrl(options.recipesUrl, options.recipesVersion);
  if (url === null) return null;
  return sharedRecipesLoader(url, options.recipesStorage);
}

/** Forget the shared loaders (tests). */
export function resetSharedRecipesLoaders(): void {
  shared = new WeakMap();
}
