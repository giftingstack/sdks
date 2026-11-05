import { useEffect, useRef, useState } from "react";
import {
  type GiftingClient,
  GiftWallLoader,
  type GiftingError,
  type ReceivedGift,
  asGiftingError,
} from "../core";

/** One loader per client: every wall of a screen shares it, so a feed makes few requests. */
const loaders = new WeakMap<GiftingClient, GiftWallLoader>();

export function wallLoaderFor(client: GiftingClient): GiftWallLoader {
  let loader = loaders.get(client);
  if (!loader) {
    loader = new GiftWallLoader({ query: (items) => client.queryGiftWalls(items) });
    loaders.set(client, loader);
  }
  return loader;
}

export interface UseGiftWallOptions {
  client: GiftingClient;
  /** The receiver. */
  user: string;
  /** Your content id; absent = the profile wall. */
  reference?: string;
  /** Preloaded counters: no request is made. */
  data?: readonly ReceivedGift[];
  /** Change it to fetch again (for example after the person sent a gift). */
  refreshKey?: unknown;
  onError?: (error: GiftingError) => void;
}

export interface UseGiftWall {
  status: "loading" | "ready" | "error";
  /** Catalog order, as the API sends it. Empty while loading and after an error. */
  gifts: readonly ReceivedGift[];
  /** True when the answer came from the network after the first paint (the wall fades in). */
  arrived: boolean;
}

/**
 * Loads one wall through the shared `GiftWallLoader` (walls asked within 50 ms go out as one
 * request, answers are kept for 60 s). A failure only reaches `onError`.
 */
export function useGiftWall(options: UseGiftWallOptions): UseGiftWall {
  const { client, user, reference, data, refreshKey } = options;
  const id = `${user}\u0000${reference ?? ""}`;
  const [result, setResult] = useState<{
    id: string;
    gifts: readonly ReceivedGift[] | null;
    arrived: boolean;
  } | null>(null);
  const onError = useRef(options.onError);
  onError.current = options.onError;
  const lastKey = useRef(refreshKey);

  useEffect(() => {
    if (data) return;
    const loader = wallLoaderFor(client);
    const fresh = lastKey.current !== refreshKey;
    lastKey.current = refreshKey;
    if (fresh) loader.invalidate(user, reference);
    let alive = true;
    const cached = fresh ? undefined : loader.peek(user, reference);
    if (cached) {
      setResult({ id, gifts: cached, arrived: false });
      return;
    }
    loader.load(user, reference).then(
      (gifts) => alive && setResult({ id, gifts, arrived: true }),
      (err: unknown) => {
        if (!alive) return;
        setResult({ id, gifts: null, arrived: false });
        onError.current?.(asGiftingError(err));
      },
    );
    return () => {
      alive = false;
    };
  }, [client, user, reference, data, refreshKey, id]);

  if (data) return { status: "ready", gifts: data, arrived: false };
  if (!result || result.id !== id) {
    const peeked = wallLoaderFor(client).peek(user, reference);
    return peeked
      ? { status: "ready", gifts: peeked, arrived: false }
      : { status: "loading", gifts: [], arrived: false };
  }
  return result.gifts
    ? { status: "ready", gifts: result.gifts, arrived: result.arrived }
    : { status: "error", gifts: [], arrived: false };
}
