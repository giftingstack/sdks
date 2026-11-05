/**
 * The `_headers` file of the hosted demo (apps/demo, Cloudflare static assets). The site embeds
 * the demo in an iframe, so the demo must be framable by giftingstack.com and nobody else:
 * `frame-ancestors` does that. `X-Frame-Options` is left out on purpose, because it cannot name
 * more than one origin and would fight the CSP. Nothing else is restricted here: the demo is mock
 * data and loads its pictures from assets.giftingstack.com.
 */
export const DEMO_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Content-Security-Policy":
    "frame-ancestors https://giftingstack.com https://*.giftingstack.com 'self'",
} as const;

/** The text of the `_headers` file: one rule for every path. */
export function demoHeadersFile(): string {
  const lines = Object.entries(DEMO_HEADERS).map(([name, value]) => `  ${name}: ${value}`);
  return `/*\n${lines.join("\n")}\n`;
}
