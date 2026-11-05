// Widget tests of GiftAwaySummary (SPEC 15.5): the card, the replay through the
// effect layer's controller, the acknowledgement timing, reduced motion and
// accessibility. The pure rules (plan, controller states) are in
// components_conformance_test.dart (away.json). What these cannot judge (how
// the card and the replay look and feel on a phone) needs a device.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';

import 'support/component_harness.dart';
import 'support/scripted_client.dart';
import 'support/ui_harness.dart';

/// Records every play with the elapsed fake time, then plays it for real.
class SpyEffects extends GiftEffectController {
  SpyEffects(this.elapsed);

  final int Function() elapsed;
  final List<({int atMs, String gift, int? quantity, String? sender})> plays =
      <({int atMs, String gift, int? quantity, String? sender})>[];

  @override
  int play(GiftEffectEvent event) {
    plays.add((
      atMs: elapsed(),
      gift: event.gift.id,
      quantity: event.quantity,
      sender: event.sender,
    ));
    return super.play(event);
  }
}

const Key _card = ValueKey<String>('gift-away-card');
const Key _dismiss = ValueKey<String>('gift-away-dismiss');
const Key _body = ValueKey<String>('gift-away-body');

void main() {
  late ScriptedClient api;
  late SpyEffects fx;
  late ControlledImages images;
  var elapsed = 0;
  final key = GlobalKey<GiftAwaySummaryState>();

  setUp(() {
    api = ScriptedClient();
    elapsed = 0;
    fx = SpyEffects(() => elapsed);
  });

  /// Fake time moves in 50 ms steps so animations and timers run in order.
  Future<void> advance(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
      elapsed += 50;
    }
  }

  Future<void> pumpAway(
    WidgetTester tester, {
    bool withLayer = true,
    bool useEffects = true,
    bool autoCheck = true,
    AwayAckOn ackOn = AwayAckOn.shown,
    int? maxGroups,
    int maxEffects = 5,
    int budgetMs = 8000,
    bool focusOnShow = false,
    Widget? Function(BuildContext, AwaySummaryContext)? renderSummary,
    bool? reducedMotion,
    bool disableAnimations = false,
    Future<Map<String, AwayUser>> Function(List<String>)? resolveUsers,
    void Function(AwaySummary)? onShow,
    VoidCallback? onDone,
    void Function(GiftingException)? onError,
    GiftingTheme theme = const GiftingTheme(),
    GiftLabels labels = const GiftLabels(),
    Size size = const Size(400, 800),
    Widget? under,
  }) async {
    images = ControlledImages(autoLoad: true);
    await images.init(tester);
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            disableAnimations: disableAnimations,
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: under ?? const SizedBox.shrink()),
              GiftAwaySummary(
                key: key,
                client: api,
                effects: useEffects ? fx : null,
                autoCheck: autoCheck,
                ackOn: ackOn,
                maxGroups: maxGroups,
                maxEffects: maxEffects,
                budgetMs: budgetMs,
                focusOnShow: focusOnShow,
                renderSummary: renderSummary,
                reducedMotion: reducedMotion,
                resolveUsers: resolveUsers,
                onShow: onShow,
                onDone: onDone,
                onError: onError,
                theme: theme,
                labels: labels,
                imageProvider: images.call,
              ),
              if (withLayer)
                Positioned.fill(
                  child: GiftEffectLayer(
                    controller: fx,
                    imageProvider: images.call,
                    remoteRecipes: false,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> resolveAway(WidgetTester tester, AwaySummary s) async {
    api.take('getAway', 'resolveAway').completer.complete(s);
    await tester.idle();
    await tester.pump();
  }

  Future<void> rejectAway(WidgetTester tester, Object e) async {
    api.take('getAway', 'rejectAway').completer.completeError(e);
    await tester.idle();
    await tester.pump();
  }

  Future<void> resolveAck(WidgetTester tester) async {
    api.take('ackAway', 'resolveAck').completer.complete(null);
    await tester.idle();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  /// Texts of the card itself (the effect layer's notices have names too).
  Finder inCard(Finder f) =>
      find.descendant(of: find.byKey(_card), matching: f);

  List<String> methods() =>
      api.calls.map((c) => c['method']! as String).toList();

  int acks() => methods().where((m) => m == 'ackAway').length;

  double cardOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find.ancestor(of: find.byKey(_card), matching: find.byType(Opacity)),
      )
      .opacity;

  group('what the card shows', () {
    testWidgets('nothing new: draws nothing, no ack, no replay',
        (tester) async {
      await pumpAway(tester);
      expect(methods(), <String>['getAway']);
      await resolveAway(tester, emptySummary());
      await advance(tester, 500);
      expect(find.byKey(_card), findsNothing);
      expect(fx.plays, isEmpty);
      expect(acks(), 0);
      await finish(tester);
    });

    testWidgets('a summary: title, line, top 3 senders, one chip per gift',
        (tester) async {
      final handle = tester.ensureSemantics();
      final shown = <AwaySummary>[];
      await pumpAway(tester, onShow: shown.add);
      await resolveAway(tester, workedSummary());
      await advance(tester, 300);
      expect(find.text('While you were away'), findsOneWidget);
      expect(find.text('74 gifts from 9 people'), findsOneWidget);
      // top_senders has four entries, three are shown; a deleted one is Someone.
      expect(find.byKey(const ValueKey<String>('gift-away-sender-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('gift-away-sender-2')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('gift-away-sender-3')),
          findsNothing);
      expect(inCard(find.text('ayla')), findsOneWidget);
      expect(inCard(find.text('Someone')), findsOneWidget);
      expect(inCard(find.text('mert')), findsOneWidget);
      expect(inCard(find.text('ece')), findsNothing,
          reason: 'the fourth is cut');
      // Initial avatars.
      expect(inCard(find.text('A')), findsOneWidget);
      expect(inCard(find.text('S')), findsOneWidget);
      // Gift chips with counts.
      for (final id in <String>['dragon', 'hat', 'rose', 'star']) {
        expect(find.byKey(ValueKey<String>('gift-away-group-$id')),
            findsOneWidget);
      }
      expect(inCard(find.text('20')), findsOneWidget);
      expect(inCard(find.text('50')), findsOneWidget);
      // Accessibility.
      expect(
        find.bySemanticsLabel(
          'You received 74 gifts from 9 people while you were away',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('ayla, 15 gifts'), findsOneWidget);
      expect(find.bySemanticsLabel('Hat, 20'), findsOneWidget);
      final close = tester.getSemantics(find.bySemanticsLabel('Dismiss'));
      expect(isSemantics(isButton: true).matches(close, <dynamic, dynamic>{}),
          isTrue);
      expect(shown.single.cursor, 'aw1.AAA');
      handle.dispose();
      await finish(tester);
    });

    testWidgets('live region: the announcement is polite and on the heading',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAway(tester);
      await resolveAway(tester, workedSummary());
      await advance(tester, 300);
      final node = tester.getSemantics(
        find.bySemanticsLabel(
          'You received 74 gifts from 9 people while you were away',
        ),
      );
      expect(
        isSemantics(isLiveRegion: true).matches(node, <dynamic, dynamic>{}),
        isTrue,
      );
      handle.dispose();
      await finish(tester);
    });

    testWidgets('truncated totals read "2,000+"; singular forms',
        (tester) async {
      await pumpAway(tester);
      await resolveAway(
        tester,
        workedSummary(truncated: true, totalGifts: 2000, senderCount: 41),
      );
      await advance(tester, 100);
      expect(find.text('2,000+ gifts from 41 people'), findsOneWidget);
      await finish(tester);

      await pumpAway(tester);
      await resolveAway(
        tester,
        workedSummary(
          totalGifts: 1,
          senderCount: 1,
          groups: <AwayGroup>[awayGroup('rose', 10, 1)],
        ),
      );
      await advance(tester, 100);
      expect(find.text('1 gift from 1 person'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('large totals are grouped (1,234 gifts)', (tester) async {
      await pumpAway(tester);
      await resolveAway(
        tester,
        workedSummary(totalGifts: 1234, senderCount: 1200),
      );
      await advance(tester, 100);
      expect(find.text('1,234 gifts from 1,200 people'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('labels: every word is replaceable', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAway(
        tester,
        labels: const GiftLabels(
          awayTitle: 'Yokken',
          awaySummary: '{people} kisiden {gifts}',
          giftOther: '{n} hediye',
          personOther: '{n} kisi',
          dismiss: 'Kapat',
          awayAnnounce: 'Sen yokken: {summary}',
          someone: 'Biri',
        ),
      );
      await resolveAway(tester, workedSummary());
      await advance(tester, 100);
      expect(find.text('Yokken'), findsOneWidget);
      expect(find.text('9 kisi kisiden 74 hediye'), findsOneWidget);
      expect(find.bySemanticsLabel('Kapat'), findsOneWidget);
      expect(find.bySemanticsLabel('Sen yokken: 9 kisi kisiden 74 hediye'),
          findsOneWidget);
      expect(inCard(find.text('Biri')), findsOneWidget);
      handle.dispose();
      await finish(tester);
    });

    testWidgets('theme: surface, text, muted and the avatar accent',
        (tester) async {
      const theme = GiftingTheme(
        surface: Color(0xFF112233),
        text: Color(0xFFAA0000),
        muted: Color(0xFF00AA00),
        accent: Color(0xFF0000CC),
      );
      await pumpAway(tester, theme: theme);
      await resolveAway(tester, workedSummary());
      await advance(tester, 300);
      final box = tester.widget<Container>(find.byKey(_card)).decoration!
          as BoxDecoration;
      expect(box.color, const Color(0xFF112233));
      expect(box.borderRadius, BorderRadius.circular(20));
      expect(tester.widget<Text>(find.text('While you were away')).style!.color,
          const Color(0xFFAA0000));
      expect(
          tester.widget<Text>(find.text('74 gifts from 9 people')).style!.color,
          const Color(0xFF00AA00));
      final avatar = tester.widget<Container>(
        find
            .ancestor(
                of: inCard(find.text('A')), matching: find.byType(Container))
            .first,
      );
      expect(
          (avatar.decoration! as BoxDecoration).color, const Color(0xFF0000CC));
      await finish(tester);
    });

    testWidgets('the card is centred and at most 360 dp wide', (tester) async {
      await pumpAway(tester, size: const Size(800, 600));
      await resolveAway(tester, workedSummary());
      await advance(tester, 300);
      final r = tester.getRect(find.byKey(_card));
      expect(r.width, 360);
      expect(r.center.dx, closeTo(400, 0.5));
      expect(r.center.dy, closeTo(300, 1));
      await finish(tester);
    });

    testWidgets('only the card takes touches; the screen below keeps its own',
        (tester) async {
      var under = 0;
      await pumpAway(
        tester,
        under: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => under++,
        ),
      );
      await resolveAway(tester, workedSummary());
      await advance(tester, 300);
      await tester.tapAt(const Offset(5, 5));
      expect(under, 1, reason: 'outside the card passes through');
      expect(find.byKey(_card), findsOneWidget);
      await finish(tester);
    });
  });

  group('the replay through the effect layer', () {
    testWidgets(
        'plays the worked example: star, rose, hat, dragon, biggest last',
        (tester) async {
      await pumpAway(tester);
      await resolveAway(tester, workedSummary());
      await advance(tester, 100);
      final t0 = fx.plays.first.atMs;
      await advance(tester, 4000);
      expect(fx.plays.map((p) => p.gift),
          <String>['star', 'rose', 'hat', 'dragon']);
      const want = <int>[0, 450, 900, 3300];
      final offsets = fx.plays.map((p) => p.atMs - t0).toList();
      for (var i = 0; i < want.length; i++) {
        expect(offsets[i], closeTo(want[i], 50), reason: 'play ${i + 1}');
      }
      expect(fx.plays.map((p) => p.quantity), <int?>[3, 50, 20, 1]);
      expect(
        fx.plays.map((p) => p.sender),
        <String?>['Someone', 'ece and mert', 'mert and 5 others', 'ayla'],
      );
      await finish(tester);
    });

    testWidgets('the effect layer really draws them (notice of the last one)',
        (tester) async {
      await pumpAway(tester);
      await resolveAway(tester, workedSummary());
      await advance(tester, 4000);
      expect(find.textContaining('Dragon'), findsWidgets);
      await advance(tester, 6000);
      await finish(tester);
    });

    testWidgets(
        'at most maxEffects groups play, the rest only show on the card',
        (tester) async {
      final groups = <AwayGroup>[
        for (var i = 0; i < 7; i++) awayGroup('g$i', 350, 10 + i),
      ];
      await pumpAway(tester, maxEffects: 5);
      await resolveAway(tester, workedSummary(groups: groups));
      await advance(tester, 7000);
      expect(fx.plays.length, 5);
      expect(
        fx.plays.map((p) => p.gift).toSet(),
        <String>{'g0', 'g1', 'g2', 'g3', 'g4'},
      );
      // All seven are on the card.
      for (var i = 0; i < 7; i++) {
        expect(find.byKey(ValueKey<String>('gift-away-group-g$i')),
            findsOneWidget);
      }
      await finish(tester);
    });

    testWidgets('maxEffects 2 plays two', (tester) async {
      await pumpAway(tester, maxEffects: 2);
      await resolveAway(tester, workedSummary());
      await advance(tester, 6000);
      // dragon (large) and hat (medium) are the first two groups.
      expect(fx.plays.map((p) => p.gift), <String>['hat', 'dragon']);
      await finish(tester);
    });

    testWidgets('the replay ends within budgetMs: lowest units are dropped',
        (tester) async {
      final groups = <AwayGroup>[
        for (var i = 0; i < 5; i++) awayGroup('m$i', 350, 100 - i * 10),
      ];
      // Five mediums: starts 0, 1100, 2200, 3300, 4400, end 6500 <= 8000.
      await pumpAway(tester);
      await resolveAway(tester, workedSummary(groups: groups));
      await advance(tester, 8000);
      expect(fx.plays.length, 5);
      await finish(tester);

      // A budget of 3000 only fits one medium (end 2100; two end at 3200).
      fx = SpyEffects(() => elapsed);
      api = ScriptedClient();
      await pumpAway(tester, budgetMs: 3000);
      await resolveAway(tester, workedSummary(groups: groups));
      await advance(tester, 6000);
      expect(fx.plays.length, 1);
      expect(fx.plays.single.gift, 'm0', reason: 'the highest units stay');
      await finish(tester);
    });

    testWidgets('no effect layer given: card only', (tester) async {
      await pumpAway(tester, useEffects: false);
      await resolveAway(tester, workedSummary());
      await advance(tester, 2000);
      expect(find.byKey(_card), findsOneWidget);
      expect(fx.plays, isEmpty);
      await finish(tester);
    });

    testWidgets('a controller that is not attached to a layer: card only',
        (tester) async {
      await pumpAway(tester, withLayer: false);
      await resolveAway(tester, workedSummary());
      await advance(tester, 2000);
      expect(find.byKey(_card), findsOneWidget);
      expect(fx.plays, isEmpty);
      await finish(tester);
    });

    testWidgets('names from resolveUsers are used in the replay notices',
        (tester) async {
      await pumpAway(
        tester,
        resolveUsers: (ids) async => <String, AwayUser>{
          'ayla': const AwayUser(name: 'Ayla K.'),
          'mert': const AwayUser(name: 'Mert'),
          'ece': const AwayUser(name: 'Ece'),
        },
      );
      await resolveAway(tester, workedSummary());
      await advance(tester, 4500);
      expect(
        fx.plays.map((p) => p.sender),
        <String?>['Someone', 'Ece and Mert', 'Mert and 5 others', 'Ayla K.'],
      );
      await finish(tester);
    });
  });

  group('acknowledging the summary', () {
    testWidgets('ackOn shown (default): once, with the shown cursor, at once',
        (tester) async {
      await pumpAway(tester);
      await resolveAway(tester, workedSummary(cursor: 'aw1.SHOWN'));
      expect(api.calls.last, <String, Object?>{
        'method': 'ackAway',
        'args': <String, Object?>{'cursor': 'aw1.SHOWN'},
      });
      await resolveAck(tester);
      await tester.tap(find.byKey(_body));
      await advance(tester, 100);
      expect(find.byKey(_card), findsNothing);
      expect(acks(), 1, reason: 'a dismissal does not ack twice');
      await finish(tester);
    });

    testWidgets('ackOn finished: nothing while the card is up; a tap acks',
        (tester) async {
      await pumpAway(tester, ackOn: AwayAckOn.finished);
      await resolveAway(tester, workedSummary());
      await advance(tester, 2000);
      expect(acks(), 0);
      await tester.tap(find.byKey(_dismiss));
      await tester.pump();
      expect(acks(), 1);
      await resolveAck(tester);
      await advance(tester, 20000);
      expect(acks(), 1);
      await finish(tester);
    });

    testWidgets('ackOn finished: the automatic dismissal acks too',
        (tester) async {
      await pumpAway(tester, ackOn: AwayAckOn.finished);
      await resolveAway(tester, workedSummary());
      await advance(tester, 8500);
      expect(acks(), 0, reason: '7150 + 1500 = 8650');
      await advance(tester, 300);
      expect(find.byKey(_card), findsNothing);
      expect(acks(), 1);
      await finish(tester);
    });

    testWidgets('ackOn manual: only state.ack(), and only once per summary',
        (tester) async {
      await pumpAway(tester, ackOn: AwayAckOn.manual);
      await resolveAway(tester, workedSummary());
      await tester.tap(find.byKey(_dismiss));
      await advance(tester, 100);
      expect(acks(), 0);
      unawaited(key.currentState!.ack());
      await tester.idle();
      expect(acks(), 1);
      unawaited(key.currentState!.ack());
      await tester.idle();
      expect(acks(), 1);
      await finish(tester);
    });

    testWidgets('a failed ack goes to onError and is retried at the next check',
        (tester) async {
      final errors = <String>[];
      await pumpAway(tester, onError: (e) => errors.add(e.type));
      await resolveAway(tester, workedSummary(cursor: 'aw1.X'));
      api.take('ackAway', 'x').completer.completeError(
            const GiftingException(500, 'internal', 'x'),
          );
      await tester.idle();
      await tester.pump();
      expect(errors, <String>['internal']);
      await tester.tap(find.byKey(_dismiss));
      await advance(tester, 100);
      // The next check sends the stored cursor first, then reads.
      unawaited(key.currentState!.check());
      await tester.idle();
      expect(
        api.calls.skip(2).map((c) => c['method']).toList(),
        <Object?>['ackAway'],
      );
      expect(api.calls[2]['args'], <String, Object?>{'cursor': 'aw1.X'});
      await resolveAck(tester);
      expect(methods().last, 'getAway');
      await finish(tester);
    });
  });

  group('closing the card', () {
    testWidgets('it goes by itself after max(4000, planEnd + 1500) ms',
        (tester) async {
      var done = 0;
      await pumpAway(tester, onDone: () => done++);
      await resolveAway(tester, workedSummary());
      await advance(tester, 8500);
      expect(find.byKey(_card), findsOneWidget);
      await advance(tester, 300);
      expect(find.byKey(_card), findsNothing);
      expect(done, 1);
      await finish(tester);
    });

    testWidgets('card only: 4000 ms', (tester) async {
      await pumpAway(tester, useEffects: false);
      await resolveAway(tester, workedSummary());
      await advance(tester, 3800);
      expect(find.byKey(_card), findsOneWidget);
      await advance(tester, 300);
      expect(find.byKey(_card), findsNothing);
      await finish(tester);
    });

    testWidgets('a tap on the body dismisses; plays not started are dropped',
        (tester) async {
      var done = 0;
      await pumpAway(tester, onDone: () => done++);
      await resolveAway(tester, workedSummary());
      await advance(tester, 1000);
      await tester.tap(find.byKey(_body));
      await tester.pump();
      expect(find.byKey(_card), findsNothing);
      expect(done, 1);
      await advance(tester, 6000);
      expect(fx.plays.map((p) => p.gift), <String>['star', 'rose', 'hat'],
          reason: 'the dragon at 3300 ms never starts');
      await finish(tester);
    });

    testWidgets('the close button dismisses', (tester) async {
      await pumpAway(tester);
      await resolveAway(tester, workedSummary());
      await advance(tester, 200);
      expect(tester.getSize(find.byKey(_dismiss)), const Size(44, 44));
      await tester.tap(find.byKey(_dismiss));
      await tester.pump();
      expect(find.byKey(_card), findsNothing);
      await finish(tester);
    });

    testWidgets('after done a new check can show a new card', (tester) async {
      await pumpAway(tester);
      await resolveAway(tester, workedSummary(cursor: 'aw1.A'));
      await tester.tap(find.byKey(_dismiss));
      await tester.pump();
      await resolveAck(tester);
      unawaited(key.currentState!.check());
      await tester.idle();
      await resolveAway(tester, workedSummary(cursor: 'aw1.B', totalGifts: 5));
      await advance(tester, 300);
      expect(find.text('5 gifts from 9 people'), findsOneWidget);
      expect(find.byKey(_card), findsOneWidget);
      await finish(tester);
    });

    testWidgets('check() while a card is up is ignored', (tester) async {
      await pumpAway(tester);
      await resolveAway(tester, workedSummary());
      await advance(tester, 100);
      unawaited(key.currentState!.check());
      await tester.idle();
      expect(methods().where((m) => m == 'getAway').length, 1);
      await finish(tester);
    });

    testWidgets('dispose while the card is up stops the timers',
        (tester) async {
      await pumpAway(tester);
      await resolveAway(tester, workedSummary());
      await advance(tester, 500);
      await tester.pumpWidget(const SizedBox());
      // No exception, no timer left (the test would fail on a pending one).
      await tester.pump(const Duration(seconds: 20));
    });

    testWidgets('a late answer after dispose changes nothing', (tester) async {
      final shown = <AwaySummary>[];
      await pumpAway(tester, onShow: shown.add);
      await tester.pumpWidget(const SizedBox());
      api.take('getAway', 'late').completer.complete(workedSummary());
      await tester.idle();
      await tester.pump();
      expect(shown, isEmpty);
      expect(acks(), 0);
    });
  });

  group('requests', () {
    testWidgets('autoCheck false: no request until state.check()',
        (tester) async {
      await pumpAway(tester, autoCheck: false);
      await advance(tester, 500);
      expect(api.calls, isEmpty);
      unawaited(key.currentState!.check());
      await tester.idle();
      expect(methods(), <String>['getAway']);
      await finish(tester);
    });

    testWidgets('maxGroups is sent as max_groups', (tester) async {
      await pumpAway(tester, maxGroups: 3);
      expect(api.calls.single['args'], <String, Object?>{'maxGroups': 3});
      await finish(tester);
    });

    testWidgets('no maxGroups: the read has no arguments', (tester) async {
      await pumpAway(tester);
      expect(api.calls.single['args'], <String, Object?>{});
      await finish(tester);
    });

    testWidgets('a failed read is silent: nothing drawn, onError hears it',
        (tester) async {
      final errors = <String>[];
      await pumpAway(tester, onError: (e) => errors.add(e.type));
      await rejectAway(
        tester,
        const GiftingException(0, 'network_error', 'offline'),
      );
      await advance(tester, 500);
      expect(errors, <String>['network_error']);
      expect(find.byKey(_card), findsNothing);
      expect(find.byType(Text), findsNothing);
      // The next check tries again.
      unawaited(key.currentState!.check());
      await tester.idle();
      await resolveAway(tester, workedSummary());
      await advance(tester, 200);
      expect(find.byKey(_card), findsOneWidget);
      await finish(tester);
    });

    testWidgets('back to the foreground within a minute asks nothing',
        (tester) async {
      await pumpAway(tester);
      await resolveAway(tester, emptySummary());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.idle();
      expect(methods(), <String>['getAway'], reason: 'throttled to 60 s');
      await finish(tester);
    });

    testWidgets('autoCheck false: the foreground does nothing', (tester) async {
      await pumpAway(tester, autoCheck: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.idle();
      expect(api.calls, isEmpty);
      await finish(tester);
    });
  });

  group('resolveUsers', () {
    testWidgets('asked once with the distinct ids; names on the card',
        (tester) async {
      final asked = <List<String>>[];
      await pumpAway(
        tester,
        resolveUsers: (ids) async {
          asked.add(ids);
          return <String, AwayUser>{
            'ayla': const AwayUser(name: 'Ayla Kaya'),
            'mert': const AwayUser(name: 'Mert'),
          };
        },
      );
      await resolveAway(tester, workedSummary());
      await advance(tester, 100);
      expect(asked.single, <String>['ayla', 'mert', 'ece']);
      expect(inCard(find.text('Ayla Kaya')), findsOneWidget);
      expect(inCard(find.text('Mert')), findsOneWidget);
      expect(inCard(find.text('Someone')), findsOneWidget);
      expect(find.byKey(_card), findsOneWidget);
      await finish(tester);
    });

    testWidgets('the card waits for the names, but at most 1.5 s',
        (tester) async {
      final never = Completer<Map<String, AwayUser>>();
      await pumpAway(tester, resolveUsers: (_) => never.future);
      await resolveAway(tester, workedSummary());
      await advance(tester, 1400);
      expect(find.byKey(_card), findsNothing, reason: 'still waiting');
      expect(fx.plays, isEmpty, reason: 'the replay starts with the card');
      await advance(tester, 200);
      expect(find.byKey(_card), findsOneWidget);
      expect(inCard(find.text('ayla')), findsOneWidget,
          reason: 'ids as fallback');
      await finish(tester);
    });

    testWidgets('a failing lookup shows the ids at once', (tester) async {
      await pumpAway(
        tester,
        resolveUsers: (_) =>
            Future<Map<String, AwayUser>>.error(StateError('x')),
      );
      await resolveAway(tester, workedSummary());
      await advance(tester, 100);
      expect(find.byKey(_card), findsOneWidget);
      expect(inCard(find.text('ayla')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('only deleted senders: nothing to look up', (tester) async {
      var asked = 0;
      await pumpAway(
        tester,
        resolveUsers: (ids) async {
          asked++;
          return <String, AwayUser>{};
        },
      );
      await resolveAway(
        tester,
        workedSummary(
          groups: <AwayGroup>[
            awayGroup(
              'star',
              5,
              3,
              senders: const <AwaySender>[AwaySender(user: null, count: 3)],
            ),
          ],
        ).copyWithTops(const <AwayTopSender>[]),
      );
      await advance(tester, 100);
      expect(asked, 0);
      expect(find.byKey(_card), findsOneWidget);
      await finish(tester);
    });
  });

  group('reduced motion', () {
    for (final mode in <(String, bool?, bool)>[
      ('prop', true, false),
      ('system setting', null, true),
    ]) {
      testWidgets('${mode.$1}: the card just appears, no replay, still acked',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpAway(
          tester,
          reducedMotion: mode.$2,
          disableAnimations: mode.$3,
        );
        await resolveAway(tester, workedSummary());
        // One frame later it is fully there: no slide-in.
        expect(cardOpacity(tester), 1);
        expect(
          find.bySemanticsLabel(
            'You received 74 gifts from 9 people while you were away',
          ),
          findsOneWidget,
        );
        await advance(tester, 3500);
        expect(fx.plays, isEmpty);
        expect(acks(), 1);
        expect(find.byKey(_card), findsOneWidget);
        // Card only: it goes after 4000 ms.
        await advance(tester, 600);
        expect(find.byKey(_card), findsNothing);
        handle.dispose();
        await finish(tester);
      });
    }

    testWidgets('with motion the card slides in over 240 ms', (tester) async {
      await pumpAway(tester);
      await resolveAway(tester, workedSummary());
      expect(cardOpacity(tester), lessThan(0.2));
      final y0 = tester.getRect(find.byKey(_card)).top;
      await advance(tester, 300);
      expect(cardOpacity(tester), 1);
      expect(tester.getRect(find.byKey(_card)).top, lessThan(y0));
      await finish(tester);
    });
  });

  group('focus', () {
    testWidgets('focusOnShow asks for focus on the card; default does not',
        (tester) async {
      await pumpAway(tester, focusOnShow: true);
      await resolveAway(tester, workedSummary());
      await advance(tester, 100);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'gift-away-card');
      await finish(tester);

      await pumpAway(tester);
      await resolveAway(tester, workedSummary());
      await advance(tester, 100);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('gift-away-card'),
      );
      await finish(tester);
    });
  });

  group('renderSummary slot', () {
    testWidgets('draws its own body; the context carries the computed data',
        (tester) async {
      AwaySummaryContext? seen;
      await pumpAway(
        tester,
        resolveUsers: (ids) async => <String, AwayUser>{
          'ayla': const AwayUser(name: 'Ayla K'),
        },
        renderSummary: (context, summary) {
          seen = summary;
          return Text('mine ${summary.headline}');
        },
      );
      await resolveAway(tester, workedSummary());
      await advance(tester, 2000);
      expect(inCard(find.text('mine 74 gifts from 9 people')), findsOneWidget);
      expect(find.text('While you were away'), findsNothing,
          reason: 'default body is gone');
      final c = seen!;
      expect(c.title, 'While you were away');
      expect(c.gifts, '74 gifts');
      expect(c.people, '9 people');
      expect(c.senders.length, 4, reason: 'every top sender, not just three');
      expect(c.senders.first.name, 'Ayla K');
      expect(c.summary.totalGifts, 74);
      await finish(tester);
    });

    testWidgets('null falls back to the default body', (tester) async {
      await pumpAway(tester, renderSummary: (context, summary) => null);
      await resolveAway(tester, workedSummary());
      await advance(tester, 300);
      expect(find.text('While you were away'), findsOneWidget);
      expect(find.byKey(_dismiss), findsOneWidget);
      await tester.tap(find.byKey(_body));
      await advance(tester, 100);
      expect(find.byKey(_card), findsNothing);
      await finish(tester);
    });

    testWidgets('a tap does not dismiss; dismiss() and ack() are the actions',
        (tester) async {
      await pumpAway(
        tester,
        ackOn: AwayAckOn.manual,
        renderSummary: (context, summary) => Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('mine'),
            GestureDetector(
              onTap: summary.dismiss,
              child: const Text('close me'),
            ),
            GestureDetector(
              onTap: () => unawaited(summary.ack()),
              child: const Text('seen'),
            ),
          ],
        ),
      );
      await resolveAway(tester, workedSummary());
      await advance(tester, 300);
      expect(find.byKey(_dismiss), findsNothing, reason: 'no default ×');
      await tester.tap(find.text('mine'));
      await advance(tester, 100);
      expect(find.byKey(_card), findsOneWidget, reason: 'a tap on content');
      await tester.tap(find.text('seen'));
      await tester.pump();
      expect(acks(), 1);
      await resolveAck(tester);
      await tester.tap(find.text('close me'));
      await advance(tester, 100);
      expect(find.byKey(_card), findsNothing);
      await finish(tester);
    });

    testWidgets('the replay still runs and the announcement is kept',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAway(
        tester,
        renderSummary: (context, summary) => const Text('mine'),
      );
      await resolveAway(tester, workedSummary());
      await advance(tester, 300);
      expect(fx.plays, isNotEmpty);
      final node = tester.getSemantics(
        find.bySemanticsLabel(
          'You received 74 gifts from 9 people while you were away',
        ),
      );
      expect(
        isSemantics(isLiveRegion: true).matches(node, <dynamic, dynamic>{}),
        isTrue,
      );
      handle.dispose();
      await finish(tester);
    });
  });
}

extension on AwaySummary {
  AwaySummary copyWithTops(List<AwayTopSender> tops) => AwaySummary(
        user: user,
        since: since,
        until: until,
        cursor: cursor,
        truncated: truncated,
        totalGifts: totalGifts,
        totalUnits: totalUnits,
        senderCount: senderCount,
        groups: groups,
        topSenders: tops,
      );
}
