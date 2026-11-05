/**
 * Fetches and caches the remote recipes document (spec section 13) for the web layer.
 * The cached copy is used at once; a refresh runs in the background at most once per 6 hours.
 * Nothing here ever throws to the app or delays an effect: on any failure the layer simply keeps
 * the cached or embedded numbers. The platform-neutral part lives in `../shared/recipes-loader`.
 */
import { remoteRecipesUrl } from "../core";
import {
  type FetchLike,
  type RecipesLoader,
  type StorageLike,
  createRecipesLoaderCore,
} from "../shared/recipes-loader";

export {
  RECIPES_BACKOFF_MS,
  RECIPES_FETCH_TIMEOUT_MS,
  RECIPES_REFRESH_MS,
  type FetchLike,
  type RecipesLoader,
  type StorageLike,
} from "../shared/recipes-loader";

export interface RecipesLoaderDeps {
  url: string;
  /** Default: the page's `fetch`. */
  fetch?: FetchLike | null;
  /** Default: `localStorage` when the page may use it; null = memory only. */
  storage?: StorageLike | null;
  now?: () => number;
}

function defaultStorage(): StorageLike | null {
  try {
    // Reading `localStorage` itself throws when the page may not use storage.
    return typeof localStorage === "undefined" ? null : localStorage;
  } catch {
    return null;
  }
}

function defaultFetch(): FetchLike | null {
  return typeof fetch === "function" ? (fetch.bind(globalThis) as FetchLike) : null;
}

export function createRecipesLoader(deps: RecipesLoaderDeps): RecipesLoader {
  return createRecipesLoaderCore({
    url: deps.url,
    storage: deps.storage === undefined ? defaultStorage() : deps.storage,
    getFetch: () => (deps.fetch === undefined ? defaultFetch() : deps.fetch),
    now: deps.now,
  });
}

/** One loader per URL for the whole page, shared by every layer (one request at a time). */
const shared = new Map<string, RecipesLoader>();

export function sharedRecipesLoader(url: string): RecipesLoader {
  let loader = shared.get(url);
  if (!loader) {
    loader = createRecipesLoader({ url });
    shared.set(url, loader);
  }
  return loader;
}

/** The layer options that control remote recipes. */
export interface RemoteRecipesOptions {
  remoteRecipes?: boolean;
  recipesVersion?: string;
  recipesUrl?: string;
}

/**
 * The shared loader for a layer, with its background refresh started, or null when remote
 * recipes are off (`remoteRecipes: false`, or a version that cannot be pinned): no network.
 */
export function startRemoteRecipes(options: RemoteRecipesOptions): RecipesLoader | null {
  if (options.remoteRecipes === false) return null;
  const url = remoteRecipesUrl(options.recipesUrl, options.recipesVersion);
  if (url === null) return null;
  const loader = sharedRecipesLoader(url);
  void loader.refresh();
  return loader;
}

/** Forget the shared loaders (tests). */
export function resetSharedRecipesLoaders(): void {
  shared.clear();
}
