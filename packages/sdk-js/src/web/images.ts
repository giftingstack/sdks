import { pictureFailed, pictureSrc } from "../core";

const warm = new Map<string, HTMLImageElement>();

/**
 * Starts downloading and decoding a picture so it is ready when needed. Without this the first
 * gift shows its picture a moment late. Never throws; each URL is only requested once (the
 * image object is kept so the browser does not drop the request). A URL the SDK refuses
 * (SPEC 7.6) or one that failed in the last minute is not requested.
 */
export function prefetch(url: string | null | undefined): void {
  const src = pictureSrc(url);
  if (!src || warm.has(src) || typeof Image === "undefined") return;
  try {
    const img = new Image();
    img.decoding = "async";
    img.addEventListener("error", () => {
      pictureFailed(src);
      warm.delete(src);
    });
    img.src = src;
    warm.set(src, img);
    void img.decode?.().catch(() => {
      pictureFailed(src);
      warm.delete(src);
    });
  } catch {
    // Not supported here: nothing to warm up.
  }
}

/**
 * Gives an `<img>` its picture. Returns `false` (and sets nothing) when the URL is refused or
 * failed in the last minute (SPEC 7.6): draw the placeholder then. A load error is remembered.
 */
export function setPicture(img: HTMLImageElement, url: string | null | undefined): boolean {
  const src = pictureSrc(url);
  if (!src) return false;
  img.addEventListener("error", () => pictureFailed(src));
  img.src = src;
  return true;
}
