// L1: the shared numbers equal packages/sdk-spec/recipes.json, and the
// generated Dart file has not drifted from that JSON.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';

import '../tool/generate_spec_data.dart';
import 'support/fixtures.dart';

void main() {
  final spec = readFixture('recipes.json');

  test(
      'lib/src/core/spec_data.g.dart is what the generator makes from '
      'recipes.json (run: dart run tool/generate_spec_data.dart)', () {
    final json = File('$specDir/recipes.json').readAsStringSync();
    final file = File('lib/src/core/spec_data.g.dart');
    expect(file.existsSync(), isTrue, reason: 'generated file missing');
    expect(
      file.readAsStringSync().replaceAll('\r\n', '\n'),
      generateSpecData(json),
      reason: 'The generated file drifted from recipes.json. '
          'Run: dart run tool/generate_spec_data.dart',
    );
  });

  test('specVersion', () {
    expect(kSpecVersion, spec['specVersion']);
  });

  test('thresholds, combo window, caps, queue size, default sender', () {
    final t = asMap(spec['thresholds']);
    const d = TierThresholds();
    expect(d.mediumFrom, t['mediumFrom']);
    expect(d.largeFrom, t['largeFrom']);
    expect(ComboTracker().windowMs, spec['comboWindowMs']);
    // With no option the scheduler's window is the embedded one.
    expect(EffectScheduler().comboWindowMs, spec['comboWindowMs']);
    final caps = asMap(spec['maxConcurrentEffects']);
    for (final tier in EffectTier.values) {
      expect(maxConcurrentEffects[tier], caps[tier.name], reason: tier.name);
    }
    expect(maxQueuedLarge, spec['maxQueuedLarge']);
    expect(defaultSenderName, spec['defaultSenderName']);
  });

  for (final quality in EffectQuality.values) {
    for (final tier in EffectTier.values) {
      test(
          'recipe ${tier.name}/${quality.name} equals recipes.json field by '
          'field', () {
        final want = asMap(
          asMap(asMap(spec['recipes'])[quality.name])[tier.name],
        );
        final got = recipeFor(tier, quality).toJson();
        expect(got.keys.toSet(), want.keys.toSet());
        for (final k in want.keys) {
          expect(got[k], want[k], reason: '${tier.name}/${quality.name}.$k');
        }
      });
    }
  }

  test('allRecipes returns all three tiers, as fresh copies', () {
    final all = allRecipes(EffectQuality.low);
    expect(all.keys, EffectTier.values);
    expect(all[EffectTier.large]!.sparks, 16);
    expect(identical(recipeFor(EffectTier.small), recipeFor(EffectTier.small)),
        isFalse);
  });
}
