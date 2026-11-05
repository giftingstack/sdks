// Widget tests of the tray as a bottom sheet (SPEC 9.1): the layout it
// measures, the three states, drag / flick / tap / accessibility, the nested
// scroll of the grid, taps after a drag, and the theme. The pure decisions are
// in sheet_conformance_test.dart; what these prove is that the widget feeds the
// controller the right numbers and draws what it says. Feel on a real phone
// is not tested here.
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';

import 'support/ui_harness.dart';

List<Gift> catalog(int n) => <Gift>[
      for (var i = 0; i < n; i++)
        Gift(
          id: 'g$i',
          name: 'Gift $i',
          price: 10 + i,
          sortOrder: i,
          iconUrl: 'https://assets.test/g$i/256.webp',
        ),
    ];

const ValueKey<String> trayKey = ValueKey<String>('gift-tray');
const ValueKey<String> footerKey = ValueKey<String>('gift-footer');
const ValueKey<String> gridKey = ValueKey<String>('gift-grid');
const ValueKey<String> handleKey = ValueKey<String>('gift-handle');

class Harness {
  final List<SheetSnap> snaps = <SheetSnap>[];
  final List<double> insets = <double>[];
  final List<String> sent = <String>[];
  int underTaps = 0;
  GiftingTheme theme = const GiftingTheme();
}

void main() {
  late ControlledImages images;
  late Harness h;

  Future<void> pump(
    WidgetTester tester, {
    int gifts = 90,
    SheetSnap initialSnap = SheetSnap.standard,
    Map<SheetSnap, double?> snaps = const <SheetSnap, double?>{},
    bool reducedMotion = false,
    GiftingTheme? theme,
    Size size = const Size(400, 800),
    VoidCallback? onTopUp,
    int balance = 100000,
    bool collapseOnSelect = false,
    GlobalKey<GiftTrayWidgetState>? key,
    bool scrim = false,
    ScrimTap scrimTap = ScrimTap.lower,
    VoidCallback? onDismiss,
    ValueNotifier<bool>? openNotifier,
  }) async {
    images = ControlledImages();
    await images.init(tester);
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => h.underTaps++,
                ),
              ),
              Positioned.fill(
                child: ValueListenableBuilder<bool>(
                  valueListenable: openNotifier ?? ValueNotifier<bool>(true),
                  builder: (context, open, _) => GiftTray(
                    key: key,
                    collapseOnSelect: collapseOnSelect,
                    gifts: catalog(gifts),
                    balance: balance,
                    onSend: (g) => h.sent.add(g.id),
                    onTopUp: onTopUp,
                    initialSnap: initialSnap,
                    snaps: snaps,
                    reducedMotion: reducedMotion,
                    theme: theme ?? const GiftingTheme(),
                    imageProvider: images.call,
                    onSnapChange: h.snaps.add,
                    onInsetChange: h.insets.add,
                    scrim: scrim,
                    scrimTap: scrimTap,
                    onDismiss: onDismiss,
                    open: openNotifier == null ? null : open,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Layout, the post-frame measurement, the controller, the first frame.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // The sheet fades and slides in (220 ms) once it is placed; let that finish.
    await tester.pump(const Duration(milliseconds: 300));
  }

  setUp(() => h = Harness());

  double top(WidgetTester tester) => tester.getTopLeft(find.byKey(trayKey)).dy;
  double row(WidgetTester tester) =>
      tester.getSize(find.byKey(const ValueKey<String>('gift-g0'))).height;
  double footerHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(footerKey)).height;
  double gridTop(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(gridKey)).dy - top(tester);
  double peekHeight(WidgetTester tester) =>
      gridTop(tester) + footerHeight(tester);

  /// The spring's ticker starts on the first frame after the change, so one
  /// frame to start it and then the time it needs.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  /// A drag with timestamps, so the velocity is what the test says (px/s).
  Future<void> dragFrom(
    WidgetTester tester,
    Offset from,
    double dy, {
    double velocity = 100,
    bool release = true,
  }) async {
    final gesture = await tester.createGesture();
    await gesture.down(from, timeStamp: Duration.zero);
    final steps = 10;
    final dt = (dy.abs() / velocity * 1000 / steps).round().clamp(1, 100000);
    for (var i = 1; i <= steps; i++) {
      await gesture.moveBy(
        Offset(0, dy / steps),
        timeStamp: Duration(milliseconds: dt * i),
      );
      await tester.pump(Duration(milliseconds: dt));
    }
    if (release) {
      await gesture.up(timeStamp: Duration(milliseconds: dt * steps));
      await settle(tester);
    }
  }

  group('an empty catalog', () {
    testWidgets('the sheet still becomes visible, at its peek height',
        (tester) async {
      await pump(tester, gifts: 0, balance: 0);
      expect(tester.takeException(), isNull);
      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(const ValueKey<String>('gift-sheet')),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 1, reason: 'shown, not stuck waiting for a row');
      expect(find.byKey(footerKey), findsOneWidget);
      // Peek height: the handle, the header and the footer; no grid rows.
      expect(800 - top(tester), closeTo(peekHeight(tester), 0.6));
      expect(h.insets, isNotEmpty);
    });

    testWidgets('gifts arriving later grow the sheet to the default state',
        (tester) async {
      final images = ControlledImages();
      await images.init(tester);
      tester.view.physicalSize = const Size(400, 800);
      final inserts = ValueNotifier<int>(0);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: ValueListenableBuilder<int>(
              valueListenable: inserts,
              builder: (_, n, __) => GiftTray(
                gifts: catalog(n),
                balance: 100,
                onSend: (_) {},
                imageProvider: images.call,
                onInsetChange: h.insets.add,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      final emptyInset = h.insets.last;
      inserts.value = 12;
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(h.insets.last, greaterThan(emptyInset));
      expect(tester.takeException(), isNull);
    });
  });

  group('layout', () {
    testWidgets('opens in the default state: peek content plus two rows',
        (tester) async {
      await pump(tester);
      expect(tester.takeException(), isNull);
      final peek = peekHeight(tester);
      expect(row(tester), greaterThan(0));
      final visible = 800 - top(tester);
      expect(visible, closeTo(peek + 2 * row(tester), 0.6));
      expect(h.insets.last, closeTo(visible, 0.6));
      expect(h.snaps, isEmpty); // opening is not a change
    });

    testWidgets('expanded is 90 % of the container (the default fraction)',
        (tester) async {
      await pump(tester, initialSnap: SheetSnap.expanded);
      expect(800 - top(tester), closeTo(720, 0.6));
      expect(h.insets.last, 720);
    });

    testWidgets('peek shows the handle, header and footer only',
        (tester) async {
      await pump(tester, initialSnap: SheetSnap.peek);
      final peek = peekHeight(tester);
      expect(800 - top(tester), closeTo(peek, 0.6));
      expect(h.insets.last, closeTo(peek, 0.6));
    });

    testWidgets('a few gifts: expanded never exceeds the content',
        (tester) async {
      await pump(tester, gifts: 4, initialSnap: SheetSnap.expanded);
      final peek = peekHeight(tester);
      // 4 gifts = one row; default and expanded are both peek + 1 row... but
      // default is at least peek + min(2, rows) rows = 1 row here.
      expect(800 - top(tester), closeTo(peek + row(tester), 0.6));
    });

    testWidgets('snaps fractions are honoured', (tester) async {
      await pump(
        tester,
        initialSnap: SheetSnap.expanded,
        snaps: const <SheetSnap, double?>{SheetSnap.expanded: 0.6},
      );
      expect(800 - top(tester), closeTo(480, 0.6));
    });

    testWidgets('icons are bigger than 48: min(72, 78 % of the cell)',
        (tester) async {
      await pump(tester);
      final icon = tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey<String>('gift-g0')),
          matching: find.byType(Image),
        ),
      );
      // 400 wide, the sheet's hairline edges (0.5 each side) and 14 padding.
      final cell = (400 - 1 - 28) / 4;
      expect(icon.width, closeTo(0.78 * (cell - 8 - 3), 0.01));
      expect(icon.width, greaterThan(48));
      expect(icon.width, lessThanOrEqualTo(72));
      expect(icon.height, icon.width);
    });

    testWidgets('a wide cell caps the icon at 72', (tester) async {
      await pump(tester, size: const Size(900, 700));
      final icon = tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey<String>('gift-g0')),
          matching: find.byType(Image),
        ),
      );
      expect(icon.width, 72);
    });

    testWidgets('touches above the sheet reach the screen behind it',
        (tester) async {
      await pump(tester);
      await tester.tapAt(const Offset(200, 100));
      expect(h.underTaps, 1);
      // and not below its top edge
      await tester.tapAt(Offset(200, top(tester) + 8));
      expect(h.underTaps, 1);
    });
  });

  group('gestures', () {
    testWidgets('drag the header down: the sheet follows, release goes to peek',
        (tester) async {
      await pump(tester);
      final start = top(tester);
      final header = tester.getCenter(find.text('Send a gift'));
      await dragFrom(tester, header, 200, velocity: 100, release: false);
      // The sheet moved with the finger (200 px, clamped at peek).
      expect(top(tester), greaterThan(start + 50));
      final gesture = await tester.startGesture(header); // a second finger
      await gesture.up();
      await tester.pump();
    });

    testWidgets(
        'a slow drag down past the middle settles on peek, one up opens default',
        (tester) async {
      await pump(tester);
      final peek = peekHeight(tester);
      final header = tester.getCenter(find.text('Send a gift'));
      await dragFrom(tester, header, 300);
      expect(h.snaps, <SheetSnap>[SheetSnap.peek]);
      expect(800 - top(tester), closeTo(peek, 0.6));
      expect(h.insets.last, closeTo(peek, 0.6));
      // Back up with a slow drag by about one row and a half: nearest is default.
      final handle = tester.getCenter(find.byKey(handleKey));
      await dragFrom(tester, handle, -(2 * row(tester)));
      expect(h.snaps.last, SheetSnap.standard);
    });

    testWidgets('a fast flick up from peek opens ONE state, not two',
        (tester) async {
      await pump(tester, initialSnap: SheetSnap.peek);
      final handle = tester.getCenter(find.byKey(handleKey));
      await dragFrom(tester, handle, -40, velocity: 2000);
      expect(h.snaps, <SheetSnap>[SheetSnap.standard]);
    });

    testWidgets(
        'a flick of 600 px/s counts, 599 does not (from default, small drag)',
        (tester) async {
      await pump(tester);
      final handle = tester.getCenter(find.byKey(handleKey));
      await dragFrom(tester, handle, -24, velocity: 2000);
      expect(h.snaps.last, SheetSnap.expanded);
      h.snaps.clear();
      await dragFrom(tester, tester.getCenter(find.byKey(handleKey)), 24,
          velocity: 120);
      // slow and short: nearest state is where it started (expanded)
      expect(h.snaps, isEmpty);
    });

    testWidgets('tapping the handle toggles default -> peek -> default',
        (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(handleKey));
      await settle(tester);
      expect(h.snaps, <SheetSnap>[SheetSnap.peek]);
      await tester.tap(find.byKey(handleKey));
      await settle(tester);
      expect(h.snaps, <SheetSnap>[SheetSnap.peek, SheetSnap.standard]);
    });

    testWidgets(
        'collapseOnSelect: picking a gift lowers the sheet to peek, the handle '
        'brings the grid back, and snapTo moves it from code', (tester) async {
      final key = GlobalKey<GiftTrayWidgetState>();
      await pump(tester, collapseOnSelect: true, key: key);
      await tester.tap(find.byKey(const ValueKey<String>('gift-g5')));
      await settle(tester);
      expect(h.snaps, <SheetSnap>[SheetSnap.peek]);
      // The picked gift is the one Send sends.
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      await tester.pump();
      expect(h.sent, <String>['g5']);
      await tester.tap(find.byKey(handleKey));
      await settle(tester);
      expect(h.snaps, <SheetSnap>[SheetSnap.peek, SheetSnap.standard]);
      key.currentState!.snapTo(SheetSnap.peek);
      await settle(tester);
      expect(h.snaps.last, SheetSnap.peek);
    });

    testWidgets('without collapseOnSelect a pick leaves the sheet where it is',
        (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey<String>('gift-g5')));
      await settle(tester);
      expect(h.snaps, isEmpty);
    });

    testWidgets('a drag that starts on a cell is a drag, not a tap',
        (tester) async {
      await pump(tester);
      final cell = find.byKey(const ValueKey<String>('gift-g5'));
      await dragFrom(tester, tester.getCenter(cell), 160, velocity: 100);
      // The sheet moved; the cell under the finger was not selected.
      expect(h.snaps, isNotEmpty);
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      await tester.pump();
      expect(h.sent, <String>['g0']); // still the first gift
    });

    testWidgets('a press below the slop stays a tap on the cell',
        (tester) async {
      await pump(tester);
      final cell = find.byKey(const ValueKey<String>('gift-g5'));
      final gesture = await tester.startGesture(tester.getCenter(cell));
      await gesture.moveBy(const Offset(0, 4));
      await gesture.up();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      await tester.pump();
      expect(h.sent, <String>['g5']);
      expect(h.snaps, isEmpty);
    });

    testWidgets(
        'below fully open the grid does not scroll: its drags move the sheet',
        (tester) async {
      await pump(tester);
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(gridKey),
          matching: find.byType(Scrollable),
        ),
      );
      final cell = find.byKey(const ValueKey<String>('gift-g4'));
      await dragFrom(tester, tester.getCenter(cell), -200, velocity: 100);
      expect(scroll.position.pixels, 0);
      expect(h.snaps.last, SheetSnap.expanded);
    });

    testWidgets(
        'fully open: the grid scrolls; at its top a pull down collapses the sheet',
        (tester) async {
      await pump(tester, initialSnap: SheetSnap.expanded);
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(gridKey),
          matching: find.byType(Scrollable),
        ),
      );
      final cell = find.byKey(const ValueKey<String>('gift-g4'));
      // Drag up: the grid scrolls, the sheet stays.
      await dragFrom(tester, tester.getCenter(cell), -240, velocity: 200);
      expect(scroll.position.pixels, greaterThan(100));
      expect(h.snaps, isEmpty);
      expect(800 - top(tester), closeTo(720, 0.6));
      // Drag down while the grid is not at its top: it scrolls back, not the sheet.
      await dragFrom(tester, tester.getCenter(cell), 100, velocity: 200);
      expect(h.snaps, isEmpty);
      // Back to the very top, then pull down: now the sheet moves.
      scroll.position.jumpTo(0);
      await tester.pump();
      await dragFrom(tester, tester.getCenter(cell), 220, velocity: 100);
      expect(h.snaps.last, SheetSnap.standard);
      expect(scroll.position.pixels, 0);
    });

    testWidgets('a drag the sheet owns does not fling the grid when it ends',
        (tester) async {
      await pump(tester);
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(gridKey),
          matching: find.byType(Scrollable),
        ),
      );
      final cell = find.byKey(const ValueKey<String>('gift-g4'));
      await dragFrom(tester, tester.getCenter(cell), -60, velocity: 3000);
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.position.pixels, 0);
    });

    testWidgets('a cancelled drag goes back and says nothing', (tester) async {
      await pump(tester);
      final before = top(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Send a gift')),
      );
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump();
      expect(top(tester), greaterThan(before));
      await gesture.cancel();
      await settle(tester);
      expect(top(tester), closeTo(before, 0.6));
      expect(h.snaps, isEmpty);
    });

    testWidgets('reduced motion: a snap jumps, no animation', (tester) async {
      await pump(tester, reducedMotion: true);
      await tester.tap(find.byKey(handleKey));
      await tester.pump(); // one frame, no time passes
      expect(800 - top(tester), closeTo(peekHeight(tester), 0.6));
    });

    testWidgets('a snap animates (not a jump) when motion is on',
        (tester) async {
      await pump(tester);
      final before = top(tester);
      await tester.tap(find.byKey(handleKey));
      await tester.pump(); // starts the spring
      await tester.pump(const Duration(milliseconds: 40));
      final mid = top(tester);
      expect(mid, greaterThan(before));
      await settle(tester);
      expect(top(tester), greaterThan(mid));
    });
  });

  group('semantics and sending', () {
    testWidgets('the handle is a button with the state as its value',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      final node = tester.getSemantics(find.byKey(handleKey));
      expect(node.label, contains('Gift tray'));
      expect(node.value, 'default');
      expect(node.flagsCollection.isButton, isTrue);
      final data = node.getSemanticsData();
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.customSemanticsActionIds, hasLength(2));
      tester.semantics.performAction(
        find.semantics.byLabel('Gift tray'),
        SemanticsAction.increase,
      );
      await settle(tester);
      expect(h.snaps, <SheetSnap>[SheetSnap.expanded]);
      tester.semantics.performAction(
        find.semantics.byLabel('Gift tray'),
        SemanticsAction.decrease,
      );
      await settle(tester);
      expect(h.snaps.last, SheetSnap.standard);
      handle.dispose();
    });

    testWidgets('in peek the grid is out of the accessibility tree',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, initialSnap: SheetSnap.peek);
      expect(find.bySemanticsLabel('Gift 3, 13 coins'), findsNothing);
      await tester.tap(find.byKey(handleKey));
      await settle(tester);
      expect(find.bySemanticsLabel('Gift 3, 13 coins'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the footer shows the selected gift and Send sends it',
        (tester) async {
      await pump(tester);
      expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey<String>('gift-picked-name')))
            .data,
        'Gift 0',
      );
      await tester.tap(find.byKey(const ValueKey<String>('gift-g2')));
      await tester.pump();
      expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey<String>('gift-picked-name')))
            .data,
        'Gift 2',
      );
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      await tester.pump();
      expect(h.sent, <String>['g2']);
    });

    testWidgets('Send stays reachable in peek', (tester) async {
      await pump(tester, initialSnap: SheetSnap.peek);
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')));
      await tester.pump();
      expect(h.sent, <String>['g0']);
    });
  });

  group('theme', () {
    Color? bg(WidgetTester tester, Finder f) {
      final box = tester.widget<Container>(f).decoration! as BoxDecoration;
      return box.color;
    }

    testWidgets('lightTheme paints the sheet, the cells and the Send button',
        (tester) async {
      await pump(tester, theme: lightTheme);
      final surface = tester
          .widget<Container>(
            find
                .descendant(
                  of: find.byKey(trayKey),
                  matching: find.byType(Container),
                )
                .first,
          )
          .decoration! as BoxDecoration;
      expect(surface.color, lightTheme.surface);
      final send = find.descendant(
        of: find.byKey(const ValueKey<String>('gift-send')),
        matching: find.byType(Container),
      );
      expect(bg(tester, send.first), lightTheme.accent);
      // The selected cell uses the `selected` token, the others `background`.
      final selectedCell = find.descendant(
        of: find.byKey(const ValueKey<String>('gift-g0')),
        matching: find.byType(Container),
      );
      expect(bg(tester, selectedCell.first), lightTheme.selected);
      final otherCell = find.descendant(
        of: find.byKey(const ValueKey<String>('gift-g1')),
        matching: find.byType(Container),
      );
      expect(bg(tester, otherCell.first), lightTheme.background);
    });

    testWidgets('Get coins uses coin and coinText', (tester) async {
      final theme = themeFromAccent('#2fbf71', GiftThemeMode.light);
      await pump(tester, theme: theme, balance: 5, onTopUp: () {});
      final send = find.byKey(const ValueKey<String>('gift-send'));
      final box = tester
          .widget<Container>(
            find.descendant(of: send, matching: find.byType(Container)).first,
          )
          .decoration! as BoxDecoration;
      expect(box.color, theme.coin);
      final text = tester.widget<Text>(
        find.descendant(of: send, matching: find.byType(Text)),
      );
      expect(text.style!.color, theme.coinText);
      expect(text.data, 'Get coins');
    });
  });

  group('scrim, open and close (SPEC 9.4)', () {
    const scrimKey = ValueKey<String>('tray-scrim');
    double dim(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.descendant(
            of: find.byKey(scrimKey),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    testWidgets('no scrim unless asked', (tester) async {
      await pump(tester);
      expect(find.byKey(scrimKey), findsNothing);
      await tester.tapAt(const Offset(200, 40));
      expect(h.underTaps, 1);
    });

    testWidgets('the dim shows (0.4) once placed and takes the touches',
        (tester) async {
      await pump(tester, scrim: true);
      expect(dim(tester), kScrimOpacity);
      await tester.tapAt(const Offset(200, 40));
      await settle(tester);
      expect(h.underTaps, 0);
    });

    testWidgets(
        'scrimTap lower: a tap lowers the sheet to peek, the dim goes and '
        'the screen behind gets the next tap', (tester) async {
      var dismissed = 0;
      await pump(tester, scrim: true, onDismiss: () => dismissed++);
      await tester.tapAt(const Offset(200, 40));
      await settle(tester);
      expect(h.snaps, <SheetSnap>[SheetSnap.peek]);
      expect(dim(tester), 0);
      expect(dismissed, 0);
      await tester.tapAt(const Offset(200, 40));
      await tester.pump();
      expect(h.underTaps, 1);
      expect(dismissed, 0);
    });

    testWidgets('scrimTap dismiss: a tap calls onDismiss', (tester) async {
      var dismissed = 0;
      await pump(
        tester,
        scrim: true,
        scrimTap: ScrimTap.dismiss,
        onDismiss: () => dismissed++,
      );
      await tester.tapAt(const Offset(200, 40));
      await settle(tester);
      expect(dismissed, 1);
      expect(h.snaps, isEmpty);
      expect(h.underTaps, 0);
    });

    testWidgets('reduced motion: the dim fades in 0 ms', (tester) async {
      await pump(tester, scrim: true, reducedMotion: true);
      final fade = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byKey(scrimKey),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(fade.duration, Duration.zero);
      expect(fade.opacity, kScrimOpacity);
    });

    testWidgets('motion allowed: the dim fades over 200 ms', (tester) async {
      await pump(tester, scrim: true);
      final fade = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byKey(scrimKey),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(fade.duration, const Duration(milliseconds: 200));
    });

    testWidgets(
        'open false hides the sheet and the dim, reports inset 0 and takes no '
        'touches; open again shows it at initialSnap', (tester) async {
      final open = ValueNotifier<bool>(true);
      await pump(tester, scrim: true, openNotifier: open);
      expect(h.insets.last, greaterThan(0));
      // Lower it first, so opening has to bring it back to default.
      await tester.tap(find.byKey(handleKey));
      await settle(tester);
      expect(h.snaps, <SheetSnap>[SheetSnap.peek]);
      open.value = false;
      await settle(tester);
      expect(h.insets.last, 0);
      await tester.tapAt(const Offset(200, 40));
      await tester.tap(find.byKey(const ValueKey<String>('gift-send')),
          warnIfMissed: false);
      await tester.pump();
      expect(h.underTaps, 2); // both taps reached the screen behind
      expect(h.sent, isEmpty);
      open.value = true;
      await settle(tester);
      expect(h.snaps.last, SheetSnap.standard);
      expect(h.insets.last, greaterThan(0));
      expect(dim(tester), kScrimOpacity);
    });
  });
}
