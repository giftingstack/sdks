/// Plain-text base URLs (SPEC 3.1). A token travels in every request, so
/// `http://` and `ws://` are refused unless the host is this machine (or the
/// Android emulator's host alias) or the app says `allowInsecure: true`.
library;

/// Hosts that may use `http://` and `ws://` without `allowInsecure`.
const List<String> loopbackHosts = <String>[
  'localhost',
  '127.0.0.1',
  '::1',
  '10.0.2.2',
];

final RegExp _authority = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]*)');

/// The lower-case host of [url] (no userinfo, port or IPv6 brackets), null when
/// there is none.
String? urlHost(String url) {
  final m = _authority.firstMatch(url.trim());
  if (m == null) return null;
  var authority = m.group(1)!;
  final at = authority.lastIndexOf('@');
  if (at >= 0) authority = authority.substring(at + 1);
  String host;
  if (authority.startsWith('[')) {
    final end = authority.indexOf(']');
    host = end < 0 ? authority.substring(1) : authority.substring(1, end);
  } else {
    final colon = authority.lastIndexOf(':');
    host = colon < 0 ? authority : authority.substring(0, colon);
  }
  return host.toLowerCase();
}

/// `localhost`, `127.0.0.1`, `::1` or `10.0.2.2`.
bool isLoopbackHost(String host) => loopbackHosts.contains(host.toLowerCase());

/// Plain text on the wire: `http://` or `ws://` (any case).
bool isInsecureUrl(String url) =>
    RegExp(r'^(http|ws)://', caseSensitive: false).hasMatch(url.trim());

/// Throws an [ArgumentError] when [url] is `http://` or `ws://` to a host that
/// is not loopback, unless [allowInsecure]. `https://` and `wss://` always
/// pass. A programmer error: the message names the option, never the token or
/// the URL's userinfo.
void assertSecureUrl(String url, bool allowInsecure, String what) {
  if (allowInsecure || !isInsecureUrl(url)) return;
  final host = urlHost(url);
  if (host != null && isLoopbackHost(host)) return;
  final shown = '${url.substring(0, url.indexOf('://'))}://${host ?? '?'}';
  throw ArgumentError.value(
    shown,
    what,
    'is not secure. Use https:// (wss:// for rooms), or pass '
    'allowInsecure: true. localhost, 127.0.0.1, ::1 and 10.0.2.2 are always '
    'allowed.',
  );
}
