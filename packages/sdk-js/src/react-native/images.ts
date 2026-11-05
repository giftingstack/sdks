import { Image } from "react-native";
import { pictureFailed, pictureSrc } from "../core";

/**
 * Starts loading a picture so it is ready when needed. Without this, the first time a gift
 * is shown the phone decodes its picture on the spot and the effect appears a moment late.
 * Never throws: a picture that cannot load is just not warmed up. A URL the SDK refuses
 * (SPEC 7.6) or one that failed in the last minute is not requested.
 */
export function prefetch(url: string | null | undefined): void {
  const src = pictureSrc(url);
  if (!src) return;
  try {
    void Image.prefetch(src).catch(() => pictureFailed(src));
  } catch {
    // Not supported on this platform: nothing to warm up.
  }
}
