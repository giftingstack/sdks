// Widget tests of GiftEffectLayer on the fake clock. What they prove is listed
// in the README ("Verification"): the scheduler decisions drawn correctly, the
// timeline end times, the notice, reduced motion, pass-through and cleanup.
// What they cannot judge (smoothness, easing feel) needs a device.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack/src/ui/effect_item.dart';
import 'package:giftingstack/src/ui/notice.dart';

import 'support/ui_harness.dart';

Future<void> advance(WidgetTester tester, int ms, {int step = 50}) async {
  for (var t = 0; t < ms; t += step) {
    await tester.pump(Duration(milliseconds: step));
  }
}

GiftNotice notice(WidgetTester tester) =>
    tester.widget<GiftNotice>(find.byType(GiftNotice).last);

void main() {
  late ControlledImages images;
  late GiftEffectController fx;

  setUp(() {
    fx = GiftEffectController();
  });

  Future<void> start(
    WidgetTester tester, {
    bool disableAnimations = false,
    EffectQuality quality = EffectQuality.high,
    bool? reducedMotion,
    int Function()? now,
    Widget? under,
    void Function(GiftEffectEvent, EffectTier)? onEffectEnd,
    bool autoLoad = true,
  }) async {
    images = ControlledImages(autoLoad: autoLoad);
    await images.init(tester);
    await tester.pumpWidget(
      layerApp(
        controller: fx,
        images: images,
        disableAnimations: disableAnimations,
        quality: quality,
        reducedMotion: reducedMotion,
        now: now,
        under: under,
        onEffectEnd: onEffectEnd,
      ),
    );
  }

  group('effects appear and disappear', () {
    testWidgets('ids start at 1 and count up; unattached controller is a no-op',
        (tester) async {
      expect(GiftEffectController().play(giftEvent('rose', 10)), 0);
      await start(tester);
      expect(fx.isAttached, isTrue);
      expect(fx.play(giftEvent('rose', 10)), 1);
      expect(fx.play(giftEvent('rose', 10)), 2);
      fx.clear();
      expect(fx.play(giftEvent('rose', 10)), 3, reason: 'clear does not reset');
      await tester.pump();
      await advance(tester, 3500);
    });

    for (final c in <(String, int, int)>[
      ('small', 10, 1600),
      ('medium', 350, 2100),
      ('large', 40000, 3850),
    ]) {
      testWidgets('${c.$1}: on screen until ${c.$3} ms, then gone and ended',
          (tester) async {
        final ended = <EffectTier>[];
        await start(tester, onEffectEnd: (e, t) => ended.add(t));
        fx.play(
          giftEvent(
            'g',
            c.$2,
            sender: 'ayla',
            image: 'https://assets.test/g/512.webp',
            icon: 'https://assets.test/g/256.webp',
          ),
        );
        await tester.pump(); // enters, starts (picture already there)
        expect(find.byType(EffectItem), findsOneWidget);
        await tester.pump(); // notice shows with the effect
        expect(notice(tester).data.senderName, 'ayla');
        expect(notice(tester).visible, isTrue);

        // The timeline starts at the first frame after the start.
        await advance(tester, c.$3 - 100);
        expect(find.byType(EffectItem), findsOneWidget,
            reason: 'still playing');
        expect(ended, isEmpty);
        await advance(tester, 300);
        expect(find.byType(EffectItem), findsNothing);
        expect(ended.length, 1);

        // Let the notice time out and slide out: nothing is left running.
        await advance(tester, 3500);
        expect(find.byType(GiftNotice), findsNothing);
      });
    }

    testWidgets('low quality uses the low recipe', (tester) async {
      await start(tester, quality: EffectQuality.low);
      fx.play(giftEvent('g', 40000));
      await tester.pump();
      final r = tester.widget<EffectItem>(find.byType(EffectItem)).recipe;
      expect(r.sparks, 16);
      expect(r.coins, 0);
      expect(r.rays, isFalse);
      await advance(tester, 3300);
      await advance(tester, 3500);
    });

    testWidgets('high quality large: the full recipe', (tester) async {
      await start(tester);
      fx.play(giftEvent('g', 40000));
      await tester.pump();
      final r = tester.widget<EffectItem>(find.byType(EffectItem)).recipe;
      expect((r.sparks, r.coins, r.rays, r.dim), (50, 34, true, true));
      await advance(tester, 4000);
      await advance(tester, 3500);
    });
  });

  group('concurrency caps', () {
    testWidgets('small: 6 at once, the rest only a notice', (tester) async {
      await start(tester);
      for (var i = 0; i < 8; i++) {
        fx.play(giftEvent('g$i', 10, sender: 'ayla'));
      }
      await tester.pump();
      expect(find.byType(EffectItem), findsNWidgets(6));
      await advance(tester, 2000);
      await advance(tester, 3500);
    });

    testWidgets('medium: 2 at once', (tester) async {
      await start(tester);
      for (var i = 0; i < 5; i++) {
        fx.play(giftEvent('g$i', 350));
      }
      await tester.pump();
      expect(tiersOnScreen(tester), <EffectTier>[
        EffectTier.medium,
        EffectTier.medium,
      ]);
      await advance(tester, 2500);
      await advance(tester, 3500);
    });

    testWidgets('large: one at a time, the next enters when it ends',
        (tester) async {
      final ended = <String>[];
      await start(tester, onEffectEnd: (e, t) => ended.add(e.gift.id));
      fx
        ..play(giftEvent('a', 40000))
        ..play(giftEvent('b', 40000))
        ..play(giftEvent('c', 40000));
      await tester.pump();
      expect(find.byType(EffectItem), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await advance(tester, 4000);
      }
      expect(ended, <String>['a', 'b', 'c']);
      expect(find.byType(EffectItem), findsNothing);
      await advance(tester, 3500);
    });

    testWidgets('large queue holds 5; a new one drops the oldest waiting',
        (tester) async {
      final ended = <String>[];
      await start(tester, onEffectEnd: (e, t) => ended.add(e.gift.id));
      for (var i = 0; i < 8; i++) {
        fx.play(giftEvent('g$i', 40000));
      }
      await advance(tester, 8 * 4000);
      // g0 runs; g1..g5 wait; g6 drops g1; g7 drops g2.
      expect(ended, <String>['g0', 'g3', 'g4', 'g5', 'g6', 'g7']);
      await advance(tester, 3500);
    });

    testWidgets('small and medium do not wait for a running large one',
        (tester) async {
      await start(tester);
      fx
        ..play(giftEvent('l', 40000))
        ..play(giftEvent('m', 350))
        ..play(giftEvent('s', 10));
      await tester.pump();
      expect(tiersOnScreen(tester), <EffectTier>[
        EffectTier.large,
        EffectTier.medium,
        EffectTier.small,
      ]);
      await advance(tester, 4000);
      await advance(tester, 3500);
    });
  });

  group('cancel and clear', () {
    testWidgets('cancel takes the effect and its notice back', (tester) async {
      final ended = <String>[];
      await start(tester, onEffectEnd: (e, t) => ended.add(e.gift.id));
      final id = fx.play(giftEvent('g', 350, sender: 'ayla'));
      await tester.pump();
      await tester.pump();
      expect(notice(tester).visible, isTrue);
      fx.cancel(id);
      await tester.pump();
      expect(find.byType(EffectItem), findsNothing);
      expect(notice(tester).visible, isFalse);
      await advance(tester, 3000);
      expect(ended, isEmpty, reason: 'a cancelled effect never ends');
    });

    testWidgets('clear removes every effect and the queue', (tester) async {
      final ended = <String>[];
      await start(tester, onEffectEnd: (e, t) => ended.add(e.gift.id));
      for (var i = 0; i < 3; i++) {
        fx
          ..play(giftEvent('l$i', 40000))
          ..play(giftEvent('s$i', 10));
      }
      await tester.pump();
      expect(find.byType(EffectItem), findsNWidgets(4));
      fx.clear();
      await tester.pump();
      expect(find.byType(EffectItem), findsNothing);
      await advance(tester, 8000);
      expect(find.byType(EffectItem), findsNothing);
      expect(ended, isEmpty);
    });
  });

  group('notice', () {
    testWidgets('bottom-left, with sender, gift and no counter for one gift',
        (tester) async {
      await start(tester, reducedMotion: true);
      fx.play(giftEvent('rose', 10, sender: 'ayla'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('ayla'), findsOneWidget);
      expect(find.text('sent rose'), findsOneWidget);
      expect(find.text('A'), findsOneWidget, reason: 'avatar initial');
      expect(find.byKey(const ValueKey<String>('gift-combo')), findsNothing);
      final rect = tester.getRect(find.byType(GiftNotice));
      expect(rect.left, 12);
      expect(rect.bottom, 800 - 150);
      await advance(tester, 3000);
    });

    testWidgets('a battle gift names the receiver and borders the pill',
        (tester) async {
      const theme = GiftingTheme();
      // The 2 px border in the side colour (the newest pill is the last one).
      Border? pillBorder() {
        Border? last;
        for (final e in find.byType(Container).evaluate()) {
          final d = (e.widget as Container).decoration;
          if (d is BoxDecoration && d.border is Border) {
            final b = d.border! as Border;
            if (b.top.width == 2) last = b;
          }
        }
        return last;
      }

      await start(tester, reducedMotion: true);
      fx.play(giftEvent('rose', 10, sender: 'ayla'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(pillBorder(), isNull, reason: 'no receiver: no border');
      fx.play(
        GiftEffectEvent(
          gift: giftEvent('lily', 10).gift,
          sender: 'ayla',
          receiver: const GiftEffectReceiver(name: 'Mia', side: 1),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('sent lily to Mia'), findsOneWidget);
      expect(pillBorder()!.top.width, 2);
      expect(pillBorder()!.top.color, theme.coin, reason: 'side 1 default');
      await advance(tester, 3500);
    });

    testWidgets('missing sender is Someone', (tester) async {
      await start(tester, reducedMotion: true);
      fx.play(giftEvent('rose', 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Someone'), findsOneWidget);
      await advance(tester, 3000);
    });

    testWidgets(
        'combo counter grows with the run and restarts after the window',
        (tester) async {
      var clock = 0;
      await start(tester, reducedMotion: true, now: () => clock);
      void send() => fx.play(giftEvent('rose', 10, sender: 'ayla'));

      send();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('x2'), findsNothing);
      clock = 2000;
      send();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('x2'), findsOneWidget);
      clock = 4000; // 2000 after the previous hit: still a run
      send();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('x3'), findsOneWidget);
      await advance(tester, 1000); // the counter pops and settles
      clock = 6500; // exactly the window after the previous hit: starts over
      send();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey<String>('gift-combo')), findsNothing);
      await advance(tester, 3500);
    });

    testWidgets('quantity above 1 shows the quantity', (tester) async {
      await start(tester, reducedMotion: true);
      fx.play(giftEvent('rose', 10, sender: 'ayla', quantity: 5));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('x5'), findsOneWidget);
      await advance(tester, 3500);
    });

    testWidgets('a large gift gets the golden notice', (tester) async {
      const theme = GiftingTheme();
      bool hasPillColor(Color c) => find
          .byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).color == c &&
                (w.decoration! as BoxDecoration).borderRadius != null,
          )
          .evaluate()
          .isNotEmpty;

      await start(tester, reducedMotion: true);
      fx.play(giftEvent('rose', 10));
      await tester.pump(const Duration(milliseconds: 500));
      expect(hasPillColor(theme.noticeBackground), isTrue);
      expect(hasPillColor(theme.noticeBigBackground), isFalse);
      fx.play(giftEvent('dragon', 40000));
      await tester.pump(const Duration(milliseconds: 500));
      expect(hasPillColor(theme.noticeBigBackground), isTrue);
      await advance(tester, 3500);
    });

    testWidgets('lasts noticeMs (2400 small, 2800 large), then slides out',
        (tester) async {
      await start(tester, reducedMotion: true);
      fx.play(giftEvent('rose', 10));
      await tester.pump();
      await advance(tester, 2300);
      expect(notice(tester).visible, isTrue);
      await advance(tester, 200);
      expect(notice(tester).visible, isFalse);
      fx.play(giftEvent('dragon', 40000));
      await tester.pump();
      await advance(tester, 2700);
      expect(notice(tester).visible, isTrue);
      await advance(tester, 200);
      expect(notice(tester).visible, isFalse);
      await advance(tester, 500);
    });
  });

  group('notice stack', () {
    testWidgets('two senders make two lines, the newest below', (tester) async {
      await start(tester, reducedMotion: true);
      fx.play(giftEvent('rose', 10, sender: 'ayla'));
      await tester.pump(const Duration(milliseconds: 100));
      fx.play(giftEvent('rose', 10, sender: 'bora'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GiftNotice), findsNWidgets(2));
      expect(
        tester.getRect(find.text('ayla')).top,
        lessThan(tester.getRect(find.text('bora')).top),
      );
      final older = tester.getRect(find.byType(GiftNotice).first);
      final newest = tester.getRect(find.byType(GiftNotice).last);
      expect(newest.bottom, 800 - 150);
      expect(newest.top - older.bottom, closeTo(6, 0.01));
      await advance(tester, 3500);
    });

    testWidgets('the same id updates its line in place and restarts its timer',
        (tester) async {
      var clock = 0;
      await start(tester, reducedMotion: true, now: () => clock);
      fx.play(giftEvent('rose', 10, sender: 'ayla'));
      await tester.pump(const Duration(milliseconds: 500));
      clock = 1000;
      fx.play(giftEvent('rose', 10, sender: 'ayla'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(GiftNotice), findsOneWidget);
      expect(find.text('x2'), findsOneWidget);
      // 2300 ms after the second hit: the first hit's timer would be gone.
      await advance(tester, 2200);
      expect(notice(tester).visible, isTrue);
      await advance(tester, 200);
      expect(notice(tester).visible, isFalse);
      await advance(tester, 500);
      expect(find.byType(GiftNotice), findsNothing);
    });

    testWidgets('a fourth line drops the oldest at once', (tester) async {
      await start(tester, reducedMotion: true);
      for (final name in <String>['ayla', 'bora', 'cem', 'deniz']) {
        fx.play(giftEvent('rose', 10, sender: name));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(GiftNotice), findsNWidgets(maxNoticeLines));
      expect(find.text('ayla'), findsNothing);
      expect(find.text('bora'), findsOneWidget);
      expect(find.text('deniz'), findsOneWidget);
      await advance(tester, 3500);
    });

    testWidgets('each line expires on its own timer', (tester) async {
      await start(tester, reducedMotion: true);
      fx.play(giftEvent('rose', 10, sender: 'ayla'));
      await tester.pump(const Duration(milliseconds: 1000));
      fx.play(giftEvent('rose', 10, sender: 'bora'));
      await tester.pump();
      expect(find.byType(GiftNotice), findsNWidgets(2));
      // 2800 ms: the first line (2400 + 260 slide) is gone, the second stays.
      await advance(tester, 1800);
      expect(find.text('ayla'), findsNothing);
      expect(find.text('bora'), findsOneWidget);
      expect(notice(tester).visible, isTrue);
      await advance(tester, 1000);
      expect(find.byType(GiftNotice), findsNothing);
    });

    testWidgets('cancel hides only the newest line', (tester) async {
      await start(tester, reducedMotion: true);
      fx.play(giftEvent('rose', 10, sender: 'ayla'));
      await tester.pump(const Duration(milliseconds: 100));
      final id = fx.play(giftEvent('rose', 10, sender: 'bora'));
      await tester.pump(const Duration(milliseconds: 500));
      fx.cancel(id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GiftNotice), findsOneWidget);
      expect(find.text('ayla'), findsOneWidget);
      expect(find.text('bora'), findsNothing);
      expect(notice(tester).visible, isTrue);
      await advance(tester, 3500);
    });

    testWidgets('clear removes every line at once', (tester) async {
      await start(tester, reducedMotion: true);
      fx.play(giftEvent('rose', 10, sender: 'ayla'));
      fx.play(giftEvent('rose', 10, sender: 'bora'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GiftNotice), findsNWidgets(2));
      fx.clear();
      await tester.pump();
      expect(find.byType(GiftNotice), findsNothing);
      await advance(tester, 3500);
    });
  });

  group('reduced motion', () {
    testWidgets('follows MediaQuery.disableAnimations: only the notice',
        (tester) async {
      await start(tester, disableAnimations: true);
      fx.play(giftEvent('dragon', 40000, sender: 'ayla'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(EffectItem), findsNothing);
      expect(notice(tester).data.senderName, 'ayla');
      expect(notice(tester).visible, isTrue);
      await advance(tester, 3500);
    });

    testWidgets('picked up live when the setting changes', (tester) async {
      await start(tester);
      fx.play(giftEvent('rose', 10));
      await tester.pump();
      expect(find.byType(EffectItem), findsOneWidget);
      await advance(tester, 2000);
      await tester.pumpWidget(
        layerApp(
          controller: fx,
          images: images,
          disableAnimations: true,
        ),
      );
      fx.play(giftEvent('rose', 10));
      await tester.pump();
      expect(find.byType(EffectItem), findsNothing);
      await advance(tester, 3500);
    });

    testWidgets('the reducedMotion prop wins over the system setting',
        (tester) async {
      await start(tester, disableAnimations: true, reducedMotion: false);
      fx.play(giftEvent('rose', 10));
      await tester.pump();
      expect(find.byType(EffectItem), findsOneWidget);
      await advance(tester, 2000);
      await advance(tester, 3500);
    });
  });

  group('touches and cleanup', () {
    testWidgets('touches pass through the layer, effects and notice',
        (tester) async {
      var taps = 0;
      await start(
        tester,
        under: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox.expand(),
        ),
      );
      fx.play(giftEvent('dragon', 40000, sender: 'ayla'));
      await tester.pump();
      await advance(tester, 1000);
      expect(find.byType(EffectItem), findsOneWidget);
      // Tap where the picture and where the notice are.
      // The big picture is at the stage point; the notice is a real, visible pill.
      await tester.tapAt(const Offset(200, 800 * 0.38));
      expect(notice(tester).visible, isTrue);
      await tester.tapAt(tester.getCenter(find.byType(GiftNotice)));
      expect(taps, 2);
      final layer = find.byType(GiftEffectLayer);
      expect(
        find.descendant(of: layer, matching: find.byType(IgnorePointer)),
        findsWidgets,
      );
      await advance(tester, 4000);
      await advance(tester, 3500);
    });

    testWidgets('a cached picture reports during the build and starts cleanly',
        (tester) async {
      // autoLoad: the stream answers synchronously while the tree is built.
      await start(tester);
      fx.play(
        giftEvent('g', 350, image: 'https://assets.test/g/512.webp'),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(GiftNotice), findsOneWidget);
      await advance(tester, 2500);
      await advance(tester, 3500);
    });

    testWidgets('removing the layer mid-effect leaves no timers or errors',
        (tester) async {
      await start(tester, autoLoad: false);
      fx
        ..play(
          giftEvent('slow', 40000, image: 'https://assets.test/slow/512.webp'),
        )
        ..play(giftEvent('small', 10, sender: 'ayla'))
        ..play(giftEvent('l2', 40000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      expect(fx.isAttached, isFalse);
      expect(fx.play(giftEvent('rose', 10)), 0);
      // The test framework fails here if any Timer is still pending.
    });
  });
}
