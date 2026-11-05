/// Leaderboard logic (SPEC section 16): tabs, a per-tab cache that answers at
/// once and revalidates in the background, the pinned "your rank" row and rank
/// labels. No drawing; the clock is injected. Port of
/// `packages/sdk-js/src/core/leaderboard.ts`.
library;

import 'dart:async';

import 'client.dart';
import 'component_types.dart';
import 'error.dart';
import 'timers.dart';
import 'tray.dart' show asGiftingError;

/// The shortest polling period a leaderboard accepts: 5 s (SPEC 16.4, audit
/// R-17).
const int leaderboardMinPollMs = 5000;

/// The polling period of a `refreshIntervalMs` option: 0 (or less) is no
/// polling, anything else is at least [leaderboardMinPollMs], so
/// `refreshIntervalMs: 50` cannot turn a screen into a request flood.
int leaderboardPollMs(int? refreshIntervalMs) {
  final ms = refreshIntervalMs ?? 0;
  return ms > 0 ? (ms < leaderboardMinPollMs ? leaderboardMinPollMs : ms) : 0;
}

/// The tabs of a board, in order.
const List<LeaderboardPeriod> leaderboardPeriods = <LeaderboardPeriod>[
  LeaderboardPeriod.day,
  LeaderboardPeriod.week,
  LeaderboardPeriod.month,
  LeaderboardPeriod.all,
];

/// A cached tab older than this is shown and fetched again in the background.
const int leaderboardStaleMs = 30000;

/// Rows asked for by default.
const int defaultLeaderboardLimit = 10;

/// Medal colours for ranks 1 to 3 (tokens used only by the leaderboard). The
/// rank number on them uses the theme's `noticeBigText`; the contract is
/// >= 4.5:1 (fixture `leaderboard.json#rankColors`).
const Map<String, String> leaderboardRankColors = <String, String>{
  'rank1': '#e8a93a',
  'rank2': '#b8bcc8',
  'rank3': '#c07a45',
};

/// `1234567` -> `1,234,567`: whole numbers with a separator every three
/// digits.
String groupThousands(int n, [String separator = ',']) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(separator);
    out.write(digits[i]);
  }
  return out.toString();
}

/// `#1`, `#417`, `#1,000`; null (beyond the top 1,000) -> [overflow]
/// (`1,000+`).
String leaderboardRankLabel(int? rank, {String overflow = '1,000+'}) =>
    rank == null ? overflow : '#${groupThousands(rank)}';

/// The viewer's own row, pinned under the list, or null. Pinned when the
/// viewer has a `me` block, is not hidden, has a score above 0 on the metric,
/// and is not visible in the rows: `rank` is null (beyond the top 1,000) or
/// greater than [limit], or a tie at the cut put them outside the returned
/// rows.
LeaderboardMe? pinnedMe(Leaderboard? board, int limit) {
  final me = board?.me;
  if (board == null || me == null || me.hidden) return null;
  if ((board.metric == LeaderboardMetric.gifts ? me.gifts : me.units) <= 0) {
    return null;
  }
  final rank = me.rank;
  if (rank == null || rank > limit) return me;
  return board.data.any((r) => r.user == me.user) ? null : me;
}

/// What a leaderboard shows.
enum LeaderboardStatus {
  /// Nothing to show yet (skeleton rows).
  loading,

  /// Rows are shown.
  ready,

  /// The board has no rows.
  empty,

  /// The first load of this tab failed (message and "Try again").
  error,
}

/// Settings of a [LeaderboardController]; read again at every use.
class LeaderboardControllerOptions {
  /// Creates options.
  const LeaderboardControllerOptions({
    required this.client,
    this.board = LeaderboardBoard.senders,
    this.periods = leaderboardPeriods,
    this.initialPeriod = LeaderboardPeriod.week,
    this.metric,
    this.limit = defaultLeaderboardLimit,
    this.includeMe = true,
    this.staleMs = leaderboardStaleMs,
    this.now,
    this.onError,
  });

  /// The API client.
  final GiftingClient client;

  /// Default senders.
  final LeaderboardBoard board;

  /// Tabs, in this order. An empty list counts as the default.
  final List<LeaderboardPeriod> periods;

  /// Default week, or the first of [periods] when week is not one of them.
  final LeaderboardPeriod initialPeriod;

  /// Default gifts for receivers, units for senders.
  final LeaderboardMetric? metric;

  /// Rows, 1 to 100. Default 10.
  final int limit;

  /// Default true: ask for the viewer's own `me` block.
  final bool includeMe;

  /// A cached tab at least this old is fetched again (ms).
  final int staleMs;

  /// Clock in ms. Default: wall clock.
  final int Function()? now;

  /// Called for every failure (also when rows stay visible).
  final void Function(GiftingException error)? onError;
}

/// What a leaderboard shows.
class LeaderboardState {
  /// Creates a state.
  const LeaderboardState({
    required this.periods,
    required this.period,
    required this.metric,
    required this.status,
    this.data,
    this.refreshing = false,
    this.error,
    this.pinned,
  });

  /// The tabs.
  final List<LeaderboardPeriod> periods;

  /// The current tab.
  final LeaderboardPeriod period;

  /// The current metric.
  final LeaderboardMetric metric;

  /// loading: nothing to show yet (skeleton rows); ready / empty: [data] is
  /// shown (empty = no rows); error: the first load of this tab failed.
  final LeaderboardStatus status;

  /// The answer shown for the current tab (possibly stale), else null.
  final Leaderboard? data;

  /// A request for the current tab is in flight while [data] stays visible.
  final bool refreshing;

  /// The last failure for the current tab, cleared by its next success.
  final GiftingException? error;

  /// The viewer's row to pin under the list ([pinnedMe]).
  final LeaderboardMe? pinned;

  LeaderboardState _withTab(
          {LeaderboardPeriod? period, LeaderboardMetric? metric}) =>
      LeaderboardState(
        periods: periods,
        period: period ?? this.period,
        metric: metric ?? this.metric,
        status: status,
        data: data,
        refreshing: refreshing,
        error: error,
        pinned: pinned,
      );
}

/// Tabs, a per-tab cache and the pinned row of a leaderboard (SPEC 16.3).
class LeaderboardController {
  /// Creates a controller. Call [start] when the screen opens.
  LeaderboardController(LeaderboardControllerOptions options)
      : _options = options {
    final periods =
        options.periods.isEmpty ? leaderboardPeriods : options.periods;
    _state = LeaderboardState(
      periods: periods,
      period: periods.contains(options.initialPeriod)
          ? options.initialPeriod
          : periods.first,
      metric: options.metric ??
          (options.board == LeaderboardBoard.receivers
              ? LeaderboardMetric.gifts
              : LeaderboardMetric.units),
      status: LeaderboardStatus.loading,
    );
  }

  LeaderboardControllerOptions _options;
  late LeaderboardState _state;
  final List<void Function()> _listeners = <void Function()>[];
  final Map<String, ({Leaderboard value, int at})> _cache =
      <String, ({Leaderboard value, int at})>{};
  final Map<String, GiftingException> _errors = <String, GiftingException>{};
  final Set<String> _inFlight = <String>{};
  bool _alive = true;

  /// Callbacks are read when used. `board`, `limit` and `includeMe` changes
  /// apply to new requests.
  // ignore: use_setters_to_change_properties
  void setOptions(LeaderboardControllerOptions options) => _options = options;

  /// The current state.
  LeaderboardState get state => _state;

  /// Calls [listener] after every state change. Returns a function that stops
  /// it.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  int _now() => (_options.now ?? wallClockMs)();

  String _key() => '${_state.period.name}|${_state.metric.name}';

  /// Recompute the visible state of the current tab from the cache and the
  /// requests.
  void _render() {
    final key = _key();
    final hit = _cache[key];
    final error = _errors[key];
    final data = hit?.value;
    final LeaderboardStatus status;
    if (data != null) {
      status = data.data.isNotEmpty
          ? LeaderboardStatus.ready
          : LeaderboardStatus.empty;
    } else {
      status = error != null && !_inFlight.contains(key)
          ? LeaderboardStatus.error
          : LeaderboardStatus.loading;
    }
    _state = LeaderboardState(
      periods: _state.periods,
      period: _state.period,
      metric: _state.metric,
      status: status,
      data: data,
      refreshing: data != null && _inFlight.contains(key),
      error: error,
      pinned: pinnedMe(data, _options.limit),
    );
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  /// Show the current tab: cached answer at once, a request if none or if it
  /// is stale.
  void _show({required bool force}) {
    final key = _key();
    final hit = _cache[key];
    final stale = hit == null || _now() - hit.at >= _options.staleMs;
    if ((force || stale) && !_inFlight.contains(key)) unawaited(_fetch(key));
    _render();
  }

  Future<void> _fetch(String key) async {
    final parts = key.split('|');
    final period = LeaderboardPeriod.values.byName(parts[0]);
    final metric = LeaderboardMetric.values.byName(parts[1]);
    _inFlight.add(key);
    final o = _options;
    try {
      final value = await o.client.getLeaderboard(
        o.board,
        period: period,
        metric: metric,
        limit: o.limit,
        includeMe: o.includeMe ? null : false,
      );
      _cache[key] = (value: value, at: _now());
      _errors.remove(key);
    } on Object catch (err) {
      final e = asGiftingError(err);
      _errors[key] = e;
      if (_alive) _options.onError?.call(e);
    } finally {
      _inFlight.remove(key);
    }
    if (_alive) _render();
  }

  /// The screen opened: load the first tab.
  void start() => _show(force: false);

  /// Switch to another tab; ignored when unchanged.
  void setPeriod(LeaderboardPeriod period) {
    if (period == _state.period) return;
    _state = _state._withTab(period: period);
    _show(force: false);
  }

  /// Switch the metric; ignored when unchanged.
  void setMetric(LeaderboardMetric metric) {
    if (metric == _state.metric) return;
    _state = _state._withTab(metric: metric);
    _show(force: false);
  }

  /// Fetch the current tab again now (pull to refresh, "Try again", a poll).
  void refresh() => _show(force: true);

  /// The screen is gone: answers that arrive later change nothing.
  void dispose() => _alive = false;
}
