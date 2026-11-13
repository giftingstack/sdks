// The receiver picker of a battle tray (SPEC 21): the "Send to" row (only
// with two or more receivers), a tap picks the side the next gift goes to, the
// side gifted last is the default, selectReceiver, the peek height counts the
// row, the battle bar's tappable sides (onPressSide) and no change without
// receivers. The pure resolveReceiver is in receivers_conformance_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';

import 'support/component_harness.dart';
import 'support/scripted_client.dart';
import 'support/ui_harness.dart';

const Gift rose = Gift(id: 'rose', name: 'Rose', price: 10, sortOrder: 1);
const Gift hat = Gift(id: 'hat', name: 'Hat', price: 20, sortOrder: 2);

/// Answers at once; records every send. A receiver in [failFor] fails.
class Api with UnusedComponentCalls implements GiftingClient {
  final List<SendGiftInput> sends = <SendGiftInput>[];
  final Set<String> failFor = <String>{};

  @override
  Future<List<Gift>> getGifts() async => const <Gift>[rose, hat];

  @override
  Future<Me> getMe() async => const Me(user: 'ayla', balance: 1000);

  @override
  Future<GiftTransaction> sendGift(SendGiftInput input) async {
    sends.add(input);
    if (failFor.contains(input.receiver)) {
      throw const GiftingException(422, 'invalid_request', 'no');
    }
    return GiftTransaction(
      id: 'gtx_${sends.length}',
      sender: 'ayla',
      receiver: input.receiver,
      gift: GiftRef(id: input.giftId, name: input.giftId),
      quantity: 1,
      unitPrice: 10,
      total: 10,
      status: 'completed',
      createdAt: '2026-11-13T00:00:00Z',
      senderBalanceAfter: 990,
    );
  }

  @override
  TokenProvider get getToken => throw UnimplementedError();

  @override
  void close() {}
}

const List<TrayReceiver> sides = <TrayReceiver>[
  TrayReceiver(id: 'mia', name: 'Mia', color: '#e0457b'),
  TrayReceiver(id: 'theo', name: 'Theo'),
];

const Key _row = ValueKey<String>('gift-send-to');
Key _side(String id) => ValueKey<String>('gift-receiver-$id');

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  late Api api;
  setUp(() => api = Api());

  GiftTrayNotifier makeTray({
    List<TrayReceiver> receivers = const <TrayReceiver>[],
    String receiver = 'host',
    void Function(String id)? onReceiverChange,
  }) {
    final tray = GiftTrayNotifier(
      client: api,
      receiver: receiver,
      receivers: receivers,
      onReceiverChange: onReceiverChange,
    );
    addTearDown(tray.dispose);
    return tray;
  }

  Future<void> pumpTray(
    WidgetTester tester,
    GiftTrayNotifier tray, {
    Size? screen,
  }) async {
    final images = ControlledImages(autoLoad: true);
    await images.init(tester);
    if (screen != null) tester.view.physicalSize = screen;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: GiftTray(
            tray: tray,
            imageProvider: images.call,
            reducedMotion: true,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tapSend(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
    await settle(tester);
  }

  group('GiftTrayNotifier(receivers:)', () {
    test('without receivers: the plain receiver, selectReceiver ignored', () {
      final tray = makeTray();
      expect(tray.receivers, isEmpty);
      expect(tray.receiver, 'host');
      tray.selectReceiver('mia');
      expect(tray.receiver, 'host');
    });

    test('the first side by default; the fallback when it is a side', () {
      expect(makeTray(receivers: sides).receiver, 'mia');
      expect(makeTray(receivers: sides, receiver: 'theo').receiver, 'theo');
    });

    test('selectReceiver picks, ignores unknown ids, reports a change', () {
      final changes = <String>[];
      final tray = makeTray(receivers: sides, onReceiverChange: changes.add);
      tray.selectReceiver('zoe');
      expect(tray.receiver, 'mia');
      tray.selectReceiver('theo');
      tray.selectReceiver('theo');
      expect(tray.receiver, 'theo');
      expect(changes, <String>['theo']);
    });

    test('a new list keeps the pick when it is still in it', () {
      final tray = makeTray(receivers: sides)..selectReceiver('theo');
      tray.receivers = const <TrayReceiver>[
        TrayReceiver(id: 'ava', name: 'Ava'),
        TrayReceiver(id: 'theo', name: 'Theo'),
      ];
      expect(tray.receiver, 'theo');
      tray.receivers = const <TrayReceiver>[
        TrayReceiver(id: 'ava', name: 'Ava'),
        TrayReceiver(id: 'zoe', name: 'Zoe'),
      ];
      expect(tray.receiver, 'ava');
    });

    test(
        'a send goes to the resolved side; the side gifted last stays the '
        'default in the next round', () async {
      final tray = makeTray(receivers: sides);
      await tray.refresh();
      tray.selectReceiver('theo');
      await tray.send(rose);
      expect(api.sends.single.receiver, 'theo');
      // A new round with the same people: no pick, the side gifted last.
      tray.receivers = const <TrayReceiver>[
        TrayReceiver(id: 'mia', name: 'Mia'),
        TrayReceiver(id: 'ava', name: 'Ava'),
        TrayReceiver(id: 'theo', name: 'Theo'),
      ];
      expect(tray.receiver, 'theo');
    });

    test('a failed send does not become the default', () async {
      api.failFor.add('theo');
      final tray = makeTray(receivers: sides);
      await tray.refresh();
      tray
        ..selectReceiver('mia')
        ..selectReceiver('theo');
      await tray.send(rose);
      tray.receivers = const <TrayReceiver>[
        TrayReceiver(id: 'mia', name: 'Mia'),
        TrayReceiver(id: 'theo', name: 'Theo'),
        TrayReceiver(id: 'ava', name: 'Ava'),
      ];
      // The pick is still theo (it is in the list); drop it with a list
      // without theo: last was never set, so the first.
      tray.receivers = const <TrayReceiver>[
        TrayReceiver(id: 'ava', name: 'Ava'),
        TrayReceiver(id: 'zoe', name: 'Zoe'),
      ];
      expect(tray.receiver, 'ava');
    });

    test('the controller sends to the side it is given; receiverOf too',
        () async {
      final asked = <String>[];
      final fx = _Effects();
      final c = GiftTrayController(
        GiftTrayOptions(
          client: api,
          receiver: 'host',
          effects: () => fx,
          receiverOf: (id) {
            asked.add(id);
            return null;
          },
        ),
      );
      await c.refresh();
      expect(await c.send(rose, receiver: 'theo'), isTrue);
      expect(await c.send(rose), isTrue);
      expect(api.sends.map((s) => s.receiver), <String>['theo', 'host']);
      expect(asked, <String>['theo', 'host']);
      api.failFor.add('mia');
      expect(await c.send(rose, receiver: 'mia'), isFalse);
    });
  });

  group('the "Send to" row', () {
    testWidgets('no row without receivers or with one', (tester) async {
      await pumpTray(tester, makeTray());
      expect(find.byKey(_row), findsNothing);
      await tapSend(tester);
      expect(api.sends.single.receiver, 'host');

      await pumpTray(
        tester,
        makeTray(receivers: const <TrayReceiver>[sidesFirst]),
      );
      expect(find.byKey(_row), findsNothing);
      await tapSend(tester);
      expect(api.sends.last.receiver, 'mia');
    });

    testWidgets(
        'two sides: the row, the first picked, a tap picks and the '
        'next send goes there', (tester) async {
      final changes = <String>[];
      final tray = makeTray(receivers: sides, onReceiverChange: changes.add);
      await pumpTray(tester, tray);
      expect(find.byKey(_row), findsOneWidget);
      expect(find.text('Send to'), findsOneWidget);
      // Only the picked side shows its name.
      expect(find.text('Mia'), findsOneWidget);
      expect(find.text('Theo'), findsNothing);
      double opacityOf(String id) => tester
          .widget<Opacity>(
            find.descendant(
              of: find.byKey(_side(id)),
              matching: find.byType(Opacity),
            ),
          )
          .opacity;
      expect(opacityOf('mia'), 1);
      expect(opacityOf('theo'), 0.55);

      final snapBefore = find.byKey(const ValueKey<String>('gift-sheet'));
      final heightBefore = tester.getSize(snapBefore).height;
      await tester.tap(find.byKey(_side('theo')));
      await settle(tester);
      expect(tray.receiver, 'theo');
      expect(changes, <String>['theo']);
      expect(opacityOf('theo'), 1);
      expect(opacityOf('mia'), 0.55);
      expect(find.text('Theo'), findsOneWidget);
      expect(find.text('Mia'), findsNothing);
      // A tap neither sends nor moves the sheet.
      expect(api.sends, isEmpty);
      expect(tester.getSize(snapBefore).height, heightBefore);

      await tapSend(tester);
      expect(api.sends.single.receiver, 'theo');
    });

    testWidgets(
        'the side gifted last is the default; selectReceiver from '
        'app code moves the pick', (tester) async {
      final tray = makeTray(receivers: sides);
      await pumpTray(tester, tray);
      await tester.tap(find.byKey(_side('theo')));
      await settle(tester);
      await tapSend(tester);
      tray.receivers = const <TrayReceiver>[
        TrayReceiver(id: 'ava', name: 'Ava'),
        TrayReceiver(id: 'theo', name: 'Theo'),
        TrayReceiver(id: 'mia', name: 'Mia'),
      ];
      await settle(tester);
      expect(tray.receiver, 'theo');
      tray.selectReceiver('ava');
      await settle(tester);
      await tapSend(tester);
      expect(api.sends.map((s) => s.receiver), <String>['theo', 'ava']);
    });

    testWidgets('a radio group for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTray(tester, makeTray(receivers: sides));
      expect(
        tester.getSemantics(find.byKey(_side('mia'))),
        matchesSemantics(
          label: 'Mia',
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(_side('theo'))),
        matchesSemantics(
          label: 'Theo',
          hasCheckedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    // SPEC 21.3 sizing rule: a phone test at 375 px cut the picked side off.
    const phone = Size(375, 812);

    const Key scroll = ValueKey<String>('gift-send-to-scroll');
    ScrollPosition rowPosition(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(scroll),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    void expectInside(WidgetTester tester, String id, Rect box) {
      final chip = tester.getRect(find.byKey(_side(id)));
      expect(chip.left, greaterThanOrEqualTo(box.left - 0.01), reason: id);
      expect(chip.right, lessThanOrEqualTo(box.right + 0.01), reason: id);
    }

    testWidgets(
        'four sides and a long picked name fit a 375 px phone; only the '
        'picked side shows its name', (tester) async {
      final tray = makeTray(
        receivers: const <TrayReceiver>[
          TrayReceiver(id: 'mia', name: 'Mia'),
          TrayReceiver(id: 'theo', name: 'Theo'),
          TrayReceiver(id: 'ava', name: 'Ava'),
          TrayReceiver(id: 'max', name: 'Maximilian the Great'),
        ],
      )..selectReceiver('max');
      await pumpTray(tester, tray, screen: phone);
      expect(tester.takeException(), isNull);
      expect(rowPosition(tester).maxScrollExtent, 0);
      final row = tester.getRect(find.byKey(_row));
      final box = tester.getRect(find.byKey(scroll));
      expect(row.right, lessThanOrEqualTo(375));
      for (final id in <String>['mia', 'theo', 'ava', 'max']) {
        expectInside(tester, id, row);
        expectInside(tester, id, box);
      }
      expect(find.text('Maximilian the Great'), findsOneWidget);
      for (final name in <String>['Mia', 'Theo', 'Ava']) {
        expect(find.text(name), findsNothing);
      }
      // The picked name ends with "…" after 72 dp.
      expect(
        tester.getSize(find.text('Maximilian the Great')).width,
        lessThanOrEqualTo(72),
      );
    });

    testWidgets(
        'picking a side out of sight scrolls the row (only the row) so the '
        'whole chip is in sight', (tester) async {
      final tray = makeTray(
        receivers: <TrayReceiver>[
          for (var i = 0; i < 8; i++) TrayReceiver(id: 's$i', name: 'Side $i'),
        ],
      );
      await pumpTray(tester, tray, screen: phone);
      final position = rowPosition(tester);
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, 0);
      const grid = ValueKey<String>('gift-grid');
      const sheet = ValueKey<String>('gift-sheet');
      final gridAt = tester.getRect(find.byKey(grid));
      final sheetAt = tester.getRect(find.byKey(sheet));
      final box = tester.getRect(find.byKey(scroll));

      tray.selectReceiver('s7');
      await settle(tester);
      expect(position.pixels, greaterThan(0));
      expectInside(tester, 's7', box);
      expect(tester.getRect(find.byKey(grid)), gridAt);
      expect(tester.getRect(find.byKey(sheet)), sheetAt);

      // Back to the first: the least distance, to the start.
      tray.selectReceiver('s0');
      await settle(tester);
      expect(position.pixels, 0);
      expectInside(tester, 's0', box);
      expect(tester.getRect(find.byKey(sheet)), sheetAt);
    });

    testWidgets('the peek height grows by the row', (tester) async {
      Future<double> peekInset(GiftTrayNotifier tray) async {
        final insets = <double>[];
        final key = GlobalKey<GiftTrayWidgetState>();
        final images = ControlledImages(autoLoad: true);
        await images.init(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: GiftTray(
                key: key,
                tray: tray,
                imageProvider: images.call,
                reducedMotion: true,
                onInsetChange: insets.add,
              ),
            ),
          ),
        );
        await settle(tester);
        key.currentState!.snapTo(SheetSnap.peek);
        await settle(tester);
        return insets.last;
      }

      final plain = await peekInset(makeTray());
      await tester.pumpWidget(const SizedBox());
      final withRow = await peekInset(makeTray(receivers: sides));
      expect(withRow, greaterThan(plain + 30));
    });
  });

  group('GiftBattleBar(onPressSide:)', () {
    BattleView view({int sides = 2}) => BattleView(
          round: 'r1',
          open: true,
          remainingMs: 60000,
          total: 0,
          sides: <BattleSide>[
            for (final id in <String>['mia', 'theo', 'ava'].take(sides))
              BattleSide(id: id, units: 0, gifts: 0, share: 1 / sides),
          ],
          leader: null,
        );
    const users = <String, BattleBarUser>{
      'mia': BattleBarUser(name: 'Mia'),
      'theo': BattleBarUser(name: 'Theo'),
      'ava': BattleBarUser(name: 'Ava'),
    };

    Future<void> pumpBar(
      WidgetTester tester,
      BattleView v, {
      void Function(String id)? onPressSide,
    }) async {
      final images = await loadedImages(tester);
      await tester.pumpWidget(
        hostApp(
          SizedBox(
            width: 358,
            child: GiftBattleBar(
              view: v,
              users: users,
              reducedMotion: true,
              imageProvider: images.call,
              onPressSide: onPressSide,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final n in <int>[2, 3]) {
      testWidgets('$n sides: a press calls onPressSide with the id',
          (tester) async {
        final handle = tester.ensureSemantics();
        final pressed = <String>[];
        await pumpBar(tester, view(sides: n), onPressSide: pressed.add);
        final second = find.byKey(const ValueKey<String>('gift-battle-side-1'));
        expect(second, findsOneWidget);
        final size = tester.getSize(second);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
        await tester.tap(second);
        await tester.tap(
          find.byKey(const ValueKey<String>('gift-battle-side-0')),
        );
        expect(pressed, <String>['theo', 'mia']);
        expect(find.bySemanticsLabel('Send Theo a gift'), findsOneWidget);
        handle.dispose();
      });
    }

    testWidgets('pressSideLabel replaces {name}', (tester) async {
      final handle = tester.ensureSemantics();
      final images = await loadedImages(tester);
      await tester.pumpWidget(
        hostApp(
          SizedBox(
            width: 358,
            child: GiftBattleBar(
              view: view(),
              users: users,
              imageProvider: images.call,
              onPressSide: (_) {},
              pressSideLabel: 'Gift {name}',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Gift Mia'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('without onPressSide: no buttons, one read-only element',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBar(tester, view());
      expect(
        find.byKey(const ValueKey<String>('gift-battle-side-0')),
        findsNothing,
      );
      expect(find.bySemanticsLabel(RegExp('a gift')), findsNothing);
      final node = tester.getSemantics(
        find.byKey(const ValueKey<String>('gift-battle-bar')),
      );
      var children = 0;
      node.visitChildren((_) {
        children++;
        return true;
      });
      expect(children, 0);
      handle.dispose();
    });
  });
}

const TrayReceiver sidesFirst = TrayReceiver(id: 'mia', name: 'Mia');

class _Effects implements EffectPlayer {
  @override
  int play(GiftEffectEvent event) => 1;

  @override
  void cancel(int id) {}
}
