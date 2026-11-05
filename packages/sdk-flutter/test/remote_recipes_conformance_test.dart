// conformance/remote-recipes.json (SPEC 13): parse, merge, URLs. The loader
// (network, cache, backoff) and the scheduler with a recipe set are covered in
// test/recipes_loader_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack_core.dart';

import 'support/fixtures.dart';

/// The embedded set as `recipes.json` writes it.
Map<String, Object?> embeddedJson() {
  final spec = readFixture('recipes.json');
  return <String, Object?>{
    'thresholds': spec['thresholds'],
    'comboWindowMs': spec['comboWindowMs'],
    'recipes': spec['recipes'],
  };
}

/// [base] with [patch] laid over it: objects merge recursively, any other
/// value replaces.
Object? patched(Object? base, Object? patch) {
  if (base is Map<dynamic, dynamic> && patch is Map<dynamic, dynamic>) {
    final out = <String, Object?>{...base.cast<String, Object?>()};
    patch.cast<String, Object?>().forEach((k, v) {
      out[k] = patched(out[k], v);
    });
    return out;
  }
  return patch;
}

void main() {
  final f = readFixture('conformance/remote-recipes.json');
  final embeddedDoc = readFixture('recipes.json');

  test('remote-recipes.json has cases (nothing is silently skipped)', () {
    expect(asList(f['parse']).length, greaterThan(25));
    expect(asList(f['merge']).length, greaterThan(3));
    expect(asList(f['urls']).length, greaterThan(5));
  });

  group('parse', () {
    for (final c in asList(f['parse']).map(asMap)) {
      test(c['name'] as String, () {
        final input = c['input'] == '@embedded' ? embeddedDoc : c['input'];
        final got = parseRemoteRecipes(input);
        if (c['expect'] == null) {
          expect(got, isNull);
          return;
        }
        expect(got, isNotNull, reason: 'the document must be accepted');
        final want =
            patched(embeddedJson(), c['expect'])! as Map<String, Object?>;
        want['specVersion'] = asMap(input)['specVersion'];
        final json = got!.toJson();
        expect(
          jsonEquals(json, want),
          isTrue,
          reason: 'got $json\nwant $want',
        );
        // No caps, queue size or sender name ever come from a document.
        expect(
          json.keys.toSet(),
          <String>{'specVersion', 'thresholds', 'comboWindowMs', 'recipes'},
        );
      });
    }
  });

  group('merge', () {
    final embedded = RecipeSet.embedded();
    for (final c in asList(f['merge']).map(asMap)) {
      test(c['name'] as String, () {
        final remote =
            c['remote'] == null ? null : parseRemoteRecipes(c['remote']);
        final app = asMap(c['app']);
        final got = mergeRecipeSet(
          embedded,
          remote,
          appThresholds: app['thresholds'] == null
              ? null
              : TierThresholds(
                  mediumFrom: asMap(app['thresholds'])['mediumFrom'] as int?,
                  largeFrom: asMap(app['thresholds'])['largeFrom'] as int?,
                ),
          appComboWindowMs: app['comboWindowMs'] as int?,
        );
        final want = asMap(c['expect']);
        final json = got.toJson();
        expect(
          jsonEquals(json['thresholds'], want['thresholds']),
          isTrue,
          reason: 'thresholds: ${json['thresholds']} vs ${want['thresholds']}',
        );
        expect(json['comboWindowMs'], want['comboWindowMs']);
        final wantRecipes = want['recipes'] == 'embedded'
            ? embedded.toJson()['recipes']
            : want['recipes'] == 'remote'
                ? remote!.toJson()['recipes']
                : want['recipes'];
        expect(jsonEquals(json['recipes'], wantRecipes), isTrue);
      });
    }
  });

  group('urls', () {
    for (final c in asList(f['urls']).map(asMap)) {
      test(c['name'] as String, () {
        expect(
          remoteRecipesUrl(c['url'] as String?, c['version'] as String?),
          c['expect'],
        );
      });
    }
  });

  group('limits', () {
    test('the limits table equals SPEC.md section 13.3', () {
      final spec = File('$specDir/SPEC.md').readAsStringSync();
      final from = spec.indexOf('| field           | min | max');
      expect(from, greaterThan(0), reason: 'the 13.3 table moved');
      final rows = spec
          .substring(from)
          .split('\n')
          .skip(2)
          .takeWhile((l) => l.startsWith('|'))
          .map((l) => l.split('|').map((c) => c.trim()).toList())
          .toList();
      final fromSpec = <String, String>{
        for (final r in rows)
          r[1].replaceAll('`', ''):
              '${r[2].replaceAll(',', '')}/${r[3].replaceAll(',', '')}/${r[4]}',
      };
      String fmt(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
      final fromCode = <String, String>{
        for (final e in remoteRecipeLimits.entries)
          e.key:
              '${fmt(e.value.min)}/${fmt(e.value.max)}/${e.value.integer ? 'yes' : 'no'}',
      };
      expect(fromCode, fromSpec);
    });

    test('every embedded number lies inside the limits', () {
      for (final q in EffectQuality.values) {
        for (final t in EffectTier.values) {
          final j = recipeFor(t, q).toJson();
          for (final e in remoteRecipeLimits.entries) {
            final v = j[e.key];
            if (v is! num) continue;
            // coins and sparks of the low tables may be 0, which is inside.
            expect(v, inInclusiveRange(e.value.min, e.value.max),
                reason: '${q.name}/${t.name}.${e.key}');
          }
        }
      }
      final d = const TierThresholds();
      expect(d.mediumFrom, inInclusiveRange(1, 1000000));
      expect(d.largeFrom, inInclusiveRange(2, 10000000));
    });
  });
}
