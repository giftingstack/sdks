/**
 * Which pictures the SDK draws and what a failed one does (SPEC 7.6, audit R-08), on the web
 * layer. The pure rules are pinned by pictures.json in conformance.test.ts.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { type Gift, isPictureUrl, pictureFailed, pictureSrc, pictureFailures } from "../src/core";
import { GiftTray, prefetch } from "../src/web";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";

const gift = (id: string, over: Partial<Gift> = {}): Gift => ({
  id,
  name: id,
  description: null,
  price: 10,
  icon_url: `https://assets.test/${id}/256.webp`,
  animation_url: `https://assets.test/${id}/512.webp`,
  sort_order: 0,
  ...over,
});

let env: ReturnType<typeof installWebEnv>;
let container: HTMLElement;
let trays: GiftTray[] = [];
beforeEach(() => {
  env = installWebEnv();
  vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
  container = document.createElement("div");
  document.body.appendChild(container);
});
afterEach(() => {
  for (const t of trays) t.destroy();
  trays = [];
  container.remove();
  vi.useRealTimers();
  env.restore();
});
const mk = (options: ConstructorParameters<typeof GiftTray>[1]) => {
  const tray = new GiftTray(container, options);
  trays.push(tray);
  return tray;
};

describe("picture URLs on the web", () => {
  it("a path without a scheme is the page's own origin: allowed", () => {
    expect(isPictureUrl("/gifts/rose/256.webp")).toBe(true);
    expect(isPictureUrl("art/rose.webp")).toBe(true);
    expect(isPictureUrl("//cdn.example.com/rose.webp")).toBe(false);
  });

  it("pictureSrc is the trimmed URL, or null when refused or failed a moment ago", () => {
    expect(pictureSrc("  https://assets.test/a.webp ")).toBe("https://assets.test/a.webp");
    expect(pictureSrc("javascript:alert(1)")).toBeNull();
    pictureFailed("https://assets.test/a.webp");
    expect(pictureSrc("https://assets.test/a.webp")).toBeNull();
    vi.setSystemTime(Date.now() + 60_000);
    expect(pictureSrc("https://assets.test/a.webp")).toBe("https://assets.test/a.webp");
  });
});

describe("web GiftTray pictures", () => {
  const icons = () => [...container.querySelectorAll<HTMLImageElement>("img.gs-icon")];

  it("draws a refused icon URL as the empty placeholder and never sets a src for it", () => {
    mk({
      gifts: [
        gift("ok"),
        gift("js", { icon_url: "javascript:alert(1)" }),
        gift("plain", { icon_url: "http://assets.example.com/a.webp" }),
        gift("local", { icon_url: "http://localhost:8788/a.webp" }),
      ],
      balance: 100,
    });
    expect(icons().map((i) => i.getAttribute("src"))).toEqual([
      "https://assets.test/ok/256.webp",
      "http://localhost:8788/a.webp",
    ]);
    expect(container.querySelectorAll(".gs-icon-empty")).toHaveLength(2);
  });

  it("an icon that failed to load is a placeholder when the grid is rebuilt within a minute", () => {
    const gifts = [gift("a"), gift("b")];
    const tray = mk({ gifts, balance: 100 });
    icons()[0]!.dispatchEvent(new Event("error"));
    tray.update({ gifts: [...gifts], balance: 100 });
    expect(icons().map((i) => i.getAttribute("src"))).toEqual(["https://assets.test/b/256.webp"]);
    expect(container.querySelectorAll(".gs-icon-empty")).toHaveLength(1);
    vi.setSystemTime(Date.now() + 61_000);
    tray.update({ gifts: [...gifts], balance: 100 });
    expect(icons()).toHaveLength(2);
  });

  it("warms the icons of every gift but the big picture of the selected one only", () => {
    const urls: string[] = [];
    mk({
      gifts: [gift("a"), gift("b"), gift("c")],
      balance: 100,
      defaultSelectedId: "b",
      prefetch: (u) => urls.push(u),
    });
    expect(urls).toEqual([
      "https://assets.test/a/256.webp",
      "https://assets.test/b/256.webp",
      "https://assets.test/c/256.webp",
      "https://assets.test/b/512.webp",
    ]);
  });
});

describe("web prefetch", () => {
  it("does not request a refused URL or one that failed a moment ago", () => {
    const made: string[] = [];
    const Real = globalThis.Image;
    class Fake {
      decoding = "";
      listeners: Record<string, () => void> = {};
      addEventListener(name: string, fn: () => void) {
        this.listeners[name] = fn;
      }
      set src(v: string) {
        made.push(v);
      }
      decode() {
        return Promise.resolve();
      }
    }
    globalThis.Image = Fake as unknown as typeof Image;
    try {
      prefetch("file:///etc/passwd");
      prefetch("http://assets.example.com/a.webp");
      pictureFailed("https://assets.test/failed.webp");
      prefetch("https://assets.test/failed.webp");
      prefetch("https://assets.test/fine.webp");
      expect(made).toEqual(["https://assets.test/fine.webp"]);
    } finally {
      globalThis.Image = Real;
      pictureFailures.clear();
    }
  });
});
