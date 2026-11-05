// The theme tokens and palettes are plain data in the core, shared by every platform.
export {
  darkTheme,
  defaultTheme,
  lightTheme,
  resolveTheme,
  themeFromAccent,
  type GiftTheme,
  type ThemeMode,
} from "../core/theme";
import { type GiftTheme, defaultTheme } from "../core/theme";

/** `noticeBigBackground` becomes `--gs-notice-big-background`. */
export function cssVarName(token: string): string {
  return `--gs-${token.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`;
}

/**
 * Puts the theme on an element as CSS variables. The theme replaces the previous one: tokens it
 * does not set go back to the CSS defaults (so switching themes live leaves nothing behind).
 */
export function applyTheme(el: HTMLElement, theme: Partial<GiftTheme> | undefined): void {
  for (const token of Object.keys(defaultTheme) as (keyof GiftTheme)[]) {
    const value = theme?.[token];
    if (value) el.style.setProperty(cssVarName(token), value);
    else el.style.removeProperty(cssVarName(token));
  }
}
