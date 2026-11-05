import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../core/pictures.dart';

/// Makes the [ImageProvider] for a picture URL. Tests and apps with their own
/// cache replace the default.
typedef GiftImageProviderBuilder = ImageProvider Function(String url);

/// The default: a [GiftNetworkImage], cached by Flutter's image cache.
ImageProvider defaultGiftImageProvider(String url) => GiftNetworkImage(url);

/// A network picture with the SDK's rules (SPEC 7.6, audit R-08):
///
/// - only `https://`, `data:image/...` and `http://` to a loopback host
///   (localhost, 127.0.0.1, ::1, 10.0.2.2); anything else fails at once and is
///   never requested;
/// - at most [pictureMaxBytes] (5 MB): a bigger download is stopped;
/// - a picture that failed (refused, too big, network, not an image) is
///   remembered for 60 s: the same URL fails at once instead of being requested
///   again by every rebuild.
///
/// A failing provider reports through `Image.errorBuilder`, so the widgets draw
/// their placeholder.
@immutable
class GiftNetworkImage extends ImageProvider<GiftNetworkImage> {
  /// Creates the provider. [client] and [failures] are for tests.
  const GiftNetworkImage(
    this.url, {
    this.scale = 1.0,
    this.client,
    this.failures,
    this.timeout = const Duration(seconds: 20),
  });

  /// The picture's address.
  final String url;

  /// Pixel density of the picture.
  final double scale;

  /// The HTTP client. Default: a new one per download.
  final http.Client? client;

  /// The failure memory. Default: [pictureFailures].
  final PictureFailures? failures;

  /// Time allowed for the whole download.
  final Duration timeout;

  PictureFailures get _failures => failures ?? pictureFailures;

  @override
  Future<GiftNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<GiftNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(
    GiftNetworkImage key,
    ImageDecoderCallback decode,
  ) =>
      MultiFrameImageStreamCompleter(
        codec: _load(key, decode),
        scale: key.scale,
        debugLabel: 'GiftNetworkImage',
      );

  Future<ui.Codec> _load(
    GiftNetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    final u = key.url.trim();
    if (!isPictureUrl(u)) throw const GiftPictureException('refused');
    if (_failures.has(u)) throw const GiftPictureException('failed recently');
    try {
      final Uint8List bytes;
      if (u.toLowerCase().startsWith('data:')) {
        bytes = UriData.parse(u).contentAsBytes();
        if (bytes.length > pictureMaxBytes) {
          throw const GiftPictureException('too big');
        }
      } else {
        bytes = await _download(u);
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } on Object {
      _failures.mark(u);
      rethrow;
    }
  }

  Future<Uint8List> _download(String u) async {
    final http.Client c = client ?? http.Client();
    try {
      Future<Uint8List> go() async {
        final res = await c.send(http.Request('GET', Uri.parse(u)));
        if (res.statusCode != 200) {
          throw GiftPictureException('status ${res.statusCode}');
        }
        final length = res.contentLength;
        if (length != null && length > pictureMaxBytes) {
          throw const GiftPictureException('too big');
        }
        final out = BytesBuilder(copy: false);
        await for (final chunk in res.stream) {
          out.add(chunk);
          if (out.length > pictureMaxBytes) {
            throw const GiftPictureException('too big');
          }
        }
        return out.takeBytes();
      }

      return timeout > Duration.zero ? await go().timeout(timeout) : await go();
    } finally {
      if (client == null) c.close();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is GiftNetworkImage && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => 'GiftNetworkImage(scale: $scale)';
}

/// Why a [GiftNetworkImage] did not load. Never carries the URL.
class GiftPictureException implements Exception {
  /// Creates the exception.
  const GiftPictureException(this.reason);

  /// `refused`, `failed recently`, `too big` or `status NNN`.
  final String reason;

  @override
  String toString() => 'GiftPictureException: $reason';
}

/// Starts loading and decoding [url] so it is ready when needed. Needs no
/// `BuildContext`. Never throws: a picture that cannot load is just not warmed.
/// With the default provider, a URL the SDK refuses, or one that failed in the
/// last minute, is not requested.
void warmUpImage(String url, [GiftImageProviderBuilder? builder]) {
  if (builder == null &&
      (!isPictureUrl(url) || pictureFailures.has(url.trim()))) {
    return; // only the default provider knows the SDK's rules
  }
  try {
    final stream = (builder ?? defaultGiftImageProvider)(url)
        .resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo _, bool __) => stream.removeListener(listener),
      onError: (Object _, StackTrace? __) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  } on Object {
    // Not supported here: nothing to warm up.
  }
}
