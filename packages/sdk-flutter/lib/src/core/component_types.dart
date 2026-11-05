/// Models of the gift wall, away summary and leaderboard calls (SPEC 14 to 16).
/// JSON keys stay snake_case; Dart names are camelCase.
library;

import 'types.dart';

Map<String, Object?> _map(Object? v) {
  if (v is Map<dynamic, dynamic>) return v.cast<String, Object?>();
  throw FormatException('Expected a JSON object, got ${v.runtimeType}.');
}

List<Object?> _list(Object? v) {
  if (v is List<dynamic>) return v.cast<Object?>();
  throw FormatException('Expected a JSON array, got ${v.runtimeType}.');
}

int _int(Object? v) {
  if (v is num) return v.toInt();
  throw FormatException('Expected a number, got ${v.runtimeType}.');
}

String _str(Object? v) {
  if (v is String) return v;
  throw FormatException('Expected a string, got ${v.runtimeType}.');
}

String? _strOrNull(Object? v) => v == null ? null : _str(v);

bool _bool(Object? v) {
  if (v is bool) return v;
  throw FormatException('Expected a boolean, got ${v.runtimeType}.');
}

// ---------------------------------------------------------------- gift walls (SPEC 14)

/// One wall of the batch call `GiftingClient.queryGiftWalls`: a receiver's
/// profile wall, or with [reference] one post's wall.
class GiftWallQueryItem {
  /// Creates an item. A null [reference] is the profile wall.
  const GiftWallQueryItem({required this.receiver, this.reference});

  /// Whose gifts.
  final String receiver;

  /// Your own context id the gifts were sent with (for example a post id).
  final String? reference;

  /// Request JSON: a null reference is left out.
  Map<String, Object?> toJson() => <String, Object?>{
        'receiver': receiver,
        if (reference != null) 'reference': reference,
      };
}

/// One answer of `POST /v1/client/gift-walls/query`, in the order of the
/// request. (Named `GiftWallResult` so it does not clash with the `GiftWall`
/// widget.)
class GiftWallResult {
  /// Creates an answer.
  const GiftWallResult({
    required this.receiver,
    required this.gifts,
    this.reference,
  });

  /// Decodes the API's JSON.
  factory GiftWallResult.fromJson(Map<String, Object?> json) => GiftWallResult(
        receiver: _str(json['receiver']),
        reference: _strOrNull(json['reference']),
        gifts: _list(json['gifts'])
            .map((e) => ReceivedGift.fromJson(_map(e)))
            .toList(),
      );

  /// The receiver asked for.
  final String receiver;

  /// The reference asked for, or null for the profile wall.
  final String? reference;

  /// Counters per gift, in catalog order. Empty for unknown users.
  final List<ReceivedGift> gifts;

  /// Wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'receiver': receiver,
        'reference': reference,
        'gifts': gifts.map((g) => g.toJson()).toList(),
      };
}

// ---------------------------------------------------------------- away (SPEC 15)

/// One sender in an away summary.
class AwaySender {
  /// Creates a sender.
  const AwaySender({required this.user, required this.count});

  /// Decodes the API's JSON.
  factory AwaySender.fromJson(Map<String, Object?> json) => AwaySender(
        user: _strOrNull(json['user']),
        count: _int(json['count']),
      );

  /// External id; null = deleted senders (all merged into one entry).
  final String? user;

  /// How many gifts.
  final int count;

  /// Wire JSON.
  Map<String, Object?> toJson() =>
      <String, Object?>{'user': user, 'count': count};
}

/// A sender of the away summary's `top_senders`: also the value they sent.
class AwayTopSender extends AwaySender {
  /// Creates a top sender.
  const AwayTopSender({
    required super.user,
    required super.count,
    required this.units,
  });

  /// Decodes the API's JSON.
  factory AwayTopSender.fromJson(Map<String, Object?> json) => AwayTopSender(
        user: _strOrNull(json['user']),
        count: _int(json['count']),
        units: _int(json['units']),
      );

  /// Value in your own coin units. A display counter, never a balance.
  final int units;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'user': user,
        'count': count,
        'units': units,
      };
}

/// The gift of an [AwayGroup]: today's catalog row.
class AwayGift {
  /// Creates a gift.
  const AwayGift({
    required this.id,
    required this.name,
    required this.price,
    this.iconUrl,
    this.animationUrl,
  });

  /// Decodes the API's JSON.
  factory AwayGift.fromJson(Map<String, Object?> json) => AwayGift(
        id: _str(json['id']),
        name: _str(json['name']),
        price: _int(json['price']),
        iconUrl: _strOrNull(json['icon_url']),
        animationUrl: _strOrNull(json['animation_url']),
      );

  /// Gift id.
  final String id;

  /// Display name.
  final String name;

  /// Today's catalog price: the effect tier matches the tray's.
  final int price;

  /// Small picture.
  final String? iconUrl;

  /// Big picture.
  final String? animationUrl;

  /// Wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'price': price,
        'icon_url': iconUrl,
        'animation_url': animationUrl,
      };
}

/// One gift kind received while away.
class AwayGroup {
  /// Creates a group.
  const AwayGroup({
    required this.gift,
    required this.count,
    required this.units,
    required this.senderCount,
    required this.senders,
  });

  /// Decodes the API's JSON.
  factory AwayGroup.fromJson(Map<String, Object?> json) => AwayGroup(
        gift: AwayGift.fromJson(_map(json['gift'])),
        count: _int(json['count']),
        units: _int(json['units']),
        senderCount: _int(json['sender_count']),
        senders: _list(json['senders'])
            .map((e) => AwaySender.fromJson(_map(e)))
            .toList(),
      );

  /// Which gift.
  final AwayGift gift;

  /// Number of gifts (sum of quantities).
  final int count;

  /// Value in your own coin units. A display counter, never a balance.
  final int units;

  /// Distinct people who sent this gift.
  final int senderCount;

  /// At most 3, by count.
  final List<AwaySender> senders;

  /// Wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'gift': gift.toJson(),
        'count': count,
        'units': units,
        'sender_count': senderCount,
        'senders': senders.map((s) => s.toJson()).toList(),
      };
}

/// What `GET /v1/client/me/away` returns: gifts received since the person
/// last looked.
class AwaySummary {
  /// Creates a summary.
  const AwaySummary({
    required this.user,
    required this.since,
    required this.until,
    required this.truncated,
    required this.totalGifts,
    required this.totalUnits,
    required this.senderCount,
    required this.groups,
    required this.topSenders,
    this.cursor,
  });

  /// Decodes the API's JSON.
  factory AwaySummary.fromJson(Map<String, Object?> json) => AwaySummary(
        user: _str(json['user']),
        since: _str(json['since']),
        until: _str(json['until']),
        cursor: _strOrNull(json['cursor']),
        truncated: _bool(json['truncated']),
        totalGifts: _int(json['total_gifts']),
        totalUnits: _int(json['total_units']),
        senderCount: _int(json['sender_count']),
        groups: _list(json['groups'])
            .map((e) => AwayGroup.fromJson(_map(e)))
            .toList(),
        topSenders: _list(json['top_senders'])
            .map((e) => AwayTopSender.fromJson(_map(e)))
            .toList(),
      );

  /// The token user.
  final String user;

  /// Start of the window (ISO 8601).
  final String since;

  /// End of the window (ISO 8601).
  final String until;

  /// Send this to `ackAway` once the summary was shown. Unchanged when
  /// nothing is new; may be null.
  final String? cursor;

  /// More than 2,000 gifts arrived: the totals are lower bounds ("2,000+").
  final bool truncated;

  /// Gifts received.
  final int totalGifts;

  /// Their value in your own coin units (a display counter).
  final int totalUnits;

  /// Distinct senders.
  final int senderCount;

  /// Biggest first (by units), at most `maxGroups`.
  final List<AwayGroup> groups;

  /// At most 5, by count.
  final List<AwayTopSender> topSenders;

  /// Wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'user': user,
        'since': since,
        'until': until,
        'cursor': cursor,
        'truncated': truncated,
        'total_gifts': totalGifts,
        'total_units': totalUnits,
        'sender_count': senderCount,
        'groups': groups.map((g) => g.toJson()).toList(),
        'top_senders': topSenders.map((s) => s.toJson()).toList(),
      };
}

// ---------------------------------------------------------------- leaderboards (SPEC 16)

/// Which board: top senders or top receivers.
enum LeaderboardBoard {
  /// People who sent the most.
  senders,

  /// People who received the most.
  receivers,
}

/// The window of a board (UTC).
enum LeaderboardPeriod {
  /// Today.
  day,

  /// This week (Monday to Sunday).
  week,

  /// This month.
  month,

  /// All time.
  all,
}

/// What a board ranks by.
enum LeaderboardMetric {
  /// Value, in your own coin units.
  units,

  /// Number of gifts.
  gifts,
}

/// One row of a board. Ranks are competition ranks (1, 2, 2, 4).
class LeaderboardEntry {
  /// Creates a row.
  const LeaderboardEntry({
    required this.rank,
    required this.user,
    required this.gifts,
    required this.units,
  });

  /// Decodes the API's JSON.
  factory LeaderboardEntry.fromJson(Map<String, Object?> json) =>
      LeaderboardEntry(
        rank: _int(json['rank']),
        user: _str(json['user']),
        gifts: _int(json['gifts']),
        units: _int(json['units']),
      );

  /// Competition rank on the metric: equal scores share a rank.
  final int rank;

  /// External id.
  final String user;

  /// Gifts.
  final int gifts;

  /// Value in your own coin units.
  final int units;

  /// Wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'rank': rank,
        'user': user,
        'gifts': gifts,
        'units': units,
      };
}

/// The signed-in user's own position on a board.
class LeaderboardMe {
  /// Creates a block.
  const LeaderboardMe({
    required this.user,
    required this.gifts,
    required this.units,
    required this.hidden,
    this.rank,
  });

  /// Decodes the API's JSON.
  factory LeaderboardMe.fromJson(Map<String, Object?> json) => LeaderboardMe(
        user: _str(json['user']),
        rank: json['rank'] == null ? null : _int(json['rank']),
        gifts: _int(json['gifts']),
        units: _int(json['units']),
        hidden: _bool(json['hidden']),
      );

  /// External id.
  final String user;

  /// Exact within the top 1,000, else null ("1,000+"). Also null without a
  /// score or when hidden.
  final int? rank;

  /// Gifts.
  final int gifts;

  /// Value in your own coin units.
  final int units;

  /// Opted out of boards.
  final bool hidden;

  /// Wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'user': user,
        'rank': rank,
        'gifts': gifts,
        'units': units,
        'hidden': hidden,
      };
}

/// What `GET /v1/client/leaderboards/{board}` returns.
class Leaderboard {
  /// Creates a board.
  const Leaderboard({
    required this.board,
    required this.period,
    required this.metric,
    required this.label,
    required this.asOf,
    required this.data,
    required this.hasMore,
    this.startsAt,
    this.endsAt,
    this.me,
  });

  /// Decodes the API's JSON.
  factory Leaderboard.fromJson(Map<String, Object?> json) => Leaderboard(
        board: LeaderboardBoard.values.byName(_str(json['board'])),
        period: LeaderboardPeriod.values.byName(_str(json['period'])),
        metric: LeaderboardMetric.values.byName(_str(json['metric'])),
        label: _str(json['label']),
        startsAt: _strOrNull(json['starts_at']),
        endsAt: _strOrNull(json['ends_at']),
        asOf: _str(json['as_of']),
        data: _list(json['data'])
            .map((e) => LeaderboardEntry.fromJson(_map(e)))
            .toList(),
        hasMore: _bool(json['has_more']),
        me: json['me'] == null
            ? null
            : LeaderboardMe.fromJson(_map(json['me'])),
      );

  /// Which board.
  final LeaderboardBoard board;

  /// Its window.
  final LeaderboardPeriod period;

  /// What it ranks by.
  final LeaderboardMetric metric;

  /// `2026-10-11`, `2026-W41`, `2026-10` or `all`.
  final String label;

  /// Start of the window, or null for all time.
  final String? startsAt;

  /// End of the window, or null for all time.
  final String? endsAt;

  /// When the server computed it (ISO 8601).
  final String asOf;

  /// The rows, best first.
  final List<LeaderboardEntry> data;

  /// More ranked users exist beyond the rows.
  final bool hasMore;

  /// The signed-in user's own position, if asked for.
  final LeaderboardMe? me;

  /// Wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'board': board.name,
        'period': period.name,
        'metric': metric.name,
        'label': label,
        'starts_at': startsAt,
        'ends_at': endsAt,
        'as_of': asOf,
        'data': data.map((e) => e.toJson()).toList(),
        'has_more': hasMore,
        'me': me?.toJson(),
      };
}
