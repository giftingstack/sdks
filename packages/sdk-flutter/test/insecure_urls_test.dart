// Plain-text base URLs (SPEC 3.1, audit R-07) and the send repeat after a lost
// connection (SPEC 3.4, audit R-18) where the fixtures do not look: a timeout.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<String> _token({required bool forceRefresh}) async => 'tok';

GiftingClient _client(String? baseUrl, {bool allowInsecure = false}) =>
    GiftingClient(
      getToken: _token,
      baseUrl: baseUrl ?? defaultBaseUrl,
      allowInsecure: allowInsecure,
    );

RoomClient _room(String? url, {bool allowInsecure = false}) => RoomClient(
      RoomClientOptions(
        room: 'live_1',
        getToken: _token,
        socket: (url, protocols, handlers) => throw StateError('no socket'),
        url: url,
        allowInsecure: allowInsecure,
      ),
    );

void main() {
  group('urlHost and isLoopbackHost', () {
    test('read the host without userinfo, port or brackets, lower case', () {
      expect(urlHost('http://LocalHost:8787/x'), 'localhost');
      expect(urlHost('ws://user:pw@10.0.2.2:8788'), '10.0.2.2');
      expect(urlHost('http://[::1]:8787'), '::1');
      expect(urlHost('api.giftingstack.com'), isNull);
    });

    test('the four loopback hosts and nothing else', () {
      for (final h in <String>['localhost', '127.0.0.1', '::1', '10.0.2.2']) {
        expect(isLoopbackHost(h), isTrue, reason: h);
      }
      for (final h in <String>[
        '127.0.0.2',
        '192.168.1.5',
        'localhost.evil.com',
        'example.com',
      ]) {
        expect(isLoopbackHost(h), isFalse, reason: h);
      }
    });
  });

  group('GiftingClient base URL', () {
    test('accepts https and http to loopback hosts', () {
      for (final u in <String?>[
        null,
        'https://api.example.com',
        'HTTPS://api.example.com/',
        'http://localhost:8787',
        'http://127.0.0.1:8787/proxy/',
        'http://[::1]:8787',
        'http://10.0.2.2:8787',
      ]) {
        expect(() => _client(u), returnsNormally, reason: '$u');
      }
    });

    test('refuses http to any other host, never printing the userinfo', () {
      for (final u in <String>[
        'http://api.example.com',
        'HTTP://api.example.com',
        'http://192.168.1.20:8787',
        'http://localhost.evil.com',
      ]) {
        expect(() => _client(u), throwsArgumentError, reason: u);
      }
      try {
        _client('http://me:secret@api.example.com');
        fail('expected an ArgumentError');
      } on ArgumentError catch (e) {
        expect(e.toString(), contains('allowInsecure'));
        expect(e.toString(), isNot(contains('secret')));
      }
    });

    test('allowInsecure: true lets a plain http URL through', () {
      expect(
        () => _client('http://staging.example.com', allowInsecure: true),
        returnsNormally,
      );
      expect(
        () => createGiftingClient(
          getToken: _token,
          baseUrl: 'http://staging.example.com',
          allowInsecure: true,
        ),
        returnsNormally,
      );
    });
  });

  group('RoomClient url', () {
    test('accepts the default, wss and ws to loopback hosts', () {
      for (final u in <String?>[
        null,
        'wss://rt.example.com',
        'ws://localhost:8788',
        'ws://127.0.0.1:8788/',
        'ws://[::1]:8788',
        'ws://10.0.2.2:8788',
      ]) {
        expect(() => _room(u), returnsNormally, reason: '$u');
      }
    });

    test('refuses ws to any other host unless allowInsecure', () {
      expect(() => _room('ws://rt.example.com'), throwsArgumentError);
      expect(() => _room('ws://192.168.1.20:8788'), throwsArgumentError);
      expect(
        () => _room('ws://rt.example.com', allowInsecure: true),
        returnsNormally,
      );
    });

    test('setOptions checks the new url too', () {
      final room = _room(null);
      expect(
        () => room.setOptions(
          RoomClientOptions(
            room: 'live_1',
            getToken: _token,
            socket: (url, protocols, handlers) => throw StateError('no'),
            url: 'ws://rt.example.com',
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('sendGift after a lost connection', () {
    const input = SendGiftInput(receiver: 'bob', giftId: 'rose');

    test('a timed-out send is not repeated', () async {
      var calls = 0;
      final c = GiftingClient(
        getToken: _token,
        httpClient: MockClient((req) {
          calls++;
          return Completer<http.Response>().future;
        }),
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        c.sendGift(input),
        throwsA(isA<GiftingException>()
            .having((e) => e.type, 'type', 'network_error')),
      );
      expect(calls, 1);
    });

    test('a refused connection is repeated once with the same key', () async {
      final keys = <String?>[];
      final c = GiftingClient(
        getToken: _token,
        httpClient: MockClient((req) async {
          keys.add(req.headers['Idempotency-Key']);
          if (keys.length == 1) throw http.ClientException('connection reset');
          return http.Response(
            '{"id":"gtx_1","sender":"a","receiver":"bob","gift":{"id":"rose",'
            '"name":"Rose","icon_url":null},"quantity":1,"unit_price":10,'
            '"total":10,"message":null,"reference":null,"status":"completed",'
            '"created_at":"2026-11-03T00:00:00.000Z","sender_balance_after":1}',
            201,
          );
        }),
      );
      final tx = await c.sendGift(input);
      expect(tx.id, 'gtx_1');
      expect(keys, hasLength(2));
      expect(keys[0], isNotNull);
      expect(keys[1], keys[0]);
    });
  });
}
