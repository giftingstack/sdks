// Runs pictures.json (SPEC 7.6, audit R-08) against the pure Dart core:
// isPictureUrl and PictureFailures. The format is the pictures.json part of
// conformance/README.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

import 'support/fixtures.dart';

void main() {
  final f = readFixture('conformance/pictures.json');

  test('constants', () {
    expect(pictureMaxBytes, f['maxBytes']);
    expect(pictureFailureMemoryMs, f['failureMemoryMs']);
  });

  group('conformance: pictures.json urls', () {
    for (final c in asList(f['urls']).map(asMap)) {
      test('isPictureUrl(${c['url']}) = ${c['allowed']}', () {
        expect(isPictureUrl(c['url']! as String), c['allowed']);
      });
    }
  });

  group('conformance: pictures.json data URL size', () {
    for (final c in asList(asMap(f['dataUrlSize'])['cases']).map(asMap)) {
      test('${c['totalChars']} characters: allowed ${c['allowed']}', () {
        const prefix = 'data:image/png;base64,';
        final url = prefix + 'A' * ((c['totalChars']! as int) - prefix.length);
        expect(isPictureUrl(url), c['allowed']);
      });
    }
  });

  group('conformance: pictures.json failures', () {
    for (final s in asList(f['failures']).map(asMap)) {
      test(s['name']! as String, () {
        final memory = PictureFailures(() => 0);
        final steps = asList(s['steps']).map(asMap).toList();
        for (var i = 0; i < steps.length; i++) {
          final step = steps[i];
          final at = '${s['name']} step ${i + 1}';
          final atMs = step['atMs']! as int;
          if (step['fail'] != null) {
            memory.mark(step['fail']! as String, atMs);
          } else if (step['failMany'] != null) {
            final m = asMap(step['failMany']);
            for (var n = 0; n < (m['count']! as int); n++) {
              memory.mark('${m['prefix']}$n', atMs);
            }
          } else if (step['failed'] != null) {
            for (final e in asMap(step['failed']).entries) {
              expect(memory.has(e.key, atMs), e.value, reason: '$at ${e.key}');
            }
          } else {
            fail('$at: unknown step $step');
          }
        }
      });
    }
  });
}
