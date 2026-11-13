// conformance/input-swap.json against the pure inputSwapStep and
// keyboardPlaceHeight (SPEC 20.2). Format: conformance/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

import 'support/fixtures.dart';

InputSwapEvent _event(Object? name) => switch (name) {
      'button' => InputSwapEvent.button,
      'inputFocus' => InputSwapEvent.inputFocus,
      _ => throw StateError('unknown event $name'),
    };

Map<String, String> _wire(InputSwapStep s) =>
    <String, String>{'tray': s.tray.name, 'input': s.input.name};

double? _num(Object? v) => v == null ? null : (v as num).toDouble();

void main() {
  final f = readFixture('conformance/input-swap.json');

  test('input-swap.json has cases (nothing is silently skipped)', () {
    expect(asList(f['step']).length, 4);
    expect(asList(f['place']).length, greaterThan(10));
    expect(asList(f['sequence']), isNotEmpty);
  });

  test('constants', () {
    final c = asMap(f['constants']);
    expect(kKeyboardPlaceFallback, c['fallback']);
    expect(kKeyboardMinHeight, c['minKeyboard']);
    expect(kKeyboardPlaceMaxFraction, c['maxFraction']);
  });

  group('inputSwapStep', () {
    var i = 0;
    for (final c in asList(f['step']).map(asMap)) {
      i++;
      test('#$i $c', () {
        final got = inputSwapStep(c['open']! as bool, _event(c['event']));
        expect(jsonEquals(_wire(got), c['expect']), isTrue,
            reason: 'got ${_wire(got)}');
      });
    }
  });

  group('keyboardPlaceHeight', () {
    for (final c in asList(f['place']).map(asMap)) {
      test(c['note'] as String, () {
        expect(
          keyboardPlaceHeight(
            keyboardHeight: _num(c['keyboardHeight']),
            containerHeight: _num(c['containerHeight']),
          ),
          c['expect'],
        );
      });
    }
  });

  group('sequence', () {
    for (final s in asList(f['sequence']).map(asMap)) {
      test(s['name'] as String, () {
        var open = s['open']! as bool;
        var n = 0;
        for (final step in asList(s['steps']).map(asMap)) {
          n++;
          final got = inputSwapStep(open, _event(step['event']));
          expect(jsonEquals(_wire(got), step['expect']), isTrue,
              reason: 'step $n: got ${_wire(got)}');
          if (got.tray == InputSwapTray.open) open = true;
          if (got.tray == InputSwapTray.close) open = false;
          expect(open, step['open'], reason: 'step $n open');
        }
      });
    }
  });
}
