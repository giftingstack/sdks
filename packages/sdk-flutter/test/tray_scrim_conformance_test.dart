// conformance/tray-scrim.json against the pure scrimVisible, scrimFadeMs,
// scrimTapOutcome and TrayOpenState (SPEC 9.4). Format: conformance/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

import 'support/fixtures.dart';

void main() {
  final f = readFixture('conformance/tray-scrim.json');

  test('tray-scrim.json has cases (nothing is silently skipped)', () {
    expect(asList(f['visible']).length, 24);
    expect(asList(f['tap']).length, greaterThan(10));
    expect(asList(f['open']).length, greaterThan(3));
  });

  test('constants', () {
    final c = asMap(f['constants']);
    expect(kScrimFadeMs, c['fadeMs']);
    expect(kScrimOpacity, c['opacity']);
  });

  group('scrimVisible', () {
    var i = 0;
    for (final c in asList(f['visible']).map(asMap)) {
      i++;
      test('#$i $c', () {
        expect(
          scrimVisible(
            scrim: c['scrim']! as bool,
            open: c['open']! as bool,
            snap: SheetSnapName.fromWireName(c['snap'] as String)!,
            placed: c['placed']! as bool,
          ),
          c['expect'],
        );
      });
    }
  });

  group('scrimFadeMs', () {
    for (final c in asList(f['fade']).map(asMap)) {
      test(c['name'] as String, () {
        expect(scrimFadeMs(c['reducedMotion']! as bool), c['ms']);
      });
    }
  });

  group('scrimTapOutcome', () {
    var i = 0;
    for (final c in asList(f['tap']).map(asMap)) {
      i++;
      test('#$i $c', () {
        final tap = c['scrimTap'] as String?;
        final got = scrimTapOutcome(
          scrim: c['scrim']! as bool,
          scrimTap: tap == null ? ScrimTap.lower : ScrimTap.values.byName(tap),
          open: c['open']! as bool,
          snap: SheetSnapName.fromWireName(c['snap'] as String)!,
        );
        expect(got.name, c['expect']);
      });
    }
  });

  group('TrayOpenState', () {
    for (final s in asList(f['open']).map(asMap)) {
      test(s['name'] as String, () {
        final changes = <bool>[];
        final o = TrayOpenState(
          open: (s['open'] as bool?) ?? true,
          onChange: changes.add,
        );
        var n = 0;
        for (final step in asList(s['steps']).map(asMap)) {
          n++;
          final at = '${s['name']}, step $n';
          final call = step['call'] as String?;
          if (call != null) {
            final returned = switch (call) {
              'open' => o.open(),
              'close' => o.close(),
              'toggle' => o.toggle(),
              _ => throw StateError('$at: unknown call $call'),
            };
            expect(returned, step['returns'], reason: '$at returns');
          } else if (step['expect'] != null) {
            final want = asMap(step['expect']);
            expect(o.isOpen, want['open'], reason: '$at open');
            expect(
              jsonEquals(changes, want['changes']),
              isTrue,
              reason: '$at changes: got $changes, want ${want['changes']}',
            );
          } else {
            throw StateError('$at: unknown step');
          }
        }
      });
    }
  });
}
