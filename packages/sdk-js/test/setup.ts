import { vi } from "vitest";

/**
 * jsdom does no layout. react-native-web measures a view with its ResizeObserver and its
 * offsetWidth/offsetHeight, so report a phone-sized box for every element: that is what makes
 * `onLayout` fire in tests.
 */
export const PHONE = { width: 390, height: 780 };

export function installPhoneLayout(): () => void {
  class FakeResizeObserver {
    constructor(private cb: ResizeObserverCallback) {}
    observe(target: Element) {
      this.cb([{ target } as unknown as ResizeObserverEntry], this as unknown as ResizeObserver);
    }
    unobserve() {}
    disconnect() {}
  }
  vi.stubGlobal("ResizeObserver", FakeResizeObserver);
  const proto = HTMLElement.prototype;
  const saved = {
    w: Object.getOwnPropertyDescriptor(proto, "offsetWidth"),
    h: Object.getOwnPropertyDescriptor(proto, "offsetHeight"),
  };
  Object.defineProperty(proto, "offsetWidth", { configurable: true, get: () => PHONE.width });
  Object.defineProperty(proto, "offsetHeight", { configurable: true, get: () => PHONE.height });
  return () => {
    if (saved.w) Object.defineProperty(proto, "offsetWidth", saved.w);
    if (saved.h) Object.defineProperty(proto, "offsetHeight", saved.h);
    vi.unstubAllGlobals();
  };
}
