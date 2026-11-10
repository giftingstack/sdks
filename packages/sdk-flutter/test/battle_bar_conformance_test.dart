// Runs battle-bar.json (SPEC 18.7) against the pure Dart core. The format is
// "Battle bar" of conformance/README.md; the reference runner is the
// "conformance: battle-bar.json" block of
// packages/sdk-js/test/battle-bar-core.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

import 'support/fixtures.dart';

BattleBarLabels _labels(Object? raw) {
  if (raw == null) return const BattleBarLabels();
  final m = asMap(raw);
  return BattleBarLabels(
    vs: (m['vs'] as String?) ?? 'VS',
    finalText: (m['final'] as String?) ?? 'Final',
    wins: (m['wins'] as String?) ?? '{name} wins the round',
    draw: (m['draw'] as String?) ?? 'Draw: nobody wins this round',
    spoken: (m['spoken'] as String?) ?? '{a}, {b}',
    side: (m['side'] as String?) ?? '{name} {score}',
    thousand: (m['thousand'] as String?) ?? 'K',
    million: (m['million'] as String?) ?? 'M',
  );
}

RoomBattle _battle(Object? raw) {
  final m = asMap(raw);
  return RoomBattle(
    round: m['round']! as String,
    started: m['started']! as int,
    ends: m['ends']! as int,
    scores: <RoomScoreEntry>[
      for (final s in asList(m['scores']))
        RoomScoreEntry(
          id: asMap(s)['id']! as String,
          units: asMap(s)['units']! as int,
          gifts: asMap(s)['gifts']! as int,
        ),
    ],
  );
}

GiftThemeTokens _theme(String name) => switch (name) {
      'dark' => darkThemeTokens,
      'light' => lightThemeTokens,
      _ => defaultThemeTokens,
    };

void main() {
  final f = readFixture('conformance/battle-bar.json');

  test('the fixture has cases (nothing is silently skipped)', () {
    expect(asList(f['score']), hasLength(greaterThan(4)));
    expect(asList(f['clock']), hasLength(greaterThan(4)));
    expect(asList(f['model']), hasLength(greaterThan(10)));
    expect(asList(f['gains']), hasLength(greaterThan(3)));
    expect(asList(f['colors']), hasLength(greaterThan(5)));
  });

  group('score', () {
    for (final raw in asList(f['score'])) {
      final c = asMap(raw);
      test('${c['units']} ${c['labels'] ?? {}}', () {
        expect(formatBattleScore(c['units']! as int, _labels(c['labels'])),
            c['expect']);
      });
    }
  });

  group('clock', () {
    for (final raw in asList(f['clock'])) {
      final c = asMap(raw);
      test('${c['remainingMs']}', () {
        expect(formatBattleClock(c['remainingMs']! as int), c['expect']);
      });
    }
  });

  group('model', () {
    for (final raw in asList(f['model'])) {
      final c = asMap(raw);
      test(c['name']! as String, () {
        final names =
            c['names'] == null ? const <String, Object?>{} : asMap(c['names']);
        final m = battleBarModel(
          battleView(_battle(c['battle']), c['serverNow'] as int?),
          nameOf: (id) => (names[id] as String?) ?? id,
          labels: _labels(c['labels']),
        );
        if (c['expect'] == null) {
          expect(m, isNull);
          return;
        }
        final want = asMap(c['expect']);
        expect(m, isNotNull);
        final got = <String, Object?>{
          'clock': m!.clock,
          'urgent': m.urgent,
          'final': m.isFinal,
          'winner': m.winner,
          'banner': m.banner,
          'spoken': m.spoken,
        };
        for (final e in want.entries) {
          if (e.key == 'sides' || e.key == 'pcts') continue;
          if (e.key == 'pct') {
            expect(m.pct, closeTo((e.value! as num).toDouble(), 1e-6),
                reason: 'pct');
          } else {
            expect(got[e.key], e.value, reason: e.key);
          }
        }
        final pcts = want['pcts'];
        if (pcts != null) {
          final list = asList(pcts);
          expect(m.pcts, hasLength(list.length));
          for (var i = 0; i < list.length; i++) {
            expect(m.pcts[i], closeTo((list[i]! as num).toDouble(), 1e-6),
                reason: 'pcts[$i]');
          }
          expect(m.pcts.reduce((a, b) => a + b), closeTo(100, 1e-6));
        }
        final sides = want['sides'];
        if (sides != null) {
          final list = asList(sides);
          expect(m.sides, hasLength(list.length));
          for (var i = 0; i < list.length; i++) {
            final s = m.sides[i];
            final side = <String, Object?>{
              'id': s.id,
              'name': s.name,
              'units': s.units,
              'score': s.score,
              'spoken': s.spoken,
              'leads': s.leads,
              'won': s.won,
              'lost': s.lost,
            };
            for (final e in asMap(list[i]).entries) {
              expect(side[e.key], e.value, reason: 'sides[$i].${e.key}');
            }
          }
        }
      });
    }
  });

  group('gains', () {
    for (final raw in asList(f['gains'])) {
      final c = asMap(raw);
      test('${c['before']} -> ${c['after']}', () {
        final before = c['before'] == null
            ? null
            : <int>[for (final v in asList(c['before'])) v! as int];
        final after = <int>[for (final v in asList(c['after'])) v! as int];
        expect(battleGains(before, after), asList(c['expect']));
      });
    }
  });

  group('palette', () {
    for (final raw in asList(f['palette'])) {
      final c = asMap(raw);
      test(c['name']! as String, () {
        final over = c['override'] == null
            ? null
            : <String>[for (final v in asList(c['override'])) v! as String];
        final got = battleSidePalette(
            _theme(c['theme']! as String), c['count']! as int, over);
        final want = asList(c['expect']);
        expect(got, hasLength(want.length));
        for (var i = 0; i < want.length; i++) {
          expect(got[i].color, asMap(want[i])['color'], reason: 'color $i');
          expect(got[i].text, asMap(want[i])['text'], reason: 'text $i');
        }
      });
    }
  });

  group('colors', () {
    for (final raw in asList(f['colors'])) {
      final c = asMap(raw);
      test(c['name']! as String, () {
        final over = c['override'] == null
            ? null
            : <String>[for (final v in asList(c['override'])) v! as String];
        final got = battleSideColors(_theme(c['theme']! as String), over);
        final want = asList(c['expect']);
        expect(got, hasLength(2));
        for (var i = 0; i < 2; i++) {
          expect(got[i].color, asMap(want[i])['color']);
          expect(got[i].text, asMap(want[i])['text']);
        }
      });
    }
  });
}
