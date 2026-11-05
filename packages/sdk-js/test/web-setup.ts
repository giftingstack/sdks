export interface RecordedAnimation {
  el: Element;
  frames: Keyframe[];
  options: KeyframeAnimationOptions;
  cancelled: boolean;
}

export const PAGE = { width: 390, height: 780 };

/**
 * jsdom has no layout, no Web Animations and no matchMedia. This gives the web layer a phone-sized
 * box, records every `element.animate` call, and lets a test flip `prefers-reduced-motion`.
 */
export function installWebEnv() {
  const animations: RecordedAnimation[] = [];
  let reduced = false;
  const listeners = new Set<() => void>();

  const proto = HTMLElement.prototype;
  const saved = {
    w: Object.getOwnPropertyDescriptor(proto, "clientWidth"),
    h: Object.getOwnPropertyDescriptor(proto, "clientHeight"),
  };
  Object.defineProperty(proto, "clientWidth", { configurable: true, get: () => PAGE.width });
  Object.defineProperty(proto, "clientHeight", { configurable: true, get: () => PAGE.height });
  Object.defineProperty(Element.prototype, "animate", {
    configurable: true,
    writable: true,
    value(this: Element, frames: Keyframe[], options: KeyframeAnimationOptions) {
      const rec: RecordedAnimation = { el: this, frames, options, cancelled: false };
      animations.push(rec);
      return {
        cancel() {
          rec.cancelled = true;
        },
      };
    },
  });
  const matchMedia = (query: string) => ({
    media: query,
    get matches() {
      return reduced && query.includes("prefers-reduced-motion");
    },
    addEventListener: (_: string, l: () => void) => listeners.add(l),
    removeEventListener: (_: string, l: () => void) => listeners.delete(l),
  });
  // The layer asks the document's own window, which is not always the test's global.
  const windows = new Set<object>([globalThis, document.defaultView!]);
  for (const w of windows)
    Object.defineProperty(w, "matchMedia", {
      configurable: true,
      writable: true,
      value: matchMedia,
    });

  return {
    animations,
    setReducedMotion(on: boolean) {
      reduced = on;
      for (const l of listeners) l();
    },
    restore() {
      if (saved.w) Object.defineProperty(proto, "clientWidth", saved.w);
      if (saved.h) Object.defineProperty(proto, "clientHeight", saved.h);
      delete (Element.prototype as { animate?: unknown }).animate;
      for (const w of windows) delete (w as { matchMedia?: unknown }).matchMedia;
    },
  };
}

export const FAKE_TIMERS = [
  "setTimeout",
  "clearTimeout",
  "requestAnimationFrame",
  "cancelAnimationFrame",
  "performance",
  "Date",
] as const;
