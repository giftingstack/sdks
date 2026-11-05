/// "While you were away" logic (SPEC section 15): the replay plan for the
/// effect layer and the controller behind the summary card. No drawing; the
/// clock and timers are injected. Port of
/// `packages/sdk-js/src/core/away.ts`.
library;

import 'dart:async';
import 'dart:math' as math;

import 'client.dart';
import 'component_types.dart';
import 'error.dart';
import 'recipes.dart';
import 'timers.dart';
import 'tray.dart' show asGiftingError;
import 'types.dart';

/// Gift groups replayed at most.
const int defaultAwayMaxEffects = 5;

/// The replay must have ended by then (ms after the card appears).
const int defaultAwayBudgetMs = 8000;

/// Start gap after a small effect (keeps medium at <= 2 at once).
const int awayGapAfterSmallMs = 450;

/// Start gap after a medium effect.
const int awayGapAfterMediumMs = 1100;

/// The large effect starts this long after every earlier effect has ended.
const int awayLargePauseMs = 300;

/// The card stays at least this long...
const int awayCardMinMs = 4000;

/// ...and this long after the last effect ends.
const int awayCardTailMs = 1500;

/// `foreground()` checks again at most this often.
const int awayForegroundThrottleMs = 60000;

/// How long one effect runs, from SPEC 7.3:
/// `flyInMs + max(900, tail, coins > 0 ? tail + 800 : 0)` with
/// `tail = holdMs + flyOutMs`. Small 1600, medium 2100, large 3850 (3050 at
/// low quality).
int effectDurationMs(EffectRecipe recipe) {
  final tail = recipe.holdMs + recipe.flyOutMs;
  return recipe.flyInMs +
      math.max(900, math.max(tail, recipe.coins > 0 ? tail + 800 : 0));
}

/// Texts of [awaySenderLabel]; null fields take the English defaults.
class AwaySenderLabels {
  /// Creates the labels.
  const AwaySenderLabels({
    this.someone = 'Someone',
    this.pair = '{a} and {b}',
    this.oneOther = '{a} and 1 other',
    this.others = '{a} and {n} others',
  });

  /// A deleted sender.
  final String someone;

  /// Two people.
  final String pair;

  /// One named person and one more.
  final String oneOther;

  /// One named person and `{n}` more.
  final String others;
}

/// Who sent a group, for the effect's notice. [names] are display names in the
/// server's order (a deleted sender already turned into `labels.someone`),
/// [senderCount] the number of distinct people. 1 -> `ayla`; 2 with two names
/// -> `ayla and mert`; otherwise `ayla and {senderCount - 1} others` (`... and
/// 1 other` for one). No name -> `someone`.
String awaySenderLabel(
  List<String> names,
  int senderCount, [
  AwaySenderLabels labels = const AwaySenderLabels(),
]) {
  final a = names.isEmpty ? labels.someone : names[0];
  if (senderCount <= 1) return a;
  if (senderCount == 2 && names.length >= 2) {
    return labels.pair.replaceFirst('{a}', a).replaceFirst('{b}', names[1]);
  }
  final n = senderCount - 1;
  if (n == 1) return labels.oneOther.replaceFirst('{a}', a);
  return labels.others.replaceFirst('{a}', a).replaceFirst('{n}', '$n');
}

/// One planned effect of the replay.
class AwayReplayItem {
  /// Creates an item.
  const AwayReplayItem({
    required this.atMs,
    required this.durationMs,
    required this.tier,
    required this.group,
    required this.event,
  });

  /// Start, in ms after the card appeared.
  final int atMs;

  /// How long the effect runs.
  final int durationMs;

  /// Its tier.
  final EffectTier tier;

  /// The gift group it stands for.
  final AwayGroup group;

  /// What to pass to the effect layer's `play`.
  final GiftEffectEvent event;
}

/// The replay of an away summary.
class AwayReplayPlan {
  /// Creates a plan.
  const AwayReplayPlan({required this.items, required this.endMs});

  /// In start order.
  final List<AwayReplayItem> items;

  /// When the last effect ends (0 for an empty plan).
  final int endMs;
}

/// Plans the replay of an away summary as one short sequence, biggest last
/// (SPEC 15.3): the first [maxEffects] groups; only the first large one; small
/// and medium by units ascending (ties: gift id), then the large one; gaps 450
/// after small, 1100 after medium, the large one 300 ms after everything
/// before it ended; while the end is past [budgetMs], the non-large item with
/// the lowest units goes (a lone large item that does not fit goes too).
/// [reducedMotion]: the plan is empty and only the card shows.
AwayReplayPlan planAwayReplay(
  List<AwayGroup> groups, {
  int maxEffects = defaultAwayMaxEffects,
  int budgetMs = defaultAwayBudgetMs,
  TierThresholds thresholds = const TierThresholds(),
  EffectQuality quality = EffectQuality.high,
  bool reducedMotion = false,
  String Function(String user)? resolveName,
  AwaySenderLabels labels = const AwaySenderLabels(),
}) {
  if (reducedMotion) {
    return const AwayReplayPlan(items: <AwayReplayItem>[], endMs: 0);
  }
  final max = math.max(0, maxEffects);
  final name = resolveName ?? (String u) => u;
  final tiered = groups
      .take(max)
      .map((g) => (group: g, tier: tierFor(g.gift.price, thresholds)))
      .toList();
  ({AwayGroup group, EffectTier tier})? large;
  for (final t in tiered) {
    if (t.tier == EffectTier.large) {
      large = t;
      break;
    }
  }
  // Stable by index; ties of units and gift id keep the server's order.
  final indexed = <(int, ({AwayGroup group, EffectTier tier}))>[
    for (var i = 0; i < tiered.length; i++)
      if (tiered[i].tier != EffectTier.large) (i, tiered[i]),
  ]..sort((a, b) {
      final byUnits = a.$2.group.units.compareTo(b.$2.group.units);
      if (byUnits != 0) return byUnits;
      final byId = a.$2.group.gift.id.compareTo(b.$2.group.gift.id);
      return byId != 0 ? byId : a.$1.compareTo(b.$1);
    });
  var rest = <({AwayGroup group, EffectTier tier})>[
    for (final e in indexed) e.$2,
  ];

  AwayReplayItem makeItem(
    AwayGroup group,
    EffectTier tier,
    int atMs,
    int durationMs,
  ) =>
      AwayReplayItem(
        atMs: atMs,
        durationMs: durationMs,
        tier: tier,
        group: group,
        event: GiftEffectEvent(
          gift: GiftEffectGift(
            id: group.gift.id,
            name: group.gift.name,
            price: group.gift.price,
            image: group.gift.animationUrl ?? group.gift.iconUrl,
            icon: group.gift.iconUrl,
          ),
          quantity: group.count,
          sender: awaySenderLabel(
            group.senders
                .map((s) => s.user == null ? labels.someone : name(s.user!))
                .toList(),
            group.senderCount,
            labels,
          ),
        ),
      );

  AwayReplayPlan layout(
    List<({AwayGroup group, EffectTier tier})> small,
    ({AwayGroup group, EffectTier tier})? big,
  ) {
    final items = <AwayReplayItem>[];
    var at = 0;
    var end = 0;
    for (final t in small) {
      final durationMs = effectDurationMs(recipeFor(t.tier, quality));
      items.add(makeItem(t.group, t.tier, at, durationMs));
      end = math.max(end, at + durationMs);
      at += t.tier == EffectTier.small
          ? awayGapAfterSmallMs
          : awayGapAfterMediumMs;
    }
    if (big != null) {
      final start = items.isNotEmpty ? end + awayLargePauseMs : 0;
      final durationMs = effectDurationMs(recipeFor(EffectTier.large, quality));
      items.add(makeItem(big.group, EffectTier.large, start, durationMs));
      end = start + durationMs;
    }
    return AwayReplayPlan(items: items, endMs: end);
  }

  var plan = layout(rest, large);
  while (plan.endMs > budgetMs && plan.items.isNotEmpty) {
    if (rest.isNotEmpty) {
      rest = rest.sublist(1);
    } else {
      large = null;
    }
    plan = layout(rest, large);
  }
  return plan;
}

/// How long the card stays: `max(4000, plan end + 1500)` ms.
int awayCardDurationMs(AwayReplayPlan plan) =>
    math.max(awayCardMinMs, plan.endMs + awayCardTailMs);

// ---------------------------------------------------------------- controller

/// Where the summary card is in its life.
enum AwayStatus {
  /// Nothing asked yet, or the last read failed.
  idle,

  /// Asking the server.
  loading,

  /// Nothing new.
  empty,

  /// A summary is there; the card is about to show.
  ready,

  /// The card is on screen and the replay runs.
  playing,

  /// The card went away.
  done,
}

/// When the summary counts as seen.
enum AwayAckOn {
  /// When the card appears (default).
  shown,

  /// When the card goes away (tap or timeout).
  finished,

  /// Only when the app calls `ack()`.
  manual,
}

/// The part of an effect layer the replay needs.
abstract interface class AwayEffectPlayer {
  /// Shows a gift; returns an id.
  int play(GiftEffectEvent event);
}

/// Settings of an [AwayController]; read again at every use.
class AwayControllerOptions {
  /// Creates options.
  const AwayControllerOptions({
    required this.client,
    this.effects,
    this.reducedMotion,
    this.ackOn = AwayAckOn.shown,
    this.maxGroups,
    this.maxEffects = defaultAwayMaxEffects,
    this.budgetMs = defaultAwayBudgetMs,
    this.thresholds = const TierThresholds(),
    this.quality = EffectQuality.high,
    this.resolveName,
    this.labels = const AwaySenderLabels(),
    this.onShow,
    this.onDone,
    this.onError,
    this.now,
    this.setTimeout,
    this.clearTimeout,
    this.throttleMs = awayForegroundThrottleMs,
  });

  /// The API client (`getAway`, `ackAway`).
  final GiftingClient client;

  /// The effect layer, read at each play. None: card only.
  final AwayEffectPlayer? Function()? effects;

  /// Read when the card appears.
  final bool Function()? reducedMotion;

  /// When the summary counts as seen.
  final AwayAckOn ackOn;

  /// Sent as `max_groups` when given.
  final int? maxGroups;

  /// Gift groups replayed at most.
  final int maxEffects;

  /// The replay ends within this many ms.
  final int budgetMs;

  /// Tier thresholds, as the layer's.
  final TierThresholds thresholds;

  /// Effect quality, as the layer's.
  final EffectQuality quality;

  /// Display name of a sender id. Default: the id itself.
  final String Function(String user)? resolveName;

  /// Texts of the sender label.
  final AwaySenderLabels labels;

  /// The card appeared.
  final void Function(AwaySummary summary)? onShow;

  /// The card went away.
  final void Function()? onDone;

  /// Failures never show; they come here.
  final void Function(GiftingException error)? onError;

  /// Clock in ms. Default: wall clock.
  final int Function()? now;

  /// Timer starter. Default: `dart:async` [Timer].
  final TimerStarter? setTimeout;

  /// Timer canceller matching [setTimeout].
  final TimerCanceller? clearTimeout;

  /// `foreground()` checks again at most this often (ms).
  final int throttleMs;
}

/// What the card shows.
class AwayState {
  /// Creates a state.
  const AwayState({this.status = AwayStatus.idle, this.summary, this.plan});

  /// Where the card is in its life.
  final AwayStatus status;

  /// The summary being shown (ready, playing, done), else null.
  final AwaySummary? summary;

  /// The replay, planned when the card appears (playing, done), else null.
  final AwayReplayPlan? plan;
}

/// Drives one summary card: [check] loads, the UI shows the card and calls
/// [start], the controller plays the replay and dismisses the card after
/// [awayCardDurationMs], or earlier on [dismiss]. idle -> loading -> empty |
/// ready -> playing -> done; a failed load goes back to idle silently. [check]
/// runs only from a resting state (idle, empty, done).
class AwayController {
  /// Creates a controller.
  AwayController(AwayControllerOptions options) : _options = options;

  AwayControllerOptions _options;
  AwayState _state = const AwayState();
  final List<void Function()> _listeners = <void Function()>[];
  final List<Object?> _timers = <Object?>[];
  bool _alive = true;

  /// Whether the summary on screen was acknowledged (or its one attempt made).
  bool _acked = false;

  /// A cursor whose acknowledgement failed: retried once, at the next check.
  String? _retryCursor;
  int? _lastCheckAt;

  /// Callbacks and settings are read when used, so they can change.
  // ignore: use_setters_to_change_properties
  void setOptions(AwayControllerOptions options) => _options = options;

  /// The current state.
  AwayState get state => _state;

  /// Calls [listener] after every state change. Returns a function that stops
  /// it.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _set(
      {AwayStatus? status, Object? summary = _keep, Object? plan = _keep}) {
    _state = AwayState(
      status: status ?? _state.status,
      summary:
          identical(summary, _keep) ? _state.summary : summary as AwaySummary?,
      plan: identical(plan, _keep) ? _state.plan : plan as AwayReplayPlan?,
    );
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  static const Object _keep = Object();

  int _now() => (_options.now ?? wallClockMs)();

  void _later(void Function() fn, int ms) =>
      _timers.add((_options.setTimeout ?? startTimer)(fn, ms));

  void _stopTimers() {
    final cancel = _options.clearTimeout ?? cancelTimer;
    for (final t in _timers) {
      cancel(t);
    }
    _timers.clear();
  }

  /// Ask the server what arrived. Ignored while loading, ready or playing.
  Future<void> check() async {
    final s = _state.status;
    if (s != AwayStatus.idle && s != AwayStatus.empty && s != AwayStatus.done) {
      return;
    }
    _lastCheckAt = _now();
    _set(status: AwayStatus.loading, summary: null, plan: null);
    final client = _options.client;
    final retry = _retryCursor;
    if (retry != null) {
      _retryCursor = null;
      try {
        await client.ackAway(retry);
      } on Object catch (err) {
        if (_alive) _options.onError?.call(asGiftingError(err));
      }
      if (!_alive) return;
    }
    final AwaySummary summary;
    try {
      final max = _options.maxGroups;
      summary = await client.getAway(maxGroups: max);
    } on Object catch (err) {
      if (!_alive) return;
      _set(status: AwayStatus.idle);
      _options.onError?.call(asGiftingError(err));
      return;
    }
    if (!_alive) return;
    _acked = false;
    if (summary.totalGifts <= 0) {
      _set(status: AwayStatus.empty);
    } else {
      _set(status: AwayStatus.ready, summary: summary);
    }
  }

  /// The app came back to the foreground: [check] unless one ran less than
  /// `throttleMs` (60 s) ago.
  Future<void> foreground() {
    final last = _lastCheckAt;
    if (last != null && _now() - last < _options.throttleMs) {
      return Future<void>.value();
    }
    return check();
  }

  /// The card is on screen: plan and play the replay, schedule the dismissal.
  /// Only from ready.
  void start() {
    final summary = _state.summary;
    if (_state.status != AwayStatus.ready || summary == null) return;
    final o = _options;
    final player = o.effects?.call();
    final plan = planAwayReplay(
      summary.groups,
      maxEffects: o.maxEffects,
      budgetMs: o.budgetMs,
      thresholds: o.thresholds,
      quality: o.quality,
      resolveName: o.resolveName,
      labels: o.labels,
      reducedMotion: player == null || (o.reducedMotion?.call() ?? false),
    );
    _set(status: AwayStatus.playing, plan: plan);
    for (final item in plan.items) {
      _later(() {
        if (_alive && _state.status == AwayStatus.playing) {
          _options.effects?.call()?.play(item.event);
        }
      }, item.atMs);
    }
    _later(dismiss, awayCardDurationMs(plan));
    o.onShow?.call(summary);
    if (o.ackOn == AwayAckOn.shown) unawaited(ack());
  }

  /// Tap or timeout: the card goes. Plays not started yet are dropped; running
  /// ones finish.
  void dismiss() {
    final s = _state.status;
    if (s != AwayStatus.ready && s != AwayStatus.playing) return;
    _stopTimers();
    _set(status: AwayStatus.done);
    if (_options.ackOn != AwayAckOn.manual) unawaited(ack());
    _options.onDone?.call();
  }

  /// Marks the summary on screen as seen (`ackAway(summary.cursor)`). At most
  /// once per summary; a failure is retried once at the next [check].
  /// `AwayAckOn.manual` apps call this themselves.
  Future<void> ack() async {
    final cursor = _state.summary?.cursor;
    if (_acked || cursor == null || cursor.isEmpty) return;
    _acked = true;
    try {
      await _options.client.ackAway(cursor);
    } on Object catch (err) {
      _retryCursor = cursor;
      if (_alive) _options.onError?.call(asGiftingError(err));
    }
  }

  /// The screen is gone: timers stop, answers that arrive later change
  /// nothing.
  void dispose() {
    _alive = false;
    _stopTimers();
  }
}
