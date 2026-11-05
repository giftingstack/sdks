// Unit tests of the pure Dart pieces that the fixtures do not pin down.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack/src/ui/effect_timeline.dart';

void main() {
  group('encodeUriComponent equals JavaScript encodeURIComponent', () {
    const cases = <String, String>{
      'ayla': 'ayla',
      'a b': 'a%20b',
      'a+b': 'a%2Bb',
      'a/b': 'a%2Fb',
      'a:b': 'a%3Ab',
      "-_.!~*'()": "-_.!~*'()",
      'a@b#c?d=e&f': 'a%40b%23c%3Fd%3De%26f',
      '%': '%25',
      'çğ': '%C3%A7%C4%9F',
      'Ünal Çelik': '%C3%9Cnal%20%C3%87elik',
      '日本': '%E6%97%A5%E6%9C%AC',
      '😀': '%F0%9F%98%80',
      '': '',
    };
    cases.forEach((input, want) {
      test('"$input"', () => expect(encodeUriComponent(input), want));
    });
    test('agrees with Uri.encodeComponent on random text', () {
      final r = Random(7);
      for (var i = 0; i < 300; i++) {
        final s = String.fromCharCodes(
          List<int>.generate(1 + r.nextInt(8), (_) => 32 + r.nextInt(0x2FF)),
        );
        expect(encodeUriComponent(s), Uri.encodeComponent(s), reason: s);
      }
    });
  });

  group('newIdempotencyKey', () {
    test('is a UUID v4', () {
      final re = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      final keys = <String>{for (var i = 0; i < 50; i++) newIdempotencyKey()};
      expect(keys.length, 50);
      expect(keys.every(re.hasMatch), isTrue);
    });
  });

  group('GiftingException', () {
    test('retryable and insufficientBalance', () {
      expect(const GiftingException(0, 'network_error', 'x').retryable, isTrue);
      expect(
          const GiftingException(429, 'rate_limited', 'x').retryable, isTrue);
      expect(const GiftingException(503, 'x', 'x').retryable, isTrue);
      expect(const GiftingException(422, 'x', 'x').retryable, isFalse);
      expect(
        const GiftingException(422, 'insufficient_balance', 'x')
            .insufficientBalance,
        isTrue,
      );
    });

    test('asGiftingError keeps an SDK error and wraps anything else', () {
      const e = GiftingException(422, 'x', 'm');
      expect(identical(asGiftingError(e), e), isTrue);
      final w = asGiftingError(Exception('boom'));
      expect((w.status, w.type, w.message), (0, 'unknown_error', 'boom'));
      expect(asGiftingError(StateError('bad')).message, 'bad');
    });
  });

  group('models ignore unknown fields and accept nulls', () {
    test('Gift', () {
      final g = Gift.fromJson(<String, Object?>{
        'id': 'a',
        'name': 'A',
        'description': null,
        'price': 5,
        'icon_url': null,
        'animation_url': null,
        'sort_order': 1,
        'surprise': true,
      });
      expect(g.iconUrl, isNull);
      expect(g.toJson()['icon_url'], isNull);
    });
  });

  group('effect timeline (SPEC 7.3)', () {
    int total(EffectTier t, EffectQuality q) =>
        EffectTimeline(recipeFor(t, q)).totalMs;

    test('finishes at 1600 / 2100 / 3850 ms (3050 ms for low-quality large)',
        () {
      expect(total(EffectTier.small, EffectQuality.high), 1600);
      expect(total(EffectTier.medium, EffectQuality.high), 2100);
      expect(total(EffectTier.large, EffectQuality.high), 3850);
      expect(total(EffectTier.large, EffectQuality.low), 3050);
    });

    test('fly: back-out overshoot, ends at 1', () {
      final tl = EffectTimeline(recipeFor(EffectTier.medium));
      expect(tl.at(0).fly, closeTo(0, 1e-12));
      expect(tl.at(800).fly, closeTo(1, 1e-9));
      final peak =
          List<double>.generate(81, (i) => tl.at(i * 10.0).fly).reduce(max);
      expect(peak, greaterThan(1.0), reason: 'overshoot');
    });

    test('large: dim in over 300 ms, out during leave; rays run to the end',
        () {
      final tl = EffectTimeline(recipeFor(EffectTier.large));
      expect(tl.at(0).dim, 0);
      expect(tl.at(150).dim, closeTo(0.5, 1e-9));
      expect(tl.at(300).dim, 1);
      expect(tl.at(900 + 1600).dim, 1, reason: 'hold');
      expect(tl.at(900 + 1600 + 275).dim, closeTo(0.5, 1e-9));
      expect(tl.at(900 + 1600 + 550).dim, 0);
      expect(tl.at(0).spin, 0);
      expect(tl.at(900 + 1600 + 550).spin, closeTo(1, 1e-9));
    });

    test('small and medium never dim', () {
      expect(EffectTimeline(recipeFor(EffectTier.medium)).at(1000).dim, 0);
    });

    test('burst starts when the fly ends; leave after the hold', () {
      final tl = EffectTimeline(recipeFor(EffectTier.medium));
      expect(tl.at(799).burst, 0);
      expect(tl.at(800 + 900).burst, 1);
      expect(tl.at(800 + 700).leave, 0);
      expect(tl.at(800 + 700 + 600).leave, 1);
    });

    test('interpolate extends (reference default) or clamps', () {
      expect(interpolate(2, <double>[0, 1], <double>[0, 10]), 20);
      expect(interpolate(2, <double>[0, 1], <double>[0, 10], clamp: true), 10);
      expect(
        interpolate(0.5, <double>[0, 0.1, 0.85, 1], <double>[0, 1, 1, 0]),
        1,
      );
    });
  });

  test('formatCoins', () {
    expect(formatCoins(0), '0');
    expect(formatCoins(999), '999');
    expect(formatCoins(1000), '1,000');
    expect(formatCoins(1234567), '1,234,567');
    expect(formatCoins(-4200), '-4,200');
  });
}
