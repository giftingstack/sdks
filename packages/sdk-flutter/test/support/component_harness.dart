import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/giftingstack.dart';

import 'ui_harness.dart';

/// A screen for the component widgets: a Directionality and the media settings
/// a phone has. [stack] puts [child] in a full-size `Stack` (the away card
/// fills its parent).
Widget hostApp(
  Widget child, {
  bool disableAnimations = false,
  Size size = const Size(400, 800),
  bool stack = false,
}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: disableAnimations),
        child: stack
            ? SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(children: <Widget>[child]),
              )
            : Align(alignment: Alignment.topLeft, child: child),
      ),
    );

/// Pictures that are always loaded (no network), on a 400 x 800 screen.
Future<ControlledImages> loadedImages(WidgetTester tester) async {
  final images = ControlledImages(autoLoad: true);
  await images.init(tester);
  return images;
}

/// A received gift with the picture URL `https://assets.test/<id>/256.webp`.
ReceivedGift received(String id, int count, {String? name, bool icon = true}) =>
    ReceivedGift(
      gift: GiftRef(
        id: id,
        name: name ?? '${id[0].toUpperCase()}${id.substring(1)}',
        iconUrl: icon ? 'https://assets.test/$id/256.webp' : null,
      ),
      count: count,
    );

/// A wall answer for each queried item (the same gifts for every wall).
List<GiftWallResult> wallAnswers(
  List<Map<String, Object?>> items,
  List<ReceivedGift> gifts,
) =>
    <GiftWallResult>[
      for (final i in items)
        GiftWallResult(
          receiver: i['receiver']! as String,
          reference: i['reference'] as String?,
          gifts: gifts,
        ),
    ];

AwayGift awayGift(String id, int price, {String? name}) => AwayGift(
      id: id,
      name: name ?? '${id[0].toUpperCase()}${id.substring(1)}',
      price: price,
      iconUrl: 'https://assets.test/$id/256.webp',
      animationUrl: price >= 100 ? 'https://assets.test/$id/512.webp' : null,
    );

AwayGroup awayGroup(
  String id,
  int price,
  int count, {
  int? senderCount,
  List<AwaySender>? senders,
}) =>
    AwayGroup(
      gift: awayGift(id, price),
      count: count,
      units: count * price,
      senderCount: senderCount ?? 1,
      senders: senders ?? <AwaySender>[AwaySender(user: 'ayla', count: count)],
    );

/// The worked example of the fixtures: dragon, hat, rose, star.
AwaySummary workedSummary({
  String cursor = 'aw1.AAA',
  bool truncated = false,
  int totalGifts = 74,
  int senderCount = 9,
  List<AwayGroup>? groups,
}) =>
    AwaySummary(
      user: 'user_123',
      since: '2026-10-08T09:12:44.120Z',
      until: '2026-10-11T07:30:02.511Z',
      cursor: cursor,
      truncated: truncated,
      totalGifts: totalGifts,
      totalUnits: 47515,
      senderCount: senderCount,
      groups: groups ??
          <AwayGroup>[
            awayGroup('dragon', 40000, 1),
            awayGroup(
              'hat',
              350,
              20,
              senderCount: 6,
              senders: const <AwaySender>[
                AwaySender(user: 'mert', count: 9),
                AwaySender(user: null, count: 4),
                AwaySender(user: 'ece', count: 3),
              ],
            ),
            awayGroup(
              'rose',
              10,
              50,
              senderCount: 2,
              senders: const <AwaySender>[
                AwaySender(user: 'ece', count: 30),
                AwaySender(user: 'mert', count: 20),
              ],
            ),
            awayGroup(
              'star',
              5,
              3,
              senders: const <AwaySender>[AwaySender(user: null, count: 3)],
            ),
          ],
      topSenders: const <AwayTopSender>[
        AwayTopSender(user: 'ayla', count: 15, units: 41200),
        AwayTopSender(user: null, count: 7, units: 900),
        AwayTopSender(user: 'mert', count: 29, units: 5000),
        AwayTopSender(user: 'ece', count: 33, units: 800),
      ],
    );

/// An empty summary (nothing new).
AwaySummary emptySummary() => const AwaySummary(
      user: 'user_123',
      since: '2026-10-08T09:12:44.120Z',
      until: '2026-10-11T07:30:02.511Z',
      cursor: 'aw1.OLD',
      truncated: false,
      totalGifts: 0,
      totalUnits: 0,
      senderCount: 0,
      groups: <AwayGroup>[],
      topSenders: <AwayTopSender>[],
    );

/// A board of senders. [rows] is `(rank, user, gifts, units)`.
Leaderboard boardOf({
  required List<(int, String, int, int)> rows,
  LeaderboardPeriod period = LeaderboardPeriod.week,
  LeaderboardMetric metric = LeaderboardMetric.units,
  LeaderboardBoard board = LeaderboardBoard.senders,
  LeaderboardMe? me,
  String asOf = '2026-10-11T07:30:00.000Z',
}) =>
    Leaderboard(
      board: board,
      period: period,
      metric: metric,
      label: '2026-W41',
      asOf: asOf,
      hasMore: false,
      data: <LeaderboardEntry>[
        for (final r in rows)
          LeaderboardEntry(rank: r.$1, user: r.$2, gifts: r.$3, units: r.$4),
      ],
      me: me,
    );

/// ayla 54,000 / mert 41,000 / ece 41,000 (tie) / can 900, and a viewer outside.
Leaderboard standardBoard({
  LeaderboardPeriod period = LeaderboardPeriod.week,
  LeaderboardMetric metric = LeaderboardMetric.units,
  LeaderboardMe? me = const LeaderboardMe(
    user: 'user_123',
    rank: 417,
    gifts: 3,
    units: 120,
    hidden: false,
  ),
  String asOf = '2026-10-11T07:30:00.000Z',
}) =>
    boardOf(
      period: period,
      metric: metric,
      asOf: asOf,
      me: me,
      rows: const <(int, String, int, int)>[
        (1, 'ayla', 120, 54000),
        (2, 'mert', 300, 41000),
        (2, 'ece', 80, 41000),
        (4, 'can', 7, 900),
      ],
    );
