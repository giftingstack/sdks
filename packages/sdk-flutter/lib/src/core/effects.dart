/// Decides which gift effects are on screen, which wait and what the notice
/// says. No drawing, no timers: a player tells it when an effect really
/// started and when it finished, and draws what the listener reports.
/// Port of `packages/sdk-js/src/core/effects.ts` (SPEC section 6).
library;

import 'combo.dart';
import 'recipes.dart';
import 'remote_recipes.dart';
import 'spec_data.g.dart';
import 'types.dart';

/// At most this many effects of a kind on screen at once. Large ones queue.
const Map<EffectTier, int> maxConcurrentEffects = <EffectTier, int>{
  EffectTier.small: kMaxConcurrentSmall,
  EffectTier.medium: kMaxConcurrentMedium,
  EffectTier.large: kMaxConcurrentLarge,
};

/// Large gifts waiting their turn. A new one beyond this drops the oldest.
const int maxQueuedLarge = kMaxQueuedLarge;

/// Shown in the notice when an event has no sender.
const String defaultSenderName = kDefaultSenderName;

/// Notice ids remembered at once, one per (sender, gift) pair; the oldest is dropped beyond this.
const int maxNoticeKeys = 32;

/// One gift to draw.
class ScheduledEffect {
  /// Creates a scheduled effect.
  const ScheduledEffect({
    required this.id,
    required this.event,
    required this.recipe,
    required this.count,
  });

  /// The id `play` returned.
  final int id;

  /// What was played.
  final GiftEffectEvent event;

  /// The recipe fixed when the gift was played.
  final EffectRecipe recipe;

  /// Combo count for the notice, fixed when the gift was sent.
  final int count;
}

/// What the notice shows.
class NoticeData {
  /// Creates notice data.
  const NoticeData({
    required this.id,
    required this.senderName,
    required this.giftName,
    required this.image,
    required this.count,
    required this.big,
  });

  /// Changes when a different gift or sender starts a new notice.
  final int id;

  /// Who sent.
  final String senderName;

  /// What was sent.
  final String giftName;

  /// Picture of the gift, if any.
  final String? image;

  /// Gifts in a row, 1 for a single gift.
  final int count;

  /// Large-gift (golden) notice.
  final bool big;

  /// Wire-style JSON, for comparison in tests.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'senderName': senderName,
        'giftName': giftName,
        'image': image,
        'count': count,
        'big': big,
      };
}

/// The UI side of an [EffectScheduler]. Every callback is optional.
class EffectSchedulerListener {
  /// Creates a listener.
  const EffectSchedulerListener({
    this.enter,
    this.exit,
    this.end,
    this.notice,
    this.noticeHide,
    this.clear,
  });

  /// An effect enters the screen. Draw it; call `started(id)` once its picture
  /// is ready.
  final void Function(ScheduledEffect effect)? enter;

  /// An effect leaves the screen (finished or cancelled). Remove it.
  final void Function(ScheduledEffect effect)? exit;

  /// An effect played to its end. Not called for cancelled or cleared ones.
  final void Function(ScheduledEffect effect)? end;

  /// Show this notice now and call `noticeExpired()` after `durationMs`,
  /// replacing any earlier timer.
  final void Function(NoticeData notice, int durationMs)? notice;

  /// Hide the notice and drop its timer.
  final void Function()? noticeHide;

  /// Every effect is gone at once.
  final void Function()? clear;
}

/// Options read at every `play`.
class EffectSchedulerOptions {
  /// Creates options.
  const EffectSchedulerOptions({
    this.thresholds = const TierThresholds(),
    this.quality = EffectQuality.high,
    this.reducedMotion = false,
    this.recipes,
  });

  /// Price thresholds the app gave. Fields it did not give come from [recipes]
  /// or the embedded values (SPEC 13.4).
  final TierThresholds thresholds;

  /// `low` for slow phones.
  final EffectQuality quality;

  /// Only the notice shows, no effect.
  final bool reducedMotion;

  /// A remote recipe set (SPEC 13), read at each `play`. Default: the embedded
  /// one. [thresholds] and the constructor's `comboWindowMs` still win.
  final RecipeSet? recipes;
}

/// The notice as last written.
class NoticeState {
  /// Creates a notice state.
  const NoticeState({
    required this.data,
    required this.visible,
    required this.owner,
  });

  /// The last notice written (it stays after hiding).
  final NoticeData? data;

  /// Whether it is showing.
  final bool visible;

  /// The play id that wrote it, 0 before any.
  final int owner;
}

/// Decides what is on screen. See SPEC section 6.
class EffectScheduler {
  /// Creates a scheduler. [now] is in milliseconds (default: monotonic clock).
  /// [comboWindowMs] is the app's own combo window; without it the recipe
  /// set's window applies at each `play`.
  EffectScheduler({int? comboWindowMs, int Function()? now})
      : _appComboWindowMs = comboWindowMs,
        _combo = ComboTracker(comboWindowMs ?? kComboWindowMs),
        _now = now ?? monotonicNowMs;

  /// The UI side. Replace it to receive the events.
  EffectSchedulerListener listener = const EffectSchedulerListener();

  EffectSchedulerOptions _options = const EffectSchedulerOptions();
  static final RecipeSet _embedded = RecipeSet.embedded();
  final int? _appComboWindowMs;
  final ComboTracker _combo;
  final int Function() _now;
  int _nextId = 1;
  final Map<EffectTier, int> _running = <EffectTier, int>{
    EffectTier.small: 0,
    EffectTier.medium: 0,
    EffectTier.large: 0,
  };
  List<ScheduledEffect> _queue = <ScheduledEffect>[];
  final Map<int, ScheduledEffect> _onScreen = <int, ScheduledEffect>{};
  // (sender, gift) pair -> notice id, oldest first.
  final Map<String, int> _noticeIds = <String, int>{};
  String _lastNoticeKey = '';
  int _noticeId = 0;
  int _noticeOwner = 0;
  NoticeData? _noticeData;
  bool _noticeVisible = false;

  /// Replaces the options (they may change at any time).
  // ignore: use_setters_to_change_properties
  void setOptions(EffectSchedulerOptions options) => _options = options;

  /// The combo window of the last `play` (the app's own, else the set's).
  int get comboWindowMs => _combo.windowMs;

  /// Effects on screen, in the order they entered.
  List<ScheduledEffect> active() => _onScreen.values.toList();

  /// Large effects waiting their turn, oldest first.
  List<ScheduledEffect> queued() => List<ScheduledEffect>.of(_queue);

  /// The last notice written and whether it is showing.
  NoticeState notice() => NoticeState(
        data: _noticeData,
        visible: _noticeVisible,
        owner: _noticeOwner,
      );

  /// Shows a gift. Large gifts wait their turn; small and medium ones play at
  /// once, or show only the notice when too many are on screen. Returns an id
  /// for [cancel].
  int play(GiftEffectEvent event) {
    // Merge order: embedded < remote < app (SPEC 13.4). The recipe is fixed
    // here, so effects already playing or waiting keep it when a new remote
    // set arrives.
    final set = mergeRecipeSet(
      _embedded,
      _options.recipes,
      appThresholds: _options.thresholds,
      appComboWindowMs: _appComboWindowMs,
    );
    _combo.windowMs = set.comboWindowMs;
    final tier = tierFor(event.gift.price, set.thresholds);
    final recipe = set.recipes[_options.quality]![tier]!;
    final sender = event.sender ?? defaultSenderName;
    final quantity = event.quantity ?? 1;
    final id = _nextId++;
    final run = _combo.hit(sender, event.gift.id, _now());
    final count = quantity > 1 ? quantity : run;
    final item = ScheduledEffect(
      id: id,
      event: event,
      recipe: recipe,
      count: count,
    );
    // Without an effect the notice shows now; with one, when the effect starts.
    if (_options.reducedMotion) {
      _showNotice(item);
      return id;
    }
    if (tier == EffectTier.large) {
      if (_running[EffectTier.large]! >=
          maxConcurrentEffects[EffectTier.large]!) {
        if (_queue.length >= maxQueuedLarge) _queue.removeAt(0);
        _queue.add(item);
      } else {
        _start(item);
      }
    } else if (_running[tier]! < maxConcurrentEffects[tier]!) {
      _start(item);
    } else {
      _showNotice(item); // too many on screen: notice only
    }
    return id;
  }

  /// The effect's picture is ready (or the wait ran out): it really starts,
  /// with its notice.
  void started(int id) {
    final item = _onScreen[id];
    if (item != null) _showNotice(item);
  }

  /// The effect's animation ran to its end.
  void finished(int id) {
    final item = _onScreen[id];
    if (item == null) return;
    _release(item);
    listener.end?.call(item);
  }

  /// Takes back a gift shown too early, for example because its send failed.
  void cancel(int id) {
    _queue = _queue.where((i) => i.id != id).toList();
    final item = _onScreen[id];
    if (item != null) _release(item);
    if (_noticeOwner == id) _hideNotice();
  }

  /// Stops everything, forgets the queue and the combo run.
  void clear() {
    _queue = <ScheduledEffect>[];
    _onScreen.clear();
    for (final t in EffectTier.values) {
      _running[t] = 0;
    }
    listener.clear?.call();
    _hideNotice();
    _noticeIds.clear();
    _combo.reset();
  }

  /// The notice's time is up.
  void noticeExpired() {
    _noticeVisible = false;
    _noticeIds.clear();
    _lastNoticeKey = '';
    listener.noticeHide?.call();
  }

  void _start(ScheduledEffect item) {
    _running[item.recipe.tier] = _running[item.recipe.tier]! + 1;
    _onScreen[item.id] = item;
    listener.enter?.call(item);
  }

  /// Takes an effect off the screen and lets the next large one in.
  void _release(ScheduledEffect item) {
    final tier = item.recipe.tier;
    _onScreen.remove(item.id);
    final left = _running[tier]! - 1;
    _running[tier] = left < 0 ? 0 : left;
    listener.exit?.call(item);
    if (tier == EffectTier.large && _queue.isNotEmpty) {
      _start(_queue.removeAt(0));
    }
  }

  void _showNotice(ScheduledEffect item) {
    final event = item.event;
    final sender = event.sender ?? defaultSenderName;
    final key = '$sender|${event.gift.id}';
    _noticeOwner = item.id;
    // Every pair keeps its own id while it is remembered, so a combo returns to
    // its own line even when other people sent gifts in between.
    final id = _noticeIds.remove(key) ?? ++_noticeId;
    _noticeIds[key] = id;
    if (_noticeIds.length > maxNoticeKeys) {
      _noticeIds.remove(_noticeIds.keys.first);
    }
    _lastNoticeKey = key;
    final data = NoticeData(
      id: id,
      senderName: sender,
      giftName: event.gift.name,
      image: event.gift.icon ?? event.gift.image,
      count: item.count,
      big: item.recipe.noticeBig,
    );
    _noticeData = data;
    _noticeVisible = true;
    listener.notice?.call(data, item.recipe.noticeMs);
  }

  void _hideNotice() {
    _noticeVisible = false;
    _noticeIds.remove(_lastNoticeKey);
    _lastNoticeKey = '';
    listener.noticeHide?.call();
  }
}
