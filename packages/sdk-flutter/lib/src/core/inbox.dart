/// The gift inbox (SPEC section 19): the models of `GET /v1/client/me/inbox`
/// and the pure helpers behind the list (time label, rows, unread count). No
/// drawing. Port of `packages/sdk-js/src/core/inbox.ts`.
library;

import 'component_types.dart';

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

/// `status` of a gift that stands.
const String inboxStatusCompleted = 'completed';

/// `status` of a gift that was taken back; the rows hide it.
const String inboxStatusReversed = 'reversed';

/// One gift the signed-in user received (`data` of [Inbox]). Never carries the
/// gift's message, metadata or reference.
class InboxItem {
  /// Creates an item.
  const InboxItem({
    required this.id,
    required this.createdAt,
    required this.sender,
    required this.gift,
    required this.quantity,
    required this.units,
    required this.status,
  });

  /// Decodes the API's JSON.
  factory InboxItem.fromJson(Map<String, Object?> json) => InboxItem(
        id: _str(json['id']),
        createdAt: _str(json['created_at']),
        sender: _strOrNull(json['sender']),
        gift: AwayGift.fromJson(_map(json['gift'])),
        quantity: _int(json['quantity']),
        units: _int(json['units']),
        status: _str(json['status']),
      );

  /// The gift transaction (`gtx_...`).
  final String id;

  /// When it was sent (ISO 8601).
  final String createdAt;

  /// External id of the sender; null for a deleted sender.
  final String? sender;

  /// Which gift (today's catalog price, name and pictures).
  final AwayGift gift;

  /// How many.
  final int quantity;

  /// Value of the gift (price x quantity) when it was sent.
  final int units;

  /// `completed` or `reversed`.
  final String status;

  /// Wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'created_at': createdAt,
        'sender': sender,
        'gift': gift.toJson(),
        'quantity': quantity,
        'units': units,
        'status': status,
      };
}

/// One page of `GET /v1/client/me/inbox`: gifts received in the last 24 hours,
/// newest first.
class Inbox {
  /// Creates a page.
  const Inbox({
    required this.user,
    required this.since,
    required this.until,
    required this.data,
    required this.hasMore,
    this.nextCursor,
  });

  /// Decodes the API's JSON.
  factory Inbox.fromJson(Map<String, Object?> json) => Inbox(
        user: _str(json['user']),
        since: _str(json['since']),
        until: _str(json['until']),
        data: _list(json['data'])
            .map((e) => InboxItem.fromJson(_map(e)))
            .toList(),
        hasMore: _bool(json['has_more']),
        nextCursor: _strOrNull(json['next_cursor']),
      );

  /// The token user.
  final String user;

  /// Start of the window (24 hours before [until]).
  final String since;

  /// When the page was read.
  final String until;

  /// Newest first.
  final List<InboxItem> data;

  /// Whether an older page exists.
  final bool hasMore;

  /// Pass it to `getInbox(cursor: ...)` for the next (older) page; null on the
  /// last page.
  final String? nextCursor;

  /// Wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'user': user,
        'since': since,
        'until': until,
        'data': data.map((i) => i.toJson()).toList(),
        'has_more': hasMore,
        'next_cursor': nextCursor,
      };
}

/// One row of the list, ready to draw.
class InboxRow {
  /// Creates a row.
  const InboxRow({
    required this.id,
    required this.senderName,
    required this.giftName,
    required this.quantity,
    required this.time,
    required this.iconUrl,
    required this.sender,
  });

  /// The gift transaction.
  final String id;

  /// `Someone` for a deleted sender, else the resolved name, else the id.
  final String senderName;

  /// The gift's name.
  final String giftName;

  /// How many.
  final int quantity;

  /// `now`, `5m`, `3h` or `2d`.
  final String time;

  /// The gift's small picture, if any.
  final String? iconUrl;

  /// External id of the sender; null for a deleted sender.
  final String? sender;
}

/// The age of a gift as a short label: under a minute (or a clock that went
/// back) `now`, then `5m`, `3h`, `2d` (SPEC 19.2).
String inboxTimeLabel(int createdAtMs, int nowMs) {
  final d = nowMs - createdAtMs;
  if (d < 60000) return 'now';
  if (d < 3600000) return '${d ~/ 60000}m';
  if (d < 86400000) return '${d ~/ 3600000}h';
  return '${d ~/ 86400000}d';
}

/// The rows of [items] in the same order, without reversed gifts. [names] maps
/// a sender id to a display name (an unknown id keeps the id).
List<InboxRow> inboxRows(
  List<InboxItem> items,
  int nowMs,
  Map<String, String> names,
) =>
    <InboxRow>[
      for (final i in items)
        if (i.status != inboxStatusReversed)
          InboxRow(
            id: i.id,
            senderName:
                i.sender == null ? 'Someone' : (names[i.sender] ?? i.sender!),
            giftName: i.gift.name,
            quantity: i.quantity,
            time: inboxTimeLabel(
              DateTime.tryParse(i.createdAt)?.millisecondsSinceEpoch ?? nowMs,
              nowMs,
            ),
            iconUrl: i.gift.iconUrl,
            sender: i.sender,
          ),
    ];

/// How many completed gifts are strictly newer than [lastSeenMs] (all of them
/// when it is null). Reversed gifts never count.
int inboxUnread(List<InboxItem> items, int? lastSeenMs) {
  var n = 0;
  for (final i in items) {
    if (i.status != inboxStatusCompleted) continue;
    final at = DateTime.tryParse(i.createdAt)?.millisecondsSinceEpoch;
    if (at == null) continue;
    if (lastSeenMs == null || at > lastSeenMs) n++;
  }
  return n;
}
