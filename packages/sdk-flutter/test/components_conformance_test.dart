// Runs wall.json, away.json and leaderboard.json (SPEC sections 14-16) against
// the pure Dart core. The format and matching rules are the "Component
// fixtures" part of conformance/README.md; the reference runner is
// packages/sdk-js/test/components-conformance.test.ts.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

import 'support/client_runner.dart';
import 'support/fixtures.dart';
import 'support/scripted_client.dart';

/// A virtual clock with timers. [advance] fires every timer due up to the new
/// time, in due order (ties: the order they were set), with the clock set to
/// each timer's due time.
class FakeClock {
  int now = 0;
  int _seq = 0;
  final List<({int id, int due, void Function() fn})> _timers =
      <({int id, int due, void Function() fn})>[];

  Object? setTimeout(void Function() fn, int ms) {
    final id = ++_seq;
    _timers.add((id: id, due: now + (ms < 0 ? 0 : ms), fn: fn));
    return id;
  }

  void clearTimeout(Object? id) => _timers.removeWhere((t) => t.id == id);

  ({int id, int due, void Function() fn})? _next(int limit) {
    ({int id, int due, void Function() fn})? best;
    for (final t in _timers) {
      if (t.due <= limit &&
          (best == null ||
              t.due < best.due ||
              (t.due == best.due && t.id < best.id))) {
        best = t;
      }
    }
    return best;
  }

  /// Fire the timers due now.
  void runDue() {
    for (var t = _next(now); t != null; t = _next(now)) {
      clearTimeout(t.id);
      t.fn();
    }
  }

  void advance(int ms) {
    final target = now + ms;
    for (var t = _next(target); t != null; t = _next(target)) {
      now = t.due;
      clearTimeout(t.id);
      t.fn();
    }
    now = target;
  }
}

/// Lets pending asynchronous work run, then fires timers that became due,
/// until nothing changes.
Future<void> settle(FakeClock clock) async {
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      await Future<void>.delayed(Duration.zero);
    }
    clock.runDue();
  }
}

GiftingException toError(Map<String, Object?> e) => GiftingException(
      e['status']! as int,
      e['type']! as String,
      e['message']! as String,
      e['requestId'] as String?,
    );

void main() {
  test('every component fixture has cases (nothing is silently skipped)', () {
    int n(String file, String key) =>
        asList(readFixture('conformance/$file')[key]).length;
    expect(n('wall.json', 'chips'), greaterThan(8));
    expect(n('wall.json', 'formatCount'), greaterThan(15));
    expect(n('wall.json', 'loader'), greaterThan(5));
    expect(n('wall.json', 'client'), greaterThan(2));
    expect(n('away.json', 'plan'), greaterThan(10));
    expect(n('away.json', 'senderLabel'), greaterThan(5));
    expect(n('away.json', 'controller'), greaterThan(10));
    expect(n('away.json', 'client'), greaterThan(3));
    expect(n('leaderboard.json', 'rankLabel'), greaterThan(3));
    expect(n('leaderboard.json', 'pin'), greaterThan(6));
    expect(n('leaderboard.json', 'controller'), greaterThan(10));
    expect(n('leaderboard.json', 'client'), greaterThan(3));
  });
  _wall();
  _away();
  _leaderboard();
}

// ================================================================ wall.json

void _wall() {
  final f = readFixture('conformance/wall.json');
  final gifts = asMap(f['gifts']);
  List<ReceivedGift> received(List<Object?> items) => <ReceivedGift>[
        for (final i in items.map(asMap))
          ReceivedGift.fromJson(<String, Object?>{
            'gift': gifts[i['gift']],
            'count': i['count'],
          }),
      ];
  List<Map<String, Object?>> compact(List<ReceivedGift> list) =>
      <Map<String, Object?>>[
        for (final r in list)
          <String, Object?>{'gift': r.gift.id, 'count': r.count},
      ];

  group('conformance: wall.json', () {
    group('chips', () {
      for (final c in asList(f['chips']).map(asMap)) {
        test(c['name']! as String, () {
          final o =
              c['options'] == null ? <String, Object?>{} : asMap(c['options']);
          final chips = wallChips(
            received(asList(c['items'])),
            max: (o['max'] as int?) ?? defaultWallMax,
            order:
                o['order'] == 'catalog' ? WallOrder.catalog : WallOrder.count,
          );
          final json = <Map<String, Object?>>[
            for (final chip in chips)
              switch (chip) {
                WallGiftChip() => <String, Object?>{
                    'gift': chip.gift.id,
                    'count': chip.count,
                  },
                WallOverflowChip() => <String, Object?>{
                    'overflow': chip.count,
                    'hidden': chip.hidden,
                  },
              },
          ];
          expect(jsonEquals(json, c['expect']), isTrue,
              reason: '${jsonEncode(json)} != ${jsonEncode(c['expect'])}');
        });
      }
    });

    group('formatCount', () {
      for (final c in asList(f['formatCount']).map(asMap)) {
        test('${c['n']} ${jsonEncode(c['labels'] ?? {})} -> ${c['expect']}',
            () {
          final l =
              c['labels'] == null ? <String, Object?>{} : asMap(c['labels']);
          final labels = CountLabels(
            thousand: (l['thousand'] as String?) ?? 'K',
            million: (l['million'] as String?) ?? 'M',
            decimal: (l['decimal'] as String?) ?? '.',
          );
          expect(formatCount(c['n']! as num, labels), c['expect']);
        });
      }
    });

    group('loader', () {
      for (final s in asList(f['loader']).map(asMap)) {
        test(s['name']! as String, () async {
          final clock = FakeClock();
          final batches = <({
            List<Map<String, Object?>> items,
            Completer<List<GiftWallResult>> done,
          })>[];
          final loader = GiftWallLoader(
            now: () => clock.now,
            setTimeout: clock.setTimeout,
            query: (items) {
              final done = Completer<List<GiftWallResult>>();
              batches.add((
                items: <Map<String, Object?>>[
                  for (final i in items) i.toJson()
                ],
                done: done,
              ));
              return done.future;
            },
          );
          final settled = <String, ({bool ok, Object? value})>{};
          final order = <String>[];
          final steps = asList(s['steps']).map(asMap).toList();
          for (var i = 0; i < steps.length; i++) {
            final step = steps[i];
            final at = 'step ${i + 1}';
            if (step['load'] != null) {
              final id = step['id']! as String;
              final args = asList(step['load']);
              order.add(id);
              unawaited(
                loader
                    .load(args[0]! as String,
                        args.length > 1 ? args[1] as String? : null)
                    .then(
                      (v) => settled[id] = (ok: true, value: compact(v)),
                      onError: (Object e) => settled[id] =
                          (ok: false, value: (e as GiftingException).type),
                    ),
              );
            } else if (step['advance'] != null) {
              clock.advance(step['advance']! as int);
            } else if (step['invalidate'] != null) {
              final args = asList(step['invalidate']);
              loader.invalidate(
                args[0]! as String,
                args.length > 1 ? args[1] as String? : null,
              );
            } else if (step['respond'] != null) {
              final r = asMap(step['respond']);
              final b = batches[(r['batch']! as int) - 1];
              final walls = asList(r['walls']);
              b.done.complete(<GiftWallResult>[
                for (var k = 0; k < b.items.length; k++)
                  GiftWallResult(
                    receiver: b.items[k]['receiver']! as String,
                    reference: b.items[k]['reference'] as String?,
                    gifts: received(asList(walls[k])),
                  ),
              ]);
            } else if (step['fail'] != null) {
              final r = asMap(step['fail']);
              batches[(r['batch']! as int) - 1]
                  .done
                  .completeError(toError(asMap(r['error'])));
            } else if (step['expect'] != null) {
              final x = asMap(step['expect']);
              if (x.containsKey('batches')) {
                expect(
                  jsonEquals(
                      batches.map((b) => b.items).toList(), x['batches']),
                  isTrue,
                  reason:
                      '$at batches: ${jsonEncode(batches.map((b) => b.items).toList())}',
                );
              }
              if (x.containsKey('waiting')) {
                expect(
                  order.where((id) => !settled.containsKey(id)).toList(),
                  x['waiting'],
                  reason: '$at waiting',
                );
              }
              asMap(x['resolved'] ?? <String, Object?>{}).forEach((id, v) {
                expect(settled[id]?.ok, isTrue, reason: '$at resolved $id');
                expect(jsonEquals(settled[id]?.value, v), isTrue,
                    reason: '$at resolved $id: ${settled[id]?.value}');
              });
              asMap(x['rejected'] ?? <String, Object?>{}).forEach((id, v) {
                expect(settled[id]?.ok, isFalse, reason: '$at rejected $id');
                expect(settled[id]?.value, v, reason: '$at rejected $id');
              });
            } else {
              fail('$at: unknown step $step');
            }
            await settle(clock);
          }
        });
      }
    });

    group('client', () {
      for (final s in asList(f['client']).map(asMap)) {
        test(s['name']! as String, () => runClientScenario(s));
      }
    });
  });
}

// ================================================================ away.json

void _away() {
  final f = readFixture('conformance/away.json');
  final gifts = asMap(f['gifts']);
  // Fixture groups are written with `"gift": "<id>"`: build the wire group.
  Map<String, Object?> wireGroup(Map<String, Object?> g) =>
      <String, Object?>{...g, 'gift': gifts[g['gift']]};
  List<AwayGroup> groups(List<Object?> list) => <AwayGroup>[
        for (final g in list.map(asMap)) AwayGroup.fromJson(wireGroup(g)),
      ];
  AwaySummary summary(String key) {
    final s = asMap(asMap(f['summaries'])[key]);
    return AwaySummary.fromJson(<String, Object?>{
      ...s,
      'groups': <Object?>[
        for (final g in asList(s['groups']).map(asMap)) wireGroup(g)
      ],
    });
  }

  group('conformance: away.json', () {
    group('plan', () {
      for (final c in asList(f['plan']).map(asMap)) {
        test(c['name']! as String, () {
          final names =
              c['names'] == null ? <String, Object?>{} : asMap(c['names']);
          final o =
              c['options'] == null ? <String, Object?>{} : asMap(c['options']);
          final l =
              o['labels'] == null ? <String, Object?>{} : asMap(o['labels']);
          final plan = planAwayReplay(
            groups(asList(c['groups'])),
            maxEffects: (o['maxEffects'] as int?) ?? defaultAwayMaxEffects,
            budgetMs: (o['budgetMs'] as int?) ?? defaultAwayBudgetMs,
            thresholds: o['thresholds'] == null
                ? const TierThresholds()
                : TierThresholds(
                    mediumFrom: asMap(o['thresholds'])['mediumFrom'] as int?,
                    largeFrom: asMap(o['thresholds'])['largeFrom'] as int?,
                  ),
            quality:
                o['quality'] == 'low' ? EffectQuality.low : EffectQuality.high,
            reducedMotion: (o['reducedMotion'] as bool?) ?? false,
            resolveName: (u) => (names[u] as String?) ?? u,
            labels: AwaySenderLabels(
                someone: (l['someone'] as String?) ?? 'Someone'),
          );
          final want = asMap(c['expect']);
          expect(plan.endMs, want['endMs'], reason: 'endMs');
          final items = asList(want['items']).map(asMap).toList();
          expect(plan.items.length, items.length, reason: 'items');
          for (var i = 0; i < plan.items.length; i++) {
            final item = plan.items[i];
            final actual = <String, Object?>{
              'gift': item.event.gift.id,
              'name': item.event.gift.name,
              'price': item.event.gift.price,
              'image': item.event.gift.image,
              'icon': item.event.gift.icon,
              'atMs': item.atMs,
              'durationMs': item.durationMs,
              'tier': item.tier.name,
              'quantity': item.event.quantity,
              'sender': item.event.sender,
            };
            items[i].forEach((k, v) {
              expect(jsonEquals(actual[k], v), isTrue,
                  reason: 'item ${i + 1}.$k: ${actual[k]} != $v');
            });
          }
        });
      }
    });

    group('senderLabel', () {
      for (final c in asList(f['senderLabel']).map(asMap)) {
        test(
            '${jsonEncode(c['names'])} x${c['senderCount']} ${jsonEncode(c['labels'] ?? {})} -> ${c['expect']}',
            () {
          final l =
              c['labels'] == null ? <String, Object?>{} : asMap(c['labels']);
          const d = AwaySenderLabels();
          expect(
            awaySenderLabel(
              asList(c['names']).cast<String>(),
              c['senderCount']! as int,
              AwaySenderLabels(
                someone: (l['someone'] as String?) ?? d.someone,
                pair: (l['pair'] as String?) ?? d.pair,
                oneOther: (l['oneOther'] as String?) ?? d.oneOther,
                others: (l['others'] as String?) ?? d.others,
              ),
            ),
            c['expect'],
          );
        });
      }
    });

    group('controller', () {
      for (final s in asList(f['controller']).map(asMap)) {
        test(s['name']! as String, () async {
          final clock = FakeClock();
          final api = ScriptedClient();
          final played = <Map<String, Object?>>[];
          final errors = <String>[];
          var shown = 0;
          var done = 0;
          final o =
              s['options'] == null ? <String, Object?>{} : asMap(s['options']);
          final player = _StubAwayPlayer((e) {
            played.add(<String, Object?>{
              'atMs': clock.now,
              'gift': e.gift.id,
              'quantity': e.quantity,
              'sender': e.sender,
            });
          });
          final controller = AwayController(
            AwayControllerOptions(
              client: api,
              effects: o['effects'] == false ? null : () => player,
              reducedMotion: o['reducedMotion'] == true ? () => true : null,
              ackOn: switch (o['ackOn']) {
                'finished' => AwayAckOn.finished,
                'manual' => AwayAckOn.manual,
                _ => AwayAckOn.shown,
              },
              maxGroups: o['maxGroups'] as int?,
              maxEffects: (o['maxEffects'] as int?) ?? defaultAwayMaxEffects,
              budgetMs: (o['budgetMs'] as int?) ?? defaultAwayBudgetMs,
              onShow: (_) => shown++,
              onDone: () => done++,
              onError: (e) => errors.add(e.type),
              now: () => clock.now,
              setTimeout: clock.setTimeout,
              clearTimeout: clock.clearTimeout,
            ),
          );
          final steps = asList(s['steps']).map(asMap).toList();
          for (var i = 0; i < steps.length; i++) {
            final step = steps[i];
            final at = 'step ${i + 1}';
            if (step['check'] == true) {
              unawaited(controller.check());
            } else if (step['foreground'] == true) {
              unawaited(controller.foreground());
            } else if (step['start'] == true) {
              controller.start();
            } else if (step['dismiss'] == true) {
              controller.dismiss();
            } else if (step['ack'] == true) {
              unawaited(controller.ack());
            } else if (step['dispose'] == true) {
              controller.dispose();
            } else if (step['advance'] != null) {
              clock.advance(step['advance']! as int);
            } else if (step['resolve'] != null) {
              final r = asMap(step['resolve']);
              final m = r['method']! as String;
              api.take(m, at).completer.complete(
                    m == 'getAway' ? summary(r['value']! as String) : null,
                  );
            } else if (step['reject'] != null) {
              final r = asMap(step['reject']);
              api
                  .take(r['method']! as String, at)
                  .completer
                  .completeError(toError(asMap(r['error'])));
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

              check('status', st.status.name);
              check('summaryCursor', st.summary?.cursor);
              check('planEndMs', st.plan?.endMs);
              check('played', played);
              check('calls', api.calls);
              check('pending', api.pending.map((p) => p.method).toList());
              check('shown', shown);
              check('done', done);
              check('errors', errors);
            } else {
              fail('$at: unknown step $step');
            }
            await settle(clock);
          }
        });
      }
    });

    group('client', () {
      for (final s in asList(f['client']).map(asMap)) {
        test(s['name']! as String, () => runClientScenario(s));
      }
    });
  });
}

class _StubAwayPlayer implements AwayEffectPlayer {
  _StubAwayPlayer(this.onPlay);

  final void Function(GiftEffectEvent event) onPlay;
  int _n = 0;

  @override
  int play(GiftEffectEvent event) {
    onPlay(event);
    return ++_n;
  }
}

// ================================================================ leaderboard.json

void _leaderboard() {
  final f = readFixture('conformance/leaderboard.json');
  final boards = asMap(f['boards']);

  group('conformance: leaderboard.json', () {
    group('pollMs', () {
      final poll = asMap(f['pollMs']);
      test('minPollMs', () => expect(leaderboardMinPollMs, poll['minPollMs']));
      for (final c in asList(poll['cases']).map(asMap)) {
        test('${c['refreshIntervalMs']} -> ${c['expect']}', () {
          expect(
            leaderboardPollMs(c['refreshIntervalMs']! as int),
            c['expect'],
          );
        });
      }
    });

    group('rankLabel', () {
      for (final c in asList(f['rankLabel']).map(asMap)) {
        test('${c['rank']} ${jsonEncode(c['labels'] ?? {})} -> ${c['expect']}',
            () {
          final l =
              c['labels'] == null ? <String, Object?>{} : asMap(c['labels']);
          expect(
            leaderboardRankLabel(
              c['rank'] as int?,
              overflow: (l['overflow'] as String?) ?? '1,000+',
            ),
            c['expect'],
          );
        });
      }
    });

    group('pin', () {
      for (final c in asList(f['pin']).map(asMap)) {
        test(c['name']! as String, () {
          final board = Leaderboard.fromJson(<String, Object?>{
            'board': 'senders',
            'period': 'week',
            'metric': c['metric'],
            'label': '2026-W41',
            'starts_at': null,
            'ends_at': null,
            'as_of': '2026-10-11T07:30:00.000Z',
            'data': c['data'],
            'has_more': false,
            'me': c['me'],
          });
          final pinned = pinnedMe(board, c['limit']! as int);
          expect(pinned != null, c['expect']);
          if (c['expect'] == true) {
            expect(jsonEquals(pinned!.toJson(), c['me']), isTrue);
          }
        });
      }
    });

    test('rankColors: the medal tokens and their contrast with noticeBigText',
        () {
      final rc = asMap(f['rankColors']);
      expect(jsonEquals(leaderboardRankColors, rc['tokens']), isTrue);
      final themes = <String, GiftThemeTokens>{
        'defaultTheme': defaultThemeTokens,
        'darkTheme': darkThemeTokens,
        'lightTheme': lightThemeTokens,
      };
      for (final name in asList(rc['themes']).cast<String>()) {
        final text = themes[name]!.toMap()[rc['text']]!;
        asMap(rc['tokens']).forEach((token, color) {
          expect(
            contrastRatio(color! as String, text),
            greaterThanOrEqualTo((rc['min']! as num).toDouble()),
            reason: '$name.${rc['text']} on $token',
          );
        });
      }
    });

    group('controller', () {
      for (final s in asList(f['controller']).map(asMap)) {
        test(s['name']! as String, () async {
          final clock = FakeClock();
          final api = ScriptedClient();
          final errors = <String>[];
          final o =
              s['options'] == null ? <String, Object?>{} : asMap(s['options']);
          final controller = LeaderboardController(
            LeaderboardControllerOptions(
              client: api,
              board: o['board'] == null
                  ? LeaderboardBoard.senders
                  : LeaderboardBoard.values.byName(o['board']! as String),
              periods: o['periods'] == null
                  ? leaderboardPeriods
                  : <LeaderboardPeriod>[
                      for (final p in asList(o['periods']).cast<String>())
                        LeaderboardPeriod.values.byName(p),
                    ],
              initialPeriod: o['initialPeriod'] == null
                  ? LeaderboardPeriod.week
                  : LeaderboardPeriod.values
                      .byName(o['initialPeriod']! as String),
              metric: o['metric'] == null
                  ? null
                  : LeaderboardMetric.values.byName(o['metric']! as String),
              limit: (o['limit'] as int?) ?? defaultLeaderboardLimit,
              includeMe: (o['includeMe'] as bool?) ?? true,
              now: () => clock.now,
              onError: (e) => errors.add(e.type),
            ),
          );
          final steps = asList(s['steps']).map(asMap).toList();
          for (var i = 0; i < steps.length; i++) {
            final step = steps[i];
            final at = 'step ${i + 1}';
            if (step['start'] == true) {
              controller.start();
            } else if (step['setPeriod'] != null) {
              controller.setPeriod(
                LeaderboardPeriod.values.byName(step['setPeriod']! as String),
              );
            } else if (step['setMetric'] != null) {
              controller.setMetric(
                LeaderboardMetric.values.byName(step['setMetric']! as String),
              );
            } else if (step['refresh'] == true) {
              controller.refresh();
            } else if (step['dispose'] == true) {
              controller.dispose();
            } else if (step['advance'] != null) {
              clock.advance(step['advance']! as int);
            } else if (step['resolve'] != null) {
              final r = asMap(step['resolve']);
              api.take(r['method']! as String, at).completer.complete(
                    Leaderboard.fromJson(asMap(boards[r['value']])),
                  );
            } else if (step['reject'] != null) {
              final r = asMap(step['reject']);
              api
                  .take(r['method']! as String, at)
                  .completer
                  .completeError(toError(asMap(r['error'])));
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

              check('status', st.status.name);
              check('period', st.period.name);
              check('periods', st.periods.map((p) => p.name).toList());
              check('metric', st.metric.name);
              check('rows', st.data?.data.map((r) => r.user).toList());
              check('asOf', st.data?.asOf);
              check('refreshing', st.refreshing);
              check('error', st.error?.type);
              check('pinned', st.pinned?.user);
              check('calls', api.calls);
              check('pending', api.pending.length);
              check('errors', errors);
            } else {
              fail('$at: unknown step $step');
            }
            await settle(clock);
          }
        });
      }
    });

    group('client', () {
      for (final s in asList(f['client']).map(asMap)) {
        test(s['name']! as String, () => runClientScenario(s));
      }
    });
  });
}
