// Widget tests of GiftWall (SPEC 14.5): every state and prop, the shared batch
// request, accessibility and reduced motion. What they cannot judge (how the
// chips look on a phone) needs a device.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack/src/ui/gift_parts.dart' show GiftPicture;

import 'support/component_harness.dart';
import 'support/scripted_client.dart';
import 'support/ui_harness.dart';

const Key _wall = ValueKey<String>('gift-wall');
const Key _skeleton = ValueKey<String>('gift-wall-skeleton');

Key chipKey(String id) => ValueKey<String>('gift-wall-chip-$id');

/// 12 Roses, 3 Hearts, 1 Dragon and 37 more in 7 other kinds (catalog order).
final List<ReceivedGift> feedGifts = <ReceivedGift>[
  received('rose', 12),
  received('heart', 3),
  received('dragon', 1),
  received('star', 10),
  received('hat', 9),
  received('cake', 8),
  received('lion', 5),
  received('car', 3),
  received('pin', 2),
  received('kiss', 0),
];

void main() {
  late ControlledImages images;
  late ScriptedClient api;

  setUp(() => api = ScriptedClient());

  /// The loader's 50 ms window closes and the batch call is answered.
  Future<void> answer(
    WidgetTester tester, {
    List<ReceivedGift>? gifts,
    int ms = 50,
  }) async {
    await tester.pump(Duration(milliseconds: ms));
    final call = api.take('queryGiftWalls', 'answer');
    final items = (api.calls.last['args']! as Map<String, Object?>)['items']!
        as List<Map<String, Object?>>;
    call.completer.complete(wallAnswers(items, gifts ?? feedGifts));
    await tester.idle();
    await tester.pump();
  }

  Future<void> fail(WidgetTester tester, [GiftingException? e]) async {
    await tester.pump(const Duration(milliseconds: 50));
    api.take('queryGiftWalls', 'fail').completer.completeError(
          e ?? const GiftingException(503, 'leaderboard_building', 'later'),
        );
    await tester.pump();
  }

  Future<void> pumpWall(
    WidgetTester tester, {
    String user = 'mert',
    String? reference,
    int max = 6,
    WallOrder order = WallOrder.count,
    GiftWallSize size = GiftWallSize.md,
    List<ReceivedGift>? data,
    Object? refreshKey,
    Widget? Function(BuildContext, WallChipContext)? renderChip,
    void Function(GiftRef)? onPressChip,
    void Function(GiftingException)? onError,
    bool? reducedMotion,
    bool disableAnimations = false,
    GiftingTheme theme = const GiftingTheme(),
    GiftLabels labels = const GiftLabels(),
    GiftWallLoader? loader,
  }) async {
    images = ControlledImages(autoLoad: true);
    await images.init(tester);
    await tester.pumpWidget(
      hostApp(
        GiftWall(
          client: api,
          user: user,
          reference: reference,
          max: max,
          order: order,
          size: size,
          data: data,
          refreshKey: refreshKey,
          renderChip: renderChip,
          onPressChip: onPressChip,
          onError: onError,
          reducedMotion: reducedMotion,
          theme: theme,
          labels: labels,
          imageProvider: images.call,
          loader: loader,
        ),
        disableAnimations: disableAnimations,
      ),
    );
  }

  List<String> counts(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(_wall), matching: find.byType(Text)),
      )
      .map((t) => t.data!)
      .toList();

  group('loading, ready, empty, error', () {
    testWidgets('loading: three skeleton chips, pulsing; static when reduced',
        (tester) async {
      await pumpWall(tester);
      expect(find.byKey(_skeleton), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        expect(
          find.byKey(ValueKey<String>('gift-wall-skeleton-chip-$i')),
          findsOneWidget,
        );
      }
      expect(find.byKey(_wall), findsNothing);
      expect(tester.hasRunningAnimations, isTrue, reason: 'it pulses');
      await answer(tester, gifts: const <ReceivedGift>[]);
      await tester.pumpAndSettle();

      await pumpWall(tester, user: 'other', reducedMotion: true);
      expect(find.byKey(_skeleton), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse, reason: 'static skeleton');
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the system "remove animations" setting makes it static too',
        (tester) async {
      await pumpWall(tester, disableAnimations: true);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ready: icons and counts, biggest first, +N for the rest',
        (tester) async {
      await pumpWall(tester);
      await answer(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(_skeleton), findsNothing);
      // max 6 = 5 chips + overflow; zero counts are dropped (kiss).
      expect(counts(tester), <String>['12', '10', '9', '8', '5', '+9']);
      expect(find.byKey(chipKey('rose')), findsOneWidget);
      expect(find.byKey(chipKey('heart')), findsNothing, reason: 'hidden');
      expect(find.byKey(const ValueKey<String>('gift-wall-overflow')),
          findsOneWidget);
      // One picture per gift chip, loaded from the gift's icon.
      expect(images.requested.length, 5);
      expect(images.requested, contains('https://assets.test/rose/256.webp'));
    });

    testWidgets('the request is the wall of (user, reference)', (tester) async {
      await pumpWall(tester, user: 'mert', reference: 'post_42');
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.calls.single, <String, Object?>{
        'method': 'queryGiftWalls',
        'args': <String, Object?>{
          'items': <Map<String, Object?>>[
            <String, Object?>{'receiver': 'mert', 'reference': 'post_42'},
          ],
        },
      });
      await answer(tester, ms: 0);
      await tester.pumpAndSettle();
    });

    testWidgets('empty: draws nothing, or only emptyText', (tester) async {
      await pumpWall(tester);
      await answer(tester, gifts: const <ReceivedGift>[]);
      await tester.pumpAndSettle();
      expect(find.byType(GiftWall), findsOneWidget);
      expect(tester.getSize(find.byType(GiftWall)), Size.zero);

      await pumpWall(
        tester,
        user: 'other',
        labels: const GiftLabels(emptyText: 'No gifts yet'),
      );
      await answer(tester, gifts: <ReceivedGift>[received('rose', 0)]);
      await tester.pumpAndSettle();
      expect(find.text('No gifts yet'), findsOneWidget);
      expect(find.byKey(_wall), findsNothing);
    });

    testWidgets('error: draws nothing and only onError hears of it',
        (tester) async {
      final errors = <String>[];
      await pumpWall(tester, onError: (e) => errors.add(e.type));
      await fail(tester);
      await tester.pumpAndSettle();
      expect(errors, <String>['leaderboard_building']);
      expect(find.byKey(_wall), findsNothing);
      expect(find.byKey(_skeleton), findsNothing);
      expect(tester.getSize(find.byType(GiftWall)), Size.zero);
      expect(find.byType(Text), findsNothing, reason: 'never an error text');
    });

    testWidgets('a failure that is not a GiftingException is wrapped',
        (tester) async {
      final errors = <GiftingException>[];
      await pumpWall(tester, user: 'x', onError: errors.add);
      await tester.pump(const Duration(milliseconds: 50));
      api
          .take('queryGiftWalls', 'x')
          .completer
          .completeError(StateError('boom'));
      await tester.pump();
      expect(errors.single.type, 'unknown_error');
      expect(errors.single.message, 'boom');
    });

    testWidgets('data: used as is, no request at all', (tester) async {
      await pumpWall(tester, data: <ReceivedGift>[received('rose', 2)]);
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.calls, isEmpty);
      expect(counts(tester), <String>['2']);
      // New data replaces the old without a request.
      await tester.pumpWidget(
        hostApp(
          GiftWall(
            client: api,
            user: 'mert',
            data: <ReceivedGift>[received('heart', 1000)],
            imageProvider: images.call,
          ),
        ),
      );
      expect(counts(tester), <String>['1K']);
      expect(api.calls, isEmpty);
    });
  });

  group('props', () {
    testWidgets('max and order: count order (default) vs catalog order',
        (tester) async {
      await pumpWall(tester, max: 4, order: WallOrder.catalog);
      await answer(tester);
      await tester.pumpAndSettle();
      // catalog: rose, heart, dragon, then +sum of the rest (10+9+8+5+3+2).
      expect(counts(tester), <String>['12', '3', '1', '+37']);
    });

    testWidgets('max 1 shows only the overflow chip with every count',
        (tester) async {
      await pumpWall(tester, max: 1);
      await answer(tester);
      await tester.pumpAndSettle();
      expect(counts(tester), <String>['+53']);
    });

    testWidgets('size: md is 24 dp high with a 20 icon, sm 20 with a 16',
        (tester) async {
      Size chip(String id) => tester.getSize(
            find
                .descendant(
                  of: find.byKey(chipKey(id)),
                  matching: find.byType(Container),
                )
                .first,
          );
      await pumpWall(tester, user: 'md');
      await answer(tester);
      await tester.pumpAndSettle();
      expect(chip('rose').height, 24);
      expect(counts(tester).first, '12');
      final md = tester.widget<Text>(find.text('12')).style!.fontSize;
      expect(md, 12.5);

      await pumpWall(tester, user: 'sm', size: GiftWallSize.sm);
      await answer(tester);
      await tester.pumpAndSettle();
      expect(chip('rose').height, 20);
      expect(tester.widget<Text>(find.text('12')).style!.fontSize, 11);
    });

    testWidgets('theme: surface, border, text and muted colours',
        (tester) async {
      const theme = GiftingTheme(
        surface: Color(0xFF112233),
        border: Color(0xFF445566),
        text: Color(0xFFAA0000),
        muted: Color(0xFF00AA00),
      );
      await pumpWall(tester, theme: theme);
      await answer(tester);
      await tester.pumpAndSettle();
      final box = tester
          .widget<Container>(
            find
                .descendant(
                  of: find.byKey(chipKey('rose')),
                  matching: find.byType(Container),
                )
                .first,
          )
          .decoration! as BoxDecoration;
      expect(box.color, const Color(0xFF112233));
      expect((box.border! as Border).top.color, const Color(0xFF445566));
      expect(tester.widget<Text>(find.text('12')).style!.color,
          const Color(0xFFAA0000));
      expect(tester.widget<Text>(find.text('+9')).style!.color,
          const Color(0xFF00AA00));
    });

    testWidgets('labels: the count suffixes and the plural come from labels',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWall(
        tester,
        labels: const GiftLabels(
          thousand: ' B',
          wallSummary: 'Hediyeler: {list}',
          wallMore: '{n} tane daha',
          plural: 'lar',
        ),
      );
      await answer(
        tester,
        gifts: <ReceivedGift>[received('rose', 1500), received('heart', 1)],
      );
      await tester.pumpAndSettle();
      expect(counts(tester), <String>['1.5 B', '1']);
      expect(
        find.bySemanticsLabel('Hediyeler: 1,500 Roselar, 1 Heart'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a gift without a picture draws a disc, not a hole',
        (tester) async {
      await pumpWall(tester);
      await answer(
        tester,
        gifts: <ReceivedGift>[received('rose', 2, icon: false)],
      );
      await tester.pumpAndSettle();
      expect(images.requested, isEmpty);
      expect(
        tester.getSize(
          find.descendant(
            of: find.byKey(chipKey('rose')),
            matching: find.byType(GiftPicture),
          ),
        ),
        const Size(20, 20),
      );
    });
  });

  group('requests: one batch, cache, refresh', () {
    testWidgets('three walls on one screen make ONE batch call, in order',
        (tester) async {
      images = ControlledImages(autoLoad: true);
      await images.init(tester);
      await tester.pumpWidget(
        hostApp(
          Column(
            children: <Widget>[
              for (final u in <String>['a', 'b', 'c'])
                GiftWall(
                  client: api,
                  user: u,
                  reference: u == 'b' ? 'post_1' : null,
                  imageProvider: images.call,
                ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 49));
      expect(api.calls, isEmpty, reason: 'the window is still open');
      await tester.pump(const Duration(milliseconds: 1));
      expect(api.calls.length, 1);
      expect(api.calls.single['method'], 'queryGiftWalls');
      final items = (api.calls.single['args']!
          as Map<String, Object?>)['items']! as List<Map<String, Object?>>;
      expect(items, <Map<String, Object?>>[
        <String, Object?>{'receiver': 'a'},
        <String, Object?>{'receiver': 'b', 'reference': 'post_1'},
        <String, Object?>{'receiver': 'c'},
      ]);
      api.take('queryGiftWalls', 'x').completer.complete(
            wallAnswers(items, <ReceivedGift>[received('rose', 1)]),
          );
      await tester.pump();
      expect(find.byKey(_wall), findsNWidgets(3));
    });

    testWidgets('a wall already answered draws at once from the 60 s cache',
        (tester) async {
      var now = 0;
      final loader = GiftWallLoader(
        query: api.queryGiftWalls,
        now: () => now,
      );
      await pumpWall(tester, loader: loader);
      await answer(tester);
      await tester.pumpAndSettle();
      // A second wall of the same user and reference: no skeleton, no request.
      await tester.pumpWidget(
        hostApp(
          GiftWall(
            client: api,
            user: 'mert',
            loader: loader,
            imageProvider: images.call,
          ),
        ),
      );
      expect(find.byKey(_skeleton), findsNothing);
      expect(find.byKey(_wall), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls.length, 1);
      // 60 s later it is asked again.
      now = 60000;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        hostApp(
          GiftWall(
            client: api,
            user: 'mert',
            loader: loader,
            imageProvider: images.call,
          ),
        ),
      );
      expect(find.byKey(_skeleton), findsOneWidget);
      await answer(tester);
      expect(api.calls.length, 2);
    });

    testWidgets('refreshKey: a new key forgets the wall and asks again',
        (tester) async {
      await pumpWall(tester, user: 'refresh', refreshKey: 1);
      await answer(tester, gifts: <ReceivedGift>[received('rose', 1)]);
      await tester.pumpAndSettle();
      expect(counts(tester), <String>['1']);

      // Same key on rebuild: nothing happens.
      await tester.pumpWidget(
        hostApp(
          GiftWall(
            client: api,
            user: 'refresh',
            refreshKey: 1,
            imageProvider: images.call,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.calls.length, 1);

      // Another key: the viewer sent a gift, count it.
      await tester.pumpWidget(
        hostApp(
          GiftWall(
            client: api,
            user: 'refresh',
            refreshKey: 2,
            imageProvider: images.call,
          ),
        ),
      );
      await answer(tester, gifts: <ReceivedGift>[received('rose', 2)]);
      await tester.pumpAndSettle();
      expect(api.calls.length, 2);
      expect(counts(tester), <String>['2']);
    });

    testWidgets('another user or reference loads that wall', (tester) async {
      await pumpWall(tester, user: 'u1');
      await answer(tester, gifts: <ReceivedGift>[received('rose', 1)]);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        hostApp(
          GiftWall(
            client: api,
            user: 'u1',
            reference: 'post_9',
            imageProvider: images.call,
          ),
        ),
      );
      expect(find.byKey(_skeleton), findsOneWidget);
      await answer(tester, gifts: <ReceivedGift>[received('heart', 5)]);
      await tester.pumpAndSettle();
      expect(counts(tester), <String>['5']);
    });

    testWidgets('a late answer after dispose changes nothing', (tester) async {
      final errors = <GiftingException>[];
      await pumpWall(tester, user: 'gone', onError: errors.add);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox());
      api
          .take('queryGiftWalls', 'x')
          .completer
          .completeError(const GiftingException(0, 'network_error', 'x'));
      await tester.pump();
      expect(errors, isEmpty);
    });
  });

  group('tapping and accessibility', () {
    testWidgets('read-only: ONE element for a screen reader, no buttons',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWall(tester, max: 4);
      await answer(tester);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(
        find.bySemanticsLabel(
          'Gifts: 12 Roses, 10 Stars, 9 Hats, and 22 more',
        ),
      );
      expect(
        isSemantics(isButton: true).matches(node, <dynamic, dynamic>{}),
        isFalse,
      );
      // Nothing inside is reachable on its own.
      expect(find.bySemanticsLabel('Rose, 12'), findsNothing);
      handle.dispose();
    });

    testWidgets('onPressChip: each gift chip is a button "Rose, 12"',
        (tester) async {
      final handle = tester.ensureSemantics();
      final pressed = <String>[];
      await pumpWall(tester, onPressChip: (g) => pressed.add(g.id));
      await answer(tester);
      await tester.pumpAndSettle();
      final rose = tester.getSemantics(find.bySemanticsLabel('Rose, 12'));
      expect(isSemantics(isButton: true).matches(rose, <dynamic, dynamic>{}),
          isTrue);
      expect(find.bySemanticsLabel('Star, 10'), findsOneWidget);
      // The overflow chip is read, not pressed.
      final more = tester.getSemantics(find.bySemanticsLabel('and 9 more'));
      expect(isSemantics(isButton: true).matches(more, <dynamic, dynamic>{}),
          isFalse);
      await tester.tap(find.byKey(chipKey('star')));
      await tester
          .tap(find.byKey(const ValueKey<String>('gift-wall-overflow')));
      expect(pressed, <String>['star']);
      handle.dispose();
    });

    testWidgets('a tappable chip has a touch target of at least 44 dp',
        (tester) async {
      final pressed = <String>[];
      await pumpWall(
        tester,
        onPressChip: (g) => pressed.add(g.id),
        size: GiftWallSize.sm,
      );
      await answer(tester);
      await tester.pumpAndSettle();
      final cell = tester.getRect(find.byKey(chipKey('rose')));
      expect(cell.height, greaterThanOrEqualTo(44));
      // 18 dp above the centre of a 20 dp chip is outside the chip, inside
      // the target.
      await tester.tapAt(cell.center + const Offset(0, -20));
      expect(pressed, <String>['rose']);
    });

    testWidgets('the default size without onPressChip keeps the chip height',
        (tester) async {
      await pumpWall(tester);
      await answer(tester);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(chipKey('rose'))).height, 24);
      await tester.tap(find.byKey(chipKey('rose')), warnIfMissed: false);
    });
  });

  group('motion', () {
    double opacity(WidgetTester tester) => tester
        .widget<FadeTransition>(
          find.ancestor(
            of: find.byKey(_wall),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

    testWidgets('data from the network fades in over 120 ms', (tester) async {
      await pumpWall(tester);
      await answer(tester);
      expect(opacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacity(tester), closeTo(0.5, 0.1));
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacity(tester), 1);
    });

    testWidgets('reduced motion (prop and system): no fade', (tester) async {
      await pumpWall(tester, reducedMotion: true);
      await answer(tester);
      expect(opacity(tester), 1);
      await pumpWall(tester, user: 'x', disableAnimations: true);
      await answer(tester);
      expect(opacity(tester), 1);
    });

    testWidgets('preloaded data and cached walls do not fade', (tester) async {
      await pumpWall(tester, data: <ReceivedGift>[received('rose', 2)]);
      expect(opacity(tester), 1);
    });
  });

  group('renderChip slot', () {
    testWidgets('draws its own chip inside the wall; overflow stays default',
        (tester) async {
      final seen = <WallChipContext>[];
      await pumpWall(
        tester,
        renderChip: (context, chip) {
          seen.add(chip);
          return Text('mine ${chip.gift.id} ${chip.countText}');
        },
      );
      await answer(tester);
      await tester.pumpAndSettle();
      expect(find.text('mine rose 12'), findsOneWidget);
      expect(find.byType(GiftPicture), findsNothing, reason: 'no default icon');
      expect(find.text('+9'), findsOneWidget, reason: 'overflow is default');
      expect(seen.map((c) => c.gift.id), <String>[
        'rose', 'star', 'hat', 'cake', 'lion', // overflow is never passed
      ]);
      expect(seen.first.count, 12);
      expect(seen.first.theme, const GiftingTheme());
    });

    testWidgets('null falls back to the default icon and count',
        (tester) async {
      await pumpWall(tester, renderChip: (context, chip) => null);
      await answer(tester);
      await tester.pumpAndSettle();
      expect(counts(tester), <String>['12', '10', '9', '8', '5', '+9']);
      expect(find.byType(GiftPicture), findsNWidgets(5));
    });

    testWidgets('null for some chips only: those draw the default',
        (tester) async {
      await pumpWall(
        tester,
        renderChip: (context, chip) =>
            chip.gift.id == 'rose' ? const Text('custom rose') : null,
      );
      await answer(tester);
      await tester.pumpAndSettle();
      expect(find.text('custom rose'), findsOneWidget);
      expect(find.byType(GiftPicture), findsNWidgets(4));
    });

    testWidgets('the press and the spoken label stay with the SDK',
        (tester) async {
      final handle = tester.ensureSemantics();
      final pressed = <String>[];
      await pumpWall(
        tester,
        renderChip: (context, chip) => Text('mine ${chip.gift.id}'),
        onPressChip: (g) => pressed.add(g.id),
      );
      await answer(tester);
      await tester.pumpAndSettle();
      final rose = tester.getSemantics(find.bySemanticsLabel('Rose, 12'));
      expect(isSemantics(isButton: true).matches(rose, <dynamic, dynamic>{}),
          isTrue);
      await tester.tap(find.text('mine star'));
      expect(pressed, <String>['star']);
      handle.dispose();
    });

    testWidgets('read-only wall keeps its one summary label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWall(
        tester,
        renderChip: (context, chip) => Text('mine ${chip.gift.id}'),
      );
      await answer(tester);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^Gifts: 12 Roses')), findsOneWidget);
      expect(find.bySemanticsLabel('mine rose'), findsNothing);
      handle.dispose();
    });
  });
}
