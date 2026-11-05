// Runs the six rooms-*.json fixtures (SPEC sections 17-18) against the pure
// Dart core. The format and matching rules are "Rooms fixtures" of
// conformance/README.md; the reference runner is
// packages/sdk-js/test/rooms-conformance.test.ts.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

import 'support/fake_clock.dart';
import 'support/fixtures.dart';

/// A JSON frame object is sent as its JSON text; `text` is sent as is.
String _frameText(Map<String, Object?> c) =>
    c['text'] != null ? c['text']! as String : jsonEncode(c['frame']);

EffectTier _tier(Object? name) => switch (name) {
      'medium' => EffectTier.medium,
      'large' => EffectTier.large,
      _ => EffectTier.small,
    };

TierThresholds _thresholds(Object? t) {
  if (t == null) return const TierThresholds();
  final m = asMap(t);
  return TierThresholds(
    mediumFrom: m['mediumFrom'] as int?,
    largeFrom: m['largeFrom'] as int?,
  );
}

void main() {
  test('every rooms fixture has cases (nothing is silently skipped)', () {
    expect(asList(readFixture('conformance/rooms-protocol.json')['parse']),
        hasLength(greaterThan(20)));
    expect(asList(readFixture('conformance/rooms-reconnect.json')['cases']),
        hasLength(greaterThan(10)));
    expect(asList(readFixture('conformance/rooms-filter.json')['scenarios']),
        hasLength(greaterThan(8)));
    expect(asList(readFixture('conformance/rooms-mapping.json')['cases']),
        hasLength(greaterThan(4)));
    expect(asList(readFixture('conformance/rooms-session.json')['scenarios']),
        hasLength(greaterThan(20)));
    final battle = readFixture('conformance/rooms-battle.json');
    expect(asList(battle['parse']), hasLength(greaterThan(6)));
    expect(asList(battle['view']), hasLength(greaterThan(4)));
  });
  _protocol();
  _reconnect();
  _filter();
  _mapping();
  _session();
  _battle();
}

// ================================================================ rooms-protocol.json

void _protocol() {
  final f = readFixture('conformance/rooms-protocol.json');
  group('conformance: rooms-protocol.json', () {
    group('parse', () {
      for (final c in asList(f['parse']).map(asMap)) {
        test(c['name']! as String, () {
          final got = parseRoomFrame(_frameText(c))?.toJson();
          expect(jsonEquals(got, c['expect']), isTrue,
              reason: '${jsonEncode(got)} != ${jsonEncode(c['expect'])}');
        });
      }
    });
    test('hello', () {
      for (final c in asList(f['hello']).map(asMap)) {
        final got = jsonDecode(roomHelloFrame(c['last'] as int?));
        expect(jsonEquals(got, c['expect']), isTrue, reason: '$got');
      }
      expect(roomHelloFrame(null), '{"t":"hello","v":1,"last":null}');
    });
    test('url', () {
      for (final c in asList(f['url']).map(asMap)) {
        final base = c['baseUrl'] as String?;
        expect(
          base == null
              ? roomUrl(c['room']! as String)
              : roomUrl(c['room']! as String, base),
          c['expect'],
        );
      }
    });
    test('tokenUser', () {
      for (final c in asList(f['tokenUser']).map(asMap)) {
        expect(roomTokenUser(c['token']! as String), c['expect'],
            reason: '${c['token']}');
      }
    });
  });
}

// ================================================================ rooms-reconnect.json

void _reconnect() {
  final f = readFixture('conformance/rooms-reconnect.json');
  group('conformance: rooms-reconnect.json', () {
    for (final c in asList(f['cases']).map(asMap)) {
      test(c['name']! as String, () {
        var calls = 0;
        double random() {
          calls++;
          expect(c['random'], isNotNull,
              reason: 'random() called but the case gives none');
          return (c['random']! as num).toDouble();
        }

        final d = roomRetryDecision(
          code: c['code']! as int,
          reason: c['reason']! as String,
          attempt: c['attempt']! as int,
          limited: c['limited']! as int,
          random: random,
        );
        final got = switch (d) {
          RoomNoRetry() => <String, Object?>{
              'retry': false,
              if (d.resumable) 'resumable': true,
              if (d.exhausted) 'exhausted': true,
            },
          RoomRetry() => <String, Object?>{
              'retry': true,
              'delayMs': d.delayMs,
              'refreshToken': d.refreshToken,
              'limited': d.limited,
            },
        };
        expect(jsonEquals(got, c['expect']), isTrue,
            reason: '${jsonEncode(got)} != ${jsonEncode(c['expect'])}');
        expect(calls, lessThanOrEqualTo(1));
      });
    }
  });
}

// ================================================================ rooms-filter.json

void _filter() {
  final f = readFixture('conformance/rooms-filter.json');
  final events = asMap(f['events']);
  RoomGiftMessage ev(String name) {
    final m = parseRoomFrame(jsonEncode(events[name]));
    expect(m, isA<RoomGiftMessage>(), reason: name);
    return m! as RoomGiftMessage;
  }

  group('conformance: rooms-filter.json', () {
    for (final s in asList(f['scenarios']).map(asMap)) {
      test(s['name']! as String, () {
        final o =
            s['options'] == null ? <String, Object?>{} : asMap(s['options']);
        final filter = RoomEventFilter(
          RoomEventFilterOptions(
            user: o['user'] as String?,
            skipOwn: (o['skipOwn'] as bool?) ?? true,
            maxReplayAgeMs:
                (o['maxReplayAgeMs'] as int?) ?? defaultMaxReplayAgeMs,
            minTier: _tier(o['minTier']),
            thresholds: _thresholds(o['thresholds']),
          ),
        );
        var fills = 0;
        var serverOffset = 0;
        final steps = asList(s['steps']).map(asMap).toList();
        for (var i = 0; i < steps.length; i++) {
          final step = steps[i];
          final at = 'step ${i + 1}';
          final stepAt = step['at']! as int;
          final RoomFilterResult r;
          if (step['welcome'] != null) {
            final w = asMap(step['welcome']);
            serverOffset = (w['now']! as int) - stepAt;
            r = filter.welcome(
              RoomWelcomeMessage(
                viewers: w['viewers']! as int,
                gap: w['gap']! as bool,
                replay: <RoomGiftMessage>[
                  for (final n in asList(w['replay'])) ev(n! as String),
                ],
                ttl: w['ttl']! as num,
                now: w['now']! as int,
              ),
              stepAt,
            );
          } else if (step['live'] != null) {
            r = filter.live(
              <RoomGiftMessage>[
                for (final n in asList(step['live'])) ev(n! as String),
              ],
              stepAt,
            );
          } else if (step['batch'] != null) {
            // A wire `batch` frame: parsed, then its gifts go through `live`.
            final frame = jsonEncode(<String, Object?>{
              't': 'batch',
              'events': <Object?>[
                for (final n in asList(step['batch'])) events[n],
              ],
            });
            final m = parseRoomFrame(frame);
            expect(m, isA<RoomBatchMessage>(), reason: '$at batch parsed');
            r = filter.live((m! as RoomBatchMessage).events, stepAt);
          } else if (step['fill'] != null) {
            final list = <RoomGiftMessage>[];
            for (var k = 0; k < (step['fill']! as int); k++) {
              fills++;
              list.add(
                RoomGiftMessage(
                  id: 1000 + fills,
                  at: stepAt + serverOffset,
                  tx: 'gtx_fill_$fills',
                  gift: const RoomGiftInfo(id: 'rose', name: 'Rose', price: 10),
                  quantity: 1,
                  sender: const RoomSender(id: 'filler'),
                  receiverId: 'host',
                ),
              );
            }
            r = filter.live(list, stepAt);
          } else {
            fail('$at: unknown step');
          }
          final x = step['expect'] == null
              ? <String, Object?>{}
              : asMap(step['expect']);
          if (x['passed'] != null) {
            expect(r.events.map((e) => e.tx).toList(), x['passed'],
                reason: '$at passed');
          }
          if (x.containsKey('last')) {
            expect(filter.last, x['last'], reason: '$at last');
          }
          if (x.containsKey('gap')) expect(r.gap, x['gap'], reason: '$at gap');
        }
      });
    }
  });
}

// ================================================================ rooms-mapping.json

void _mapping() {
  final f = readFixture('conformance/rooms-mapping.json');
  final catalog = <Gift>[
    for (final g in asList(f['catalog']).map(asMap)) Gift.fromJson(g),
  ];
  group('conformance: rooms-mapping.json', () {
    for (final c in asList(f['cases']).map(asMap)) {
      test(c['name']! as String, () {
        final msg = parseRoomFrame(jsonEncode(c['event']));
        expect(msg, isA<RoomGiftMessage>());
        final names = c['names'] == null
            ? null
            : asMap(c['names']).cast<String, String>();
        final out = roomGiftToEffect(
          msg! as RoomGiftMessage,
          catalog: c['catalog'] == true ? catalog : null,
          resolveName: names == null ? null : (u) => names[u],
          replayed: (c['replayed'] as bool?) ?? false,
        );
        final got = out.toJson();
        expect(jsonEquals(got, c['expect']), isTrue,
            reason: '${jsonEncode(got)} != ${jsonEncode(c['expect'])}');
      });
    }
  });
}

// ================================================================ rooms-session.json

class _FakeSocket {
  _FakeSocket(this.url, this.protocols, this.handlers);

  final String url;
  final List<String> protocols;
  final RoomSocketHandlers handlers;
  final List<Object?> sent = <Object?>[];
  Map<String, Object?>? closed;
}

class _Pending {
  _Pending(this.forceRefresh);

  final bool forceRefresh;
  final Completer<String> completer = Completer<String>();
}

class _Wire implements RoomSocket {
  _Wire(this.sock);

  final _FakeSocket sock;

  @override
  void send(String data) {
    Object? v = data;
    try {
      v = jsonDecode(data);
    } on FormatException {
      // plain text ("ping")
    }
    sock.sent.add(v);
  }

  @override
  void close(int code, String reason) =>
      sock.closed = <String, Object?>{'code': code, 'reason': reason};
}

Object? _stateField(RoomState st, String key) => switch (key) {
      'status' => st.status.name,
      'attempt' => st.attempt,
      'retryInMs' => st.retryInMs,
      'code' => st.code,
      'reason' => st.reason,
      'viewers' => st.viewers,
      _ => throw StateError('unknown state key $key'),
    };

Future<void> _runSession(Map<String, Object?> s) async {
  final clock = FakeRoomClock();
  final randoms = s['random'] == null
      ? null
      : asList(s['random']).map((e) => (e! as num).toDouble()).toList();
  var r = 0;
  double random() {
    if (randoms == null) return 0.5;
    expect(r, lessThan(randoms.length),
        reason: 'random() call ${r + 1} beyond the list');
    return randoms[r++];
  }

  final tokens = <bool>[];
  final pendingTokens = <_Pending>[];
  final sockets = <_FakeSocket>[];
  final events = <RoomGiftEvent>[];
  final viewers = <int>[];
  var gaps = 0;
  final o = asMap(s['options']);

  final room = RoomClient(
    RoomClientOptions(
      room: o['room']! as String,
      user: o['user'] as String?,
      skipOwn: (o['skipOwn'] as bool?) ?? true,
      heartbeatMs: (o['heartbeatMs'] as int?) ?? roomHeartbeatMs,
      refreshJitterMs: (o['refreshJitterMs'] as int?) ?? 0,
      getToken: ({required bool forceRefresh}) {
        tokens.add(forceRefresh);
        final p = _Pending(forceRefresh);
        pendingTokens.add(p);
        return p.completer.future;
      },
      socket: (url, protocols, handlers) {
        final sock = _FakeSocket(url, List<String>.of(protocols), handlers);
        sockets.add(sock);
        return _Wire(sock);
      },
      onEvent: events.add,
      onViewers: viewers.add,
      onGap: () => gaps++,
      now: () => clock.now,
      setTimeout: clock.setTimeout,
      clearTimeout: clock.clearTimeout,
      random: random,
    ),
  );
  _FakeSocket newest(String at) {
    expect(sockets, isNotEmpty, reason: '$at: no socket');
    return sockets.last;
  }

  final steps = asList(s['steps']).map(asMap).toList();
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final at = '${s['name']}: step ${i + 1}';
    if (step['start'] == true) {
      room.start();
    } else if (step['leave'] == true) {
      room.leave();
    } else if (step['pause'] == true) {
      room.pause();
    } else if (step['resume'] == true) {
      room.resume();
    } else if (step['reconnectNow'] == true) {
      room.reconnectNow();
    } else if (step['advance'] != null) {
      clock.advance(step['advance']! as int);
    } else if (step['token'] != null) {
      expect(pendingTokens, isNotEmpty, reason: '$at: no pending getToken');
      pendingTokens.removeAt(0).completer.complete(step['token']! as String);
    } else if (step['tokenFail'] == true) {
      expect(pendingTokens, isNotEmpty, reason: '$at: no pending getToken');
      pendingTokens
          .removeAt(0)
          .completer
          .completeError(StateError('token server down'));
    } else if (step['open'] == true) {
      newest(at).handlers.onOpen();
    } else if (step.containsKey('receive')) {
      final v = step['receive'];
      newest(at).handlers.onMessage(v is String ? v : jsonEncode(v));
    } else if (step['close'] != null) {
      final c = asMap(step['close']);
      newest(at).handlers.onClose(c['code']! as int, c['reason']! as String);
    } else if (step['expect'] == null) {
      fail('$at: unknown step ${jsonEncode(step)}');
    }
    await clock.settle();

    if (step['expect'] == null) continue;
    final x = asMap(step['expect']);
    if (x['state'] != null) {
      for (final e in asMap(x['state']).entries) {
        expect(_stateField(room.state, e.key), e.value,
            reason: '$at state.${e.key}');
      }
    }
    if (x['tokens'] != null) expect(tokens, x['tokens'], reason: '$at tokens');
    if (x['sockets'] != null) {
      final want = asList(x['sockets']).map(asMap).toList();
      expect(sockets.length, want.length, reason: '$at socket count');
      for (var k = 0; k < want.length; k++) {
        final got = <String, Object?>{
          'url': sockets[k].url,
          'protocols': sockets[k].protocols,
          'sent': sockets[k].sent,
          'closed': sockets[k].closed,
        };
        for (final e in want[k].entries) {
          expect(jsonEquals(got[e.key], e.value), isTrue,
              reason: '$at sockets[$k].${e.key}: ${jsonEncode(got[e.key])} '
                  '!= ${jsonEncode(e.value)}');
        }
      }
    }
    if (x['events'] != null) {
      final want = asList(x['events']).map(asMap).toList();
      final got = <Map<String, Object?>>[
        for (var k = 0; k < events.length; k++)
          <String, Object?>{
            'tx': events[k].tx,
            'sender': events[k].sender,
            'replayed': events[k].replayed,
            // `quantity` is compared only where the fixture lists it.
            if (k < want.length && want[k].containsKey('quantity'))
              'quantity': events[k].quantity,
          },
      ];
      expect(jsonEquals(got, want), isTrue,
          reason: '$at events: ${jsonEncode(got)} != ${jsonEncode(want)}');
    }
    if (x['viewers'] != null) {
      expect(viewers, x['viewers'], reason: '$at viewers');
    }
    if (x['gaps'] != null) expect(gaps, x['gaps'], reason: '$at gaps');
  }
}

void _session() {
  final f = readFixture('conformance/rooms-session.json');
  group('conformance: rooms-session.json', () {
    for (final s in asList(f['scenarios']).map(asMap)) {
      test(s['name']! as String, () => _runSession(s));
    }
  });
}

// ================================================================ rooms-battle.json

void _battle() {
  final f = readFixture('conformance/rooms-battle.json');
  group('conformance: rooms-battle.json', () {
    group('parse', () {
      for (final c in asList(f['parse']).map(asMap)) {
        test(c['name']! as String, () {
          final got = parseRoomFrame(_frameText(c))?.toJson();
          expect(jsonEquals(got, c['expect']), isTrue,
              reason: '${jsonEncode(got)} != ${jsonEncode(c['expect'])}');
        });
      }
    });
    group('view', () {
      for (final c in asList(f['view']).map(asMap)) {
        test(c['name']! as String, () {
          final battle = parseRoomFrame(jsonEncode(<String, Object?>{
            't': 'scores',
            'battle': c['battle'],
          }));
          expect(battle, isA<RoomScoresMessage>());
          final got = battleView(
            (battle! as RoomScoresMessage).battle!,
            c['serverNow'] as int?,
          ).toJson();
          expect(jsonEquals(got, c['expect']), isTrue,
              reason: '${jsonEncode(got)} != ${jsonEncode(c['expect'])}');
        });
      }
    });
  });
}
