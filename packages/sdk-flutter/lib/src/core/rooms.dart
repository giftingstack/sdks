/// Gift rooms, client side (SPEC sections 17 and 18; design in
/// docs/design/gift-rooms.md). Everything here is pure: the socket, the clock,
/// the timers, the random source and the token are injected, so the fixtures
/// `rooms-*.json` can drive it. The transport (a real WebSocket) and the app
/// lifecycle live in the UI layer. Port of
/// `packages/sdk-js/src/core/rooms.ts`.
///
/// Pieces: [parseRoomFrame] and [roomHelloFrame] (protocol),
/// [roomRetryDecision] (reconnect policy), [RoomEventFilter] (resume point,
/// dedup, staleness, own gifts, tier filter), [roomGiftToEffect] (event to
/// [GiftEffectEvent]) and [RoomClient] (the session state machine).
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'recipes.dart';
import 'secure_url.dart';
import 'timers.dart';
import 'types.dart';
import 'uri_encode.dart';

/// The only subprotocol; the client token rides as the second entry.
const String roomSubprotocol = 'gs.v1';

/// The rooms host used when no `url` is given.
const String defaultRoomsUrl = 'wss://rt.giftingstack.com';

/// Room id rule (SPEC 17.1).
final RegExp roomIdPattern = RegExp(r'^[A-Za-z0-9_.:-]{1,64}$');

/// Events older than this (server clock) are dropped instead of played.
const int defaultMaxReplayAgeMs = 10000;

/// Recent `tx` ids remembered for dedup.
const int roomDedupSize = 256;

/// Full jitter: `random(0, min(30 s, 0.5 s x 2^attempt))`, never below
/// [roomRetryFloorMs] (SPEC 18.3).
const int roomBackoffBaseMs = 500;

/// Cap of the backoff.
const int roomBackoffMaxMs = 30000;

/// First retry after a drop (1006) or a server restart (1012): `random(0, 5 s)`.
const int roomFirstDropMaxMs = 5000;

/// A jittered wait is never shorter than this, so a draw of 0 cannot start a
/// tight loop.
const int roomRetryFloorMs = 500;

/// Reconnect attempts in a row (no socket that stayed open [roomStableMs] in
/// between) before the client gives up: the state becomes `closed` with the
/// reason [roomReasonExhausted] and [RoomClient.reconnectNow] starts again with
/// a fresh budget. About 3.5 minutes at the longest.
const int roomMaxAttempts = 12;

/// `closed` reason after [roomMaxAttempts] failed attempts in a row.
const String roomReasonExhausted = 'retries_exhausted';

/// `getToken` has this long, from the start of a connection, to answer.
const int roomTokenMs = 20000;

/// A 4008 with `retry_after` never gives up; its wait grows up to this cap.
const int roomLimitedMaxMs = 300000;

/// Spread of the proactive token refresh (SPEC 18.5); the entry points set it.
const int roomRefreshJitterMs = 120000;

/// Rate limited (4008) or room full (4009): wait at least this...
const int roomLimitedMinMs = 30000;

/// ...and at most this many such waits in a row.
const int roomLimitedMaxRetries = 5;

/// The attempt counters reset after a socket stayed open this long.
const int roomStableMs = 60000;

/// App heartbeat: `ping` after this long without any frame. (Native
/// transports have protocol pings; the Flutter transport turns this off.)
const int roomHeartbeatMs = 45000;

/// No frame within this after `ping`, or no `welcome` this long after
/// opening: the socket is dead.
const int roomDeadMs = 10000;

/// A socket never lives longer than this (design D8); the server closes it
/// with 4001 anyway.
const int roomMaxLifetimeMs = 60 * 60 * 1000;

/// Reconnect with a fresh token this long before the server would close the
/// socket.
const int roomRefreshAheadMs = 30000;

/// Close codes (SPEC 17.6).
abstract final class RoomClose {
  /// The token expired (or the socket reached its lifetime).
  static const int tokenExpired = 4001;

  /// The token does not allow this room.
  static const int forbidden = 4003;

  /// The room id is not valid.
  static const int badRoomId = 4004;

  /// Too many connections or frames.
  static const int rateLimited = 4008;

  /// The room is full (or this connection was `replaced`).
  static const int roomFull = 4009;

  /// The project's plan or switch does not allow rooms.
  static const int plan = 4010;

  /// The (live) project is suspended.
  static const int suspended = 4011;

  /// The client broke the protocol.
  static const int protocol = 4400;
}

// ---------------------------------------------------------------- protocol

/// A gift of a room event: what the server sends about the gift.
class RoomGiftInfo {
  /// Creates the gift part of a [RoomGiftMessage].
  const RoomGiftInfo({
    required this.id,
    required this.name,
    required this.price,
    this.iconUrl,
  });

  /// Gift id.
  final String id;

  /// Name at send time.
  final String name;

  /// Price at send time.
  final int price;

  /// Small picture or null.
  final String? iconUrl;

  /// Wire JSON (SPEC 17.4).
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'price': price,
        'icon_url': iconUrl,
      };
}

/// The sender of a room event.
class RoomSender {
  /// Creates a sender.
  const RoomSender({required this.id, this.name});

  /// The sender's external id.
  final String id;

  /// Display name from the sender's token (claim `n`), or null.
  final String? name;

  /// Wire JSON.
  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, if (name != null) 'name': name};
}

/// A frame from the server.
sealed class RoomServerMessage {
  const RoomServerMessage();

  /// Wire JSON (SPEC 17.4), for tests and logs.
  Map<String, Object?> toJson();
}

/// A `gift` event as the server sends it, unknown fields dropped.
class RoomGiftMessage extends RoomServerMessage {
  /// Creates a gift event.
  const RoomGiftMessage({
    required this.id,
    required this.at,
    required this.tx,
    required this.gift,
    required this.quantity,
    required this.sender,
    this.receiverId,
  });

  /// Event id, also the resume point.
  final int id;

  /// Commit time, epoch ms (server clock).
  final int at;

  /// Gift transaction id.
  final String tx;

  /// The gift.
  final RoomGiftInfo gift;

  /// How many were sent.
  final int quantity;

  /// Who sent.
  final RoomSender sender;

  /// Who received, or null.
  final String? receiverId;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        't': 'gift',
        'id': id,
        'at': at,
        'tx': tx,
        'gift': gift.toJson(),
        'quantity': quantity,
        'sender': sender.toJson(),
        'receiver':
            receiverId == null ? null : <String, Object?>{'id': receiverId},
      };
}

/// One receiver's running total in a battle round (SPEC 17.8). Display
/// counters only.
class RoomScoreEntry {
  /// Creates an entry.
  const RoomScoreEntry({
    required this.id,
    required this.units,
    required this.gifts,
  });

  /// Receiver external id.
  final String id;

  /// Sum of unit price x quantity of the counted gifts.
  final int units;

  /// Number of counted gifts.
  final int gifts;

  @override
  bool operator ==(Object other) =>
      other is RoomScoreEntry &&
      other.id == id &&
      other.units == units &&
      other.gifts == gifts;

  @override
  int get hashCode => Object.hash(id, units, gifts);

  /// Wire JSON.
  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'units': units, 'gifts': gifts};
}

/// A battle round with its scores, in the server's fixed order (the round's
/// receivers first).
class RoomBattle {
  /// Creates a round.
  const RoomBattle({
    required this.round,
    required this.started,
    required this.ends,
    required this.scores,
  });

  /// The round id.
  final String round;

  /// Epoch ms (server clock).
  final int started;

  /// Epoch ms (server clock): gifts from then on no longer count.
  final int ends;

  /// One entry per receiver.
  final List<RoomScoreEntry> scores;

  @override
  bool operator ==(Object other) =>
      other is RoomBattle &&
      other.round == round &&
      other.started == started &&
      other.ends == ends &&
      other.scores.length == scores.length &&
      Iterable<int>.generate(scores.length)
          .every((i) => other.scores[i] == scores[i]);

  @override
  int get hashCode => Object.hash(round, started, ends, Object.hashAll(scores));

  /// Wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'round': round,
        'started': started,
        'ends': ends,
        'scores': <Object?>[for (final e in scores) e.toJson()],
      };
}

/// The first frame after `hello`.
class RoomWelcomeMessage extends RoomServerMessage {
  /// Creates a welcome.
  const RoomWelcomeMessage({
    required this.viewers,
    required this.gap,
    required this.replay,
    required this.ttl,
    required this.now,
    this.battle,
  });

  /// Approximate viewer count.
  final int viewers;

  /// Events may have been missed.
  final bool gap;

  /// The most recent events since `last`.
  final List<RoomGiftMessage> replay;

  /// Seconds until the server closes the socket with 4001.
  final num ttl;

  /// Server time, epoch ms.
  final int now;

  /// The room's battle round; null when there is none (or it was malformed).
  final RoomBattle? battle;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        't': 'welcome',
        'viewers': viewers,
        'gap': gap,
        'replay': <Object?>[for (final g in replay) g.toJson()],
        'ttl': ttl,
        'now': now,
        if (battle != null) 'battle': battle!.toJson(),
      };
}

/// Battle scores changed (SPEC 17.8): a new snapshot of the round, or null
/// when the round was removed.
class RoomScoresMessage extends RoomServerMessage {
  /// Creates a scores frame.
  const RoomScoresMessage(this.battle);

  /// The round now, or null.
  final RoomBattle? battle;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'t': 'scores', 'battle': battle?.toJson()};
}

/// A new viewer count.
class RoomViewersMessage extends RoomServerMessage {
  /// Creates a viewers frame.
  const RoomViewersMessage(this.n);

  /// The count.
  final int n;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'t': 'viewers', 'n': n};
}

/// Several gifts in one frame (hot rooms, SPEC 17.4).
class RoomBatchMessage extends RoomServerMessage {
  /// Creates a batch.
  const RoomBatchMessage(this.events);

  /// The gifts, in order.
  final List<RoomGiftMessage> events;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        't': 'batch',
        'events': <Object?>[for (final g in events) g.toJson()],
      };
}

/// The answer to a `ping`.
class RoomPongMessage extends RoomServerMessage {
  /// Creates a pong.
  const RoomPongMessage();

  @override
  Map<String, Object?> toJson() => <String, Object?>{'t': 'pong'};
}

const int _maxSafe = 9007199254740991;

Map<String, Object?>? _obj(Object? v) =>
    v is Map<dynamic, dynamic> ? v.cast<String, Object?>() : null;

/// A safe integer (a JSON `5.0` counts, as in JavaScript), or null.
int? _safeInt(Object? v) {
  if (v is int) return v.abs() <= _maxSafe ? v : null;
  if (v is double && v.isFinite && v == v.truncateToDouble()) {
    return v.abs() <= _maxSafe ? v.toInt() : null;
  }
  return null;
}

/// A safe integer >= 0, or null.
int? _count(Object? v) {
  final i = _safeInt(v);
  return i != null && i >= 0 ? i : null;
}

RoomGiftMessage? _parseGift(Object? raw) {
  final v = _obj(raw);
  if (v == null || v['t'] != 'gift') return null;
  final gift = _obj(v['gift']);
  final sender = _obj(v['sender']);
  final id = _count(v['id']);
  final at = _count(v['at']);
  final tx = v['tx'];
  final quantity = _safeInt(v['quantity']);
  if (id == null ||
      at == null ||
      tx is! String ||
      tx.isEmpty ||
      gift == null ||
      gift['id'] is! String ||
      gift['name'] is! String ||
      _count(gift['price']) == null ||
      quantity == null ||
      quantity < 1 ||
      sender == null ||
      sender['id'] is! String) {
    return null;
  }
  final name = sender['name'];
  final receiver = _obj(v['receiver']);
  return RoomGiftMessage(
    id: id,
    at: at,
    tx: tx,
    gift: RoomGiftInfo(
      id: gift['id']! as String,
      name: gift['name']! as String,
      price: _count(gift['price'])!,
      iconUrl: gift['icon_url'] is String ? gift['icon_url']! as String : null,
    ),
    quantity: quantity,
    sender: RoomSender(
      id: sender['id']! as String,
      name: name is String && name.isNotEmpty ? name : null,
    ),
    receiverId: receiver != null && receiver['id'] is String
        ? receiver['id']! as String
        : null,
  );
}

/// A battle object, or null when malformed. Invalid score entries are dropped
/// alone.
RoomBattle? _parseBattle(Object? raw) {
  final v = _obj(raw);
  if (v == null) return null;
  final round = v['round'];
  final started = _count(v['started']);
  final ends = _count(v['ends']);
  final list = v['scores'];
  if (round is! String || round.isEmpty) return null;
  if (started == null || ends == null || list is! List<dynamic>) return null;
  final scores = <RoomScoreEntry>[];
  for (final e in list) {
    final m = _obj(e);
    if (m == null) continue;
    final id = m['id'];
    final units = _count(m['units']);
    final gifts = _count(m['gifts']);
    if (id is String && units != null && gifts != null) {
      scores.add(RoomScoreEntry(id: id, units: units, gifts: gifts));
    }
  }
  return RoomBattle(
    round: round,
    started: started,
    ends: ends,
    scores: scores,
  );
}

List<RoomGiftMessage>? _giftList(Object? v) => v is List<dynamic>
    ? <RoomGiftMessage>[
        for (final e in v)
          if (_parseGift(e) case final g?) g,
      ]
    : null;

/// One server frame, or null for anything to ignore: not JSON, an unknown
/// `t`, a known `t` with a missing or mistyped required field. Unknown fields
/// are dropped; inside `replay` and `events` an invalid gift is dropped alone.
/// The literal text `pong` is a [RoomPongMessage].
RoomServerMessage? parseRoomFrame(Object? data) {
  if (data is! String) return null;
  if (data == 'pong') return const RoomPongMessage();
  final Object? decoded;
  try {
    decoded = jsonDecode(data);
  } on FormatException {
    return null;
  }
  final v = _obj(decoded);
  if (v == null) return null;
  switch (v['t']) {
    case 'gift':
      return _parseGift(v);
    case 'welcome':
      final replay =
          v['replay'] == null ? <RoomGiftMessage>[] : _giftList(v['replay']);
      final viewers = _count(v['viewers']);
      final now = _count(v['now']);
      final ttl = v['ttl'];
      if (viewers == null ||
          v['gap'] is! bool ||
          replay == null ||
          ttl is! num ||
          !(ttl >= 0) ||
          now == null) {
        return null;
      }
      return RoomWelcomeMessage(
        viewers: viewers,
        gap: v['gap']! as bool,
        replay: replay,
        ttl: ttl,
        now: now,
        battle: _parseBattle(v['battle']),
      );
    case 'scores':
      // Only an explicit `null` removes the round; a missing key is junk.
      if (v['battle'] == null) {
        return v.containsKey('battle') ? const RoomScoresMessage(null) : null;
      }
      final battle = _parseBattle(v['battle']);
      return battle == null ? null : RoomScoresMessage(battle);
    case 'viewers':
      final n = _count(v['n']);
      return n == null ? null : RoomViewersMessage(n);
    case 'batch':
      final events = _giftList(v['events']);
      return events == null ? null : RoomBatchMessage(events);
    default:
      return null;
  }
}

/// One side of a battle bar.
class BattleSide extends RoomScoreEntry {
  /// Creates a side.
  const BattleSide({
    required super.id,
    required super.units,
    required super.gifts,
    required this.share,
  });

  /// `units / total`, 0..1; an equal split while nobody has scored.
  final double share;

  @override
  bool operator ==(Object other) =>
      other is BattleSide && super == other && other.share == share;

  @override
  int get hashCode => Object.hash(super.hashCode, share);

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{...super.toJson(), 'share': share};
}

/// What a battle bar shows (SPEC 18.6).
class BattleView {
  /// Creates a view.
  const BattleView({
    required this.round,
    required this.open,
    required this.remainingMs,
    required this.total,
    required this.sides,
    required this.leader,
  });

  /// The round id.
  final String round;

  /// The round still counts: `started <= serverNow < ends`.
  final bool open;

  /// `max(0, ends - serverNow)`, ms.
  final int remainingMs;

  /// Sum of every side's `units`.
  final int total;

  /// The server's order (the round's receivers first): keep it for a stable
  /// left/right bar.
  final List<BattleSide> sides;

  /// The receiver with the most units; null while nobody has scored or the top
  /// is tied.
  final String? leader;

  /// The fixture's JSON shape.
  Map<String, Object?> toJson() => <String, Object?>{
        'round': round,
        'open': open,
        'remainingMs': remainingMs,
        'total': total,
        'sides': <Object?>[for (final s in sides) s.toJson()],
        'leader': leader,
      };
}

/// What a battle bar shows (SPEC 18.6), pure. [serverNow] is the server clock
/// ([RoomClient] keeps the offset from the last welcome); null (no welcome
/// yet) reads as the round's start.
BattleView battleView(RoomBattle battle, int? serverNow) {
  final now = serverNow ?? battle.started;
  var total = 0;
  for (final e in battle.scores) {
    total += e.units;
  }
  final n = battle.scores.length;
  final sides = <BattleSide>[
    for (final e in battle.scores)
      BattleSide(
        id: e.id,
        units: e.units,
        gifts: e.gifts,
        share: total > 0 ? e.units / total : 1 / n,
      ),
  ];
  String? leader;
  var best = 0;
  var tied = false;
  for (final e in battle.scores) {
    if (e.units > best) {
      best = e.units;
      leader = e.id;
      tied = false;
    } else if (e.units == best && best > 0) {
      tied = true;
    }
  }
  return BattleView(
    round: battle.round,
    open: now >= battle.started && now < battle.ends,
    remainingMs: math.max(0, battle.ends - now),
    total: total,
    sides: sides,
    leader: tied ? null : leader,
  );
}

/// The first frame after open: `{"t":"hello","v":1,"last":<id|null>}`, keys in
/// this order.
String roomHelloFrame(int? last) =>
    jsonEncode(<String, Object?>{'t': 'hello', 'v': 1, 'last': last});

/// `wss://rt.giftingstack.com/v1/rooms/<room>` (trailing slashes of [baseUrl]
/// removed).
String roomUrl(String room, [String baseUrl = defaultRoomsUrl]) =>
    '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/v1/rooms/'
    '${encodeUriComponent(room)}';

const String _b64 =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/// base64url without padding to text; throws on a bad character or bad UTF-8.
String _base64UrlToText(String s) {
  var bits = 0;
  var acc = 0;
  final bytes = <int>[];
  for (final unit in s.codeUnits) {
    final v = _b64.indexOf(String.fromCharCode(unit));
    if (v < 0) throw const FormatException('bad base64url');
    acc = ((acc << 6) | v) & 0xffff;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((acc >> bits) & 0xff);
    }
  }
  return utf8.decode(bytes);
}

/// The user a client token was minted for (claim `u`), or null when the token
/// is not a GiftingStack client token. Used only to skip the user's own gifts;
/// the token is not verified here (the server does that).
String? roomTokenUser(String token) {
  final m = RegExp(r'^gs_ct_([A-Za-z0-9_-]+)\.').firstMatch(token);
  if (m == null) return null;
  try {
    final claims = _obj(jsonDecode(_base64UrlToText(m.group(1)!)));
    final u = claims?['u'];
    return u is String ? u : null;
  } on FormatException {
    return null;
  }
}

// ---------------------------------------------------------------- reconnect policy

/// What to do after a socket closed.
sealed class RoomRetryDecision {
  const RoomRetryDecision();
}

/// Do not reconnect.
class RoomNoRetry extends RoomRetryDecision {
  /// Creates the decision.
  const RoomNoRetry({this.resumable = false, this.exhausted = false});

  /// The client stopped by its own rule, not because the server said it is
  /// final: [RoomClient.reconnectNow] may start again (SPEC 18.3).
  final bool resumable;

  /// [roomMaxAttempts] failed attempts in a row.
  final bool exhausted;
}

/// Reconnect after [delayMs].
class RoomRetry extends RoomRetryDecision {
  /// Creates the decision.
  const RoomRetry({
    required this.delayMs,
    required this.refreshToken,
    required this.limited,
  });

  /// The wait before the next attempt.
  final int delayMs;

  /// Ask `getToken` with `forceRefresh: true` before reconnecting.
  final bool refreshToken;

  /// A rate-limit or room-full wait: counts against the 5 such waits.
  final bool limited;
}

/// `retry_after` of a JSON close reason, in whole seconds; 0 when absent or
/// not a count.
int _retryAfterSeconds(String reason) {
  try {
    return _count(_obj(jsonDecode(reason))?['retry_after']) ?? 0;
  } on FormatException {
    return 0;
  }
}

/// Wait after a 4008 that carried `retry_after` (seconds): `max(30 s,
/// retry_after)` doubled per wait already in a row ([limited]), plus up to 25 %
/// jitter, never above 5 minutes. Calls [random] once.
int roomRateLimitedDelayMs(
  int retryAfterS,
  int limited,
  double Function() random,
) {
  // Clamping the base first changes nothing (the result is capped anyway) and
  // keeps the product inside 64 bits.
  final base = math.min(
    roomLimitedMaxMs,
    math.max(roomLimitedMinMs, retryAfterS * 1000),
  );
  final grown = math.min(
    roomLimitedMaxMs,
    base * (1 << math.min(math.max(0, limited), 16)),
  );
  return math.min(
    roomLimitedMaxMs,
    grown + (random() * (grown ~/ 4)).floor(),
  );
}

/// What to do after a socket closed (SPEC 18.3). [attempt]: failed connections
/// in a row before this one; [limited]: 4008/4009 waits in a row before this
/// one. [random] returns [0, 1) and is called at most once, only for a
/// jittered delay: `roomRetryFloorMs + floor(random() * (cap - floor))`.
RoomRetryDecision roomRetryDecision({
  required int code,
  required String reason,
  required int attempt,
  required int limited,
  required double Function() random,
}) {
  int jitter(int cap) =>
      roomRetryFloorMs +
      (random() * math.max(0, cap - roomRetryFloorMs)).floor();
  int backoff() => jitter(
        math.min(
          roomBackoffMaxMs,
          (roomBackoffBaseMs * math.pow(2, math.max(0, attempt))).toInt(),
        ),
      );
  switch (code) {
    case RoomClose.forbidden:
    case RoomClose.badRoomId:
    case RoomClose.plan:
    case RoomClose.protocol:
      return const RoomNoRetry();
    case RoomClose.suspended:
      return const RoomNoRetry(resumable: true);
    case RoomClose.roomFull:
    case RoomClose.rateLimited:
      if (code == RoomClose.roomFull && reason == 'replaced') {
        return const RoomNoRetry();
      }
      final retryAfter = _retryAfterSeconds(reason);
      if (code == RoomClose.rateLimited && retryAfter > 0) {
        // A platform limit that lifts by itself: grows, never gives up (and is
        // not counted against the attempt ceiling).
        return RoomRetry(
          delayMs: roomRateLimitedDelayMs(retryAfter, limited, random),
          refreshToken: false,
          limited: true,
        );
      }
      if (limited >= roomLimitedMaxRetries) {
        return const RoomNoRetry(resumable: true);
      }
      return RoomRetry(
        delayMs: math.max(roomLimitedMinMs, retryAfter * 1000),
        refreshToken: false,
        limited: true,
      );
    default:
      break;
  }
  if (attempt >= roomMaxAttempts) {
    return const RoomNoRetry(resumable: true, exhausted: true);
  }
  switch (code) {
    case RoomClose.tokenExpired:
      return RoomRetry(
        delayMs: attempt == 0 ? 0 : backoff(),
        refreshToken: true,
        limited: false,
      );
    case 1006:
    case 1012:
      return RoomRetry(
        delayMs: attempt == 0 ? jitter(roomFirstDropMaxMs) : backoff(),
        refreshToken: false,
        limited: false,
      );
    default:
      return RoomRetry(delayMs: backoff(), refreshToken: false, limited: false);
  }
}

// ---------------------------------------------------------------- filter

/// Settings of a [RoomEventFilter]; read again at every use.
class RoomEventFilterOptions {
  /// Creates options.
  const RoomEventFilterOptions({
    this.user,
    this.skipOwn = true,
    this.maxReplayAgeMs = defaultMaxReplayAgeMs,
    this.minTier = EffectTier.small,
    this.thresholds = const TierThresholds(),
  });

  /// The signed-in user (token claim `u`): with [skipOwn], their gifts are not
  /// played again.
  final String? user;

  /// Default true: the sender's own tray already played the effect on tap.
  final bool skipOwn;

  /// Default 10,000. Events at least this old (server clock) are dropped.
  final int maxReplayAgeMs;

  /// Viewer-side filter: only gifts of this tier or bigger. Default small
  /// (all).
  final EffectTier minTier;

  /// Tier boundaries; missing fields take the defaults.
  final TierThresholds thresholds;
}

/// What one step of a [RoomEventFilter] lets through.
class RoomFilterResult {
  /// Creates a result.
  const RoomFilterResult(this.events, this.gap);

  /// The gifts to play, in order.
  final List<RoomGiftMessage> events;

  /// `welcome.gap`: events may have been missed. Always false for live frames.
  final bool gap;
}

/// Decides which received gifts reach the app (SPEC 18.2). Keeps the resume
/// point [last] (id of the last gift received, played or not) and the last 256
/// `tx` across reconnects. Each gift, in order: `last = id`; a `tx` seen before
/// is dropped; then (the `tx` is remembered) a gift whose age `serverNow - at`
/// is at least `maxReplayAgeMs` is dropped, then the user's own gift
/// (`skipOwn`), then a gift below `minTier`. `serverNow` is `welcome.now` for
/// the replay and `welcome.now + (localNow - local time of the welcome)` for
/// live gifts.
class RoomEventFilter {
  /// Creates a filter.
  RoomEventFilter([this._options = const RoomEventFilterOptions()]);

  RoomEventFilterOptions _options;

  /// Resume point sent in `hello`.
  int? last;

  final Set<String> _seen = <String>{};
  final Queue<String> _order = Queue<String>();

  /// `welcome.now - local time of the welcome`; null before the first welcome.
  int? _offset;

  /// Changes the settings; the resume point and the dedup set stay.
  // ignore: use_setters_to_change_properties
  void setOptions(RoomEventFilterOptions options) => _options = options;

  /// The `tx` ids remembered, oldest first.
  List<String> seenTx() => _order.toList();

  /// Server time now, from the last welcome; null before the first one.
  int? serverNow(int localNow) {
    final offset = _offset;
    return offset == null ? null : localNow + offset;
  }

  /// The `welcome`: its replay goes through the filter.
  RoomFilterResult welcome(RoomWelcomeMessage msg, int localNow) {
    _offset = msg.now - localNow;
    return RoomFilterResult(_pass(msg.replay, msg.now), msg.gap);
  }

  /// A live `gift` or `batch`. Before any welcome nothing passes (the server
  /// never does that).
  RoomFilterResult live(List<RoomGiftMessage> events, int localNow) {
    final offset = _offset;
    if (offset == null) {
      return const RoomFilterResult(<RoomGiftMessage>[], false);
    }
    return RoomFilterResult(_pass(events, localNow + offset), false);
  }

  List<RoomGiftMessage> _pass(List<RoomGiftMessage> events, int serverNow) {
    final o = _options;
    final out = <RoomGiftMessage>[];
    for (final e in events) {
      last = e.id;
      if (_seen.contains(e.tx)) continue;
      _remember(e.tx);
      if (serverNow - e.at >= o.maxReplayAgeMs) continue;
      if (o.skipOwn && o.user != null && e.sender.id == o.user) continue;
      if (tierFor(e.gift.price, o.thresholds).index < o.minTier.index) continue;
      out.add(e);
    }
    return out;
  }

  void _remember(String tx) {
    _seen.add(tx);
    _order.add(tx);
    while (_order.length > roomDedupSize) {
      _seen.remove(_order.removeFirst());
    }
  }
}

// ---------------------------------------------------------------- mapping

/// A room gift ready for the effect layer: pass it straight to `play`.
class RoomGiftEvent extends GiftEffectEvent {
  /// Creates an event.
  const RoomGiftEvent({
    required super.gift,
    required int super.quantity,
    required this.id,
    required this.tx,
    required this.at,
    required this.senderId,
    required this.replayed,
    super.sender,
    this.senderName,
    this.receiverId,
  });

  /// Event id (the resume point).
  final int id;

  /// Gift transaction id.
  final String tx;

  /// Commit time, epoch ms (server clock).
  final int at;

  /// The sender's external id.
  final String senderId;

  /// The sender's display name from their token (claim `n`), else null.
  final String? senderName;

  /// The receiver's external id, or null.
  final String? receiverId;

  /// Came in the `welcome` replay after a (re)connect, not live.
  final bool replayed;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        ...super.toJson(),
        'id': id,
        'tx': tx,
        'at': at,
        'senderId': senderId,
        'senderName': senderName,
        'receiverId': receiverId,
        'replayed': replayed,
      };
}

/// Turns a room gift into what the effect layer plays (SPEC 18.4): name and
/// price from the event (the price at send time drives the tier); `image` =
/// the catalog gift's `animationUrl`, else its `iconUrl`, else the event's
/// icon; `icon` = the event's icon, else the catalog's; `sender` = the name
/// claim, else [resolveName] of the sender id, else absent (the effect layer
/// then shows "Someone").
RoomGiftEvent roomGiftToEffect(
  RoomGiftMessage msg, {
  List<Gift>? catalog,
  String? Function(String user)? resolveName,
  bool replayed = false,
}) {
  Gift? known;
  if (catalog != null) {
    for (final g in catalog) {
      if (g.id == msg.gift.id) {
        known = g;
        break;
      }
    }
  }
  final image = known?.animationUrl ?? known?.iconUrl ?? msg.gift.iconUrl;
  final icon = msg.gift.iconUrl ?? known?.iconUrl;
  final senderName = msg.sender.name;
  var sender = senderName;
  if (sender == null && resolveName != null) {
    try {
      final resolved = resolveName(msg.sender.id);
      sender = resolved == null || resolved.isEmpty ? null : resolved;
    } on Object {
      sender = null;
    }
  }
  return RoomGiftEvent(
    gift: GiftEffectGift(
      id: msg.gift.id,
      name: msg.gift.name,
      price: msg.gift.price,
      image: image,
      icon: icon,
    ),
    quantity: msg.quantity,
    id: msg.id,
    tx: msg.tx,
    at: msg.at,
    senderId: msg.sender.id,
    senderName: senderName,
    receiverId: msg.receiverId,
    replayed: replayed,
    sender: sender,
  );
}

// ---------------------------------------------------------------- session

/// What a platform transport implements: one WebSocket, text frames only.
abstract interface class RoomSocket {
  /// Sends a text frame.
  void send(String data);

  /// Closes the socket. After this the client ignores every callback of this
  /// socket.
  void close(int code, String reason);
}

/// What the transport calls back.
class RoomSocketHandlers {
  /// Creates the handlers (the client does).
  const RoomSocketHandlers({
    required this.onOpen,
    required this.onMessage,
    required this.onClose,
  });

  /// The socket is open.
  final void Function() onOpen;

  /// A text frame; a transport drops binary frames.
  final void Function(String data) onMessage;

  /// Exactly once per socket (an error before or after open is a close with
  /// 1006).
  final void Function(int code, String reason) onClose;
}

/// Opens [url] with the WebSocket subprotocols `['gs.v1', token]`.
typedef RoomSocketFactory = RoomSocket Function(
  String url,
  List<String> protocols,
  RoomSocketHandlers handlers,
);

/// Where a [RoomClient] is.
enum RoomStatus {
  /// Created, not started.
  idle,

  /// Asking for a token, opening the socket, waiting for `welcome`.
  connecting,

  /// Welcomed: gifts flow.
  open,

  /// Waiting before the next attempt.
  reconnecting,

  /// The app is in the background: no socket, no retry.
  paused,

  /// Over (after `leave()` or a final close code).
  closed,
}

/// What a [RoomClient] shows.
class RoomState {
  /// Creates a state.
  const RoomState({
    this.status = RoomStatus.idle,
    this.attempt = 0,
    this.retryInMs,
    this.code,
    this.reason,
    this.viewers,
  });

  /// Where the client is.
  final RoomStatus status;

  /// Failed connections in a row.
  final int attempt;

  /// `reconnecting`: the wait before the next attempt, ms. Else null.
  final int? retryInMs;

  /// `closed`: the close code (1000 after `leave()`), else the last close code
  /// seen or null.
  final int? code;

  /// The reason that came with [code].
  final String? reason;

  /// Approximate viewer count from the server; null before the first welcome.
  final int? viewers;
}

/// Settings of a [RoomClient]; callbacks and filter settings are read when
/// used, so they can change between calls ([RoomClient.setOptions]).
class RoomClientOptions {
  /// Creates options.
  const RoomClientOptions({
    required this.room,
    required this.getToken,
    required this.socket,
    this.url,
    this.allowInsecure = false,
    this.user,
    this.skipOwn = true,
    this.maxReplayAgeMs = defaultMaxReplayAgeMs,
    this.minTier = EffectTier.small,
    this.thresholds = const TierThresholds(),
    this.catalog,
    this.getCatalog,
    this.resolveName,
    this.onEvent,
    this.onViewers,
    this.onGap,
    this.onState,
    this.onBattle,
    this.heartbeatMs = roomHeartbeatMs,
    this.now,
    this.setTimeout,
    this.clearTimeout,
    this.random,
    this.refreshJitterMs = 0,
  });

  /// The room id (SPEC 17.1).
  final String room;

  /// The same token function as the client's. Mint the token with `rooms` and
  /// `name` (SPEC 17.2).
  final Future<String> Function({required bool forceRefresh}) getToken;

  /// Opens a socket.
  final RoomSocketFactory socket;

  /// Default `wss://rt.giftingstack.com`. A plain `ws://` URL makes [RoomClient]
  /// throw an [ArgumentError] unless its host is localhost, 127.0.0.1, ::1 or
  /// 10.0.2.2, or [allowInsecure] is true (SPEC 3.1).
  final String? url;

  /// Allow a plain `ws://` [url] to any host. Default false. For development
  /// only.
  final bool allowInsecure;

  /// See [RoomEventFilterOptions.user]. Default: the token's `u` claim.
  final String? user;

  /// See [RoomEventFilterOptions.skipOwn].
  final bool skipOwn;

  /// See [RoomEventFilterOptions.maxReplayAgeMs].
  final int maxReplayAgeMs;

  /// See [RoomEventFilterOptions.minTier].
  final EffectTier minTier;

  /// See [RoomEventFilterOptions.thresholds].
  final TierThresholds thresholds;

  /// The app's gift catalog (`GET /v1/client/gifts`): supplies the big
  /// picture.
  final List<Gift>? catalog;

  /// The catalog, read at each event (wins over [catalog]).
  final List<Gift>? Function()? getCatalog;

  /// Display name of a sender without a name claim. Return null for the
  /// default.
  final String? Function(String user)? resolveName;

  /// Called for every gift that passes the filter.
  final void Function(RoomGiftEvent event)? onEvent;

  /// Called with every viewer count.
  final void Function(int n)? onViewers;

  /// Called when a `welcome` says events may have been missed.
  final void Function()? onGap;

  /// Called after every state change.
  final void Function(RoomState state)? onState;

  /// Called when the battle scores change (SPEC 18.6): a new snapshot, or null
  /// when the round was removed.
  final void Function(RoomBattle? battle)? onBattle;

  /// App heartbeat interval. 0 turns it off for transports with protocol
  /// pings (native). Default 45,000.
  final int heartbeatMs;

  /// The clock, ms. Default: the wall clock.
  final int Function()? now;

  /// Starts a timer. Default: a `dart:async` timer.
  final TimerStarter? setTimeout;

  /// Cancels a timer.
  final TimerCanceller? clearTimeout;

  /// [0, 1). Default: `Random()`.
  final double Function()? random;

  /// The proactive token refresh happens `random(0, refreshJitterMs)` earlier
  /// than 30 s before the socket's end, so viewers that joined together do not
  /// all reconnect in the same second. Default 0 (exact timing, as in the
  /// fixtures); the widget sets [roomRefreshJitterMs].
  final int refreshJitterMs;
}

enum _Timer { retry, dead, beat, refresh }

const Object _keep = Object();

/// One room membership (SPEC 18): connects, says hello, plays what the filter
/// lets through, reconnects with backoff and resume, refreshes the token, keeps
/// a heartbeat. Never throws into the app; app callbacks that throw are
/// ignored.
///
/// idle -[start]-> connecting -welcome-> open -drop-> reconnecting ->
/// connecting ...; [pause] (app in background) -> paused -[resume]->
/// connecting; [leave] or a final close code -> closed (terminal).
class RoomClient {
  /// Creates a client. Nothing happens until [start].
  RoomClient(RoomClientOptions options)
      : _options = _checked(options),
        filter = RoomEventFilter(_filterOptions(options, null));

  static RoomClientOptions _checked(RoomClientOptions o) {
    assertSecureUrl(o.url ?? defaultRoomsUrl, o.allowInsecure, 'url');
    return o;
  }

  RoomClientOptions _options;
  RoomState _state = const RoomState();
  final Set<void Function()> _listeners = <void Function()>{};
  final Set<void Function(RoomGiftEvent)> _eventListeners =
      <void Function(RoomGiftEvent)>{};

  final Set<void Function()> _battleListeners = <void Function()>{};
  RoomBattle? _battle;

  /// The filter, with the resume point `last`.
  final RoomEventFilter filter;

  /// Bumped whenever the current socket or token request stops mattering.
  int _gen = 0;
  RoomSocket? _socket;
  int _limited = 0;

  /// The last close was a stop by the client's own rule (SPEC 18.3):
  /// [reconnectNow] may restart.
  bool _resumable = false;

  /// The pending retry is a 4008/4009 wait (the platform said when to come
  /// back): [reconnectNow] does not skip it.
  bool _rateWait = false;
  bool _refreshNext = false;
  String? _tokenUser;
  int? _openedAt;
  int _lastFrameAt = 0;
  final Map<_Timer, Object?> _timers = <_Timer, Object?>{};

  static RoomEventFilterOptions _filterOptions(
    RoomClientOptions o,
    String? tokenUser,
  ) =>
      RoomEventFilterOptions(
        user: o.user ?? tokenUser,
        skipOwn: o.skipOwn,
        maxReplayAgeMs: o.maxReplayAgeMs,
        minTier: o.minTier,
        thresholds: o.thresholds,
      );

  /// Callbacks and filter settings are read when used, so they can change
  /// between calls.
  void setOptions(RoomClientOptions options) {
    _options = _checked(options);
    filter.setOptions(_filterOptions(options, _tokenUser));
  }

  /// What the client shows now.
  RoomState get state => _state;

  /// Calls [listener] after every state change. Returns a function that stops
  /// it.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// The room's battle round as last received (SPEC 18.6): from `welcome`, then
  /// each `scores` frame. Kept across reconnects until the next welcome; null
  /// when there is none.
  RoomBattle? getBattle() => _battle;

  /// Calls [listener] when the battle changes. Returns a function that stops
  /// it.
  void Function() subscribeBattle(void Function() listener) {
    _battleListeners.add(listener);
    return () => _battleListeners.remove(listener);
  }

  /// Server time now (from the last welcome), null before the first welcome.
  int? serverNow() => filter.serverNow(_now());

  /// [battleView] of the current round at the server's time now, null without
  /// a round.
  BattleView? getBattleView() {
    final b = _battle;
    return b == null ? null : battleView(b, serverNow());
  }

  /// Calls [listener] for every gift that passes the filter, after
  /// `options.onEvent`. Returns a function that stops it.
  void Function() onEvent(void Function(RoomGiftEvent event) listener) {
    _eventListeners.add(listener);
    return () => _eventListeners.remove(listener);
  }

  /// Connects. Only from idle; a bad room id closes at once with 4004 and
  /// opens nothing.
  void start() {
    if (_state.status != RoomStatus.idle) return;
    if (!roomIdPattern.hasMatch(_options.room)) {
      _finish(RoomClose.badRoomId, 'bad_room_id');
      return;
    }
    _connect();
  }

  /// Leaves the room for good: closes with 1000, no callbacks after this.
  void leave() {
    if (_state.status == RoomStatus.closed) return;
    _finish(1000, 'left');
  }

  /// The app went to the background: closes (1000), keeps `last` and the dedup
  /// set, no retry.
  void pause() {
    final s = _state.status;
    if (s == RoomStatus.idle ||
        s == RoomStatus.closed ||
        s == RoomStatus.paused) {
      return;
    }
    _drop();
    _set(status: RoomStatus.paused, retryInMs: null);
  }

  /// Back in the foreground: reconnects now with `last`. Only from paused.
  void resume() {
    if (_state.status != RoomStatus.paused) return;
    _connect();
  }

  /// The network is back (or the user asked): skips a pending backoff wait,
  /// but never a 4008/4009 wait (rate limited, room full: the platform named
  /// the time). After a stop by the client's own rule (`retries_exhausted`, 4011, the
  /// 4008/4009 limit) it starts again with a fresh attempt budget. Nothing
  /// else changes.
  void reconnectNow() {
    if (_state.status == RoomStatus.closed && _resumable) {
      _resumable = false;
      _limited = 0;
      _set(attempt: 0);
      _connect();
      return;
    }
    if (_state.status != RoomStatus.reconnecting || _rateWait) return;
    _clear(_Timer.retry);
    _connect();
  }

  /// Same as [leave].
  void dispose() => leave();

  // ---------------------------------------------------------------- internals

  int _now() => (_options.now ?? wallClockMs)();

  void _set({
    RoomStatus? status,
    int? attempt,
    Object? retryInMs = _keep,
    Object? code = _keep,
    Object? reason = _keep,
    Object? viewers = _keep,
  }) {
    _state = RoomState(
      status: status ?? _state.status,
      attempt: attempt ?? _state.attempt,
      retryInMs:
          identical(retryInMs, _keep) ? _state.retryInMs : retryInMs as int?,
      code: identical(code, _keep) ? _state.code : code as int?,
      reason: identical(reason, _keep) ? _state.reason : reason as String?,
      viewers: identical(viewers, _keep) ? _state.viewers : viewers as int?,
    );
    _safe(() => _options.onState?.call(_state));
    for (final l in _listeners.toList()) {
      _safe(l);
    }
  }

  void _safe(void Function() fn) {
    try {
      fn();
    } on Object {
      // App callbacks never break the room.
    }
  }

  void _later(_Timer name, int ms, void Function() fn) {
    _clear(name);
    final start = _options.setTimeout ?? startTimer;
    _timers[name] = start(() {
      _timers.remove(name);
      fn();
    }, ms);
  }

  void _clear(_Timer name) {
    if (!_timers.containsKey(name)) return;
    final h = _timers.remove(name);
    (_options.clearTimeout ?? cancelTimer)(h);
  }

  void _clearAll() {
    for (final name in _timers.keys.toList()) {
      _clear(name);
    }
  }

  /// Forgets the current socket (closing it with 1000) and any token request
  /// in flight.
  void _drop() {
    _gen += 1;
    _clearAll();
    final s = _socket;
    _socket = null;
    _openedAt = null;
    if (s != null) _safe(() => s.close(1000, 'client'));
  }

  void _finish(int code, String reason) {
    _drop();
    _resumable = false;
    _set(
        status: RoomStatus.closed, retryInMs: null, code: code, reason: reason);
  }

  void _connect() {
    _drop();
    final gen = _gen;
    final refresh = _refreshNext;
    _refreshNext = false;
    _set(status: RoomStatus.connecting, retryInMs: null);
    // A `getToken` that never answers must not keep the room connecting forever.
    _later(_Timer.dead, roomTokenMs, () => _dead(gen));
    Future<String> pending;
    try {
      pending = _options.getToken(forceRefresh: refresh);
    } on Object catch (err, stack) {
      pending = Future<String>.error(err, stack);
    }
    pending.then(
      (token) {
        if (gen != _gen) return;
        _open(token, gen);
      },
      onError: (Object _) {
        if (gen != _gen) return;
        // No token (the app's server is down, the user signed out): retry like
        // a network error.
        _closed(gen, 1006, 'token_failed');
      },
    );
  }

  void _open(String token, int gen) {
    _tokenUser = roomTokenUser(token);
    filter.setOptions(_filterOptions(_options, _tokenUser));
    final url = roomUrl(_options.room, _options.url ?? defaultRoomsUrl);
    final handlers = RoomSocketHandlers(
      onOpen: () {
        if (gen != _gen || _socket == null) return;
        _lastFrameAt = _now();
        _sendFrame(roomHelloFrame(filter.last));
      },
      onMessage: (data) {
        if (gen != _gen) return;
        _message(data, gen);
      },
      onClose: (code, reason) {
        if (gen != _gen) return;
        _socket = null;
        _closed(gen, code, reason);
      },
    );
    try {
      _socket =
          _options.socket(url, <String>[roomSubprotocol, token], handlers);
    } on Object {
      _closed(gen, 1006, 'socket_failed');
      return;
    }
    // From creation to `welcome`: the same 10 s as a missing pong.
    _later(_Timer.dead, roomDeadMs, () => _dead(gen));
  }

  void _sendFrame(String data) {
    final s = _socket;
    if (s != null) _safe(() => s.send(data));
  }

  void _message(String data, int gen) {
    final now = _now();
    _lastFrameAt = now;
    if (_state.status == RoomStatus.open) _clear(_Timer.dead);
    final msg = parseRoomFrame(data);
    if (msg == null) return;
    switch (msg) {
      case RoomWelcomeMessage():
        _clear(_Timer.dead);
        _openedAt = now;
        final ttlMs = math.min(msg.ttl * 1000, roomMaxLifetimeMs).toInt();
        if (ttlMs > roomRefreshAheadMs) {
          final left = ttlMs - roomRefreshAheadMs;
          final spread = math.min(_options.refreshJitterMs, left ~/ 2);
          final early = spread > 0
              ? ((_options.random ?? math.Random().nextDouble)() * spread)
                  .floor()
              : 0;
          _later(_Timer.refresh, left - early, () {
            if (gen != _gen) return;
            _refreshNext = true;
            _connect();
          });
        }
        _beat(gen);
        _set(status: RoomStatus.open, viewers: msg.viewers, retryInMs: null);
        _safe(() => _options.onViewers?.call(msg.viewers));
        final r = filter.welcome(msg, now);
        _setBattle(msg.battle);
        if (r.gap) _safe(() => _options.onGap?.call());
        _emit(r.events, true, gen);
      case RoomGiftMessage():
        _emit(filter.live(<RoomGiftMessage>[msg], now).events, false, gen);
      case RoomBatchMessage():
        _emit(filter.live(msg.events, now).events, false, gen);
      case RoomViewersMessage():
        _set(viewers: msg.n);
        _safe(() => _options.onViewers?.call(msg.n));
      case RoomScoresMessage():
        if (_state.status == RoomStatus.open) _setBattle(msg.battle);
      case RoomPongMessage():
        break;
    }
  }

  void _setBattle(RoomBattle? battle) {
    if (battle == null && _battle == null) return;
    _battle = battle;
    _safe(() => _options.onBattle?.call(battle));
    for (final l in _battleListeners.toList()) {
      _safe(l);
    }
  }

  void _emit(List<RoomGiftMessage> events, bool replayed, int gen) {
    for (final e in events) {
      if (gen != _gen) return;
      final o = _options;
      final event = roomGiftToEffect(
        e,
        catalog: o.getCatalog?.call() ?? o.catalog,
        resolveName: o.resolveName,
        replayed: replayed,
      );
      _safe(() => o.onEvent?.call(event));
      for (final l in _eventListeners.toList()) {
        _safe(() => l(event));
      }
    }
  }

  /// Heartbeat: `ping` after `heartbeatMs` without frames; the next frame must
  /// come within 10 s.
  void _beat(int gen) {
    final every = _options.heartbeatMs;
    if (every <= 0) return;
    final wait = math.max(0, _lastFrameAt + every - _now());
    _later(_Timer.beat, wait, () {
      if (gen != _gen) return;
      if (_now() - _lastFrameAt >= every) {
        _sendFrame('ping');
        _later(_Timer.dead, roomDeadMs, () => _dead(gen));
        _lastFrameAt = _now();
      }
      _beat(gen);
    });
  }

  /// No token, no welcome or no answer to `ping` in time: drops the socket
  /// and retries like a 1006 (reason `token_timeout` while no socket exists
  /// yet, else `timeout`).
  void _dead(int gen) {
    if (gen != _gen) return;
    final s = _socket;
    _socket = null;
    if (s != null) _safe(() => s.close(1000, 'timeout'));
    _closed(gen, 1006, s != null ? 'timeout' : 'token_timeout');
  }

  void _closed(int gen, int code, String reason) {
    if (gen != _gen) return;
    final opened = _openedAt;
    final stable = opened != null && _now() - opened >= roomStableMs;
    _drop();
    if (stable) _limited = 0;
    final attempt = stable ? 0 : _state.attempt;
    final random = _options.random ?? math.Random().nextDouble;
    final d = roomRetryDecision(
      code: code,
      reason: reason,
      attempt: attempt,
      limited: _limited,
      random: random,
    );
    if (d is! RoomRetry) {
      final stop = d as RoomNoRetry;
      _resumable = stop.resumable;
      _set(
        status: RoomStatus.closed,
        retryInMs: null,
        code: code,
        reason: stop.exhausted ? roomReasonExhausted : reason,
        attempt: attempt,
      );
      return;
    }
    _limited = d.limited ? _limited + 1 : 0;
    _rateWait = d.limited;
    _refreshNext = d.refreshToken;
    _set(
      status: RoomStatus.reconnecting,
      attempt: attempt + 1,
      retryInMs: d.delayMs,
      code: code,
      reason: reason,
    );
    final next = _gen;
    _later(_Timer.retry, d.delayMs, () {
      if (next == _gen) _connect();
    });
  }
}
