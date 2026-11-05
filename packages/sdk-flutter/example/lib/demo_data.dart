import 'package:flutter/painting.dart' show Color;
import 'package:giftingstack/giftingstack.dart';

/// Believable mock data for the gift wall, the "while you were away" card and
/// the leaderboard. Demo only: a real app gets all of this from GiftingStack.

/// Names for the demo's external ids (what an app's own user table knows).
const Map<String, String> demoUserNames = {
  'mira': 'Mira',
  'noor': 'Noor',
  'zoe': 'Zoe Lambert',
  'caleb': 'Caleb Stone',
  'elise': 'Elise',
  'mateo': 'Mateo Silva',
  'dana': 'Dana',
  'sofia': 'Sofia Rossi',
  'ben': 'Ben',
  'emma': 'Emma',
  'owen': 'Owen Reed',
  'mila': 'Mila Hart',
  'theo': 'Theo Martin',
  'iris': 'Iris Novak',
  'kai': 'Kai',
  'daphne': 'Daphne Lee',
  'bruno': 'Bruno Diaz',
  'ava': 'Ava Carter',
};

/// Avatar colours of the demo's people (an app has its own pictures).
const Map<String, Color> demoUserColors = {
  'ava': Color(0xFFE0457B),
  'mateo': Color(0xFF2F9E8F),
  'zoe': Color(0xFF7B61FF),
  'caleb': Color(0xFFE8892B),
  'dana': Color(0xFF2A8FD6),
  'elise': Color(0xFFC2453D),
  'sofia': Color(0xFF1F9D7A),
  'ben': Color(0xFF6B7A8F),
  'emma': Color(0xFFB04FD0),
  'owen': Color(0xFF4C6EF5),
  'mila': Color(0xFFD6559A),
  'theo': Color(0xFF3B82A0),
  'iris': Color(0xFFC9822B),
  'kai': Color(0xFF3AA356),
  'daphne': Color(0xFF8E5BD9),
  'bruno': Color(0xFFD9534F),
};

/// A demo person's name, or the id itself.
String nameOf(String id) => demoUserNames[id] ?? id;

/// The first word of [nameOf].
String firstNameOf(String id) => nameOf(id).split(' ').first;

/// One post of the demo feed. [id] is the `reference` of the gifts sent to it.
class Post {
  /// Creates a post.
  const Post(this.id, this.author, this.text, this.art, this.ago, this.likes);

  /// `post_42`...
  final String id;

  /// The author's external id: the receiver of gifts sent to the post.
  final String author;

  /// The caption.
  final String text;

  /// Which drawing the post shows.
  final PostArt art;

  /// "2h".
  final String ago;

  /// The like count.
  final int likes;
}

/// The drawings of the demo posts (painted, no pictures from the network).
enum PostArt { sunset, city, ocean, aurora }

/// The posts of the feed (same content as the web demo).
const List<Post> demoPosts = [
  Post(
    'post_42',
    'mateo',
    'Golden hour on the pier. It never gets old.',
    PostArt.sunset,
    '2h',
    482,
  ),
  Post(
    'post_43',
    'zoe',
    'New skyline set, three weeks of work. Which window is your favourite?',
    PostArt.city,
    '5h',
    1204,
  ),
  Post(
    'post_44',
    'caleb',
    'The tide was perfect this morning.',
    PostArt.ocean,
    '9h',
    236,
  ),
  Post(
    'post_45',
    'dana',
    'Northern lights from the cabin porch. Hot chocolate helped.',
    PostArt.aurora,
    '1d',
    3071,
  ),
];

/// How many of each gift a post received, in catalog order: about ten kinds,
/// so the wall shows the "+N" chip.
const List<int> wallBaseCounts = [12, 3, 1, 27, 8, 5, 2, 9, 4, 6];

/// The wall of [user] (under the post [reference], or the profile when null):
/// the first ten gifts of [catalog] with [wallBaseCounts] (more for other
/// authors and for a profile), plus what reached it in this session ([extra]:
/// gift id -> count). `mateo`'s `post_42` is the plain base.
List<ReceivedGift> wallFor(
  List<Gift> catalog,
  Map<String, int> extra, {
  String user = 'mateo',
  String? reference = 'post_42',
}) {
  final seed =
      user.codeUnits.fold(0, (a, c) => a + c) + (reference ?? '').length;
  final mult = user == 'mateo' && reference == 'post_42'
      ? 1
      : reference == null
          ? 3
          : 1 + seed % 4;
  final ids = <String>{for (final g in catalog) g.id};
  final first = catalog.take(wallBaseCounts.length).toList();
  return [
    for (final (i, g) in first.indexed)
      ReceivedGift(
        gift: GiftRef(id: g.id, name: g.name, iconUrl: g.iconUrl),
        count: wallBaseCounts[i] * mult + (extra[g.id] ?? 0),
      ),
    // A gift from outside the first ten still shows up.
    for (final e in extra.entries)
      if (ids.contains(e.key) && !first.any((g) => g.id == e.key))
        ReceivedGift(
          gift: GiftRef(
            id: e.key,
            name: catalog.firstWhere((g) => g.id == e.key).name,
            iconUrl: catalog.firstWhere((g) => g.id == e.key).iconUrl,
          ),
          count: e.value,
        ),
  ];
}

Gift _pickPrice(List<Gift> catalog, int from, int to, {int skip = 0}) {
  final fit = catalog.where((g) => g.price >= from && g.price <= to).toList()
    ..sort((a, b) => a.price.compareTo(b.price));
  if (fit.isNotEmpty) return fit[skip < fit.length ? skip : fit.length - 1];
  return catalog[skip < catalog.length ? skip : catalog.length - 1];
}

AwayGroup _group(
  Gift g,
  int count,
  int senderCount,
  List<AwaySender> senders,
) =>
    AwayGroup(
      gift: AwayGift(
        id: g.id,
        name: g.name,
        price: g.price,
        iconUrl: g.iconUrl,
        animationUrl: g.animationUrl,
      ),
      count: count,
      units: count * g.price,
      senderCount: senderCount,
      senders: senders,
    );

/// A summary of gifts "received while away": one large gift, two medium and
/// two small groups, several senders and a deleted one (`user: null`).
AwaySummary awaySummaryFor(List<Gift> catalog, {String cursor = 'aw1.demo'}) {
  final large = _pickPrice(catalog, 10000, 1 << 30);
  final mediumA = _pickPrice(catalog, 100, 9999, skip: 1);
  final mediumB = _pickPrice(catalog, 100, 9999, skip: 3);
  final smallA = _pickPrice(catalog, 1, 99, skip: 1);
  final smallB = _pickPrice(catalog, 1, 99, skip: 0);
  final groups = [
    _group(large, 1, 1, const [AwaySender(user: 'zoe', count: 1)]),
    _group(mediumA, 20, 6, const [
      AwaySender(user: 'caleb', count: 9),
      AwaySender(user: null, count: 4),
      AwaySender(user: 'elise', count: 3),
    ]),
    _group(mediumB, 6, 2, const [
      AwaySender(user: 'elise', count: 4),
      AwaySender(user: 'mateo', count: 2),
    ]),
    _group(smallA, 50, 2, const [
      AwaySender(user: 'elise', count: 30),
      AwaySender(user: 'caleb', count: 20),
    ]),
    _group(smallB, 3, 1, const [AwaySender(user: null, count: 3)]),
  ]..sort((a, b) {
      final byUnits = b.units.compareTo(a.units);
      return byUnits != 0 ? byUnits : a.gift.id.compareTo(b.gift.id);
    });
  return AwaySummary(
    user: 'ava',
    since: '2026-10-08T09:12:44.120Z',
    until: '2026-10-11T07:30:02.511Z',
    cursor: cursor,
    truncated: false,
    totalGifts: groups.fold(0, (s, g) => s + g.count),
    totalUnits: groups.fold(0, (s, g) => s + g.units),
    senderCount: 9,
    groups: groups,
    // By count, as the API sends them: the card shows the first three.
    topSenders: const [
      AwayTopSender(user: 'elise', count: 37, units: 9100),
      AwayTopSender(user: 'caleb', count: 29, units: 4400),
      AwayTopSender(user: null, count: 7, units: 1200),
      AwayTopSender(user: 'mateo', count: 2, units: 500),
      AwayTopSender(user: 'zoe', count: 1, units: 40000),
    ],
  );
}

/// An empty summary (nothing new since the last look).
AwaySummary emptyAwaySummary({String cursor = 'aw1.demo'}) => AwaySummary(
      user: 'ava',
      since: '2026-10-11T07:30:02.511Z',
      until: '2026-10-11T07:31:00.000Z',
      cursor: cursor,
      truncated: false,
      totalGifts: 0,
      totalUnits: 0,
      senderCount: 0,
      groups: const [],
      topSenders: const [],
    );

/// `(user, gifts, units)` of the 15 demo users, with ties on units
/// (caleb/elise, dana/sofia, owen/mila).
const List<(String, int, int)> _people = [
  ('zoe', 120, 54000),
  ('caleb', 300, 41000),
  ('elise', 80, 41000),
  ('mateo', 45, 28000),
  ('dana', 70, 23500),
  ('sofia', 66, 23500),
  ('ben', 90, 12000),
  ('emma', 22, 9800),
  ('owen', 31, 7600),
  ('mila', 18, 7600),
  ('theo', 12, 5100),
  ('iris', 9, 3300),
  ('kai', 14, 2000),
  ('daphne', 4, 900),
  ('bruno', 3, 150),
];

const Map<LeaderboardPeriod, int> _scale = {
  LeaderboardPeriod.day: 1,
  LeaderboardPeriod.week: 4,
  LeaderboardPeriod.month: 14,
  LeaderboardPeriod.all: 60,
};

/// A board of the 15 demo users for [period] and [metric], at most [limit]
/// rows, with the viewer `ava` outside the rows (rank 417, or "1,000+" for
/// all time).
Leaderboard leaderboardFor(
  LeaderboardBoard board, {
  LeaderboardPeriod period = LeaderboardPeriod.week,
  LeaderboardMetric? metric,
  int limit = 10,
  bool includeMe = true,
  bool hidden = false,
}) {
  final m = metric ??
      (board == LeaderboardBoard.receivers
          ? LeaderboardMetric.gifts
          : LeaderboardMetric.units);
  final k = _scale[period]!;
  final scored = [
    for (final p in _people) (user: p.$1, gifts: p.$2 * k, units: p.$3 * k),
  ];
  int score(({String user, int gifts, int units}) r) =>
      m == LeaderboardMetric.gifts ? r.gifts : r.units;
  scored.sort((a, b) {
    final c = score(b).compareTo(score(a));
    return c != 0 ? c : a.user.compareTo(b.user);
  });
  // Competition ranking: equal scores share a rank (1, 2, 2, 4).
  final rows = <LeaderboardEntry>[];
  for (final (i, r) in scored.indexed) {
    final rank =
        i > 0 && score(scored[i - 1]) == score(r) ? rows[i - 1].rank : i + 1;
    rows.add(
      LeaderboardEntry(
          rank: rank, user: r.user, gifts: r.gifts, units: r.units),
    );
  }
  final shown = rows.take(limit).toList();
  return Leaderboard(
    board: board,
    period: period,
    metric: m,
    label: period == LeaderboardPeriod.all ? 'all' : '2026-W41',
    startsAt:
        period == LeaderboardPeriod.all ? null : '2026-10-05T00:00:00.000Z',
    endsAt: period == LeaderboardPeriod.all ? null : '2026-10-12T00:00:00.000Z',
    asOf: DateTime.now().toUtc().toIso8601String(),
    data: shown,
    hasMore: rows.length > shown.length,
    me: includeMe
        ? LeaderboardMe(
            user: 'ava',
            rank: period == LeaderboardPeriod.all ? null : 417,
            gifts: 3 * k,
            units: 120 * k,
            hidden: hidden,
          )
        : null,
  );
}
