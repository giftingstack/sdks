// Widget tests of GiftLeaderboard (SPEC 16.4): every state and prop, the tabs
// with their keyboard, the pinned row, medals, accessibility labels and reduced
// motion. The pure rules (controller, cache, pinning) are in
// components_conformance_test.dart (leaderboard.json). What these cannot judge
// (how it looks and feels on a phone) needs a device.
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';
import 'package:giftingstack/src/ui/gift_parts.dart' show CoinDot;

import 'support/component_harness.dart';
import 'support/scripted_client.dart';
import 'support/ui_harness.dart';

const Key _list = ValueKey<String>('gift-lb-list');
const Key _skeleton = ValueKey<String>('gift-lb-skeleton');
const Key _pinned = ValueKey<String>('gift-lb-pinned');
const Key _spinner = ValueKey<String>('gift-lb-spinner');
const Key _retry = ValueKey<String>('gift-lb-retry');

Key rowKey(String user) => ValueKey<String>('gift-lb-row-$user');
Key tabKey(String p) => ValueKey<String>('gift-lb-tab-$p');

void main() {
  late ScriptedClient api;
  late ControlledImages images;
  var now = 0;
  final key = GlobalKey<GiftLeaderboardState>();

  setUp(() {
    api = ScriptedClient();
    now = 0;
  });

  Future<void> pumpBoard(
    WidgetTester tester, {
    LeaderboardBoard board = LeaderboardBoard.senders,
    List<LeaderboardPeriod> periods = leaderboardPeriods,
    LeaderboardPeriod initialPeriod = LeaderboardPeriod.week,
    LeaderboardMetric? metric,
    bool metricToggle = false,
    int limit = 10,
    Future<Map<String, LeaderboardUser>> Function(List<String>)? resolveUsers,
    String? highlightUser,
    int refreshIntervalMs = 0,
    Widget? Function(BuildContext, LeaderboardRowContext)? renderRow,
    void Function(String)? onPressUser,
    void Function(GiftingException)? onError,
    bool? reducedMotion,
    bool disableAnimations = false,
    GiftingTheme theme = const GiftingTheme(),
    GiftLabels labels = const GiftLabels(),
    String coinName = 'coins',
  }) async {
    images = ControlledImages(autoLoad: true);
    await images.init(tester);
    await tester.pumpWidget(
      hostApp(
        SizedBox(
          width: 400,
          child: GiftLeaderboard(
            key: key,
            client: api,
            board: board,
            periods: periods,
            initialPeriod: initialPeriod,
            metric: metric,
            metricToggle: metricToggle,
            limit: limit,
            resolveUsers: resolveUsers,
            highlightUser: highlightUser,
            refreshIntervalMs: refreshIntervalMs,
            renderRow: renderRow,
            onPressUser: onPressUser,
            onError: onError,
            reducedMotion: reducedMotion,
            theme: theme,
            labels: labels,
            coinName: coinName,
            imageProvider: images.call,
            now: () => now,
          ),
        ),
        disableAnimations: disableAnimations,
      ),
    );
  }

  Future<void> answer(WidgetTester tester, Leaderboard b) async {
    api.take('getLeaderboard', 'answer').completer.complete(b);
    await tester.idle();
    await tester.pump();
  }

  Future<void> failWith(WidgetTester tester, [String type = 'boom']) async {
    api.take('getLeaderboard', 'fail').completer.completeError(
          GiftingException(503, type, 'later'),
        );
    await tester.idle();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Map<String, Object?> lastQuery() =>
      (api.calls.last['args']! as Map<String, Object?>)['query']!
          as Map<String, Object?>;

  List<String> callPeriods() => api.calls
      .map((c) => ((c['args']! as Map<String, Object?>)['query']!
          as Map<String, Object?>)['period']! as String)
      .toList();

  Color? fillOf(WidgetTester tester, Finder f) {
    final deco = tester.widget<Container>(f).decoration;
    return deco is BoxDecoration ? deco.color : null;
  }

  Finder inRow(String user, Finder f) =>
      find.descendant(of: find.byKey(rowKey(user)), matching: f);

  bool isButton(WidgetTester tester, Finder f) => isSemantics(isButton: true)
      .matches(tester.getSemantics(f), <dynamic, dynamic>{});

  group('loading, ready, empty, error', () {
    testWidgets('loading: `limit` skeleton rows; static when reduced',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(tester);
      expect(find.byKey(_skeleton), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        expect(find.byKey(ValueKey<String>('gift-lb-skeleton-row-$i')),
            findsOneWidget);
      }
      expect(find.byKey(const ValueKey<String>('gift-lb-skeleton-row-10')),
          findsNothing);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue, reason: 'it pulses');
      await answer(tester, standardBoard());

      await pumpBoard(tester, limit: 4, reducedMotion: true);
      expect(find.byKey(const ValueKey<String>('gift-lb-skeleton-row-3')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('gift-lb-skeleton-row-4')),
          findsNothing);
      expect(tester.hasRunningAnimations, isFalse, reason: 'static skeleton');
      handle.dispose();
      await finish(tester);
    });

    testWidgets('the system "remove animations" setting makes it static',
        (tester) async {
      await pumpBoard(tester, disableAnimations: true);
      expect(tester.hasRunningAnimations, isFalse);
      await finish(tester);
    });

    testWidgets('the first request: board, week, units, limit 10',
        (tester) async {
      await pumpBoard(tester);
      expect(api.calls.single, <String, Object?>{
        'method': 'getLeaderboard',
        'args': <String, Object?>{
          'board': 'senders',
          'query': <String, Object?>{
            'period': 'week',
            'metric': 'units',
            'limit': 10,
          },
        },
      });
      await finish(tester);
    });

    testWidgets('the receivers board asks for gifts and shows plain numbers',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(tester, board: LeaderboardBoard.receivers);
      expect(lastQuery()['metric'], 'gifts');
      await answer(
        tester,
        boardOf(
          board: LeaderboardBoard.receivers,
          metric: LeaderboardMetric.gifts,
          me: null,
          rows: const <(int, String, int, int)>[(1, 'ayla', 1234, 99)],
        ),
      );
      expect(inRow('ayla', find.text('1,234')), findsOneWidget);
      expect(inRow('ayla', find.text('gifts')), findsOneWidget);
      expect(inRow('ayla', find.byType(CoinDot)), findsNothing);
      expect(
          find.bySemanticsLabel('Rank 1, ayla, 1,234 gifts'), findsOneWidget);
      handle.dispose();
      await finish(tester);
    });

    testWidgets('ready: rank, name, short score and a coin for units',
        (tester) async {
      await pumpBoard(tester);
      await answer(tester, standardBoard());
      expect(find.byKey(_skeleton), findsNothing);
      expect(find.byKey(_list), findsOneWidget);
      expect(inRow('ayla', find.text('1')), findsOneWidget);
      expect(inRow('ayla', find.text('ayla')), findsOneWidget);
      expect(inRow('ayla', find.text('54K')), findsOneWidget);
      expect(inRow('mert', find.text('41K')), findsOneWidget);
      expect(inRow('can', find.text('900')), findsOneWidget);
      expect(inRow('ayla', find.byType(CoinDot)), findsOneWidget);
      expect(
        tester.widget<CoinDot>(inRow('ayla', find.byType(CoinDot))).color,
        const GiftingTheme().coin,
      );
      expect(inRow('ayla', find.text('gifts')), findsNothing);
      // Competition ranks: the tie shares 2, the next is 4.
      expect(inRow('mert', find.text('2')), findsOneWidget);
      expect(inRow('ece', find.text('2')), findsOneWidget);
      expect(inRow('can', find.text('4')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('big numbers: 1,234,567 units are 1.2M; gifts are grouped',
        (tester) async {
      await pumpBoard(tester, metricToggle: true);
      await answer(
        tester,
        boardOf(
          me: null,
          rows: const <(int, String, int, int)>[(1, 'ayla', 1234567, 1234567)],
        ),
      );
      expect(inRow('ayla', find.text('1.2M')), findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey<String>('gift-lb-metric-gifts')));
      await tester.pump();
      await answer(
        tester,
        boardOf(
          metric: LeaderboardMetric.gifts,
          me: null,
          rows: const <(int, String, int, int)>[(1, 'ayla', 1234567, 1234567)],
        ),
      );
      expect(inRow('ayla', find.text('1,234,567')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('empty: the text of the period; labels replace it',
        (tester) async {
      await pumpBoard(tester);
      await answer(
          tester, boardOf(rows: const <(int, String, int, int)>[], me: null));
      expect(find.text('No gifts yet this week'), findsOneWidget);
      expect(find.byKey(_list), findsNothing);
      await tester.tap(find.byKey(tabKey('day')));
      await tester.pump();
      await answer(
          tester,
          boardOf(
              rows: const <(int, String, int, int)>[],
              me: null,
              period: LeaderboardPeriod.day));
      expect(find.text('No gifts yet today'), findsOneWidget);
      await tester.tap(find.byKey(tabKey('all')));
      await tester.pump();
      await answer(
          tester,
          boardOf(
              rows: const <(int, String, int, int)>[],
              me: null,
              period: LeaderboardPeriod.all));
      expect(find.text('No gifts yet'), findsOneWidget);
      await finish(tester);

      await pumpBoard(
        tester,
        labels: const GiftLabels(
          empty: <LeaderboardPeriod, String>{
            LeaderboardPeriod.week: 'Henuz yok'
          },
        ),
      );
      await answer(
          tester, boardOf(rows: const <(int, String, int, int)>[], me: null));
      expect(find.text('Henuz yok'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('an empty board with a viewer who has a score still pins them',
        (tester) async {
      await pumpBoard(tester);
      await answer(
        tester,
        boardOf(
          rows: const <(int, String, int, int)>[],
          me: const LeaderboardMe(
            user: 'user_123',
            rank: null,
            gifts: 3,
            units: 120,
            hidden: false,
          ),
        ),
      );
      expect(find.text('No gifts yet this week'), findsOneWidget);
      expect(find.byKey(_pinned), findsOneWidget);
      await finish(tester);
    });

    testWidgets('error: a message and "Try again"; the retry asks again',
        (tester) async {
      final handle = tester.ensureSemantics();
      final errors = <String>[];
      await pumpBoard(tester, onError: (e) => errors.add(e.type));
      await failWith(tester, 'leaderboard_building');
      expect(errors, <String>['leaderboard_building']);
      expect(find.text('Could not load the leaderboard.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      final retry = tester.getSemantics(find.bySemanticsLabel('Try again'));
      expect(isSemantics(isButton: true).matches(retry, <dynamic, dynamic>{}),
          isTrue);
      expect(
          tester.getSize(find.byKey(_retry)).height, greaterThanOrEqualTo(44));
      await tester.tap(find.byKey(_retry));
      await tester.pump();
      expect(api.calls.length, 2);
      expect(find.byKey(_skeleton), findsOneWidget, reason: 'loading again');
      await answer(tester, standardBoard());
      expect(find.text('Could not load the leaderboard.'), findsNothing);
      expect(find.byKey(_list), findsOneWidget);
      handle.dispose();
      await finish(tester);
    });

    testWidgets('labels: error and retry texts are replaceable',
        (tester) async {
      await pumpBoard(
        tester,
        labels: const GiftLabels(error: 'Yuklenemedi', tryAgain: 'Tekrar dene'),
      );
      await failWith(tester);
      expect(find.text('Yuklenemedi'), findsOneWidget);
      expect(find.text('Tekrar dene'), findsOneWidget);
      await finish(tester);
    });
  });

  group('medals, highlight and the pinned row', () {
    testWidgets('ranks 1 to 3 sit on medals with noticeBigText; 4 does not',
        (tester) async {
      const theme = GiftingTheme(noticeBigText: Color(0xFF123456));
      await pumpBoard(tester, theme: theme);
      await answer(tester, standardBoard(me: null));
      expect(
        fillOf(tester, find.byKey(const ValueKey<String>('gift-lb-medal-1'))),
        giftColorOf('#e8a93a'),
      );
      // The tie at 2 gives both rows the silver medal.
      final silver = find.byKey(const ValueKey<String>('gift-lb-medal-2'));
      expect(silver, findsNWidgets(2));
      expect(fillOf(tester, silver.first), giftColorOf('#b8bcc8'));
      // Rank 4 is plain: no medal key and no fill.
      expect(
          find.byKey(const ValueKey<String>('gift-lb-medal-4')), findsNothing);
      expect(
        tester
            .widget<Text>(find.descendant(
              of: find.byKey(const ValueKey<String>('gift-lb-medal-1')),
              matching: find.byType(Text),
            ))
            .style!
            .color,
        const Color(0xFF123456),
      );
      expect(inRow('can', find.text('4')), findsOneWidget);
      expect(
        tester.widget<Text>(inRow('can', find.text('4'))).style!.color,
        theme.muted,
      );
      await finish(tester);
    });

    testWidgets('rank 3 is bronze', (tester) async {
      await pumpBoard(tester);
      await answer(
        tester,
        boardOf(
          me: null,
          rows: const <(int, String, int, int)>[
            (1, 'a', 1, 30),
            (2, 'b', 1, 20),
            (3, 'c', 1, 10),
          ],
        ),
      );
      expect(
        fillOf(tester, find.byKey(const ValueKey<String>('gift-lb-medal-3'))),
        giftColorOf('#c07a45'),
      );
      await finish(tester);
    });

    testWidgets('a viewer outside the rows is pinned: "You: #417"',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(tester);
      await answer(tester, standardBoard());
      expect(find.byKey(_pinned), findsOneWidget);
      expect(find.text('You: #417'), findsOneWidget);
      expect(
          find.descendant(of: find.byKey(_pinned), matching: find.text('120')),
          findsOneWidget);
      expect(
          find.bySemanticsLabel('Your rank: 417, 120 coins'), findsOneWidget);
      expect(
        fillOf(
            tester,
            find
                .descendant(
                    of: find.byKey(_pinned), matching: find.byType(Container))
                .first),
        const GiftingTheme().selected,
      );
      // Under the list.
      expect(
        tester.getTopLeft(find.byKey(_pinned)).dy,
        greaterThan(tester.getBottomLeft(find.byKey(_list)).dy - 1),
      );
      handle.dispose();
      await finish(tester);
    });

    testWidgets('beyond the top 1,000 it reads "1,000+"', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(tester);
      await answer(
        tester,
        standardBoard(
          me: const LeaderboardMe(
            user: 'user_123',
            rank: null,
            gifts: 3,
            units: 120,
            hidden: false,
          ),
        ),
      );
      expect(find.text('You: 1,000+'), findsOneWidget);
      expect(find.bySemanticsLabel('Your rank: 1,000+, 120 coins'),
          findsOneWidget);
      handle.dispose();
      await finish(tester);
    });

    testWidgets('labels: pinned texts and the overflow word', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(
        tester,
        labels: const GiftLabels(
          pinned: 'Sen: {rank}',
          pinnedSpoken: 'Siran: {rank}, {score}',
          rankOverflow: '1000+',
        ),
      );
      await answer(
        tester,
        standardBoard(
          me: const LeaderboardMe(
            user: 'user_123',
            rank: null,
            gifts: 3,
            units: 120,
            hidden: false,
          ),
        ),
      );
      expect(find.text('Sen: 1000+'), findsOneWidget);
      expect(find.bySemanticsLabel('Siran: 1000+, 120 coins'), findsOneWidget);
      handle.dispose();
      await finish(tester);
    });

    testWidgets('not pinned: hidden, no score, or already in the rows',
        (tester) async {
      await pumpBoard(tester);
      await answer(
        tester,
        standardBoard(
          me: const LeaderboardMe(
            user: 'user_123',
            rank: null,
            gifts: 3,
            units: 120,
            hidden: true,
          ),
        ),
      );
      expect(find.byKey(_pinned), findsNothing);
      await finish(tester);

      await pumpBoard(tester);
      await answer(
        tester,
        standardBoard(
          me: const LeaderboardMe(
            user: 'user_123',
            rank: null,
            gifts: 0,
            units: 0,
            hidden: false,
          ),
        ),
      );
      expect(find.byKey(_pinned), findsNothing);
      await finish(tester);

      // In the rows: highlighted there, not pinned.
      await pumpBoard(tester);
      await answer(
        tester,
        standardBoard(
          me: const LeaderboardMe(
            user: 'mert',
            rank: 2,
            gifts: 300,
            units: 41000,
            hidden: false,
          ),
        ),
      );
      expect(find.byKey(_pinned), findsNothing);
      expect(
        fillOf(
            tester,
            find
                .descendant(
                    of: find.byKey(rowKey('mert')),
                    matching: find.byType(Container))
                .first),
        const GiftingTheme().selected,
      );
      expect(
        fillOf(
            tester,
            find
                .descendant(
                    of: find.byKey(rowKey('ayla')),
                    matching: find.byType(Container))
                .first),
        isNull,
      );
      await finish(tester);
    });

    testWidgets('a tie at the cut: rank within limit but not in the rows',
        (tester) async {
      await pumpBoard(tester, limit: 3);
      await answer(
        tester,
        boardOf(
          rows: const <(int, String, int, int)>[
            (1, 'a', 1, 30),
            (2, 'b', 1, 20),
            (3, 'c', 1, 10),
          ],
          me: const LeaderboardMe(
            user: 'me',
            rank: 3,
            gifts: 1,
            units: 10,
            hidden: false,
          ),
        ),
      );
      expect(find.byKey(_pinned), findsOneWidget);
      await finish(tester);
    });

    testWidgets('highlightUser: the app names whose row is highlighted',
        (tester) async {
      await pumpBoard(tester, highlightUser: 'ece');
      await answer(tester, standardBoard(me: null));
      expect(
        fillOf(
            tester,
            find
                .descendant(
                    of: find.byKey(rowKey('ece')),
                    matching: find.byType(Container))
                .first),
        const GiftingTheme().selected,
      );
      expect(
        fillOf(
            tester,
            find
                .descendant(
                    of: find.byKey(rowKey('mert')),
                    matching: find.byType(Container))
                .first),
        isNull,
      );
      await finish(tester);
    });
  });

  group('tabs', () {
    testWidgets('four tabs by default, week selected; labels from labels',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(tester);
      for (final t in <String>[
        'Today',
        'This week',
        'This month',
        'All time'
      ]) {
        expect(find.text(t), findsOneWidget);
      }
      SemanticsNode tab(String label) =>
          tester.getSemantics(find.bySemanticsLabel(label));
      expect(
        isSemantics(isSelected: true, isButton: true)
            .matches(tab('This week'), <dynamic, dynamic>{}),
        isTrue,
      );
      expect(
        isSemantics(isSelected: false, isButton: true)
            .matches(tab('Today'), <dynamic, dynamic>{}),
        isTrue,
      );
      handle.dispose();
      await finish(tester);

      await pumpBoard(
        tester,
        labels: const GiftLabels(
          tabs: <LeaderboardPeriod, String>{LeaderboardPeriod.day: 'Bugun'},
        ),
      );
      expect(find.text('Bugun'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget, reason: 'others default');
      await finish(tester);
    });

    testWidgets('periods and initialPeriod: order, fallback, one = no tabs',
        (tester) async {
      await pumpBoard(
        tester,
        periods: const <LeaderboardPeriod>[
          LeaderboardPeriod.all,
          LeaderboardPeriod.day,
        ],
      );
      expect(lastQuery()['period'], 'all', reason: 'week is not offered');
      expect(
        tester.getTopLeft(find.byKey(tabKey('all'))).dx,
        lessThan(tester.getTopLeft(find.byKey(tabKey('day'))).dx),
      );
      expect(find.byKey(tabKey('week')), findsNothing);
      await finish(tester);

      await pumpBoard(
        tester,
        periods: const <LeaderboardPeriod>[LeaderboardPeriod.month],
        initialPeriod: LeaderboardPeriod.month,
      );
      expect(find.byKey(const ValueKey<String>('gift-lb-tabs')), findsNothing);
      expect(lastQuery()['period'], 'month');
      await finish(tester);

      await pumpBoard(tester, initialPeriod: LeaderboardPeriod.day);
      expect(lastQuery()['period'], 'day');
      await finish(tester);
    });

    testWidgets(
        'the four tabs sit side by side in one row, as wide as their labels',
        (tester) async {
      await pumpBoard(tester);
      final tops = <double>[
        for (final p in <String>['day', 'week', 'month', 'all'])
          tester.getTopLeft(find.byKey(tabKey(p))).dy,
      ];
      // The test font (Ahem) is wide: the last two wrap, the first two do not.
      expect(tops[0], tops[1], reason: 'one row: $tops');
      expect(tops[2], tops[3], reason: 'wrapped row: $tops');
      expect(tester.getSize(find.byKey(tabKey('day'))).width, lessThan(120));
      await finish(tester);
    });

    testWidgets('a tab press loads that period; a cached tab shows at once',
        (tester) async {
      await pumpBoard(tester);
      await answer(tester, standardBoard());
      await tester.tap(find.byKey(tabKey('month')));
      await tester.pump();
      expect(callPeriods(), <String>['week', 'month']);
      expect(find.byKey(_skeleton), findsOneWidget, reason: 'nothing cached');
      await answer(tester, standardBoard(period: LeaderboardPeriod.month));
      now = 10000;
      await tester.tap(find.byKey(tabKey('week')));
      await tester.pump();
      expect(find.byKey(_list), findsOneWidget, reason: 'cached: at once');
      expect(find.byKey(_skeleton), findsNothing);
      expect(api.calls.length, 2, reason: 'fresh (10 s): no request');
      // Tapping the selected tab does nothing.
      await tester.tap(find.byKey(tabKey('week')));
      await tester.pump();
      expect(api.calls.length, 2);
      await finish(tester);
    });

    testWidgets('a stale tab (30 s) shows its rows and refreshes quietly',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(tester);
      await answer(tester, standardBoard());
      await tester.tap(find.byKey(tabKey('day')));
      await tester.pump();
      await answer(tester, standardBoard(period: LeaderboardPeriod.day));
      now = 30000;
      await tester.tap(find.byKey(tabKey('week')));
      await tester.pump();
      expect(api.calls.length, 3);
      expect(find.byKey(_list), findsOneWidget, reason: 'stale rows stay');
      expect(find.byKey(_spinner), findsOneWidget);
      expect(find.bySemanticsLabel('Updating'), findsOneWidget);
      await answer(
        tester,
        boardOf(
          me: null,
          rows: const <(int, String, int, int)>[(1, 'zed', 1, 5)],
        ),
      );
      expect(find.byKey(_spinner), findsNothing);
      expect(find.byKey(rowKey('zed')), findsOneWidget);
      expect(find.byKey(rowKey('ayla')), findsNothing);
      handle.dispose();
      await finish(tester);
    });

    testWidgets('a failed revalidation keeps the rows and shows no error',
        (tester) async {
      final errors = <String>[];
      await pumpBoard(tester, onError: (e) => errors.add(e.type));
      await answer(tester, standardBoard());
      now = 40000;
      key.currentState!.refresh();
      await tester.pump();
      expect(find.byKey(_spinner), findsOneWidget);
      await failWith(tester, 'network_error');
      expect(errors, <String>['network_error']);
      expect(find.byKey(_list), findsOneWidget);
      expect(find.text('Could not load the leaderboard.'), findsNothing);
      expect(find.byKey(_spinner), findsNothing);
      await finish(tester);
    });

    testWidgets('reduced motion: no spinner, no pulse', (tester) async {
      await pumpBoard(tester, reducedMotion: true);
      await answer(tester, standardBoard());
      key.currentState!.refresh();
      await tester.pump();
      expect(find.byKey(_list), findsOneWidget);
      expect(find.byKey(_spinner), findsNothing);
      await finish(tester);
    });

    testWidgets('refresh() on the state asks again at once (pull to refresh)',
        (tester) async {
      await pumpBoard(tester);
      await answer(tester, standardBoard());
      key.currentState!.refresh();
      await tester.pump();
      expect(api.calls.length, 2, reason: 'fresh, but refresh forces it');
      await finish(tester);
    });

    testWidgets('refreshIntervalMs polls the shown tab', (tester) async {
      await pumpBoard(tester, refreshIntervalMs: 5000);
      await answer(tester, standardBoard());
      await tester.pump(const Duration(milliseconds: 4900));
      expect(api.calls.length, 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.calls.length, 2);
      await answer(tester, standardBoard());
      await tester.pump(const Duration(milliseconds: 5000));
      expect(api.calls.length, 3);
      await finish(tester);
    });

    testWidgets('no polling by default', (tester) async {
      await pumpBoard(tester);
      await answer(tester, standardBoard());
      await tester.pump(const Duration(minutes: 5));
      expect(api.calls.length, 1);
      await finish(tester);
    });

    testWidgets('a new limit or board starts a fresh controller',
        (tester) async {
      await pumpBoard(tester);
      await answer(tester, standardBoard());
      await pumpBoard(tester, limit: 3);
      expect(api.calls.length, 2);
      expect(lastQuery()['limit'], 3);
      expect(find.byKey(_skeleton), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a late answer after dispose changes nothing', (tester) async {
      final errors = <String>[];
      await pumpBoard(tester, onError: (e) => errors.add(e.type));
      await tester.pumpWidget(const SizedBox());
      await failWith(tester);
      expect(errors, isEmpty);
    });
  });

  group('tab keyboard', () {
    FocusNode tabNode(WidgetTester tester, String p) => Focus.of(
          tester.element(
            find
                .descendant(
                  of: find.descendant(
                    of: find.byKey(tabKey(p)),
                    matching: find.byType(Focus),
                  ),
                  matching: find.byType(Semantics),
                )
                .first,
          ),
        );

    testWidgets('arrows move the selection and the focus, wrapping around',
        (tester) async {
      await pumpBoard(tester);
      await answer(tester, standardBoard());
      tabNode(tester, 'week').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(callPeriods().last, 'month');
      expect(tabNode(tester, 'month').hasPrimaryFocus, isTrue);
      await answer(tester, standardBoard(period: LeaderboardPeriod.month));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(callPeriods().last, 'all');
      await answer(tester, standardBoard(period: LeaderboardPeriod.all));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(tabNode(tester, 'day').hasPrimaryFocus, isTrue, reason: 'wraps');
      await answer(tester, standardBoard(period: LeaderboardPeriod.day));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(tabNode(tester, 'all').hasPrimaryFocus, isTrue, reason: 'wraps');
      await finish(tester);
    });

    testWidgets('Home and End jump to the first and the last tab',
        (tester) async {
      await pumpBoard(tester);
      await answer(tester, standardBoard());
      tabNode(tester, 'week').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(callPeriods().last, 'all');
      await answer(tester, standardBoard(period: LeaderboardPeriod.all));
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(callPeriods().last, 'day');
      expect(tabNode(tester, 'day').hasPrimaryFocus, isTrue);
      await finish(tester);
    });

    testWidgets('other keys do nothing; only the selected tab is in Tab order',
        (tester) async {
      await pumpBoard(tester);
      await answer(tester, standardBoard());
      tabNode(tester, 'week').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(api.calls.length, 1);
      expect(tabNode(tester, 'week').skipTraversal, isFalse);
      expect(tabNode(tester, 'day').skipTraversal, isTrue);
      expect(tabNode(tester, 'all').skipTraversal, isTrue);
      await finish(tester);
    });

    testWidgets('a tab is at least 44 dp tall to touch', (tester) async {
      await pumpBoard(tester);
      expect(tester.getSize(find.byKey(tabKey('day'))).height, 44);
      await finish(tester);
    });
  });

  group('metric switch', () {
    testWidgets('off by default; on: Coins and Gifts, a radio group',
        (tester) async {
      await pumpBoard(tester);
      expect(
          find.byKey(const ValueKey<String>('gift-lb-metric')), findsNothing);
      await finish(tester);

      final handle = tester.ensureSemantics();
      await pumpBoard(tester, metricToggle: true);
      expect(find.text('Coins'), findsOneWidget);
      expect(find.text('Gifts'), findsOneWidget);
      expect(
        isSemantics(isChecked: true, hasCheckedState: true).matches(
            tester.getSemantics(find.bySemanticsLabel('Coins')),
            <dynamic, dynamic>{}),
        isTrue,
      );
      expect(
        isSemantics(isChecked: false, hasCheckedState: true).matches(
            tester.getSemantics(find.bySemanticsLabel('Gifts')),
            <dynamic, dynamic>{}),
        isTrue,
      );
      handle.dispose();
      await finish(tester);
    });

    testWidgets('pressing Gifts asks for the gifts metric; each has a cache',
        (tester) async {
      await pumpBoard(tester, metricToggle: true);
      await answer(tester, standardBoard());
      await tester
          .tap(find.byKey(const ValueKey<String>('gift-lb-metric-gifts')));
      await tester.pump();
      expect(lastQuery()['metric'], 'gifts');
      await answer(tester, standardBoard(metric: LeaderboardMetric.gifts));
      expect(inRow('ayla', find.text('120')), findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey<String>('gift-lb-metric-units')));
      await tester.pump();
      expect(api.calls.length, 2, reason: 'units are cached');
      expect(inRow('ayla', find.text('54K')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('coinName names the units button; labels override',
        (tester) async {
      await pumpBoard(tester, metricToggle: true, coinName: 'gems');
      expect(find.text('Gems'), findsOneWidget);
      await finish(tester);
      await pumpBoard(
        tester,
        metricToggle: true,
        coinName: 'gems',
        labels: const GiftLabels(metricUnits: 'Elmas', metricGifts: 'Hediye'),
      );
      expect(find.text('Elmas'), findsOneWidget);
      expect(find.text('Hediye'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('the metric prop starts on gifts', (tester) async {
      await pumpBoard(tester, metric: LeaderboardMetric.gifts);
      expect(lastQuery()['metric'], 'gifts');
      await finish(tester);
    });
  });

  group('accessibility and rows as buttons', () {
    testWidgets(
        'each row is one labelled element: "Rank 1, ayla, 54,000 coins"',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(tester, coinName: 'gems');
      await answer(tester, standardBoard(me: null));
      expect(
          find.bySemanticsLabel('Rank 1, ayla, 54,000 gems'), findsOneWidget);
      expect(
          find.bySemanticsLabel('Rank 2, mert, 41,000 gems'), findsOneWidget);
      expect(find.bySemanticsLabel('Rank 2, ece, 41,000 gems'), findsOneWidget);
      expect(find.bySemanticsLabel('Rank 4, can, 900 gems'), findsOneWidget);
      expect(
          isButton(tester, find.bySemanticsLabel('Rank 1, ayla, 54,000 gems')),
          isFalse);
      handle.dispose();
      await finish(tester);
    });

    testWidgets('labels: rowSpoken and giftsWord translate', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(
        tester,
        metric: LeaderboardMetric.gifts,
        labels: const GiftLabels(
          rowSpoken: '{rank}. sira, {name}, {score}',
          giftsWord: 'hediye',
        ),
      );
      await answer(
        tester,
        standardBoard(metric: LeaderboardMetric.gifts, me: null),
      );
      expect(
          find.bySemanticsLabel('1. sira, ayla, 120 hediye'), findsOneWidget);
      expect(inRow('ayla', find.text('hediye')), findsOneWidget);
      handle.dispose();
      await finish(tester);
    });

    testWidgets('onPressUser: rows and the pinned row are buttons',
        (tester) async {
      final handle = tester.ensureSemantics();
      final pressed = <String>[];
      await pumpBoard(tester, onPressUser: pressed.add);
      await answer(tester, standardBoard());
      expect(
          isButton(tester, find.bySemanticsLabel('Rank 1, ayla, 54,000 coins')),
          isTrue);
      await tester.tap(find.byKey(rowKey('ece')));
      await tester.tap(find.byKey(_pinned));
      expect(pressed, <String>['ece', 'user_123']);
      handle.dispose();
      await finish(tester);
    });

    testWidgets('without onPressUser a tap does nothing', (tester) async {
      await pumpBoard(tester);
      await answer(tester, standardBoard());
      await tester.tap(find.byKey(rowKey('ece')));
      await tester.pump();
      expect(api.calls.length, 1);
      await finish(tester);
    });

    testWidgets('a row is 52 dp high', (tester) async {
      await pumpBoard(tester);
      await answer(tester, standardBoard());
      expect(tester.getSize(find.byKey(rowKey('ayla'))).height, 52);
      expect(tester.getSize(find.byKey(_pinned)).height, 52);
      await finish(tester);
    });
  });

  group('names and pictures', () {
    testWidgets('resolveUsers: asked for the rows once; names and initials',
        (tester) async {
      final asked = <List<String>>[];
      await pumpBoard(
        tester,
        resolveUsers: (ids) async {
          asked.add(ids);
          return <String, LeaderboardUser>{
            'ayla': const LeaderboardUser(name: 'Ayla Kaya'),
            'user_123': const LeaderboardUser(name: 'Emma'),
          };
        },
      );
      await answer(tester, standardBoard());
      await tester.idle();
      await tester.pump();
      expect(asked.single, <String>['ayla', 'mert', 'ece', 'can', 'user_123']);
      expect(inRow('ayla', find.text('Ayla Kaya')), findsOneWidget);
      expect(inRow('ayla', find.text('A')), findsOneWidget);
      expect(inRow('mert', find.text('mert')), findsOneWidget,
          reason: 'id fallback');
      // The pinned row shows the avatar of the viewer.
      expect(
        find.descendant(of: find.byKey(_pinned), matching: find.text('E')),
        findsOneWidget,
      );
      // The same ids are not asked again on a refresh.
      key.currentState!.refresh();
      await tester.pump();
      await answer(tester, standardBoard());
      await tester.idle();
      expect(asked.length, 1);
      await finish(tester);
    });

    testWidgets('a pictured avatar loads its picture; none: an initial',
        (tester) async {
      await pumpBoard(
        tester,
        resolveUsers: (ids) async => <String, LeaderboardUser>{
          'ayla': const LeaderboardUser(
            name: 'Ayla',
            avatarUrl: 'https://assets.test/u/ayla.png',
          ),
        },
      );
      await answer(tester, standardBoard(me: null));
      await tester.idle();
      await tester.pump();
      expect(images.requested, contains('https://assets.test/u/ayla.png'));
      expect(inRow('ayla', find.text('A')), findsNothing, reason: 'picture');
      expect(inRow('mert', find.text('M')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a lookup that fails is tried again with the next answer',
        (tester) async {
      var calls = 0;
      await pumpBoard(
        tester,
        resolveUsers: (ids) async {
          calls++;
          if (calls == 1) throw StateError('x');
          return <String, LeaderboardUser>{
            'ayla': const LeaderboardUser(name: 'Ayla'),
          };
        },
      );
      await answer(tester, standardBoard(me: null));
      await tester.idle();
      expect(inRow('ayla', find.text('ayla')), findsOneWidget);
      key.currentState!.refresh();
      await tester.pump();
      await answer(tester, standardBoard(me: null));
      await tester.idle();
      await tester.pump();
      expect(calls, 2);
      expect(inRow('ayla', find.text('Ayla')), findsOneWidget);
      await finish(tester);
    });
  });

  group('theme', () {
    testWidgets('surface, border, accent tab, text, muted, selected',
        (tester) async {
      const theme = GiftingTheme(
        surface: Color(0xFF112233),
        border: Color(0xFF445566),
        accent: Color(0xFF0000CC),
        accentText: Color(0xFFFFFF00),
        text: Color(0xFFAA0000),
        muted: Color(0xFF00AA00),
        selected: Color(0xFF999999),
        coin: Color(0xFFABCDEF),
      );
      await pumpBoard(tester, theme: theme);
      await answer(tester, standardBoard(me: null));
      final root = tester.widget<Container>(
        find
            .ancestor(of: find.byKey(_list), matching: find.byType(Container))
            .last,
      );
      expect(
          (root.decoration! as BoxDecoration).color, const Color(0xFF112233));
      expect(
        tester.widget<Text>(find.text('This week')).style!.color,
        const Color(0xFFFFFF00),
      );
      expect(
        tester.widget<Text>(find.text('Today')).style!.color,
        const Color(0xFF00AA00),
      );
      expect(
        tester.widget<Text>(inRow('mert', find.text('mert'))).style!.color,
        const Color(0xFFAA0000),
      );
      await finish(tester);
    });
  });
  group('renderRow slot', () {
    testWidgets('draws its own row; the context carries the computed data',
        (tester) async {
      final seen = <LeaderboardRowContext>[];
      await pumpBoard(
        tester,
        highlightUser: 'ece',
        resolveUsers: (ids) async => <String, LeaderboardUser>{
          'ayla': const LeaderboardUser(
            name: 'Ayla K',
            avatarUrl: 'https://img.test/ayla.png',
          ),
        },
        renderRow: (context, row) {
          seen.add(row);
          return Text('mine #${row.rank} ${row.name} ${row.scoreText}');
        },
      );
      await answer(tester, standardBoard());
      await tester.pump();
      expect(find.text('mine #1 Ayla K 54K'), findsOneWidget);
      expect(find.text('mine #4 can 900'), findsOneWidget);
      final ayla = seen.lastWhere((r) => r.entry.user == 'ayla');
      expect(ayla.score, 54000);
      expect(ayla.metric, LeaderboardMetric.units);
      expect(ayla.avatarUrl, 'https://img.test/ayla.png');
      expect(ayla.isMe, isFalse);
      expect(seen.lastWhere((r) => r.entry.user == 'ece').isMe, isTrue);
      // The default rank disc and score are gone from a custom row.
      expect(inRow('ayla', find.byType(CoinDot)), findsNothing);
      // The pinned "You" row stays the default.
      expect(find.byKey(_pinned), findsOneWidget);
      expect(find.text('Sen'), findsNothing);
      await finish(tester);
    });

    testWidgets('gifts metric: score is the gift count', (tester) async {
      final seen = <LeaderboardRowContext>[];
      await pumpBoard(
        tester,
        metric: LeaderboardMetric.gifts,
        renderRow: (context, row) {
          seen.add(row);
          return Text('mine ${row.scoreText}');
        },
      );
      await answer(tester, standardBoard(metric: LeaderboardMetric.gifts));
      expect(seen.first.score, 120);
      expect(find.text('mine 120'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('null falls back to the default row', (tester) async {
      await pumpBoard(tester, renderRow: (context, row) => null);
      await answer(tester, standardBoard());
      expect(inRow('ayla', find.text('ayla')), findsOneWidget);
      expect(inRow('ayla', find.byType(CoinDot)), findsOneWidget);
      expect(tester.getSize(find.byKey(rowKey('ayla'))).height, 52);
      await finish(tester);
    });

    testWidgets('the press and the spoken label stay with the SDK',
        (tester) async {
      final handle = tester.ensureSemantics();
      final pressed = <String>[];
      await pumpBoard(
        tester,
        onPressUser: pressed.add,
        renderRow: (context, row) => Text('mine ${row.name}'),
      );
      await answer(tester, standardBoard());
      expect(
          isButton(tester, find.bySemanticsLabel('Rank 1, ayla, 54,000 coins')),
          isTrue);
      await tester.tap(find.text('mine ece'));
      expect(pressed, <String>['ece']);
      expect(find.bySemanticsLabel('mine ayla'), findsNothing);
      handle.dispose();
      await finish(tester);
    });
  });
}

/// The colour of a `#rrggbb` token as the widget builds it.
Color giftColorOf(String hex) {
  final v = int.parse(hex.substring(1), radix: 16);
  return Color(0xFF000000 | v);
}
