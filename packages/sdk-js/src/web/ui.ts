/** Small DOM helpers shared by the wall, the away card and the leaderboard. */
import { formatCount, pictureSrc } from "../core";
import { setPicture } from "./images";
import type { GiftLabels } from "./labels";

export function make<K extends keyof HTMLElementTagNameMap>(
  doc: Document,
  tag: K,
  className = "",
  parent?: Element,
): HTMLElementTagNameMap[K] {
  const e = doc.createElement(tag);
  if (className) e.className = className;
  parent?.appendChild(e);
  return e;
}

/** What a render hook may return: a DOM node, plain text (never HTML), or nothing for the default. */
export type RenderResult = Node | string | null | undefined;

/**
 * Run a render hook. `null` means "draw the default": the hook returned nothing, or it threw (the
 * error goes to `onError`, so a broken hook never blanks the component).
 */
export function runRender(
  doc: Document,
  hook: () => RenderResult,
  onError?: (error: unknown) => void,
): Node | null {
  let out: RenderResult;
  try {
    out = hook();
  } catch (err) {
    onError?.(err);
    return null;
  }
  if (out === null || out === undefined) return null;
  return typeof out === "string" ? doc.createTextNode(out) : out;
}

/** `prefers-reduced-motion`, or no Web Animations API at all (then nothing may move). */
export function motionOff(doc: Document, override?: boolean): boolean {
  const win = doc.defaultView;
  if (typeof win?.Element?.prototype?.animate !== "function") return true;
  return override ?? win.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
}

/** The count as a short string, with the labels' `K` and `M`. */
export const shortCount = (n: number, labels: Pick<GiftLabels, "thousand" | "million">): string =>
  formatCount(n, { thousand: labels.thousand, million: labels.million });

/** The first letter of a name, upper case: the avatar's initial. */
export const initialOf = (name: string): string =>
  (Array.from(name.trim())[0] ?? "?").toUpperCase();

/** A round avatar: the picture when there is one, else an initial on the accent colour. */
export function avatar(
  doc: Document,
  name: string,
  url?: string | null,
  size?: number,
): HTMLElement {
  const box = make(doc, "span", "gs-avatar");
  box.setAttribute("aria-hidden", "true");
  if (size) {
    box.style.width = `${size}px`;
    box.style.height = `${size}px`;
  }
  // The initial and the picture share one grid cell; the picture covers the initial once loaded.
  const letter = make(doc, "span", "gs-avatar-letter", box);
  letter.textContent = initialOf(name);
  if (pictureSrc(url)) {
    const img = make(doc, "img", "gs-avatar-img", box);
    img.alt = "";
    img.decoding = "async";
    img.addEventListener("load", () => (letter.style.visibility = "hidden"));
    img.addEventListener("error", () => img.remove());
    setPicture(img, url);
  }
  return box;
}

/** The picture of a gift, or a plain coin-coloured disc when it has none. */
export function giftIcon(doc: Document, url: string | null | undefined): HTMLElement {
  if (!pictureSrc(url)) {
    const disc = make(doc, "span", "gs-chip-icon gs-chip-fallback");
    disc.setAttribute("aria-hidden", "true");
    return disc;
  }
  const img = make(doc, "img", "gs-chip-icon");
  img.alt = "";
  img.decoding = "async";
  img.loading = "lazy";
  setPicture(img, url);
  return img;
}

/** Makes `container` a positioning context (as the effect layer does) and returns the undo. */
export function ensurePositioned(container: HTMLElement): () => void {
  const win = container.ownerDocument.defaultView;
  if (win && win.getComputedStyle(container).position === "static") {
    const saved = container.style.position;
    container.style.position = "relative";
    return () => {
      container.style.position = saved;
    };
  }
  return () => {};
}

let ids = 0;
/** A page-unique id for `aria-controls` and friends. */
export const uniqueId = (prefix: string): string => `${prefix}-${++ids}`;

/** The people to look up: ids that are not already known and not `null` (deleted). */
export function missingIds(
  ids: Iterable<string | null>,
  known: ReadonlyMap<string, unknown>,
): string[] {
  const out = new Set<string>();
  for (const id of ids) if (id !== null && !known.has(id)) out.add(id);
  return [...out];
}

/** Resolves with the promise's value, or `undefined` once `ms` have passed (timers are the page's). */
export function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T | undefined> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => resolve(undefined), ms);
    promise.then(
      (v) => {
        clearTimeout(t);
        resolve(v);
      },
      (e: unknown) => {
        clearTimeout(t);
        reject(e);
      },
    );
  });
}

export interface UserInfo {
  name: string;
  avatarUrl?: string | null;
}
export type ResolveUsers = (ids: string[]) => Promise<Record<string, UserInfo>>;
