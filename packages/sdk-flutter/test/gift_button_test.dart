// GiftButton and the tray bound to the app's text field (SPEC 20.3, 20.4):
// the button swaps the keyboard and the tray, a tap on the field closes the
// tray, the tray starts closed, the keyboard height drives the default state,
// and the button's looks. The pure part is in input_swap_conformance_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';

import 'support/scripted_client.dart';
import 'support/ui_harness.dart';

const List<Gift> gifts = <Gift>[
  Gift(id: 'rose', name: 'Rose', price: 10, sortOrder: 1),
  Gift(id: 'hat', name: 'Hat', price: 20, sortOrder: 2),
];

class Api with UnusedComponentCalls implements GiftingClient {
  @override
  Future<List<Gift>> getGifts() async => gifts;

  @override
  Future<Me> getMe() async => const Me(user: 'ayla', balance: 1000);

  @override
  Future<GiftTransaction> sendGift(SendGiftInput input) =>
      throw UnimplementedError();

  @override
  TokenProvider get getToken => throw UnimplementedError();

  @override
  void close() {}
}

const ValueKey<String> fieldKey = ValueKey<String>('field');
const ValueKey<String> trayKey = ValueKey<String>('gift-tray');
const ValueKey<String> circleKey = ValueKey<String>('gift-button-circle');

void main() {
  late FocusNode field;
  late List<double> insets;
  late ValueNotifier<double> keyboard;

  setUp(() {
    field = FocusNode();
    insets = <double>[];
    keyboard = ValueNotifier<double>(0);
  });
  tearDown(() {
    field.dispose();
    keyboard.dispose();
  });

  GiftTrayNotifier makeTray({bool? open, bool bind = true}) {
    final tray = GiftTrayNotifier(
      client: Api(),
      receiver: 'mert',
      input: bind ? field : null,
      open: open,
    );
    addTearDown(tray.dispose);
    return tray;
  }

  /// A chat screen: the tray fills the box above the message bar (text field +
  /// GiftButton); [keyboard] is the MediaQuery's bottom inset.
  Future<void> pumpChat(
    WidgetTester tester,
    GiftTrayNotifier tray, {
    Map<SheetSnap, double?> snaps = const <SheetSnap, double?>{},
    GiftingTheme theme = const GiftingTheme(),
  }) async {
    final images = ControlledImages(autoLoad: true);
    await images.init(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<double>(
          valueListenable: keyboard,
          builder: (context, k, _) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(viewInsets: EdgeInsets.only(bottom: k)),
            child: Material(
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: GiftTray(
                      tray: tray,
                      snaps: snaps,
                      imageProvider: images.call,
                      onInsetChange: insets.add,
                      reducedMotion: true,
                    ),
                  ),
                  SizedBox(
                    height: 56,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(key: fieldKey, focusNode: field),
                        ),
                        GiftButton(tray: tray, theme: theme),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> settleFrames(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  group('GiftTrayNotifier(input:)', () {
    test('a bound field: closed by default; explicit open wins', () {
      expect(makeTray().isOpen, isFalse);
      expect(makeTray().inputBound, isTrue);
      expect(makeTray(open: true).isOpen, isTrue);
      expect(makeTray(bind: false).isOpen, isTrue);
      expect(makeTray(bind: false).inputBound, isFalse);
    });

    test('recordKeyboardHeight keeps the last value from 120 up', () {
      final tray = makeTray();
      expect(tray.keyboardHeight, isNull);
      expect(tray.recordKeyboardHeight(44), isFalse);
      expect(tray.keyboardHeight, isNull);
      expect(tray.recordKeyboardHeight(336), isTrue);
      expect(tray.recordKeyboardHeight(0), isFalse);
      expect(tray.keyboardHeight, 336);
      expect(tray.recordKeyboardHeight(120), isTrue);
      expect(tray.keyboardHeight, 120);
    });

    test('dispose removes the focus listener; a later focus changes nothing',
        () {
      final node = FocusNode();
      addTearDown(node.dispose);
      final tray = GiftTrayNotifier(
        client: Api(),
        receiver: 'mert',
        input: node,
        autoRefresh: false,
        open: true,
      );
      tray.dispose();
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      expect(node.hasListeners, isFalse);
    });
  });

  group('the keyboard swap', () {
    testWidgets(
        'button opens (field loses focus), button again closes and '
        'focuses the field, a tap on the field closes', (tester) async {
      final tray = makeTray();
      await pumpChat(tester, tray);
      expect(tray.isOpen, isFalse);

      await tester.tap(find.byKey(fieldKey));
      await tester.pump();
      expect(field.hasFocus, isTrue);

      await tester.tap(find.byType(GiftButton));
      await tester.pump();
      expect(tray.isOpen, isTrue);
      expect(field.hasFocus, isFalse);

      await tester.tap(find.byType(GiftButton));
      await tester.pump();
      expect(tray.isOpen, isFalse);
      expect(field.hasFocus, isTrue);

      await tester.tap(find.byType(GiftButton));
      await tester.pump();
      expect(tray.isOpen, isTrue);
      expect(field.hasFocus, isFalse);

      await tester.tap(find.byKey(fieldKey));
      await tester.pump();
      expect(tray.isOpen, isFalse, reason: 'the field took focus');
      expect(field.hasFocus, isTrue);
    });

    testWidgets('open() blurs the field; close() does not move focus',
        (tester) async {
      final tray = makeTray();
      await pumpChat(tester, tray);
      field.requestFocus();
      await tester.pump();
      tray.open();
      await tester.pump();
      expect(field.hasFocus, isFalse);
      tray.close();
      await tester.pump();
      expect(field.hasFocus, isFalse);
    });

    testWidgets('the app focusing the field closes the tray', (tester) async {
      final tray = makeTray();
      await pumpChat(tester, tray);
      tray.toggle();
      await tester.pump();
      expect(tray.isOpen, isTrue);
      field.requestFocus();
      await tester.pump();
      expect(tray.isOpen, isFalse);
    });

    testWidgets('without a bound field toggle is a plain toggle',
        (tester) async {
      final tray = makeTray(bind: false, open: false);
      await pumpChat(tester, tray);
      field.requestFocus();
      await tester.pump();
      tray.toggle();
      expect(tray.isOpen, isTrue);
      expect(field.hasFocus, isTrue);
      tray.toggle();
      expect(tray.isOpen, isFalse);
    });

    testWidgets('onPressed runs after the toggle; disabled ignores taps',
        (tester) async {
      final tray = makeTray();
      final seen = <bool>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: <Widget>[
              GiftButton(tray: tray, onPressed: () => seen.add(tray.isOpen)),
              GiftButton(
                key: const ValueKey<String>('off'),
                tray: tray,
                disabled: true,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(GiftButton).first);
      expect(seen, <bool>[true]);
      await tester.tap(find.byKey(const ValueKey<String>('off')));
      expect(tray.isOpen, isTrue);
      expect(
        tester
            .widget<Opacity>(find.descendant(
              of: find.byKey(const ValueKey<String>('off')),
              matching: find.byType(Opacity),
            ))
            .opacity,
        0.5,
      );
    });
  });

  group("the keyboard's place", () {
    double containerHeight(WidgetTester tester) =>
        tester.getSize(find.byType(GiftTray)).height;

    testWidgets('fallback 300 before any keyboard was seen', (tester) async {
      final tray = makeTray();
      await pumpChat(tester, tray);
      tray.toggle();
      await settleFrames(tester);
      expect(tray.keyboardHeight, isNull);
      expect(insets.last, 300);
      final top = tester.getTopLeft(find.byKey(trayKey)).dy;
      expect(containerHeight(tester) - top, closeTo(300, 0.6));
    });

    testWidgets('the last keyboard height seen drives the default state',
        (tester) async {
      final tray = makeTray();
      await pumpChat(tester, tray);
      // The keyboard rises (frames), then goes down (frames).
      for (final k in <double>[100, 220, 336, 336]) {
        keyboard.value = k;
        await tester.pump();
      }
      for (final k in <double>[250, 130, 40, 0]) {
        keyboard.value = k;
        await tester.pump();
      }
      expect(tray.keyboardHeight, 336, reason: 'frames going down are not it');
      tray.toggle();
      await settleFrames(tester);
      expect(insets.last, 336);
    });

    testWidgets('capped at 60 % of the container', (tester) async {
      final tray = makeTray();
      await pumpChat(tester, tray);
      keyboard.value = 700;
      await tester.pump();
      keyboard.value = 0;
      await tester.pump();
      tray.toggle();
      await settleFrames(tester);
      expect(insets.last, (containerHeight(tester) * 0.6).floorToDouble());
    });

    testWidgets("the host's snaps.default wins", (tester) async {
      final tray = makeTray();
      await pumpChat(
        tester,
        tray,
        snaps: const <SheetSnap, double?>{SheetSnap.standard: 0.5},
      );
      keyboard.value = 336;
      await tester.pump();
      keyboard.value = 0;
      await tester.pump();
      tray.toggle();
      await settleFrames(tester);
      expect(
        insets.last,
        closeTo((containerHeight(tester) * 0.5).roundToDouble(), 0.6),
      );
    });

    testWidgets('no scrim by default', (tester) async {
      final tray = makeTray();
      await pumpChat(tester, tray);
      tray.toggle();
      await settleFrames(tester);
      expect(find.byKey(const ValueKey<String>('tray-scrim')), findsNothing);
    });
  });

  group('looks (SPEC 20.4)', () {
    const theme = GiftingTheme();

    BoxDecoration circle(WidgetTester tester, [Finder? within]) => tester
        .widget<Container>(within == null
            ? find.byKey(circleKey)
            : find.descendant(of: within, matching: find.byKey(circleKey)))
        .decoration! as BoxDecoration;

    Color glyph(WidgetTester tester, [Finder? within]) {
      final paint = tester.widget<CustomPaint>(within == null
          ? find.byKey(const ValueKey<String>('gift-button-glyph'))
          : find.descendant(
              of: within,
              matching: find.byKey(const ValueKey<String>('gift-button-glyph')),
            ));
      return (paint.painter! as GiftGlyphPainter).color;
    }

    testWidgets('plain, filled and active colours; size and tap target',
        (tester) async {
      final tray = makeTray();
      const plainKey = ValueKey<String>('plain');
      const filledKey = ValueKey<String>('filled');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: <Widget>[
              GiftButton(key: plainKey, tray: tray, theme: theme),
              GiftButton(
                key: filledKey,
                tray: tray,
                theme: theme,
                filled: true,
              ),
              const GiftButton(size: GiftButtonSize.small),
            ],
          ),
        ),
      );
      final plain = find.byKey(plainKey);
      final filled = find.byKey(filledKey);
      expect(circle(tester, plain).color, const Color(0x00000000));
      expect(glyph(tester, plain), theme.accent);
      expect(circle(tester, filled).color, theme.accent);
      expect(glyph(tester, filled), theme.accentText);
      expect(
          tester.getSize(
              find.descendant(of: plain, matching: find.byKey(circleKey))),
          const Size(36, 36));
      expect(tester.getSize(plain), const Size(44, 44));
      expect(tester.getSize(find.byType(GiftButton).last), const Size(44, 44));

      tray.open();
      await tester.pump();
      for (final b in <Finder>[plain, filled]) {
        expect(circle(tester, b).color, theme.selected);
        expect(glyph(tester, b), theme.accent);
      }
    });

    Widget host(Widget child) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: child),
        );
    const iconKey = ValueKey<String>('gift-button-icon');

    testWidgets('three fixed sizes: circle 32 / 36 / 44, glyph box 22 * d / 36',
        (tester) async {
      const expected = <GiftButtonSize, List<double>>{
        GiftButtonSize.small: <double>[32, 19.6],
        GiftButtonSize.medium: <double>[36, 22],
        GiftButtonSize.large: <double>[44, 26.9],
      };
      for (final e in expected.entries) {
        await tester.pumpWidget(host(GiftButton(size: e.key)));
        expect(tester.getSize(find.byKey(circleKey)),
            Size(e.value[0], e.value[0]));
        final paint = tester.widget<CustomPaint>(
            find.byKey(const ValueKey<String>('gift-button-glyph')));
        expect(paint.size.width, closeTo(e.value[1], 0.05));
        expect(paint.size.height, closeTo(e.value[1], 0.05));
      }
      await tester.pumpWidget(host(const GiftButton()));
      expect(tester.getSize(find.byKey(circleKey)), const Size(36, 36));
    });

    testWidgets('a custom icon is fitted into the glyph box and cannot grow it',
        (tester) async {
      await tester.pumpWidget(host(GiftButton(
        icon: (context, color) => const SizedBox(width: 500, height: 500),
      )));
      expect(tester.getSize(find.byKey(circleKey)), const Size(36, 36));
      expect(tester.getSize(find.byType(GiftButton)), const Size(44, 44));
      expect(tester.getSize(find.byKey(iconKey)), const Size(22, 22));
      expect(find.byKey(const ValueKey<String>('gift-button-glyph')),
          findsNothing);
      // A small icon is not scaled up.
      await tester.pumpWidget(host(GiftButton(
        size: GiftButtonSize.large,
        icon: (context, color) => const SizedBox(
          key: ValueKey<String>('small-icon'),
          width: 10,
          height: 10,
        ),
      )));
      expect(tester.getSize(find.byKey(const ValueKey<String>('small-icon'))),
          const Size(10, 10));
      expect(tester.getSize(find.byKey(iconKey)),
          Size.square(GiftButtonSize.large.glyphBox));
    });

    testWidgets(
        'the icon builder gets accent, accentText (filled), accent (active)',
        (tester) async {
      final tray = makeTray();
      final seen = <String, Color>{};
      Widget button(String name, {bool filled = false}) => GiftButton(
            tray: tray,
            theme: theme,
            filled: filled,
            icon: (context, color) {
              seen[name] = color;
              return const SizedBox(width: 10, height: 10);
            },
          );
      await tester.pumpWidget(host(Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[button('plain'), button('filled', filled: true)],
      )));
      expect(seen['plain'], theme.accent);
      expect(seen['filled'], theme.accentText);
      tray.open();
      await tester.pump();
      expect(seen['plain'], theme.accent);
      expect(seen['filled'], theme.accent);
    });

    testWidgets('without icon the gift glyph is drawn', (tester) async {
      await tester.pumpWidget(host(const GiftButton()));
      expect(find.byKey(const ValueKey<String>('gift-button-glyph')),
          findsOneWidget);
      expect(find.byKey(iconKey), findsNothing);
    });

    testWidgets('semantics: a button with its label and expanded state',
        (tester) async {
      final handle = tester.ensureSemantics();
      final tray = makeTray();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: GiftButton(tray: tray)),
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Send a gift')),
        isSemantics(
          label: 'Send a gift',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasExpandedState: true,
          isExpanded: false,
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      tray.open();
      await tester.pump();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Send a gift')),
        isSemantics(
          label: 'Send a gift',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasExpandedState: true,
          isExpanded: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    test('the glyph repaints only for a new colour', () {
      const a = GiftGlyphPainter(Color(0xff000000));
      expect(
          a.shouldRepaint(const GiftGlyphPainter(Color(0xff000000))), isFalse);
      expect(
          a.shouldRepaint(const GiftGlyphPainter(Color(0xffffffff))), isTrue);
    });
  });
}

/// Loads the catalog, measures the sheet and lets it settle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}
