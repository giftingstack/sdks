/// Gift wall logic (SPEC section 14): which chips a wall shows, how counts are
/// written, and a loader that batches the walls of a feed into few requests.
/// No drawing; the clock and the timer are injected so the fixtures can drive
/// it. Port of `packages/sdk-js/src/core/wall.ts`.
library;

import 'dart:async';

import 'component_types.dart';
import 'timers.dart';
import 'types.dart';

/// Chips a wall shows by default, the overflow chip included.
const int defaultWallMax = 6;

/// How a wall orders its chips.
enum WallOrder {
  /// Most received first (ties keep the catalog order).
  count,

  /// The server's (catalog) order.
  catalog,
}

/// One chip of a wall: a gift with its count, or the overflow chip.
sealed class WallChip {
  const WallChip();
}

/// A gift and how many were received.
class WallGiftChip extends WallChip {
  /// Creates a gift chip.
  const WallGiftChip(this.gift, this.count);

  /// Which gift.
  final GiftRef gift;

  /// How many.
  final int count;
}

/// "+37": the sum of the gifts that did not fit.
class WallOverflowChip extends WallChip {
  /// Creates the overflow chip.
  const WallOverflowChip({required this.count, required this.hidden});

  /// The SUM of the hidden gifts' counts.
  final int count;

  /// How many gift kinds it stands for.
  final int hidden;
}

/// The chips of a wall. [items] come in catalog order (as the API sends
/// them). Counts of 0 or less are dropped. With more gifts than [max], the
/// first `max - 1` are shown and one overflow chip carries the sum of the
/// rest. [max] below 1 counts as 1.
List<WallChip> wallChips(
  List<ReceivedGift> items, {
  int max = defaultWallMax,
  WallOrder order = WallOrder.count,
}) {
  final limit = max < 1 ? 1 : max;
  var kept = <ReceivedGift>[
    for (final i in items)
      if (i.count > 0) i,
  ];
  if (order == WallOrder.count) {
    // Dart's sort is not stable: equal counts keep the catalog order by index.
    final indexed = <(int, ReceivedGift)>[
      for (var i = 0; i < kept.length; i++) (i, kept[i]),
    ]..sort((a, b) {
        final byCount = b.$2.count.compareTo(a.$2.count);
        return byCount != 0 ? byCount : a.$1.compareTo(b.$1);
      });
    kept = <ReceivedGift>[for (final e in indexed) e.$2];
  }
  WallChip chip(ReceivedGift i) => WallGiftChip(i.gift, i.count);
  if (kept.length <= limit) return kept.map(chip).toList();
  final shown = kept.sublist(0, limit - 1);
  final hidden = kept.sublist(limit - 1);
  return <WallChip>[
    ...shown.map(chip),
    WallOverflowChip(
      count: hidden.fold<int>(0, (sum, i) => sum + i.count),
      hidden: hidden.length,
    ),
  ];
}

/// Count suffixes of [formatCount].
class CountLabels {
  /// Creates the labels.
  const CountLabels({
    this.thousand = 'K',
    this.million = 'M',
    this.decimal = '.',
  });

  /// Default `K`.
  final String thousand;

  /// Default `M`.
  final String million;

  /// Default `.`.
  final String decimal;
}

/// A short count that never overstates: `999`, `1K`, `1.9K` (1,999), `12K`,
/// `999K`, `1M`, `1.2M`, `12M`. Always rounded DOWN; a `.0` is left out.
/// Fractional input is truncated towards zero first (non-finite: 0); below
/// 1,000 (negative too) it is written as is.
String formatCount(num n, [CountLabels labels = const CountLabels()]) {
  final v = n.isFinite ? n.truncate() : 0;
  String tenths(int unit, String suffix) {
    final t = v ~/ (unit ~/ 10);
    final whole = t ~/ 10;
    final dec = t % 10;
    return dec == 0 ? '$whole$suffix' : '$whole${labels.decimal}$dec$suffix';
  }

  if (v < 1000) return '$v';
  if (v < 10000) return tenths(1000, labels.thousand);
  if (v < 1000000) return '${v ~/ 1000}${labels.thousand}';
  if (v < 10000000) return tenths(1000000, labels.million);
  return '${v ~/ 1000000}${labels.million}';
}

// ---------------------------------------------------------------- loader

/// Requests made within this many ms of the first one share one batch call.
const int wallBatchWindowMs = 50;

/// The API answers at most this many walls per call; more make several calls.
const int wallBatchSize = 25;

/// A wall's answer is reused for this long.
const int wallCacheTtlMs = 60000;

class _Waiter {
  _Waiter(this.item, this.generation);

  final GiftWallQueryItem item;
  final Completer<List<ReceivedGift>> completer =
      Completer<List<ReceivedGift>>();
  int generation;
}

String _keyOf(String user, String? reference) =>
    '$user\u0000${reference ?? ''}';

/// Shares wall requests across every `GiftWall` on a screen. [load] calls made
/// within `windowMs` (50) of the first queued one go out together when that
/// window closes, in batches of at most 25 walls, in the order first asked. A
/// wall that is queued or in flight is not asked again (same future). An
/// answer is cached per `(user, reference)` for `ttlMs` (60,000) from the
/// moment it arrived; a failure is not cached.
class GiftWallLoader {
  /// Creates a loader. [query] is the batch call, usually
  /// `client.queryGiftWalls`.
  GiftWallLoader({
    required this.query,
    int Function()? now,
    TimerStarter? setTimeout,
    this.windowMs = wallBatchWindowMs,
    this.batchSize = wallBatchSize,
    this.ttlMs = wallCacheTtlMs,
  })  : _now = now ?? wallClockMs,
        _setTimeout = setTimeout ?? startTimer;

  /// The batch call.
  final Future<List<GiftWallResult>> Function(List<GiftWallQueryItem> items)
      query;

  /// The window in ms.
  final int windowMs;

  /// Walls per call.
  final int batchSize;

  /// How long an answer is reused, ms.
  final int ttlMs;

  final int Function() _now;
  final TimerStarter _setTimeout;
  final Map<String, ({List<ReceivedGift> gifts, int at})> _cache =
      <String, ({List<ReceivedGift> gifts, int at})>{};

  /// Queued (window open) or in flight, by key.
  final Map<String, _Waiter> _waiting = <String, _Waiter>{};

  /// Keys queued in the open window, in the order first asked.
  List<String> _queue = <String>[];
  bool _windowOpen = false;
  final Map<String, int> _generations = <String, int>{};

  /// The cached wall if it is still fresh, else null. Lets a wall draw at once.
  List<ReceivedGift>? peek(String user, [String? reference]) {
    final hit = _cache[_keyOf(user, reference)];
    return hit != null && _now() - hit.at < ttlMs ? hit.gifts : null;
  }

  /// The wall's counters; see the class comment.
  Future<List<ReceivedGift>> load(String user, [String? reference]) {
    final fresh = peek(user, reference);
    if (fresh != null) return Future<List<ReceivedGift>>.value(fresh);
    final key = _keyOf(user, reference);
    final known = _waiting[key];
    if (known != null) return known.completer.future;
    final waiter = _Waiter(
      GiftWallQueryItem(receiver: user, reference: reference),
      _generations[key] ?? 0,
    );
    _waiting[key] = waiter;
    _queue.add(key);
    if (!_windowOpen) {
      _windowOpen = true;
      _setTimeout(_flush, windowMs);
    }
    return waiter.completer.future;
  }

  /// Forget a wall (for example after the person sent a gift to it): the next
  /// [load] asks the server again, even if an older request is still in flight
  /// (its answer is then not cached).
  void invalidate(String user, [String? reference]) {
    final key = _keyOf(user, reference);
    _cache.remove(key);
    final generation = (_generations[key] ?? 0) + 1;
    _generations[key] = generation;
    final w = _waiting[key];
    if (w == null) return;
    // A queued wall has not been asked yet: it goes out with its window and
    // its answer counts. One in flight is let go: its answer reaches its
    // callers but is not cached.
    if (_queue.contains(key)) {
      w.generation = generation;
    } else {
      _waiting.remove(key);
    }
  }

  /// Forget every cached wall (requests already queued or in flight are kept).
  void clear() => _cache.clear();

  void _flush() {
    _windowOpen = false;
    final keys = _queue;
    _queue = <String>[];
    final size = batchSize < 1 ? 1 : batchSize;
    for (var i = 0; i < keys.length; i += size) {
      final end = i + size < keys.length ? i + size : keys.length;
      final chunk = keys.sublist(i, end);
      final waiters = chunk.map((k) => _waiting[k]!).toList();
      unawaited(_send(chunk, waiters));
    }
  }

  Future<void> _send(List<String> keys, List<_Waiter> waiters) async {
    try {
      final walls = await query(waiters.map((w) => w.item).toList());
      final at = _now();
      for (var i = 0; i < waiters.length; i++) {
        final w = waiters[i];
        final key = keys[i];
        final gifts = i < walls.length ? walls[i].gifts : <ReceivedGift>[];
        if (identical(_waiting[key], w)) _waiting.remove(key);
        if ((_generations[key] ?? 0) == w.generation) {
          _cache[key] = (gifts: gifts, at: at);
        }
        w.completer.complete(gifts);
      }
    } on Object catch (err) {
      for (var i = 0; i < waiters.length; i++) {
        final w = waiters[i];
        if (identical(_waiting[keys[i]], w)) _waiting.remove(keys[i]);
        w.completer.completeError(err);
      }
    }
  }
}
