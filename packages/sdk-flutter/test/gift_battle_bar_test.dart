// Widget tests of GiftBattleBar (SPEC 18.7): hidden states, the two sides,
// the clock states, the boundary, the winner, reduced motion, the spoken
// label and a bar that follows a GiftRoom. The numbers behind them (split,
// clock, colours, words) are run by battle_bar_conformance_test.dart.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';

import 'support/component_harness.dart';

const Key _bar = ValueKey<String>('gift-battle-bar');
const Key _track = ValueKey<String>('gift-battle-track');
const Key _fill = ValueKey<String>('gift-battle-fill');
const Key _clock = ValueKey<String>('gift-battle-clock');
const Key _banner = ValueKey<String>('gift-battle-banner');
Key _score(int i) => ValueKey<String>('gift-battle-score-$i');

BattleView view(
  int a,
  int b, {
  int remainingMs = 61000,
  bool? open,
  String round = 'r1',
}) {
  final total = a + b;
  return BattleView(
    round: round,
    open: open ?? remainingMs > 0,
    remainingMs: remainingMs,
    total: total,
    sides: <BattleSide>[
      BattleSide(
          id: 'mia', units: a, gifts: 1, share: total > 0 ? a / total : 0.5),
      BattleSide(
          id: 'theo', units: b, gifts: 1, share: total > 0 ? b / total : 0.5),
    ],
    leader: a == b ? null : (a > b ? 'mia' : 'theo'),
  );
}

const Map<String, BattleBarUser> users = <String, BattleBarUser>{
  'mia': BattleBarUser(name: 'Mia'),
  'theo': BattleBarUser(name: 'Theo'),
};

/// A token whose claim `u` is `me` (not signed: the client never checks it).
final String _token =
    'gs_ct_${base64Url.encode(utf8.encode(jsonEncode(<String, Object?>{
              'u': 'me',
            }))).replaceAll('=', '')}.AAAA';

String textOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

void main() {
  Future<void> pumpBar(
    WidgetTester tester,
    BattleView? v, {
    bool disableAnimations = false,
    bool? reducedMotion,
    GiftingTheme theme = const GiftingTheme(),
    List<Color>? sideColors,
    BattleBarLabels labels = const BattleBarLabels(),
  }) async {
    final images = await loadedImages(tester);
    await tester.pumpWidget(
      hostApp(
        SizedBox(
          width: 358,
          child: GiftBattleBar(
            view: v,
            users: users,
            theme: theme,
            labels: labels,
            sideColors: sideColors,
            reducedMotion: reducedMotion,
            imageProvider: images.call,
          ),
        ),
        disableAnimations: disableAnimations,
      ),
    );
  }

  group('GiftBattleBar', () {
    testWidgets('draws nothing without a round or with one side',
        (tester) async {
      await pumpBar(tester, null);
      expect(find.byKey(_bar), findsNothing);
      final one = view(1, 1);
      await pumpBar(
        tester,
        BattleView(
          round: one.round,
          open: true,
          remainingMs: 1000,
          total: 1,
          sides: one.sides.take(1).toList(),
          leader: 'mia',
        ),
      );
      expect(find.byKey(_bar), findsNothing);
    });

    testWidgets('shows both sides, the clock and a boundary at the split',
        (tester) async {
      await pumpBar(tester, view(300, 100, remainingMs: 30000));
      await tester.pumpAndSettle();
      expect(find.text('Mia'), findsOneWidget);
      expect(find.text('Theo'), findsOneWidget);
      expect(find.text('VS'), findsOneWidget);
      expect(textOf(tester, _score(0)), '300');
      expect(textOf(tester, _score(1)), '100');
      expect(textOf(tester, _clock), '0:30');
      expect(find.byKey(_banner), findsNothing);
      final track = tester.getSize(find.byKey(_track)).width;
      expect(
          tester.getSize(find.byKey(_fill)).width, closeTo(track * 0.75, 0.5));
      expect(tester.getSize(find.byKey(_track)).height, 16);
    });

    testWidgets('keeps both sides visible when one has everything',
        (tester) async {
      await pumpBar(tester, view(5, 0));
      await tester.pumpAndSettle();
      final track = tester.getSize(find.byKey(_track)).width;
      expect(
          tester.getSize(find.byKey(_fill)).width, closeTo(track * 0.94, 0.5));
    });

    testWidgets('the clock turns urgent in the last 10 seconds',
        (tester) async {
      const theme = GiftingTheme();
      await pumpBar(tester, view(5, 1, remainingMs: 11000));
      expect(tester.widget<Text>(find.byKey(_clock)).style!.color, theme.text);
      await pumpBar(tester, view(5, 1, remainingMs: 9200));
      expect(textOf(tester, _clock), '0:10');
      expect(
          tester.widget<Text>(find.byKey(_clock)).style!.color, theme.danger);
    });

    testWidgets('an ended round: Final, crown on the winner, the banner',
        (tester) async {
      await pumpBar(tester, view(5, 1, remainingMs: 0));
      await tester.pumpAndSettle();
      expect(textOf(tester, _clock), 'Final');
      expect(textOf(tester, _banner), 'Mia wins the round');
      expect(find.text('♛'), findsOneWidget);
      final fade = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity)
          .toList();
      // The loser (Theo) is at half opacity; the spark is dimmed when final.
      expect(fade, contains(0.5));
    });

    testWidgets('a draw has no crown and says so', (tester) async {
      await pumpBar(tester, view(4, 4, remainingMs: 0));
      await tester.pumpAndSettle();
      expect(textOf(tester, _banner), 'Draw: nobody wins this round');
      expect(find.text('♛'), findsNothing);
    });

    testWidgets('scores use the short form and labels translate',
        (tester) async {
      await pumpBar(
        tester,
        view(135484, 9999, remainingMs: 0),
        labels:
            const BattleBarLabels(finalText: 'Bitti', wins: '{name} kazandı'),
      );
      await tester.pumpAndSettle();
      expect(textOf(tester, _score(0)), '135K');
      expect(textOf(tester, _score(1)), '9,999');
      expect(textOf(tester, _clock), 'Bitti');
      expect(textOf(tester, _banner), 'Mia kazandı');
    });

    testWidgets('the colours come from the theme, or from sideColors',
        (tester) async {
      await pumpBar(tester, view(3, 1), theme: darkTheme);
      await tester.pumpAndSettle();
      BoxDecoration fillDecoration() =>
          tester.widget<DecoratedBox>(find.byKey(_fill)).decoration
              as BoxDecoration;
      expect(fillDecoration().color, darkTheme.accent);
      await pumpBar(tester, view(3, 1),
          sideColors: const <Color>[Color(0xFF000000), Color(0xFFFFFFFF)]);
      await tester.pumpAndSettle();
      expect(fillDecoration().color, const Color(0xFF000000));
    });

    testWidgets('a score counts up, or jumps under reduced motion',
        (tester) async {
      await pumpBar(tester, view(100, 100));
      await tester.pumpAndSettle();
      await pumpBar(tester, view(1000, 100));
      await tester.pump(const Duration(milliseconds: 200));
      final mid = int.parse(textOf(tester, _score(0)).replaceAll(',', ''));
      expect(mid, inExclusiveRange(100, 1000));
      await tester.pumpAndSettle();
      expect(textOf(tester, _score(0)), '1,000');

      await pumpBar(tester, view(100, 100), reducedMotion: true);
      await tester.pumpAndSettle();
      await pumpBar(tester, view(1000, 100), reducedMotion: true);
      await tester.pump();
      expect(textOf(tester, _score(0)), '1,000');
      final track = tester.getSize(find.byKey(_track)).width;
      expect(tester.getSize(find.byKey(_fill)).width,
          closeTo(track * 1000 / 1100, 0.5));
    });

    testWidgets('follows the OS remove-animations setting', (tester) async {
      await pumpBar(tester, view(100, 100), disableAnimations: true);
      await tester.pumpAndSettle();
      await pumpBar(tester, view(1000, 100), disableAnimations: true);
      await tester.pump();
      expect(textOf(tester, _score(0)), '1,000');
    });

    testWidgets('a screen reader gets one sentence: both scores and the result',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBar(tester, view(5, 1, remainingMs: 0));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Mia 5, Theo 1. Mia wins the round'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('GiftBattleBar with a GiftRoom', () {
    testWidgets('follows the room: welcome round, then a scores frame',
        (tester) async {
      late FakeSocket wire;
      final room = GiftRoom(
        room: 'live_1',
        getToken: ({required bool forceRefresh}) async => _token,
        socket: (url, protocols, handlers) => wire = FakeSocket(handlers),
        heartbeatMs: 0,
      );
      final images = await loadedImages(tester);
      await tester.pumpWidget(
        hostApp(
          SizedBox(
            width: 358,
            child: GiftBattleBar(
              room: room,
              users: users,
              imageProvider: images.call,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(_bar), findsNothing);
      wire.handlers.onOpen();
      final now = DateTime.now().millisecondsSinceEpoch;
      Map<String, Object?> round(int a, int b) => <String, Object?>{
            'round': 'r1',
            'started': now - 1000,
            'ends': now + 600000,
            'scores': <Object?>[
              <String, Object?>{'id': 'mia', 'units': a, 'gifts': 1},
              <String, Object?>{'id': 'theo', 'units': b, 'gifts': 1},
            ],
          };
      wire.handlers.onMessage(jsonEncode(<String, Object?>{
        't': 'welcome',
        'viewers': 1,
        'gap': false,
        'replay': <Object?>[],
        'ttl': 3600,
        'now': now,
        'battle': round(20, 10),
      }));
      await tester.pumpAndSettle();
      expect(textOf(tester, _score(0)), '20');
      expect(textOf(tester, _score(1)), '10');
      wire.handlers.onMessage(jsonEncode(
          <String, Object?>{'t': 'scores', 'battle': round(20, 50)}));
      await tester.pumpAndSettle();
      expect(textOf(tester, _score(1)), '50');
      wire.handlers.onMessage(
          jsonEncode(<String, Object?>{'t': 'scores', 'battle': null}));
      await tester.pumpAndSettle();
      expect(find.byKey(_bar), findsNothing);
      await tester.pumpWidget(const SizedBox());
      room.dispose();
      await tester.pump(const Duration(seconds: 5));
    });
  });
}

class FakeSocket implements RoomSocket {
  FakeSocket(this.handlers);

  final RoomSocketHandlers handlers;

  @override
  void send(String data) {}

  @override
  void close(int code, String reason) {}
}
