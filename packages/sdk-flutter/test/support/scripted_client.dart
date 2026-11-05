import 'dart:async';

import 'package:giftingstack/giftingstack_core.dart';

/// A call waiting for a test step to settle it.
class PendingCall {
  PendingCall(this.method) : completer = Completer<Object?>();
  final String method;
  final Completer<Object?> completer;
}

/// For fakes that only care about the tray: the component calls answer
/// nothing useful.
mixin UnusedComponentCalls implements GiftingClient {
  @override
  Future<List<ReceivedGift>> getReceivedGifts(
    String user, [
    String? reference,
  ]) async =>
      <ReceivedGift>[];

  @override
  Future<List<GiftWallResult>> queryGiftWalls(
    List<GiftWallQueryItem> items,
  ) async =>
      <GiftWallResult>[];

  @override
  Future<AwaySummary> getAway({String? since, int? maxGroups}) =>
      throw UnimplementedError('getAway');

  @override
  Future<void> ackAway(String cursor) => throw UnimplementedError('ackAway');

  @override
  Future<Inbox> getInbox({String? cursor, int? limit}) =>
      throw UnimplementedError('getInbox');

  @override
  Future<Leaderboard> getLeaderboard(
    LeaderboardBoard board, {
    LeaderboardPeriod? period,
    LeaderboardMetric? metric,
    String? at,
    int? limit,
    bool? includeMe,
  }) =>
      throw UnimplementedError('getLeaderboard');
}

/// A client whose every call stays pending until a step settles it (as in
/// `tray.json`). Calls are recorded as `{ method, args }` with absent args
/// dropped.
class ScriptedClient implements GiftingClient {
  final List<PendingCall> pending = <PendingCall>[];
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  Future<T> _call<T>(String method, Map<String, Object?>? args) {
    calls.add(<String, Object?>{'method': method, 'args': args});
    final p = PendingCall(method);
    pending.add(p);
    return p.completer.future.then((v) => v as T);
  }

  /// Removes and returns the OLDEST pending call of [method].
  PendingCall take(String method, String at) {
    final idx = pending.indexWhere((p) => p.method == method);
    if (idx < 0) throw StateError('$at: no pending $method');
    return pending.removeAt(idx);
  }

  @override
  Future<List<Gift>> getGifts() => _call('getGifts', null);

  @override
  Future<Me> getMe() => _call('getMe', null);

  @override
  Future<List<ReceivedGift>> getReceivedGifts(
    String user, [
    String? reference,
  ]) =>
      _call('getReceivedGifts', <String, Object?>{
        'user': user,
        if (reference != null) 'reference': reference,
      });

  @override
  Future<GiftTransaction> sendGift(SendGiftInput input) =>
      _call('sendGift', <String, Object?>{
        'receiver': input.receiver,
        'giftId': input.giftId,
        if (input.quantity != null) 'quantity': input.quantity,
        if (input.message != null) 'message': input.message,
        if (input.reference != null) 'reference': input.reference,
        if (input.idempotencyKey != null)
          'idempotencyKey': input.idempotencyKey,
      });

  @override
  Future<List<GiftWallResult>> queryGiftWalls(
    List<GiftWallQueryItem> items,
  ) =>
      _call('queryGiftWalls', <String, Object?>{
        'items': items.map((i) => i.toJson()).toList(),
      });

  @override
  Future<AwaySummary> getAway({String? since, int? maxGroups}) =>
      _call('getAway', <String, Object?>{
        if (since != null) 'since': since,
        if (maxGroups != null) 'maxGroups': maxGroups,
      });

  @override
  Future<void> ackAway(String cursor) =>
      _call('ackAway', <String, Object?>{'cursor': cursor});

  @override
  Future<Inbox> getInbox({String? cursor, int? limit}) =>
      _call('getInbox', <String, Object?>{
        'query': <String, Object?>{
          if (cursor != null) 'cursor': cursor,
          if (limit != null) 'limit': limit,
        },
      });

  @override
  Future<Leaderboard> getLeaderboard(
    LeaderboardBoard board, {
    LeaderboardPeriod? period,
    LeaderboardMetric? metric,
    String? at,
    int? limit,
    bool? includeMe,
  }) =>
      _call('getLeaderboard', <String, Object?>{
        'board': board.name,
        'query': <String, Object?>{
          if (period != null) 'period': period.name,
          if (metric != null) 'metric': metric.name,
          if (at != null) 'at': at,
          if (limit != null) 'limit': limit,
          if (includeMe != null) 'includeMe': includeMe,
        },
      });

  @override
  TokenProvider get getToken => throw UnimplementedError();

  @override
  void close() {}
}
