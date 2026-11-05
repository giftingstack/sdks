/**
 * Plain-text base URLs (SPEC 3.1). A token travels in every request, so `http://` and `ws://`
 * are refused unless the host is this machine (or the Android emulator's host alias) or the
 * app says `allowInsecure: true`.
 */

/** Hosts that may use `http://` and `ws://` without `allowInsecure`. */
export const LOOPBACK_HOSTS: readonly string[] = ["localhost", "127.0.0.1", "::1", "10.0.2.2"];

/** The lower-case host of a URL (no userinfo, port or IPv6 brackets), `null` when there is none. */
export function urlHost(url: string): string | null {
  const m = /^[a-z][a-z0-9+.-]*:\/\/([^/?#]*)/i.exec(url.trim());
  if (!m) return null;
  let authority = m[1]!;
  const at = authority.lastIndexOf("@");
  if (at >= 0) authority = authority.slice(at + 1);
  let host: string;
  if (authority.startsWith("[")) {
    const end = authority.indexOf("]");
    host = end < 0 ? authority.slice(1) : authority.slice(1, end);
  } else {
    const colon = authority.lastIndexOf(":");
    host = colon < 0 ? authority : authority.slice(0, colon);
  }
  return host.toLowerCase();
}

/** `localhost`, `127.0.0.1`, `::1` or `10.0.2.2`. */
export function isLoopbackHost(host: string): boolean {
  return LOOPBACK_HOSTS.includes(host.toLowerCase());
}

/** Plain text on the wire: `http://` or `ws://` (any case). */
export function isInsecureUrl(url: string): boolean {
  return /^(http|ws):\/\//i.test(url.trim());
}

/**
 * Throws when `url` is `http://` or `ws://` to a host that is not loopback, unless
 * `allowInsecure`. `https://` and `wss://` (and anything else) always pass. A programmer error:
 * the message names the option, never the token.
 */
export function assertSecureUrl(
  url: string,
  allowInsecure: boolean | undefined,
  what: string,
): void {
  if (allowInsecure === true || !isInsecureUrl(url)) return;
  const host = urlHost(url);
  if (host !== null && isLoopbackHost(host)) return;
  const shown = `${url.slice(0, url.indexOf("://"))}://${host ?? "?"}`; // never the userinfo
  throw new Error(
    `GiftingStack: ${what} "${shown}" is not secure. Use https:// (wss:// for rooms), or pass ` +
      `allowInsecure: true. localhost, 127.0.0.1, ::1 and 10.0.2.2 are always allowed.`,
  );
}
