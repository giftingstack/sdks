/// Which picture URLs the SDK draws and how it treats pictures that fail
/// (SPEC 7.6, audit R-08). Pure Dart: the widgets call these before they load.
library;

import 'secure_url.dart';

/// A picture bigger than this is not drawn (the download is stopped).
const int pictureMaxBytes = 5 * 1024 * 1024;

/// A picture that failed to load or decode is not requested again for this
/// long.
const int pictureFailureMemoryMs = 60000;

/// Failed pictures remembered at most (the oldest are forgotten first).
const int pictureFailureLimit = 200;

final RegExp _https = RegExp(r'^https://', caseSensitive: false);
final RegExp _http = RegExp(r'^http://', caseSensitive: false);
final RegExp _dataImage = RegExp(r'^data:image/', caseSensitive: false);

/// May the SDK draw this URL?
///
/// - `https://` always; `http://` only to a loopback host (localhost,
///   127.0.0.1, ::1, 10.0.2.2);
/// - `data:image/...` unless it is longer than [pictureMaxBytes] once decoded
///   (4/3 of that in characters);
/// - anything else (`javascript:`, `file:`, `blob:`, `ftp:`, `//host/x`, a path
///   without a scheme, empty) is refused: native apps have no origin to resolve
///   a path against.
bool isPictureUrl(String? url) {
  if (url == null) return false;
  final u = url.trim();
  if (u.isEmpty) return false;
  if (_https.hasMatch(u)) return true;
  if (_http.hasMatch(u)) {
    final host = urlHost(u);
    return host != null && isLoopbackHost(host);
  }
  if (_dataImage.hasMatch(u)) {
    return u.length <= (pictureMaxBytes * 4 / 3).ceil() + 256;
  }
  return false;
}

/// Remembers pictures that failed, for [pictureFailureMemoryMs].
class PictureFailures {
  /// Creates a memory on [now] (ms; default the wall clock).
  PictureFailures([int Function()? now])
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _now;
  final Map<String, int> _failedAt = <String, int>{};

  /// The picture failed to load or decode now.
  void mark(String url, [int? atMs]) {
    _failedAt
      ..remove(url)
      ..[url] = atMs ?? _now();
    while (_failedAt.length > pictureFailureLimit) {
      _failedAt.remove(_failedAt.keys.first);
    }
  }

  /// Failed less than [pictureFailureMemoryMs] ago.
  bool has(String url, [int? atMs]) {
    final at = _failedAt[url];
    if (at == null) return false;
    if ((atMs ?? _now()) - at >= pictureFailureMemoryMs) {
      _failedAt.remove(url);
      return false;
    }
    return true;
  }

  /// Forgets everything.
  void clear() => _failedAt.clear();
}

/// The SDK's own memory, on the wall clock.
final PictureFailures pictureFailures = PictureFailures();
