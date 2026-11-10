/**
 * SPEC 9 (2026-11-10): the tray title stays on one line and ends with "…", so a long or
 * translated `title` never wraps and pushes the peek (small) tray taller.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { CSS } from "../src/web/styles";

describe("tray title on one line (SPEC 9)", () => {
  it("web: the title does not wrap and ends with an ellipsis", () => {
    const rule = /\.gs-title \{([^}]*)\}/.exec(CSS)?.[1] ?? "";
    expect(rule).toMatch(/white-space: nowrap/);
    expect(rule).toMatch(/text-overflow: ellipsis/);
    expect(rule).toMatch(/overflow: hidden/);
    expect(rule).toMatch(/min-width: 0/);
  });

  it("React Native: the title Text has numberOfLines={1}", () => {
    const src = readFileSync(join(__dirname, "../src/react-native/GiftTray.tsx"), "utf8");
    expect(src).toMatch(/<Text numberOfLines=\{1\} style=\{\[styles\.title,/);
  });
});
