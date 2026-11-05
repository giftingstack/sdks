/**
 * The hosted demo's `_headers` file (audit F-07): nosniff, a referrer policy and `frame-ancestors`
 * for giftingstack.com only, with no X-Frame-Options. The build writes it into the public dir.
 */
import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { DEMO_HEADERS, demoHeadersFile } from "../demo/headers";
import site from "../demo/site.vite.config";

describe("demo _headers", () => {
  const text = demoHeadersFile();

  it("is one rule for every path with three headers, two-space indented", () => {
    const lines = text.trimEnd().split("\n");
    expect(lines[0]).toBe("/*");
    expect(lines.slice(1).every((l) => /^ {2}[A-Za-z-]+: \S/.test(l))).toBe(true);
    expect(lines).toHaveLength(4);
    expect(text.endsWith("\n")).toBe(true);
  });

  it("sends nosniff and a referrer policy", () => {
    expect(text).toContain("  X-Content-Type-Options: nosniff\n");
    expect(text).toContain("  Referrer-Policy: strict-origin-when-cross-origin\n");
  });

  it("lets only giftingstack.com (and itself) frame the demo, and omits X-Frame-Options", () => {
    expect(DEMO_HEADERS["Content-Security-Policy"]).toBe(
      "frame-ancestors https://giftingstack.com https://*.giftingstack.com 'self'",
    );
    expect(text).toContain(
      `  Content-Security-Policy: ${DEMO_HEADERS["Content-Security-Policy"]}\n`,
    );
    expect(text.toLowerCase()).not.toContain("x-frame-options");
    // No wildcard host that would allow every site.
    expect(text).not.toMatch(/frame-ancestors[^\n]*(\*\s|\s\*$|http:|https:\/\/\*\s)/);
  });

  it("the site build writes it next to _redirects", () => {
    const plugin = (site.plugins as { name?: string; buildStart?: () => void }[]).find(
      (p) => p.name === "demo-public",
    )!;
    plugin.buildStart!();
    const pub = (site as { publicDir: string }).publicDir;
    expect(fs.readFileSync(path.join(pub, "_headers"), "utf8")).toBe(text);
    expect(fs.existsSync(path.join(pub, "_redirects"))).toBe(true);
  });
});
