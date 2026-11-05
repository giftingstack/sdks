/**
 * Which picture URLs the SDK draws and how it treats pictures that fail (SPEC 7.6, audit R-08).
 * Pure: the platform UIs call these before they hand a URL to an image loader.
 */
import { isLoopbackHost, urlHost } from "./url";

/** A picture bigger than this is not drawn, where the platform can stop the download. */
export const PICTURE_MAX_BYTES = 5 * 1024 * 1024;

/** A picture that failed to load or decode is not requested again for this long. */
export const PICTURE_FAILURE_MEMORY_MS = 60_000;

/** Failed pictures remembered at most (the oldest are forgotten first). */
export const PICTURE_FAILURE_LIMIT = 200;

/**
 * May the SDK draw this URL?
 *
 * - `https://` always; `http://` only to a loopback host (localhost, 127.0.0.1, ::1, 10.0.2.2);
 * - `data:image/...` unless it is longer than `PICTURE_MAX_BYTES` once decoded (4/3 of that in
 *   characters);
 * - a URL without a scheme (`/gifts/rose.webp`, `art/rose.webp`) is a path on the app's own origin:
 *   allowed on the web and React Native web, which have one (native SDKs have none and refuse it);
 * - anything else (`javascript:`, `file:`, `blob:`, `ftp:`, `//host/x`, empty) is refused.
 */
export function isPictureUrl(url: string | null | undefined): boolean {
  if (typeof url !== "string") return false;
  const u = url.trim();
  if (u === "") return false;
  if (/^https:\/\//i.test(u)) return true;
  if (/^http:\/\//i.test(u)) {
    const host = urlHost(u);
    return host !== null && isLoopbackHost(host);
  }
  if (/^data:image\//i.test(u)) return u.length <= Math.ceil((PICTURE_MAX_BYTES * 4) / 3) + 256;
  return !/^[a-z][a-z0-9+.-]*:/i.test(u) && !u.startsWith("//");
}

/** Remembers pictures that failed, for `PICTURE_FAILURE_MEMORY_MS`. */
export class PictureFailures {
  private readonly failedAt = new Map<string, number>();

  constructor(private readonly now: () => number = () => Date.now()) {}

  /** The picture failed to load or decode now. */
  mark(url: string, atMs: number = this.now()): void {
    this.failedAt.delete(url);
    this.failedAt.set(url, atMs);
    while (this.failedAt.size > PICTURE_FAILURE_LIMIT) {
      const oldest = this.failedAt.keys().next().value;
      if (oldest === undefined) break;
      this.failedAt.delete(oldest);
    }
  }

  /** Failed less than `PICTURE_FAILURE_MEMORY_MS` ago. */
  has(url: string, atMs: number = this.now()): boolean {
    const at = this.failedAt.get(url);
    if (at === undefined) return false;
    if (atMs - at >= PICTURE_FAILURE_MEMORY_MS) {
      this.failedAt.delete(url);
      return false;
    }
    return true;
  }

  clear(): void {
    this.failedAt.clear();
  }
}

/** The SDK's own memory, on the wall clock. */
export const pictureFailures = new PictureFailures();

/**
 * The URL to hand to an image loader, or `null` to draw the placeholder instead: the URL is not
 * allowed, or the picture failed less than a minute ago.
 */
export function pictureSrc(url: string | null | undefined): string | null {
  if (!isPictureUrl(url) || pictureFailures.has(url as string)) return null;
  return (url as string).trim();
}

/** Tell the SDK a picture failed (an image `error` event, a decode that threw). */
export function pictureFailed(url: string | null | undefined): void {
  if (typeof url === "string" && url !== "") pictureFailures.mark(url.trim());
}
