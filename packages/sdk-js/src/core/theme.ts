/**
 * Theme tokens and two ready palettes, plus `themeFromAccent`, which builds a whole readable theme
 * from one brand colour (spec section 9.2). Pure data and arithmetic, no UI: the web layer turns
 * the tokens into CSS variables, React Native reads them directly, other platforms port this file.
 */

/** Colors used by the tray and the effect notices. Override any of them. */
export interface GiftTheme {
  /** Cells and the balance pill. */
  background: string;
  /** The tray. */
  surface: string;
  border: string;
  text: string;
  muted: string;
  accent: string;
  /** Text on `accent` (the Send button). */
  accentText: string;
  /** Coin discs, "+ Coins" and the "Get coins" button. */
  coin: string;
  /** Text on `coin` (the "Get coins" button). */
  coinText: string;
  /** Background of the selected cell. */
  selected: string;
  danger: string;
  noticeBackground: string;
  noticeText: string;
  /** The combo counter ("x3") on a small or medium notice. */
  comboText: string;
  /** Notice for large gifts. */
  noticeBigBackground: string;
  noticeBigText: string;
  /** Color of the light rays and sparks of large gifts. */
  glow: string;
}

export type ThemeMode = "dark" | "light";

/** The original look. Unchanged since 1.0 (the three newer tokens keep the old fixed colours). */
export const defaultTheme: GiftTheme = {
  background: "#14141f",
  surface: "#1e1e2e",
  border: "#2d2d44",
  text: "#f4f2ff",
  muted: "#a3a1c2",
  accent: "#8b7bff",
  accentText: "#ffffff",
  coin: "#ffd27a",
  coinText: "#2a1600",
  selected: "#221f45",
  danger: "#ff8fa3",
  noticeBackground: "rgba(123, 107, 255, 0.92)",
  noticeText: "#ffffff",
  comboText: "#fff3c4",
  noticeBigBackground: "#e8a93a",
  noticeBigText: "#2a1600",
  glow: "#ffdc8c",
};

/**
 * The dark preset: the default look with a slightly deeper accent, so the white Send label reaches
 * 4.5:1 (white on the default accent `#8b7bff` is only 3.3:1; `defaultTheme` keeps it for
 * existing apps).
 */
export const darkTheme: GiftTheme = {
  ...defaultTheme,
  accent: "#6d5cf0",
  noticeBackground: "rgba(109, 92, 240, 0.92)",
};

/** A light preset. Every text pair is at least 4.5:1 (see `themeContrastPairs`). */
export const lightTheme: GiftTheme = {
  background: "#f1eff8",
  surface: "#ffffff",
  border: "#dcd8ea",
  text: "#1c1a2e",
  muted: "#5f5b78",
  accent: "#6a54e8",
  accentText: "#ffffff",
  coin: "#9a6300",
  coinText: "#ffffff",
  selected: "#e6e1ff",
  danger: "#c4204a",
  noticeBackground: "rgba(106, 84, 232, 0.94)",
  noticeText: "#ffffff",
  comboText: "#fff3c4",
  noticeBigBackground: "#e8a93a",
  noticeBigText: "#2a1600",
  glow: "#ffcf66",
};

export function resolveTheme(theme?: Partial<GiftTheme>): GiftTheme {
  return { ...defaultTheme, ...theme };
}

// ------------------------------------------------------------------ colour arithmetic

export type Rgb = [number, number, number];

/** `#rgb` or `#rrggbb` (any case) to 0..255 channels; anything else is null. */
export function parseHex(hex: string): Rgb | null {
  const m = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return null;
  const h = m[1]!.length === 3 ? [...m[1]!].map((c) => c + c).join("") : m[1]!;
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)) as Rgb;
}

export function toHex([r, g, b]: Rgb): string {
  return `#${[r, g, b]
    .map((v) =>
      Math.round(Math.min(255, Math.max(0, v)))
        .toString(16)
        .padStart(2, "0"),
    )
    .join("")}`;
}

/** WCAG 2 relative luminance of an opaque colour, 0 (black) to 1 (white). */
export function relativeLuminance(hex: string): number {
  const rgb = parseHex(hex);
  if (!rgb) throw new Error(`Not a hex colour: ${hex}`);
  const [r, g, b] = rgb.map((v) => {
    const c = v / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  }) as Rgb;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG 2 contrast ratio of two opaque colours, 1 to 21. */
export function contrastRatio(a: string, b: string): number {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

/** `a` moved towards `b` by `t` (0 = a, 1 = b), channel by channel. */
export function mixHex(a: string, b: string, t: number): string {
  const x = parseHex(a)!;
  const y = parseHex(b)!;
  return toHex([0, 1, 2].map((i) => x[i]! + (y[i]! - x[i]!) * t) as Rgb);
}

/**
 * `fg` itself if it reaches `min` against `bg`; otherwise `fg` moved step by step (5 %) towards
 * white or black, whichever is further from `bg`, until it does (pure white or black at the end).
 */
export function ensureContrast(fg: string, bg: string, min: number): string {
  if (contrastRatio(fg, bg) >= min) return fg;
  const target = relativeLuminance(bg) > 0.18 ? "#000000" : "#ffffff";
  for (let t = 0.05; t < 1; t += 0.05) {
    const c = mixHex(fg, target, t);
    if (contrastRatio(c, bg) >= min) return c;
  }
  return target;
}

/** White or black, whichever contrasts more with `bg` (always at least 4.58:1). */
export function readableOn(bg: string): string {
  return contrastRatio("#ffffff", bg) >= contrastRatio("#000000", bg) ? "#ffffff" : "#000000";
}

/**
 * A whole theme from one brand colour. The accent is used as given; every other token is derived
 * so that text stays readable: text, muted and coin text on the surface and on the background,
 * text on the selected cell, and the text on the accent and on the coin are all at least 4.5:1.
 * Throws for anything but `#rgb` / `#rrggbb`.
 */
export function themeFromAccent(accent: string, mode: ThemeMode = "dark"): GiftTheme {
  const rgb = parseHex(accent);
  if (!rgb) throw new Error(`themeFromAccent: not a hex colour: ${accent}`);
  const a = toHex(rgb);
  const dark = mode === "dark";
  const surface = dark ? mixHex("#17171f", a, 0.1) : "#ffffff";
  const background = dark ? mixHex("#0d0d14", a, 0.06) : mixHex("#f4f4f7", a, 0.06);
  const selected = dark ? mixHex(surface, a, 0.22) : mixHex("#ffffff", a, 0.16);
  // Text must read on the surface, the background and the selected cell: check the hardest one.
  const fit = (fg: string) =>
    [surface, background, selected].reduce((c, bg) => ensureContrast(c, bg, 4.5), fg);
  const text = fit(dark ? mixHex("#ffffff", a, 0.05) : mixHex("#16151f", a, 0.08));
  const muted = fit(dark ? mixHex("#b0afc0", a, 0.15) : mixHex("#5c5b6b", a, 0.15));
  const coin = dark ? "#ffd27a" : fit("#9a6300");
  const accentText = readableOn(a);
  return {
    background,
    surface,
    border: dark ? mixHex("#2a2a35", a, 0.25) : mixHex("#dedee6", a, 0.2),
    text,
    muted,
    accent: a,
    accentText,
    coin,
    coinText: readableOn(coin),
    selected,
    danger: dark ? "#ff8fa3" : "#c4204a",
    noticeBackground: `rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, 0.92)`,
    noticeText: accentText,
    comboText: accentText === "#ffffff" ? "#fff3c4" : accentText,
    noticeBigBackground: "#e8a93a",
    noticeBigText: "#2a1600",
    glow: "#ffdc8c",
  };
}

/**
 * The text/background pairs the contrast rule covers, with their minimum ratio. The notice sits on
 * its own pill, so its pairs are checked against the opaque accent (`noticeBackground` is the
 * accent at 92 %); the combo counter is large text (28, bold), so 3:1.
 */
export function themeContrastPairs(
  t: GiftTheme,
): { fg: string; bg: string; min: number; name: string }[] {
  return [
    { name: "text/surface", fg: t.text, bg: t.surface, min: 4.5 },
    { name: "text/background", fg: t.text, bg: t.background, min: 4.5 },
    { name: "text/selected", fg: t.text, bg: t.selected, min: 4.5 },
    { name: "muted/surface", fg: t.muted, bg: t.surface, min: 4.5 },
    { name: "coin/surface", fg: t.coin, bg: t.surface, min: 4.5 },
    { name: "accentText/accent", fg: t.accentText, bg: t.accent, min: 4.5 },
    { name: "coinText/coin", fg: t.coinText, bg: t.coin, min: 4.5 },
    { name: "noticeText/accent", fg: t.noticeText, bg: t.accent, min: 4.5 },
    {
      name: "noticeBigText/noticeBigBackground",
      fg: t.noticeBigText,
      bg: t.noticeBigBackground,
      min: 4.5,
    },
  ];
}
