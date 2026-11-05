// conformance/theme.json: the contrast ratio and the contrast rule every
// themeFromAccent theme and both presets must meet (SPEC 9.2).
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack/src/ui/theme.dart' show giftColor;

import 'support/fixtures.dart';

void main() {
  final f = readFixture('conformance/theme.json');
  final rules = asList(f['rules']).map(asMap).toList();

  void meetsRules(GiftThemeTokens t, String what) {
    final m = t.toMap();
    for (final r in rules) {
      final ratio = contrastRatio(m[r['bg']]!, m[r['fg']]!);
      expect(
        ratio,
        greaterThanOrEqualTo((r['min']! as num).toDouble()),
        reason: '$what: ${r['fg']} on ${r['bg']} is $ratio',
      );
    }
  }

  test('theme.json has cases (nothing is silently skipped)', () {
    expect(asList(f['contrast']).length, greaterThan(5));
    expect(rules.length, 9);
    expect(asList(f['accents']).length, greaterThan(5));
    expect(asList(f['invalid']).length, greaterThan(2));
  });

  group('contrastRatio', () {
    for (final c in asList(f['contrast']).map(asMap)) {
      test('${c['a']} on ${c['b']} is ${c['ratio']}', () {
        final got = contrastRatio(c['a']! as String, c['b']! as String);
        expect(
          (got * 100 + 0.5).floor() / 100,
          (c['ratio']! as num).toDouble(),
        );
      });
    }
  });

  group('presets', () {
    final byName = <String, GiftThemeTokens>{
      'darkTheme': darkThemeTokens,
      'lightTheme': lightThemeTokens,
    };
    for (final name in asList(f['presets']).cast<String>()) {
      test(name, () => meetsRules(byName[name]!, name));
    }
    test('the UI presets carry the same colours as the tokens', () {
      expect(darkTheme.accent, giftColor(darkThemeTokens.accent));
      expect(lightTheme.surface, giftColor(lightThemeTokens.surface));
      expect(lightTheme.coinText, giftColor(lightThemeTokens.coinText));
      expect(
        darkTheme.noticeBackground,
        giftColor(darkThemeTokens.noticeBackground),
      );
    });
  });

  group('themeFromAccent', () {
    final modes = asList(f['modes']).cast<String>();
    for (final a in asList(f['accents']).map(asMap)) {
      for (final mode in modes) {
        test('${a['accent']} ($mode)', () {
          final t = themeTokensFromAccent(
            a['accent']! as String,
            GiftThemeMode.values.byName(mode),
          );
          expect(t.accent, a['normalized']);
          meetsRules(t, '${a['accent']} $mode');
          // The UI theme built from it keeps the accent as given.
          final ui = themeFromAccent(
            a['accent']! as String,
            GiftThemeMode.values.byName(mode),
          );
          expect(ui.accent, giftColor(t.accent));
        });
      }
    }
    for (final bad in asList(f['invalid']).cast<String>()) {
      test('"$bad" is refused', () {
        expect(() => themeTokensFromAccent(bad), throwsFormatException);
        expect(() => themeFromAccent(bad), throwsFormatException);
      });
    }

    test('300 pseudo-random accents meet the rules in both modes', () {
      var seed = 12345;
      int next() {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed;
      }

      for (var i = 0; i < 300; i++) {
        final hex = '#${(next() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
        for (final mode in GiftThemeMode.values) {
          meetsRules(themeTokensFromAccent(hex, mode), '$hex ${mode.name}');
        }
      }
    });
  });

  test('the default theme keeps the 1.0 look (white on #8b7bff is only 3.3:1)',
      () {
    expect(defaultThemeTokens.accent, '#8b7bff');
    expect(
      contrastRatio(defaultThemeTokens.accentText, defaultThemeTokens.accent),
      lessThan(4.5),
    );
  });
}
