// The effect picture grows in a wide layer (the web layer's pictureScale) and
// the theme reaches the notice (comboText) and the effects.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack/src/ui/effect_item.dart';
import 'package:giftingstack/src/ui/effect_timeline.dart' show pictureScale;

import 'support/ui_harness.dart';

void main() {
  group('pictureScale (the web layer\'s numbers)', () {
    test('is 1 on a phone layer, grows in a wide layer and stops at 2', () {
      expect(pictureScale(390, 700, 2.8), 1);
      expect(pictureScale(877, 493, 1.5), inExclusiveRange(1.2, 1.4));
      expect(pictureScale(3000, 2000, 1.5), 2);
    });

    test('never lets the picture pass 90 percent of the short side', () {
      expect(pictureScale(600, 300, 2.8), closeTo(0.9643, 0.001));
      expect(pictureScale(600, 300, 2.8, 5), closeTo(0.9643, 0.001));
    });

    test('takes a manual multiplier instead of the automatic one', () {
      expect(pictureScale(390, 700, 0.9, 1.5), 1.5);
      expect(pictureScale(1200, 800, 0.9, 1), 1);
    });
  });

  double pictureScaleOnScreen(WidgetTester tester) {
    final transforms = find.descendant(
      of: find.byType(EffectItem),
      matching: find.byType(Transform),
    );
    // The picture's transform is the one with a pure scale matrix.
    for (final t in tester.widgetList<Transform>(transforms)) {
      final m = t.transform;
      if (m.entry(0, 0) == m.entry(1, 1) && m.entry(0, 0) != 1) {
        return m.entry(0, 0);
      }
    }
    fail('no picture transform found');
  }

  Future<void> holdMedium(WidgetTester tester, Size size) async {
    final images = ControlledImages(autoLoad: true);
    await images.init(tester);
    tester.view.physicalSize = size;
    final fx = GiftEffectController();
    await tester.pumpWidget(layerApp(controller: fx, images: images));
    fx.play(giftEvent('g', 350, image: 'https://assets.test/g/512.webp'));
    await tester.pump();
    await tester.pump();
    // flyIn 800 ms, then the hold: the picture is at its peak scale.
    for (var t = 0; t < 1000; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a phone layer draws the recipe\'s peak scale (medium: 1.5)',
      (tester) async {
    await holdMedium(tester, const Size(390, 700));
    expect(pictureScaleOnScreen(tester), closeTo(1.5, 0.001));
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('a wide layer draws it bigger (1200 x 800: 1.85 times)',
      (tester) async {
    await holdMedium(tester, const Size(1200, 800));
    final k = pictureScale(1200, 800, 1.5);
    expect(k, closeTo(1.85, 0.02));
    expect(pictureScaleOnScreen(tester), closeTo(1.5 * k, 0.001));
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('the layer passes pictureScale on to the effect', (tester) async {
    final images = ControlledImages(autoLoad: true);
    await images.init(tester);
    final fx = GiftEffectController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GiftEffectLayer(
          controller: fx,
          imageProvider: images.call,
          remoteRecipes: false,
          pictureScale: 1.25,
        ),
      ),
    );
    fx.play(giftEvent('g', 350));
    await tester.pump();
    expect(
        tester.widget<EffectItem>(find.byType(EffectItem)).pictureScale, 1.25);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
