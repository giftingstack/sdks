// Widget tests of GiftTray and GiftTrayNotifier.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack/src/ui/effect_item.dart';

import 'support/scripted_client.dart';
import 'support/ui_harness.dart';

const Gift rose = Gift(
  id: 'rose',
  name: 'Rose',
  price: 10,
  sortOrder: 1,
  iconUrl: 'https://assets.test/rose/256.webp',
  animationUrl: 'https://assets.test/rose/512.webp',
);
const Gift hat = Gift(
  id: 'hat',
  name: 'Hat',
  price: 350,
  sortOrder: 2,
  iconUrl: 'https://assets.test/hat/256.webp',
  animationUrl: 'https://assets.test/hat/512.webp',
);
const Gift dragon = Gift(
  id: 'dragon',
  name: 'Dragon',
  price: 40000,
  sortOrder: 3,
  iconUrl: 'https://assets.test/dragon/256.webp',
);
const Gift plain = Gift(id: 'plain', name: 'Plain', price: 5, sortOrder: 4);

Widget host(Widget tray) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Align(alignment: Alignment.bottomCenter, child: tray),
      ),
    );

String balanceText(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey<String>('gift-balance-text')))
    .data!;

/// What the semantics tree says about the tray's cells.
bool checked(WidgetTester tester, String label) {
  final node = tester.getSemantics(find.bySemanticsLabel(label));
  return isSemantics(isChecked: true).matches(node, <dynamic, dynamic>{});
}

void main() {
  late ControlledImages images;

  Future<void> pumpTray(
    WidgetTester tester, {
    List<Gift> gifts = const <Gift>[rose, hat, dragon],
    int balance = 1000,
    FutureOr<void> Function(Gift)? onSend,
    VoidCallback? onTopUp,
    bool disabled = false,
    String? defaultSelectedId,
    double gridMaxHeight = 230,
  }) async {
    images = ControlledImages();
    await images.init(tester);
    await tester.pumpWidget(
      host(
        GiftTray(
          sheet: false, // these tests are about the fixed tray (SPEC 9)
          gifts: gifts,
          balance: balance,
          onSend: onSend ?? (_) {},
          onTopUp: onTopUp,
          disabled: disabled,
          defaultSelectedId: defaultSelectedId,
          gridMaxHeight: gridMaxHeight,
          imageProvider: images.call,
        ),
      ),
    );
  }

  group('selection and sending', () {
    testWidgets('first gift selected; tapping a cell selects it; Send sends it',
        (tester) async {
      final handle = tester.ensureSemantics();
      final sent = <String>[];
      await pumpTray(tester, onSend: (g) => sent.add(g.id));
      expect(checked(tester, 'Rose, 10 coins'), isTrue);
      expect(checked(tester, 'Hat, 350 coins'), isFalse);
      expect(find.text('Send'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('gift-hat')));
      await tester.pump();
      expect(checked(tester, 'Rose, 10 coins'), isFalse);
      expect(checked(tester, 'Hat, 350 coins'), isTrue);

      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      expect(sent, <String>['hat', 'hat'], reason: 'tap again for a combo');
      handle.dispose();
    });

    testWidgets('defaultSelectedId; an unknown selection shows the first',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTray(tester, defaultSelectedId: 'hat');
      expect(checked(tester, 'Hat, 350 coins'), isTrue);
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
      await pumpTray(tester, defaultSelectedId: 'nope');
      final h2 = tester.ensureSemantics();
      expect(checked(tester, 'Rose, 10 coins'), isTrue);
      h2.dispose();
    });

    testWidgets('formats prices and balance with en-US grouping',
        (tester) async {
      await pumpTray(tester, balance: 1234567);
      expect(find.text('40,000'), findsOneWidget);
      expect(balanceText(tester), '1,234,567');
    });

    testWidgets('a gift without an icon shows a placeholder, not an error',
        (tester) async {
      await pumpTray(tester, gifts: const <Gift>[plain]);
      expect(find.text('5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the grid scrolls beyond gridMaxHeight', (tester) async {
      final many = <Gift>[
        for (var i = 0; i < 24; i++)
          Gift(id: 'g$i', name: 'G$i', price: i + 1, sortOrder: i),
      ];
      await pumpTray(tester, gifts: many, gridMaxHeight: 230);
      expect(
        tester.getSize(find.byType(SingleChildScrollView)).height,
        lessThanOrEqualTo(230),
      );
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
    });
  });

  group('insufficient balance', () {
    testWidgets('too expensive without a store: Not enough coins, off',
        (tester) async {
      final sent = <String>[];
      await pumpTray(
        tester,
        balance: 100,
        defaultSelectedId: 'hat',
        onSend: (g) => sent.add(g.id),
      );
      expect(find.text('Not enough coins'), findsOneWidget);
      expect(find.text('+ Coins'), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      expect(sent, isEmpty);
    });

    testWidgets('too expensive with a store: Get coins opens it, never sends',
        (tester) async {
      final sent = <String>[];
      var topups = 0;
      await pumpTray(
        tester,
        balance: 100,
        defaultSelectedId: 'hat',
        onSend: (g) => sent.add(g.id),
        onTopUp: () => topups++,
      );
      expect(find.text('Get coins'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      expect(topups, 1);
      expect(sent, isEmpty);
      // The small gift is affordable again: Send.
      await tester.tap(find.byKey(const ValueKey<String>('gift-rose')));
      await tester.pump();
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('+ Coins only with onTopUp, and it calls onTopUp',
        (tester) async {
      var topups = 0;
      await pumpTray(tester, onTopUp: () => topups++);
      await tester.tap(find.byKey(const ValueKey<String>('gift-topup')));
      expect(topups, 1);
      expect(find.text('+ Coins'), findsOneWidget);
    });

    testWidgets('disabled: Send does nothing, Get coins does nothing',
        (tester) async {
      final sent = <String>[];
      var topups = 0;
      await pumpTray(
        tester,
        disabled: true,
        onSend: (g) => sent.add(g.id),
        onTopUp: () => topups++,
      );
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      expect(sent, isEmpty);
      await tester.tap(find.byKey(const ValueKey<String>('gift-hat')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('gift-dragon')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      expect(topups, 0, reason: 'disabled and too expensive: off');
    });

    testWidgets('semantics: send button label names the gift', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTray(tester, balance: 100, defaultSelectedId: 'hat');
      expect(find.bySemanticsLabel('Not enough coins: Hat'), findsOneWidget);
      expect(find.bySemanticsLabel('Balance: 100 coins'), findsOneWidget);
      handle.dispose();
    });
  });

  group('balance count-up', () {
    testWidgets('counts from the old to the new value over 600 ms',
        (tester) async {
      await pumpTray(tester, balance: 1000);
      expect(balanceText(tester), '1,000');
      await tester.pumpWidget(
        host(
          GiftTray(
            sheet: false, // these tests are about the fixed tray (SPEC 9)
            gifts: const <Gift>[rose],
            balance: 2000,
            onSend: (_) {},
            imageProvider: images.call,
          ),
        ),
      );
      expect(balanceText(tester), '1,000', reason: 'starts from the old value');
      await tester.pump(const Duration(milliseconds: 150));
      final mid = int.parse(balanceText(tester).replaceAll(',', ''));
      expect(mid, greaterThan(1000));
      expect(mid, lessThan(2000));
      await tester.pump(const Duration(milliseconds: 300));
      final late = int.parse(balanceText(tester).replaceAll(',', ''));
      expect(late, greaterThan(mid));
      await tester.pump(const Duration(milliseconds: 200));
      expect(balanceText(tester), '2,000');
      await tester.pumpAndSettle();
      expect(balanceText(tester), '2,000');
    });

    testWidgets(
        'counts down, and a new target mid-count starts from what shows',
        (tester) async {
      await pumpTray(tester, balance: 1000);
      Future<void> setBalance(int b) => tester.pumpWidget(
            host(
              GiftTray(
                sheet: false, // these tests are about the fixed tray (SPEC 9)
                gifts: const <Gift>[rose],
                balance: b,
                onSend: (_) {},
                imageProvider: images.call,
              ),
            ),
          );
      await setBalance(990);
      await tester.pump(const Duration(milliseconds: 100));
      final v = int.parse(balanceText(tester));
      expect(v, inInclusiveRange(990, 1000));
      await setBalance(980);
      final restart = int.parse(balanceText(tester));
      expect(restart, closeTo(v, 1), reason: 'no jump back to the old target');
      await tester.pumpAndSettle();
      expect(balanceText(tester), '980');
    });
  });

  group('prefetch', () {
    testWidgets('every icon, and the selected gift big picture',
        (tester) async {
      await pumpTray(tester);
      expect(
        images.requested,
        containsAll(<String>[
          'https://assets.test/rose/256.webp',
          'https://assets.test/hat/256.webp',
          'https://assets.test/dragon/256.webp',
          'https://assets.test/rose/512.webp',
        ]),
      );
      expect(
        images.requested,
        isNot(contains('https://assets.test/hat/512.webp')),
        reason: 'only the selected gift big picture is warmed',
      );
      await tester.tap(find.byKey(const ValueKey<String>('gift-hat')));
      await tester.pump();
      expect(images.requested, contains('https://assets.test/hat/512.webp'));
      // A gift without a big picture warms its icon instead (already requested).
      await tester.tap(find.byKey(const ValueKey<String>('gift-dragon')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('GiftTrayNotifier with a layer', () {
    testWidgets('tap: optimistic coins and effect now; failure takes both back',
        (tester) async {
      images = ControlledImages(autoLoad: true);
      await images.init(tester);
      final api = FakeApi();
      final fx = GiftEffectController();
      final tray = GiftTrayNotifier(
        client: api,
        receiver: 'mert',
        effects: fx,
        imageProvider: images.call,
      );
      addTearDown(tray.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: tray,
                    builder: (context, _) => Align(
                      alignment: Alignment.bottomCenter,
                      child: GiftTray(
                        sheet: false,
                        gifts: tray.gifts,
                        balance: tray.balance,
                        onSend: tray.send,
                        imageProvider: images.call,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: GiftEffectLayer(
                    controller: fx,
                    remoteRecipes: false,
                    imageProvider: images.call,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(tray.loading, isTrue);
      api.gifts.complete(<Gift>[rose, hat]);
      api.me.complete(const Me(user: 'ayla', balance: 1000));
      await tester.pump();
      await tester.pump();
      expect(tray.loading, isFalse);
      await tester.pump(const Duration(milliseconds: 700)); // counts up from 0
      expect(balanceText(tester), '1,000');

      // Tap Send on the rose.
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      await tester.pump();
      expect(tray.balance, 990, reason: 'coins move with the tap');
      expect(find.byType(EffectItem), findsOneWidget, reason: 'effect at tap');

      // The server refuses: the effect and the coins come back.
      api.sends.single.completeError(
        const GiftingException(422, 'insufficient_balance', 'no'),
      );
      await tester.pump();
      await tester.pump();
      expect(tray.balance, 1000);
      expect(tray.error?.insufficientBalance, isTrue);
      expect(find.byType(EffectItem), findsNothing, reason: 'cancelled');

      // Settle: the reconcile getMe is pending; answer it.
      api.mes.last.complete(const Me(user: 'ayla', balance: 1000));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('success: coins stay taken, effect plays out, onSent runs',
        (tester) async {
      images = ControlledImages(autoLoad: true);
      await images.init(tester);
      final api = FakeApi();
      final fx = GiftEffectController();
      final sent = <String>[];
      final tray = GiftTrayNotifier(
        client: api,
        receiver: 'mert',
        effects: fx,
        reference: 'post_1',
        onSent: (tx) => sent.add(tx.id),
        imageProvider: images.call,
      );
      addTearDown(tray.dispose);
      await tester.pumpWidget(
        layerApp(controller: fx, images: images),
      );
      api.gifts.complete(<Gift>[rose, hat]);
      api.me.complete(const Me(user: 'ayla', balance: 1000));
      await tester.pump();
      unawaited(tray.send(rose));
      await tester.pump();
      expect(find.byType(EffectItem), findsOneWidget);
      api.sends.single.complete(
        const GiftTransaction(
          id: 'gtx_1',
          sender: 'ayla',
          receiver: 'mert',
          gift: GiftRef(id: 'rose', name: 'Rose'),
          quantity: 1,
          unitPrice: 10,
          total: 10,
          status: 'completed',
          createdAt: '2026-10-10T00:00:00Z',
          senderBalanceAfter: 990,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(sent, <String>['gtx_1']);
      expect(api.lastSend?.reference, 'post_1');
      expect(api.lastSend?.receiver, 'mert');
      expect(tray.balance, 990);
      api.mes.last.complete(const Me(user: 'ayla', balance: 990));
      await tester.pump();
      for (var t = 0; t < 5000; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(EffectItem), findsNothing);
    });

    test('open, close, toggle, isOpen and onOpenChange (SPEC 9.4)', () {
      final changes = <bool>[];
      final tray = GiftTrayNotifier(
        client: FakeApi(),
        receiver: 'mert',
        autoRefresh: false,
        open: false,
        onOpenChange: changes.add,
      );
      addTearDown(tray.dispose);
      var notified = 0;
      tray.addListener(() => notified++);
      expect(tray.isOpen, isFalse);
      tray.toggle();
      expect(tray.isOpen, isTrue);
      tray.open();
      tray.toggle();
      tray.close();
      expect(tray.isOpen, isFalse);
      expect(changes, <bool>[true, false]);
      expect(notified, 2);
    });

    test('a tray is open by default', () {
      final tray = GiftTrayNotifier(
        client: FakeApi(),
        receiver: 'mert',
        autoRefresh: false,
      );
      addTearDown(tray.dispose);
      expect(tray.isOpen, isTrue);
    });

    testWidgets('dispose: late answers change nothing and notify nobody',
        (tester) async {
      final api = FakeApi();
      final tray = GiftTrayNotifier(client: api, receiver: 'mert');
      var notified = 0;
      tray.addListener(() => notified++);
      tray.dispose();
      api.gifts.complete(<Gift>[rose]);
      api.me.complete(const Me(user: 'ayla', balance: 5));
      await tester.pump();
      expect(notified, 0);
    });
  });

  group('test mode badge', () {
    const badge = ValueKey<String>('gift-test-mode');

    testWidgets('shown only with testMode, in capitals, with your label',
        (tester) async {
      Future<void> pump({required bool testMode, String? label}) async {
        images = ControlledImages();
        await images.init(tester);
        await tester.pumpWidget(
          host(
            GiftTray(
              sheet: false,
              gifts: const <Gift>[rose],
              balance: 10,
              onSend: (_) {},
              testMode: testMode,
              testModeLabel: label ?? 'Test mode',
              imageProvider: images.call,
            ),
          ),
        );
      }

      await pump(testMode: false);
      expect(find.byKey(badge), findsNothing);
      await pump(testMode: true);
      expect(find.byKey(badge), findsOneWidget);
      expect(find.text('TEST MODE'), findsOneWidget);
      await pump(testMode: true, label: 'Deneme');
      expect(find.text('DENEME'), findsOneWidget);
    });

    testWidgets(
        'GiftTray(tray:) shows the badge by itself while the token is a test '
        'token; the testMode parameter overrides it', (tester) async {
      for (final (livemode, shown) in <(bool?, bool)>[
        (false, true),
        (true, false),
        (null, false),
      ]) {
        final api = FakeApi();
        final tray = GiftTrayNotifier(
          client: api,
          receiver: 'mert',
          prefetch: (_) {},
        );
        images = ControlledImages();
        await images.init(tester);
        Future<void> pump({bool? testMode}) => tester.pumpWidget(
              host(
                GiftTray(
                  sheet: false,
                  tray: tray,
                  testMode: testMode,
                  imageProvider: images.call,
                ),
              ),
            );
        await pump();
        expect(find.byKey(badge), findsNothing, reason: 'before the answer');
        api.gifts.complete(<Gift>[rose]);
        api.me.complete(Me(user: 'ayla', balance: 5, livemode: livemode));
        await tester.pump();
        await tester.pump();
        expect(find.byKey(badge), shown ? findsOneWidget : findsNothing,
            reason: 'livemode: $livemode');
        // The gifts and the balance came from the notifier too.
        await tester.pump(const Duration(seconds: 1)); // the count-up
        expect(find.byKey(const ValueKey<String>('gift-rose')), findsOneWidget);
        expect(balanceText(tester), '5');
        await pump(testMode: false);
        expect(find.byKey(badge), findsNothing, reason: 'false forces it off');
        await pump(testMode: true);
        expect(find.byKey(badge), findsOneWidget, reason: 'true forces it on');
        await tester.pumpWidget(const SizedBox());
        tray.dispose();
      }
    });

    testWidgets('GiftTrayNotifier.testMode follows me.livemode',
        (tester) async {
      for (final (livemode, expected) in <(bool?, bool)>[
        (false, true),
        (true, false),
        (null, false),
      ]) {
        final api = FakeApi();
        final tray = GiftTrayNotifier(
          client: api,
          receiver: 'mert',
          prefetch: (_) {},
        );
        expect(tray.testMode, isFalse);
        api.gifts.complete(<Gift>[rose]);
        api.me.complete(Me(user: 'ayla', balance: 5, livemode: livemode));
        await tester.pump();
        expect(tray.testMode, expected, reason: 'livemode: $livemode');
        tray.dispose();
      }
    });

    test('Me reads and writes livemode; absent stays absent', () {
      final test = Me.fromJson(
        <String, Object?>{'user': 'a', 'balance': 1, 'livemode': false},
      );
      expect(test.livemode, isFalse);
      expect(test.toJson()['livemode'], isFalse);
      final old = Me.fromJson(<String, Object?>{'user': 'a', 'balance': 1});
      expect(old.livemode, isNull);
      expect(old.toJson().containsKey('livemode'), isFalse);
    });
  });
}

/// A client whose calls the test answers.
class FakeApi with UnusedComponentCalls implements GiftingClient {
  final Completer<List<Gift>> gifts = Completer<List<Gift>>();
  final Completer<Me> me = Completer<Me>();
  final List<Completer<GiftTransaction>> sends = <Completer<GiftTransaction>>[];
  final List<Completer<Me>> mes = <Completer<Me>>[];
  SendGiftInput? lastSend;
  int _meCalls = 0;

  @override
  Future<List<Gift>> getGifts() => gifts.future;

  @override
  Future<Me> getMe() {
    if (_meCalls++ == 0) return me.future;
    final c = Completer<Me>();
    mes.add(c);
    return c.future;
  }

  @override
  Future<GiftTransaction> sendGift(SendGiftInput input) {
    lastSend = input;
    final c = Completer<GiftTransaction>();
    sends.add(c);
    return c.future;
  }

  @override
  TokenProvider get getToken => throw UnimplementedError();

  @override
  void close() {}
}
