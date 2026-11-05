/** Theming (spec 9.2): colour helpers, themeFromAccent, and live theme switching on the web. */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  contrastRatio,
  darkTheme,
  defaultTheme,
  ensureContrast,
  lightTheme,
  mixHex,
  parseHex,
  readableOn,
  themeContrastPairs,
  themeFromAccent,
} from "../src/core";
import * as web from "../src/web";
import * as rn from "../src/react-native";
import { FAKE_TIMERS, installWebEnv } from "./web-setup";

describe("colour helpers", () => {
  it("parses #rgb and #rrggbb, rejects the rest", () => {
    expect(parseHex("#f80")).toEqual([255, 136, 0]);
    expect(parseHex("#8B7BFF")).toEqual([139, 123, 255]);
    expect(parseHex("rgba(1,2,3,1)")).toBeNull();
    expect(parseHex("#12345")).toBeNull();
  });

  it("contrast ratio is symmetric and follows WCAG 2", () => {
    expect(contrastRatio("#000", "#fff")).toBe(21);
    expect(contrastRatio("#777777", "#ffffff")).toBeCloseTo(4.48, 2);
    expect(contrastRatio("#ffffff", "#777777")).toBe(contrastRatio("#777777", "#ffffff"));
  });

  it("mixHex blends channel by channel", () => {
    expect(mixHex("#000000", "#ffffff", 0.5)).toBe("#808080");
    expect(mixHex("#ff0000", "#0000ff", 0)).toBe("#ff0000");
  });

  it("ensureContrast keeps a readable colour and fixes a weak one", () => {
    expect(ensureContrast("#ffffff", "#000000", 4.5)).toBe("#ffffff");
    const fixed = ensureContrast("#888888", "#ffffff", 4.5);
    expect(contrastRatio(fixed, "#ffffff")).toBeGreaterThanOrEqual(4.5);
    expect(fixed).not.toBe("#000000"); // a small step, not straight to black
  });

  it("readableOn picks white or black, whichever is stronger (always >= 4.5:1)", () => {
    for (const bg of [
      "#000000",
      "#ffffff",
      "#777777",
      "#808080",
      "#ff4f9a",
      "#ffeb3b",
      "#3355ff",
    ]) {
      expect(contrastRatio(readableOn(bg), bg)).toBeGreaterThanOrEqual(4.5);
    }
    expect(readableOn("#ffeb3b")).toBe("#000000");
    expect(readableOn("#3355ff")).toBe("#ffffff");
  });
});

describe("presets and themeFromAccent", () => {
  it("defaultTheme is unchanged; darkTheme fixes only the weak Send label contrast", () => {
    expect(defaultTheme.accent).toBe("#8b7bff");
    expect(defaultTheme.surface).toBe("#1e1e2e");
    expect(contrastRatio(defaultTheme.accentText, defaultTheme.accent)).toBeLessThan(4.5);
    const { accent, noticeBackground, ...rest } = darkTheme;
    const { accent: a0, noticeBackground: n0, ...rest0 } = defaultTheme;
    expect(rest).toEqual(rest0);
    expect([accent, noticeBackground]).not.toEqual([a0, n0]);
  });

  it("the light preset keeps gold and the large notice legible on white", () => {
    for (const p of themeContrastPairs(lightTheme)) {
      expect(contrastRatio(p.fg, p.bg), p.name).toBeGreaterThanOrEqual(p.min);
    }
    expect(contrastRatio(lightTheme.coin, "#ffffff")).toBeGreaterThanOrEqual(4.5);
  });

  it("random accents in both modes always meet the contrast rule", () => {
    let seed = 7;
    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    for (let i = 0; i < 300; i++) {
      const hex = `#${Math.floor(rnd() * 0xffffff)
        .toString(16)
        .padStart(6, "0")}`;
      for (const mode of ["dark", "light"] as const) {
        const t = themeFromAccent(hex, mode);
        expect(t.accent).toBe(hex);
        for (const p of themeContrastPairs(t)) {
          expect(contrastRatio(p.fg, p.bg), `${hex}/${mode} ${p.name}`).toBeGreaterThanOrEqual(
            p.min,
          );
        }
      }
    }
  });

  it("light mode is light and dark mode is dark", () => {
    expect(themeFromAccent("#ff4f9a", "light").surface).toBe("#ffffff");
    expect(contrastRatio(themeFromAccent("#ff4f9a", "dark").surface, "#000000")).toBeLessThan(3);
    expect(themeFromAccent("#ff4f9a", "dark").noticeBackground).toBe("rgba(255, 79, 154, 0.92)");
  });

  it("is exported from the web and React Native entry points", () => {
    for (const m of [web, rn]) {
      expect(m.themeFromAccent).toBe(themeFromAccent);
      expect(m.lightTheme).toBe(lightTheme);
      expect(m.darkTheme).toBe(darkTheme);
      expect(m.defaultTheme).toBe(defaultTheme);
    }
  });
});

describe("live theme switching (web)", () => {
  let env: ReturnType<typeof installWebEnv>;
  let container: HTMLElement;
  beforeEach(() => {
    env = installWebEnv();
    vi.useFakeTimers({ toFake: [...FAKE_TIMERS] });
    container = document.createElement("div");
    document.body.appendChild(container);
  });
  afterEach(() => {
    container.remove();
    vi.useRealTimers();
    env.restore();
  });
  const v = (el: HTMLElement, name: string) => el.style.getPropertyValue(name);

  it("the tray takes a new theme at once and a later theme replaces it entirely", () => {
    const tray = new web.GiftTray(container, { balance: 10 });
    tray.update({ theme: lightTheme });
    expect(v(tray.element, "--gs-surface")).toBe("#ffffff");
    expect(v(tray.element, "--gs-selected")).toBe(lightTheme.selected);
    expect(v(tray.element, "--gs-coin-text")).toBe("#ffffff");
    tray.update({ theme: { accent: "#ff0000" } });
    expect(v(tray.element, "--gs-accent")).toBe("#ff0000");
    expect(v(tray.element, "--gs-surface")).toBe(""); // back to the CSS default, nothing left over
    tray.update({ balance: 20 }); // an update without a theme keeps it
    expect(v(tray.element, "--gs-accent")).toBe("#ff0000");
    tray.destroy();
  });

  it("the effect layer's notice switches too; other options leave the theme alone", () => {
    const layer = new web.GiftEffectLayer(container);
    const pink = themeFromAccent("#ff4f9a", "dark");
    layer.setOptions({ theme: pink });
    expect(v(layer.element, "--gs-notice-background")).toBe(pink.noticeBackground);
    expect(v(layer.element, "--gs-combo-text")).toBe(pink.comboText);
    layer.setOptions({ noticeBottom: 300 });
    expect(v(layer.element, "--gs-notice-background")).toBe(pink.noticeBackground);
    layer.setOptions({ theme: undefined });
    expect(v(layer.element, "--gs-notice-background")).toBe("");
    layer.destroy();
  });

  it("the style sheet reads the newer tokens instead of fixed colours", () => {
    const tray = new web.GiftTray(container, {});
    const css = document.querySelector("style[data-giftingstack]")!.textContent!;
    expect(css).toContain("background: var(--gs-selected)");
    expect(css).toContain("color: var(--gs-coin-text)");
    expect(css).toContain("color: var(--gs-combo-text)");
    tray.destroy();
  });
});
