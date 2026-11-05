import 'package:giftingstack/giftingstack.dart';

import 'demo_data.dart';

const int startBalance = 60000;
const Duration _latency = Duration(milliseconds: 250);

/// A gift the demo user received: `(sender, catalog index, quantity, minutes
/// ago)`. The last one is older than 24 hours, so the inbox leaves it out.
const List<(String, int, int, int)> _seedReceived = [
  ('mateo', 1, 1, 180),
  ('zoe', 3, 2, 300),
  ('elise', 5, 1, 480),
  ('sofia', 6, 1, 1260),
  ('dana', 2, 1, 1800),
];

/// One gift that reached the demo user.
class _Received {
  const _Received(this.id, this.at, this.sender, this.gift, this.quantity);

  final String id;
  final DateTime at;
  final String sender;
  final Gift gift;
  final int quantity;
}

/// A stand-in for GiftingStack that lives in the app: same shapes and errors as
/// `/v1/client`, a quarter second of fake network delay, and a balance you can
/// top up from the mock coin store or put back from the developer menu. Swap
/// it for `GiftingClient(getToken: ...)` to talk to the real API.
class MockGiftingClient implements GiftingClient {
  /// Creates the client. [gifts] is the catalog (it may still be loading).
  MockGiftingClient(this._gifts);

  final Future<List<Gift>> _gifts;
  int _balance = startBalance;
  final Map<String, GiftTransaction> _sent = {};

  /// Gifts that reached a wall in this session, per `receiver|reference`:
  /// gift id -> count, so a wall grows when you send one.
  final Map<String, Map<String, int>> _extra = {};
  bool _offline = false;
  bool _hidden = false;
  bool _awayAcked = false;
  int _awayRound = 0;

  /// Gifts that reached the demo user in this session, newest first.
  final List<_Received> _received = [];
  int _receivedSeq = 0;
  DateTime _seedAt = DateTime.now();

  /// A gift from [sender] reached the demo user (the inbox lists it).
  void receive(Gift gift, String sender, int quantity) {
    _received.insert(
      0,
      _Received(
        'gtx_demo${++_receivedSeq}',
        DateTime.now(),
        sender,
        gift,
        quantity,
      ),
    );
  }

  /// Cursors acknowledged by `ackAway`, for tests.
  final List<String> ackedCursors = [];

  /// "Away summary again": pretend gifts arrived again.
  void resetAway() {
    _awayAcked = false;
    _awayRound++;
  }

  /// What the developer menu's "Reset demo" does: back to 60 000 coins and the
  /// walls as they were.
  void reset() {
    _balance = startBalance;
    _extra.clear();
    _received.clear();
    _seedAt = DateTime.now();
    _hidden = false;
  }

  /// The mock failure switch: every call fails like a lost connection
  /// (`network_error`, status 0).
  set offline(bool value) => _offline = value;

  /// The "Hide me from leaderboards" flag of the signed-in person.
  set hidden(bool value) => _hidden = value;

  /// Gifts that reached a wall from elsewhere (an incoming gift, "wall +5").
  void addToWall(
    String receiver,
    String giftId,
    int quantity, [
    String? reference,
  ]) {
    final m = _extra.putIfAbsent('$receiver|${reference ?? ''}', () => {});
    m[giftId] = (m[giftId] ?? 0) + quantity;
  }

  /// What your server does after a purchase (`POST /v1/users/{id}/credit`):
  /// the coins are ADDED to the balance.
  void credit(int coins) => _balance += coins;

  /// The current balance, for tests.
  int get balance => _balance;

  void _down() {
    if (_offline) {
      throw const GiftingException(0, 'network_error', 'You are offline.');
    }
  }

  @override
  Future<List<Gift>> getGifts() async {
    await Future<void>.delayed(_latency);
    _down();
    return _gifts;
  }

  @override
  Future<Me> getMe() async {
    await Future<void>.delayed(_latency ~/ 2);
    _down();
    return Me(user: 'ava', balance: _balance, livemode: false);
  }

  @override
  Future<List<ReceivedGift>> getReceivedGifts(
    String user, [
    String? reference,
  ]) async {
    _down();
    return _wallOf(await _gifts, user, reference);
  }

  List<ReceivedGift> _wallOf(List<Gift> catalog, String user, String? ref) =>
      wallFor(
        catalog,
        _extra['$user|${ref ?? ''}'] ?? const {},
        user: user,
        reference: ref,
      );

  @override
  Future<List<GiftWallResult>> queryGiftWalls(
    List<GiftWallQueryItem> items,
  ) async {
    await Future<void>.delayed(_latency);
    _down();
    final catalog = await _gifts;
    return [
      for (final i in items)
        GiftWallResult(
          receiver: i.receiver,
          reference: i.reference,
          gifts: _wallOf(catalog, i.receiver, i.reference),
        ),
    ];
  }

  @override
  Future<AwaySummary> getAway({String? since, int? maxGroups}) async {
    await Future<void>.delayed(_latency);
    _down();
    final cursor = 'aw1.demo$_awayRound';
    if (_awayAcked) return emptyAwaySummary(cursor: cursor);
    final summary = awaySummaryFor(await _gifts, cursor: cursor);
    if (maxGroups == null || maxGroups >= summary.groups.length) return summary;
    return AwaySummary(
      user: summary.user,
      since: summary.since,
      until: summary.until,
      cursor: summary.cursor,
      truncated: summary.truncated,
      totalGifts: summary.totalGifts,
      totalUnits: summary.totalUnits,
      senderCount: summary.senderCount,
      groups: summary.groups.take(maxGroups).toList(),
      topSenders: summary.topSenders,
    );
  }

  @override
  Future<void> ackAway(String cursor) async {
    await Future<void>.delayed(_latency ~/ 2);
    _down();
    ackedCursors.add(cursor);
    _awayAcked = true;
  }

  @override
  Future<Inbox> getInbox({String? cursor, int? limit}) async {
    await Future<void>.delayed(_latency);
    _down();
    final catalog = await _gifts;
    final now = DateTime.now().toUtc();
    final since = now.subtract(const Duration(hours: 24));
    final all = <_Received>[
      ..._received,
      if (catalog.isNotEmpty)
        for (final (i, s) in _seedReceived.indexed)
          _Received(
            'gtx_seed${i + 1}',
            _seedAt.subtract(Duration(minutes: s.$4)),
            s.$1,
            catalog[s.$2 % catalog.length],
            s.$3,
          ),
    ]..sort((a, b) {
        final byTime = b.at.compareTo(a.at);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
    final window = all.where((r) => r.at.isAfter(since)).toList();
    final size = limit == null ? 20 : limit.clamp(1, 100).toInt();
    final start = cursor != null && cursor.startsWith('ib1.')
        ? (int.tryParse(cursor.substring(4)) ?? 0)
        : 0;
    final end = start + size;
    return Inbox(
      user: 'ava',
      since: since.toIso8601String(),
      until: now.toIso8601String(),
      data: [
        for (final r in window.skip(start).take(size))
          InboxItem(
            id: r.id,
            createdAt: r.at.toUtc().toIso8601String(),
            sender: r.sender,
            gift: AwayGift(
              id: r.gift.id,
              name: r.gift.name,
              price: r.gift.price,
              iconUrl: r.gift.iconUrl,
              animationUrl: r.gift.animationUrl,
            ),
            quantity: r.quantity,
            units: r.gift.price * r.quantity,
            status: inboxStatusCompleted,
          ),
      ],
      hasMore: end < window.length,
      nextCursor: end < window.length ? 'ib1.$end' : null,
    );
  }

  @override
  Future<Leaderboard> getLeaderboard(
    LeaderboardBoard board, {
    LeaderboardPeriod? period,
    LeaderboardMetric? metric,
    String? at,
    int? limit,
    bool? includeMe,
  }) async {
    await Future<void>.delayed(_latency);
    _down();
    return leaderboardFor(
      board,
      period: period ?? LeaderboardPeriod.week,
      metric: metric,
      limit: limit ?? 10,
      includeMe: includeMe != false,
      hidden: _hidden,
    );
  }

  @override
  Future<GiftTransaction> sendGift(SendGiftInput input) async {
    await Future<void>.delayed(_latency);
    _down();
    final key = input.idempotencyKey ?? newIdempotencyKey();
    final again = _sent[key];
    if (again != null) return again;
    final gifts = await _gifts;
    final gift = gifts.where((g) => g.id == input.giftId).firstOrNull;
    if (gift == null) {
      throw const GiftingException(404, 'not_found', 'Gift not found.');
    }
    final quantity = input.quantity ?? 1;
    final total = gift.price * quantity;
    if (_balance < total) {
      throw const GiftingException(
        422,
        'insufficient_balance',
        'Insufficient balance.',
      );
    }
    _balance -= total;
    addToWall(input.receiver, gift.id, quantity, input.reference);
    final tx = GiftTransaction(
      id: 'gtx_$key',
      sender: 'ava',
      receiver: input.receiver,
      gift: GiftRef(id: gift.id, name: gift.name, iconUrl: gift.iconUrl),
      quantity: quantity,
      unitPrice: gift.price,
      total: total,
      message: input.message,
      reference: input.reference,
      status: 'completed',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      senderBalanceAfter: _balance,
    );
    _sent[key] = tx;
    return tx;
  }

  @override
  TokenProvider get getToken =>
      ({required bool forceRefresh}) async => 'mock-token';

  @override
  void close() {}
}
