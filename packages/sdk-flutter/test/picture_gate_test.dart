// conformance/effects.json#pictureGate, rendered: an effect starts (and with it
// the notice) when its picture loads or fails, or after pictureWaitMs,
// whichever comes first; never before startsAtMs, and no later than
// startsAtMs + toleranceMs.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack/src/ui/notice.dart';

import 'support/fixtures.dart';
import 'support/ui_harness.dart';

void main() {
  final gate = asMap(readFixture('conformance/effects.json')['pictureGate']);
  final tolerance = gate['toleranceMs']! as int;
  final cases = asList(gate['cases']).map(asMap).toList();
  if (cases.isEmpty) throw StateError('pictureGate fixture must not be empty');

  for (var i = 0; i < cases.length; i++) {
    final c = cases[i];
    final startsAt = c['startsAtMs']! as int;
    testWidgets('${c['name']}: starts at $startsAt ms', (tester) async {
      final images = ControlledImages();
      await images.init(tester);
      final fx = GiftEffectController();
      await tester.pumpWidget(
        layerApp(
          controller: fx,
          images: images,
          reducedMotion: false,
          pictureWaitMs: c['pictureWaitMs']! as int,
        ),
      );
      final url = 'https://assets.test/gate/$i.webp';
      bool started() =>
          find.byType(GiftNotice).evaluate().isNotEmpty;

      fx.play(
        giftEvent(
          'gate',
          50000,
          image: c['image']! as bool ? url : null,
        ),
      );
      // The effect enters on this frame: that is time 0 of the gate.
      await tester.pump();
      final loadAt = c['loadAtMs'] as int?;
      final errorAt = c['errorAtMs'] as int?;
      if (loadAt != null) {
        unawaited(Future<void>.delayed(
            Duration(milliseconds: loadAt), () => images.load(url)));
      }
      if (errorAt != null) {
        unawaited(Future<void>.delayed(
            Duration(milliseconds: errorAt), () => images.fail(url)));
      }
      if (startsAt == 0) {
        // Right after play: the start is deferred out of the build, one more frame.
        await tester.pump();
        await tester.pump();
        expect(started(), isTrue, reason: 'started right after play');
      } else {
        await tester.pump(Duration(milliseconds: startsAt - 1));
        expect(started(), isFalse, reason: 'not started at ${startsAt - 1} ms');
        await tester.pump(Duration(milliseconds: 1 + tolerance));
        expect(started(), isTrue,
            reason: 'started by ${startsAt + tolerance} ms');
      }
      // Run the effect out so no timer or ticker is left behind.
      for (var t = 0; t < 8000; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
  }
}
