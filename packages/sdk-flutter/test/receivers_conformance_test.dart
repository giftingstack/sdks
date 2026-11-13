// conformance/receivers.json against the pure resolveReceiver (SPEC 21.2).
// Format: conformance/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

import 'support/fixtures.dart';

void main() {
  final f = readFixture('conformance/receivers.json');

  test('receivers.json has cases (nothing is silently skipped)', () {
    expect(asList(f['resolve']).length, greaterThanOrEqualTo(9));
  });

  test('labels', () {
    expect(kSendToLabel, 'Send to');
    expect(kPressSideLabel, 'Send {name} a gift');
  });

  group('resolveReceiver', () {
    for (final c in asList(f['resolve']).map(asMap)) {
      test(c['note'] as String, () {
        expect(
          resolveReceiver(
            asList(c['ids']).cast<String>(),
            selected: c['selected'] as String?,
            last: c['last'] as String?,
            fallback: c['fallback'] as String?,
          ),
          c['expect'],
        );
      });
    }
  });
}
