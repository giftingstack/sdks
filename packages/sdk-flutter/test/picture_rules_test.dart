// The picture rules of SPEC 7.6 (audit R-08) on Flutter: which URLs are loaded,
// the 5 MB cap and the 60 s failure memory of GiftNetworkImage. The pure rules
// are pinned by pictures.json (test/pictures_conformance_test.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A 1 x 1 PNG.
final Uint8List png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Future<ui.Codec> decode(
  ui.ImmutableBuffer buffer, {
  ui.TargetImageSizeCallback? getTargetSize,
}) =>
    ui.instantiateImageCodecFromBuffer(buffer);

/// Loads [provider] and returns null when it worked, else the error.
Future<Object?> load(GiftNetworkImage provider) {
  final done = Completer<Object?>();
  provider.loadImage(provider, decode).addListener(
        ImageStreamListener(
          (info, _) {
            info.dispose();
            if (!done.isCompleted) done.complete(null);
          },
          onError: (Object e, StackTrace? _) {
            if (!done.isCompleted) done.complete(e);
          },
        ),
      );
  return done.future;
}

http.StreamedResponse streamed(
  Stream<List<int>> body,
  int status, {
  int? contentLength,
}) =>
    http.StreamedResponse(body, status, contentLength: contentLength);

void main() {
  late PictureFailures failures;
  setUp(() => failures = PictureFailures());

  testWidgets('loads an https picture, a loopback http one and a data URL',
      (tester) async {
    await tester.runAsync(() async {
      final asked = <String>[];
      final client = MockClient.streaming((req, _) async {
        asked.add(req.url.toString());
        return streamed(
          Stream<List<int>>.value(png),
          200,
          contentLength: png.length,
        );
      });
      for (final url in <String>[
        'https://assets.test/a.png',
        'http://localhost:8788/a.png',
        'http://10.0.2.2:8788/a.png',
      ]) {
        expect(
          await load(GiftNetworkImage(url, client: client, failures: failures)),
          isNull,
          reason: url,
        );
      }
      expect(asked, hasLength(3));
      final dataUrl = 'data:image/png;base64,${base64Encode(png)}';
      expect(
        await load(
          GiftNetworkImage(dataUrl, client: client, failures: failures),
        ),
        isNull,
      );
      expect(asked, hasLength(3), reason: 'a data URL needs no request');
    });
  });

  testWidgets('refuses other schemes and plain http to other hosts, '
      'without any request', (tester) async {
    await tester.runAsync(() async {
      var calls = 0;
      final client = MockClient.streaming((req, _) async {
        calls++;
        return streamed(Stream<List<int>>.value(png), 200);
      });
      for (final url in <String>[
        'http://assets.example.com/a.png',
        'file:///etc/passwd',
        'javascript:alert(1)',
        '/gifts/a.png', // native has no origin to resolve it against
        '//assets.example.com/a.png',
        '',
        'data:text/html;base64,PHNjcmlwdD4=',
      ]) {
        final e = await load(
          GiftNetworkImage(url, client: client, failures: failures),
        );
        expect(e, isA<GiftPictureException>(), reason: url);
        expect((e! as GiftPictureException).reason, 'refused');
        expect(e.toString(), isNot(contains('assets.example.com')));
      }
      expect(calls, 0);
    });
  });

  testWidgets('stops a picture bigger than 5 MB, by header or while streaming',
      (tester) async {
    await tester.runAsync(() async {
      final big = pictureMaxBytes + 1;
      final byHeader = MockClient.streaming(
        (req, _) async => streamed(
          const Stream<List<int>>.empty(),
          200,
          contentLength: big,
        ),
      );
      var pulled = 0;
      final streaming = MockClient.streaming(
        (req, _) async => streamed(
          Stream<List<int>>.periodic(const Duration(milliseconds: 1), (i) {
            pulled++;
            return Uint8List(1024 * 1024);
          }).take(20),
          200,
        ),
      );
      var e = await load(
        GiftNetworkImage(
          'https://assets.test/h.png',
          client: byHeader,
          failures: failures,
        ),
      );
      expect((e! as GiftPictureException).reason, 'too big');
      e = await load(
        GiftNetworkImage(
          'https://assets.test/s.png',
          client: streaming,
          failures: failures,
        ),
      );
      expect((e! as GiftPictureException).reason, 'too big');
      expect(pulled, lessThan(20), reason: 'the download was stopped');
    });
  });

  testWidgets('a failure is remembered for 60 s: no request, same failure',
      (tester) async {
    await tester.runAsync(() async {
      var calls = 0;
      final client = MockClient.streaming((req, _) async {
        calls++;
        return streamed(const Stream<List<int>>.empty(), 404);
      });
      final a = GiftNetworkImage(
        'https://assets.test/x.png',
        client: client,
        failures: failures,
      );
      var e = await load(a);
      expect((e! as GiftPictureException).reason, 'status 404');
      expect(calls, 1);
      e = await load(a);
      expect((e! as GiftPictureException).reason, 'failed recently');
      expect(calls, 1, reason: 'not requested again');
      expect(failures.has('https://assets.test/x.png'), isTrue);
      // After the minute the memory lets it through again.
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(failures.has('https://assets.test/x.png', now + 60000), isFalse);
      e = await load(a);
      expect(calls, 2);
    });
  });

  testWidgets('bytes that are not an image fail and are remembered',
      (tester) async {
    await tester.runAsync(() async {
      final client = MockClient.streaming(
        (req, _) async => streamed(
          Stream<List<int>>.value(utf8.encode('<html>login</html>')),
          200,
        ),
      );
      final e = await load(
        GiftNetworkImage(
          'https://assets.test/p.png',
          client: client,
          failures: failures,
        ),
      );
      expect(e, isNotNull);
      expect(failures.has('https://assets.test/p.png'), isTrue);
    });
  });

  test('the default provider is a GiftNetworkImage; warmUpImage skips refused '
      'URLs', () {
    expect(
      defaultGiftImageProvider('https://assets.test/a.png'),
      isA<GiftNetworkImage>(),
    );
    expect(() => warmUpImage('javascript:alert(1)'), returnsNormally);
  });

  test('equal URL and scale are the same cache key', () {
    expect(
      const GiftNetworkImage('https://assets.test/a.png'),
      const GiftNetworkImage('https://assets.test/a.png'),
    );
    expect(
      const GiftNetworkImage('https://assets.test/a.png').hashCode,
      const GiftNetworkImage('https://assets.test/a.png').hashCode,
    );
    expect(
      const GiftNetworkImage('https://assets.test/a.png'),
      isNot(const GiftNetworkImage('https://assets.test/b.png')),
    );
  });
}
