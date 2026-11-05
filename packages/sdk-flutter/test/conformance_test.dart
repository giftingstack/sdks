// Runs EVERY fixture in packages/sdk-spec/conformance against the pure Dart
// core. The format and matching rules are conformance/README.md; the reference
// runner is packages/sdk-js/test/conformance.test.ts.
//
// effects.json#pictureGate is rendered timing: it is in
// test/picture_gate_test.dart (widget test).
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

import 'support/client_runner.dart';
import 'support/fixtures.dart';
import 'support/scripted_client.dart';

/// Compares only the keys the fixture names.
void expectSubset(
  Map<String, Object?> actual,
  Map<String, Object?> expected,
  String at,
) {
  expected.forEach((k, v) {
    expect(
      jsonEquals(actual[k], v),
      isTrue,
      reason: '$at.$k: got ${actual[k]}, want $v',
    );
  });
}

TierThresholds? thresholdsOf(Object? json) {
  if (json == null) return null;
  final m = asMap(json);
  return TierThresholds(
    mediumFrom: (m['mediumFrom'] as int?) ?? const TierThresholds().mediumFrom,
    largeFrom: (m['largeFrom'] as int?) ?? const TierThresholds().largeFrom,
  );
}

EffectTier tierOf(Object? name) =>
    EffectTier.values.firstWhere((t) => t.name == name);

EffectQuality qualityOf(Object? name) =>
    EffectQuality.values.firstWhere((q) => q.name == name);

void main() {
  _guard();
  _tiers();
  _combo();
  _client();
  _effects();
  _tray();
  _sendButton();
}

// ------------------------------------------------------------------ tiers

void _tiers() {
  final f = readFixture('conformance/tiers.json');
  group('conformance: tiers.json', () {
    for (final c in asList(f['cases']).map(asMap)) {
      test('price ${c['price']} ${jsonEncode(c['thresholds'] ?? {})}', () {
        final t = thresholdsOf(c['thresholds']);
        final tier = t == null
            ? tierFor(c['price']! as num)
            : tierFor(c['price']! as num, t);
        expect(tier, tierOf(c['tier']));
      });
    }
    for (final c in asList(f['recipes']).map(asMap)) {
      test('recipe ${c['tier']}/${c['quality']}', () {
        final r = recipeFor(tierOf(c['tier']), qualityOf(c['quality']));
        expectSubset(r.toJson(), asMap(c['expect']), '${c['tier']}');
      });
    }
  });
}

// ------------------------------------------------------------------ combo

void _combo() {
  final f = readFixture('conformance/combo.json');
  group('conformance: combo.json', () {
    for (final s in asList(f['scenarios']).map(asMap)) {
      test(s['name']! as String, () {
        final windowMs = s['windowMs'] as int?;
        final t = windowMs == null ? ComboTracker() : ComboTracker(windowMs);
        final steps = asList(s['steps']);
        for (var i = 0; i < steps.length; i++) {
          final step = asMap(steps[i]);
          if (step['reset'] == true) {
            t.reset();
            continue;
          }
          final hit = asList(step['hit']);
          expect(
            t.hit(hit[0]! as String, hit[1]! as String, hit[2]! as int),
            step['count'],
            reason: '${s['name']} step ${i + 1}',
          );
        }
      });
    }
  });
}

// ------------------------------------------------------------------ client

void _client() {
  final f = readFixture('conformance/client.json');
  group('conformance: client.json', () {
    for (final s in asList(f['scenarios']).map(asMap)) {
      test(s['name']! as String, () => runClientScenario(s));
    }
  });
}

// ------------------------------------------------------------------ effects

void _effects() {
  final f = readFixture('conformance/effects.json');
  final gifts = asMap(f['gifts']);
  group('conformance: effects.json scheduler', () {
    for (final s in asList(f['scenarios']).map(asMap)) {
      test(s['name']! as String, () {
        final o =
            s['options'] == null ? <String, Object?>{} : asMap(s['options']);
        var clock = 0;
        final scheduler = EffectScheduler(
          comboWindowMs: (o['comboWindowMs'] as int?) ?? 2500,
          now: () => clock,
        )..setOptions(
            EffectSchedulerOptions(
              thresholds:
                  thresholdsOf(o['thresholds']) ?? const TierThresholds(),
              quality: o['quality'] == null
                  ? EffectQuality.high
                  : qualityOf(o['quality']),
              reducedMotion: (o['reducedMotion'] as bool?) ?? false,
            ),
          );
        var events = <String>[];
        final ended = <int>[];
        int? noticeDurationMs;
        scheduler.listener = EffectSchedulerListener(
          enter: (e) => events.add('enter:${e.id}'),
          exit: (e) => events.add('exit:${e.id}'),
          end: (e) {
            events.add('end:${e.id}');
            ended.add(e.id);
          },
          notice: (d, ms) {
            events.add('notice:${d.id}');
            noticeDurationMs = ms;
          },
          noticeHide: () => events.add('noticeHide'),
          clear: () => events.add('clear'),
        );

        final steps = asList(s['steps']).map(asMap).toList();
        for (var i = 0; i < steps.length; i++) {
          final step = steps[i];
          final at = '${s['name']} step ${i + 1}';
          if (step['play'] != null) {
            clock = (step['atMs'] as int?) ?? clock;
            final p = asMap(step['play']);
            final g = asMap(gifts[p['gift']]);
            final id = scheduler.play(
              GiftEffectEvent(
                gift: GiftEffectGift(
                  id: g['id']! as String,
                  name: g['name']! as String,
                  price: g['price']! as int,
                  image: g['image'] as String?,
                  icon: g['icon'] as String?,
                ),
                sender: p['sender'] as String?,
                quantity: p['quantity'] as int?,
              ),
            );
            if (step['returns'] != null) {
              expect(id, step['returns'], reason: '$at play() id');
            }
          } else if (step['started'] != null) {
            scheduler.started(step['started']! as int);
          } else if (step['finished'] != null) {
            scheduler.finished(step['finished']! as int);
          } else if (step['cancel'] != null) {
            scheduler.cancel(step['cancel']! as int);
          } else if (step['clear'] == true) {
            scheduler.clear();
          } else if (step['noticeExpired'] == true) {
            scheduler.noticeExpired();
          } else if (step['expect'] != null) {
            final x = asMap(step['expect']);
            final notice = scheduler.notice();
            void check(String key, Object? actual) {
              if (!x.containsKey(key)) return;
              expect(
                jsonEquals(actual, x[key]),
                isTrue,
                reason:
                    '$at $key: got ${jsonEncode(actual)}, want ${jsonEncode(x[key])}',
              );
            }

            check('events', events);
            check('active', scheduler.active().map((e) => e.id).toList());
            check(
              'activeTiers',
              scheduler.active().map((e) => e.recipe.tier.name).toList(),
            );
            check('queued', scheduler.queued().map((e) => e.id).toList());
            check('ended', ended);
            check('notice', notice.data?.toJson());
            check('noticeVisible', notice.visible);
            check('noticeOwner', notice.owner);
            check('noticeDurationMs', noticeDurationMs);
            events = <String>[];
          } else {
            fail('$at: unknown step $step');
          }
        }
      });
    }
  });
}

// ------------------------------------------------------------------ tray

class _StubPlayer implements EffectPlayer {
  final List<Map<String, Object?>> played = <Map<String, Object?>>[];
  final List<int> cancelled = <int>[];

  @override
  int play(GiftEffectEvent event) {
    final id = played.length + 1;
    played.add(<String, Object?>{'id': id, 'event': event.toJson()});
    return id;
  }

  @override
  void cancel(int id) => cancelled.add(id);
}

Future<void> _flush() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void _tray() {
  final f = readFixture('conformance/tray.json');
  final gifts = asMap(f['gifts']);
  final transactions = asMap(f['transactions']);
  group('conformance: tray.json controller', () {
    for (final s in asList(f['scenarios']).map(asMap)) {
      test(s['name']! as String, () async {
        final api = ScriptedClient();
        final player = _StubPlayer();
        final prefetched = <String>[];
        final sent = <String>[];
        final errors = <String>[];
        final o =
            s['options'] == null ? <String, Object?>{} : asMap(s['options']);
        final controller = GiftTrayController(
          GiftTrayOptions(
            client: api,
            receiver: o['receiver']! as String,
            reference: o['reference'] as String?,
            playOn: o['playOn'] == 'success' ? PlayOn.success : PlayOn.tap,
            effects: o['effects'] == false ? null : () => player,
            prefetch: prefetched.add,
            onSent: (tx) => sent.add(tx.id),
            onError: (e) => errors.add(e.type),
          ),
        );

        Object? valueOf(String method, Object? v) {
          if (method == 'getGifts') {
            return asList(v)
                .map((k) => Gift.fromJson(asMap(gifts[k])))
                .toList();
          }
          if (method == 'sendGift' && v is String) {
            return GiftTransaction.fromJson(asMap(transactions[v]));
          }
          if (method == 'getMe') return Me.fromJson(asMap(v));
          return v;
        }

        Object errorOf(Map<String, Object?> e) => e['plain'] != null
            ? Exception(e['plain'])
            : GiftingException(
                e['status']! as int,
                e['type']! as String,
                e['message']! as String,
                e['requestId'] as String?,
              );

        final steps = asList(s['steps']).map(asMap).toList();
        for (var i = 0; i < steps.length; i++) {
          final step = steps[i];
          final at = '${s['name']} step ${i + 1}';
          if (step['mount'] == true || step['refresh'] == true) {
            unawaited(controller.refresh());
          } else if (step['dispose'] == true) {
            controller.dispose();
          } else if (step['send'] != null) {
            unawaited(
                controller.send(Gift.fromJson(asMap(gifts[step['send']]))));
          } else if (step['resolve'] != null) {
            final r = asMap(step['resolve']);
            final m = r['method']! as String;
            api.take(m, at).completer.complete(valueOf(m, r['value']));
          } else if (step['reject'] != null) {
            final r = asMap(step['reject']);
            api
                .take(r['method']! as String, at)
                .completer
                .completeError(errorOf(asMap(r['error'])));
          } else if (step['expect'] != null) {
            final x = asMap(step['expect']);
            final st = controller.state;
            void check(String key, Object? actual) {
              if (!x.containsKey(key)) return;
              expect(
                jsonEquals(actual, x[key]),
                isTrue,
                reason:
                    '$at $key: got ${jsonEncode(actual)}, want ${jsonEncode(x[key])}',
              );
            }

            check('balance', st.balance);
            check('user', st.user);
            check('loading', st.loading);
            check('testMode', st.testMode);
            check('gifts', st.gifts.map((g) => g.id).toList());
            if (x.containsKey('error')) {
              if (x['error'] == null) {
                expect(st.error, isNull, reason: '$at error');
              } else {
                expect(st.error, isNotNull, reason: '$at error');
                expectSubset(
                    errorFields(st.error!), asMap(x['error']), '$at error');
              }
            }
            check('played', player.played);
            check('playedCount', player.played.length);
            check('cancelled', player.cancelled);
            check('sent', sent);
            check('errors', errors);
            check('prefetched', prefetched);
            check('pending', api.pending.map((p) => p.method).toList());
            check('lastCall', api.calls.isEmpty ? null : api.calls.last);
            if (x.containsKey('callCount')) {
              final counts = <String, Object?>{};
              for (final c in api.calls) {
                final m = c['method']! as String;
                counts[m] = ((counts[m] as int?) ?? 0) + 1;
              }
              check('callCount', counts);
            }
          } else {
            fail('$at: unknown step $step');
          }
          await _flush();
        }
      });
    }
  });
}

void _sendButton() {
  final f = readFixture('conformance/tray.json');
  final cases = asList(asMap(f['sendButton'])['cases']).map(asMap).toList();
  group('conformance: tray.json sendButton', () {
    for (final c in cases) {
      test(c['name']! as String, () {
        final input = asMap(c['input']);
        final state = sendButtonState(
          gifts: <Gift>[
            for (final g in asList(input['gifts']).map(asMap))
              Gift(
                id: g['id']! as String,
                name: g['id']! as String,
                price: g['price']! as int,
                sortOrder: 0,
              ),
          ],
          selectedId: input['selectedId'] as String?,
          balance: input['balance']! as int,
          disabled: (input['disabled'] as bool?) ?? false,
          canTopUp: (input['canTopUp'] as bool?) ?? false,
        );
        final label = switch (state.label) {
          SendButtonLabel.send => 'send',
          SendButtonLabel.getCoins => 'getCoins',
          SendButtonLabel.notEnough => 'notEnough',
        };
        final action = switch (state.action) {
          SendButtonAction.send => 'send',
          SendButtonAction.topUp => 'topUp',
          SendButtonAction.none => 'none',
        };
        expect(
          jsonEquals(
            <String, Object?>{
              'selectedId': state.selectedId,
              'broke': state.broke,
              'label': label,
              'pressable': state.pressable,
              'action': action,
            },
            c['expect'],
          ),
          isTrue,
          reason: '${c['name']}: want ${c['expect']}',
        );
      });
    }
  });
}

/// A suite that finds no cases must fail, not pass.
void _guard() {
  test('every fixture file has cases (nothing is silently skipped)', () {
    int n(String file, String key) =>
        asList(readFixture('conformance/$file')[key]).length;
    expect(n('tiers.json', 'cases'), greaterThan(15));
    expect(n('tiers.json', 'recipes'), greaterThan(3));
    expect(n('combo.json', 'scenarios'), greaterThan(3));
    expect(n('client.json', 'scenarios'), greaterThan(20));
    expect(n('effects.json', 'scenarios'), greaterThan(15));
    expect(n('tray.json', 'scenarios'), greaterThan(10));
    expect(
      asList(asMap(readFixture('conformance/tray.json')['sendButton'])['cases'])
          .length,
      greaterThan(5),
    );
  });
}
