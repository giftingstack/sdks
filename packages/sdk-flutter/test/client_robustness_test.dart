// Request timeout (SPEC 3.4), a malformed 2xx (SPEC 3.5, audit R-05) and app
// callbacks that throw inside a send (SPEC 8, audit R-14). The fixtures cover
// the not-JSON cases too (client.json); these are the places they do not look.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/scripted_client.dart';

GiftingClient _client(http.Client c, {Duration? timeout}) => GiftingClient(
      getToken: ({required bool forceRefresh}) async => 'tok',
      httpClient: c,
      timeout: timeout ?? defaultRequestTimeout,
    );

Future<GiftingException> _failure(Future<Object?> f) async {
  try {
    await f;
  } on GiftingException catch (e) {
    return e;
  }
  throw StateError('expected a GiftingException');
}

void main() {
  group('request timeout', () {
    test('the default is 20 seconds', () {
      expect(defaultRequestTimeout, const Duration(seconds: 20));
    });

    test('a hanging attempt ends with the network error, without a retry',
        () async {
      var calls = 0;
      final c = _client(
        MockClient((req) {
          calls++;
          return Completer<http.Response>().future;
        }),
        timeout: const Duration(milliseconds: 50),
      );
      final e = await _failure(c.getMe());
      expect(<Object>[e.status, e.type, e.retryable],
          <Object>[0, 'network_error', true]);
      expect(calls, 1);
    });

    test('Duration.zero turns it off', () async {
      final answer = Completer<http.Response>();
      final c = _client(
        MockClient((req) => answer.future),
        timeout: Duration.zero,
      );
      final f = c.getMe();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      answer.complete(http.Response(
        '{"user":"u","balance":3,"livemode":true}',
        200,
      ));
      expect((await f).balance, 3);
    });
  });

  group('a 2xx that cannot be read', () {
    test('not JSON: invalid_response, no body text, request id from header',
        () async {
      final c = _client(MockClient((req) async => http.Response(
            '<html>Captive portal secret-text</html>',
            200,
            headers: <String, String>{'X-Request-Id': 'req_9'},
          )));
      final e = await _failure(c.getMe());
      expect(<Object?>[
        e.status,
        e.type,
        e.message,
        e.requestId,
        e.retryable
      ], <Object?>[
        200,
        'invalid_response',
        'Invalid response (200).',
        'req_9',
        false
      ]);
      expect(e.toString(), isNot(contains('secret-text')));
    });

    test('JSON of the wrong shape is invalid_response too', () async {
      final c = _client(MockClient((req) async => http.Response('[1,2]', 200)));
      final e = await _failure(c.getMe());
      expect(e.type, 'invalid_response');
      expect(e.status, 200);
    });

    test('is not retried', () async {
      var calls = 0;
      final c = _client(MockClient((req) async {
        calls++;
        return http.Response('oops', 200);
      }));
      await _failure(c.getGifts());
      expect(calls, 1);
    });
  });

  group('app callbacks never undo a charged send', () {
    const rose = Gift(id: 'rose', name: 'Rose', price: 100, sortOrder: 1);
    GiftTransaction tx() => GiftTransaction.fromJson(<String, Object?>{
          'id': 'gtx_1',
          'sender': 'alice',
          'receiver': 'bob',
          'gift': <String, Object?>{'id': 'rose', 'name': 'Rose'},
          'quantity': 1,
          'unit_price': 100,
          'total': 100,
          'status': 'completed',
          'created_at': '2026-10-10T00:00:00.000Z',
          'sender_balance_after': 900,
        });

    Future<(GiftTrayController, ScriptedClient)> tray({
      void Function(GiftTransaction)? onSent,
      void Function(GiftingException)? onError,
    }) async {
      final api = ScriptedClient();
      final c = GiftTrayController(GiftTrayOptions(
        client: api,
        receiver: 'bob',
        onSent: onSent,
        onError: onError,
      ));
      final loading = c.refresh();
      api.take('getGifts', 'setup').completer.complete(<Gift>[rose]);
      api
          .take('getMe', 'setup')
          .completer
          .complete(const Me(user: 'alice', balance: 1000, livemode: true));
      await loading;
      return (c, api);
    }

    test('a throwing onSent keeps the balance charged and sets no error',
        () async {
      var onErrorCalls = 0;
      final (c, api) = await tray(
        onSent: (_) => throw StateError('app bug'),
        onError: (_) => onErrorCalls++,
      );
      final sending = c.send(rose);
      api.take('sendGift', 'send').completer.complete(tx());
      await sending;
      expect(c.state.balance, 900);
      expect(c.state.error, isNull);
      expect(onErrorCalls, 0);
    });

    test('a throwing onError is ignored and the refund still happens',
        () async {
      final (c, api) = await tray(onError: (_) => throw StateError('app bug'));
      final sending = c.send(rose);
      api
          .take('sendGift', 'send')
          .completer
          .completeError(const GiftingException(500, 'internal_error', 'boom'));
      await sending;
      expect(c.state.balance, 1000);
      expect(c.state.error?.type, 'internal_error');
    });
  });
}
