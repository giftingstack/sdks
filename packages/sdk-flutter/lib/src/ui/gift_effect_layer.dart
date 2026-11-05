import 'dart:async';

import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/widgets.dart';

import '../core/effects.dart';
import '../core/recipes.dart';
import '../core/recipes_loader.dart';
import '../core/types.dart';
import 'effect_item.dart';
import 'gift_effect_controller.dart';
import 'images.dart';
import 'notice.dart';
import 'theme.dart';

export 'gift_effect_controller.dart' show GiftEffectController;

/// Put one of these over your screen, once (the last child of a `Stack`), and
/// call [GiftEffectController.play] whenever a gift is sent or received. It
/// draws the effect by the gift's price and the "ayla sent X" notice with a
/// combo counter. It never takes touches.
///
/// The queue, the caps, the combo and the notice text are decided by the pure
/// `EffectScheduler`; this widget only draws what the scheduler says.
class GiftEffectLayer extends StatefulWidget {
  /// Creates the layer.
  const GiftEffectLayer({
    required this.controller,
    this.thresholds = const TierThresholds(),
    this.quality = EffectQuality.high,
    this.reducedMotion,
    this.comboWindowMs,
    this.origin = const Offset(0.5, 0.86),
    this.pictureWaitMs = 300,
    this.noticeBottom = 150,
    this.theme = const GiftingTheme(),
    this.remoteRecipes = true,
    this.recipesVersion,
    this.recipesUrl,
    this.recipesLoader,
    this.pictureScale,
    this.onEffectEnd,
    this.imageProvider = defaultGiftImageProvider,
    this.now,
    super.key,
  });

  /// The handle apps call `play`, `cancel` and `clear` on.
  final GiftEffectController controller;

  /// From which price a gift is medium or large. Defaults: 100 and 10 000
  /// (or the remote recipes'; what you pass here wins, field by field).
  final TierThresholds thresholds;

  /// `low` for slow phones: fewer sparks, no coin rain, no rays.
  final EffectQuality quality;

  /// Default (null): follows the OS "remove animations" setting
  /// (`MediaQuery.disableAnimations`). Reduced motion shows only the notice.
  final bool? reducedMotion;

  /// Same gift from the same person within this time counts as a combo.
  /// Read once, when the layer is created. Default (null): 2500 ms, or the
  /// remote recipes' value; what you pass here wins.
  final int? comboWindowMs;

  /// Where gifts start, as fractions of the layer. Default bottom centre.
  final Offset origin;

  /// Longest wait for a gift's picture before its effect starts anyway, ms.
  final int pictureWaitMs;

  /// Distance of the notice from the bottom edge, dp.
  final double noticeBottom;

  /// Colors.
  final GiftingTheme theme;

  /// Fetch tuned effect numbers from `assets.giftingstack.com/recipes.json`
  /// (SPEC 13). The embedded numbers stay the fallback; the first effect never
  /// waits for the network. `false`: no request at all. Read once, when the
  /// layer is created.
  final bool remoteRecipes;

  /// Pins the remote document: `recipes.json` becomes `recipes.<version>.json`.
  final String? recipesVersion;

  /// Where the remote document lives. Default: the GiftingStack library host.
  final String? recipesUrl;

  /// Your own loader (storage, fetch), instead of the shared one.
  final RecipesLoader? recipesLoader;

  /// How much bigger the gift picture (and its burst) is drawn than on a
  /// phone. Default (null): automatic, 1 on a phone, up to 2 in a wide layer
  /// (a tablet), never beyond 90 % of the layer's short side. A number here
  /// replaces the automatic value.
  final double? pictureScale;

  /// Called when an effect has played to its end (not when cancelled).
  final void Function(GiftEffectEvent event, EffectTier tier)? onEffectEnd;

  /// Makes the provider for a picture URL.
  final GiftImageProviderBuilder imageProvider;

  /// The clock for combos, in ms. Default: a monotonic clock. For tests.
  final int Function()? now;

  @override
  State<GiftEffectLayer> createState() => _GiftEffectLayerState();
}

/// One line of the notice stack.
class _NoticeLine {
  _NoticeLine(this.data);

  NoticeData data;
  bool visible = true;
  Timer? expiry;

  void stopTimer() {
    expiry?.cancel();
    expiry = null;
  }
}

class _GiftEffectLayerState extends State<GiftEffectLayer>
    implements GiftEffectHost {
  late final EffectScheduler _scheduler;
  final List<ScheduledEffect> _items = <ScheduledEffect>[];
  final List<_NoticeLine> _lines = <_NoticeLine>[];
  RecipesLoader? _recipes;

  @override
  void initState() {
    super.initState();
    _scheduler = EffectScheduler(
      comboWindowMs: widget.comboWindowMs,
      now: widget.now,
    )..listener = EffectSchedulerListener(
        enter: (item) => _update(() => _items.add(item)),
        exit: (item) =>
            _update(() => _items.removeWhere((i) => i.id == item.id)),
        end: (item) => widget.onEffectEnd?.call(item.event, item.recipe.tier),
        notice: _showNotice,
        noticeHide: _hideNewestNotice,
        clear: () => _update(() {
          _items.clear();
          _clearNotices();
        }),
      );
    _recipes = startRemoteRecipes(
      RemoteRecipesOptions(
        remoteRecipes: widget.remoteRecipes,
        recipesVersion: widget.recipesVersion,
        recipesUrl: widget.recipesUrl,
        loader: widget.recipesLoader,
      ),
    );
    widget.controller.attach(this);
  }

  /// A call whose id is already shown updates that line in place and restarts
  /// its own timer; any other id is a new line at the bottom.
  void _showNotice(NoticeData data, int durationMs) {
    _update(() {
      _NoticeLine? found;
      for (final l in _lines) {
        if (l.data.id == data.id) found = l;
      }
      final _NoticeLine line;
      if (found != null && found.visible) {
        line = found;
        line.data = data;
        line.stopTimer();
      } else {
        // Not shown, or already sliding out: a fresh line at the bottom.
        if (found != null) {
          found.stopTimer();
          _lines.remove(found);
        }
        line = _NoticeLine(data);
        _lines.add(line);
        while (_lines.length > maxNoticeLines) {
          _lines.removeAt(0).stopTimer();
        }
      }
      line.expiry = Timer(
        Duration(milliseconds: durationMs),
        () => _slideOut(line),
      );
    });
  }

  /// The line's time is up (or it was taken back): it slides out and is
  /// removed when the slide ends.
  void _slideOut(_NoticeLine line) {
    line.stopTimer();
    if (!line.visible || !_lines.contains(line)) return;
    _update(() => line.visible = false);
  }

  void _removeLine(_NoticeLine line) {
    line.stopTimer();
    if (!_lines.contains(line)) return;
    _update(() => _lines.remove(line));
  }

  /// The core's notice owner was cancelled: only the newest line goes.
  void _hideNewestNotice() {
    if (_lines.isNotEmpty) _slideOut(_lines.last);
  }

  void _clearNotices() {
    for (final l in _lines) {
      l.stopTimer();
    }
    _lines.clear();
  }

  void _update(VoidCallback change) {
    if (!mounted) {
      change();
      return;
    }
    // A slide that ends while the layer is rebuilding (the line was taken back
    // during a build) changes the list after this frame.
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(change);
        } else {
          change();
        }
      });
      return;
    }
    setState(change);
  }

  @override
  void didUpdateWidget(GiftEffectLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.detach(this);
      widget.controller.attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller.detach(this);
    _clearNotices();
    super.dispose();
  }

  @override
  int playEffect(GiftEffectEvent event) {
    _syncOptions();
    return _scheduler.play(event);
  }

  @override
  void cancelEffect(int id) => _scheduler.cancel(id);

  @override
  void clearEffects() => _scheduler.clear();

  /// The options are read at each `play`: follow the latest props and the OS
  /// setting.
  void _syncOptions() {
    final reduced = widget.reducedMotion ??
        MediaQuery.maybeDisableAnimationsOf(context) ??
        false;
    _scheduler.setOptions(
      EffectSchedulerOptions(
        thresholds: widget.thresholds,
        quality: widget.quality,
        reducedMotion: reduced,
        recipes: _recipes?.current(),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncOptions();
  }

  Widget _noticeWidget(_NoticeLine line, Size size) => GiftNotice(
        key: ValueKey<String>('gift-notice-${line.data.id}'),
        data: line.data,
        visible: line.visible,
        maxWidth: size.width.isFinite ? size.width * 0.92 : 400,
        theme: widget.theme,
        imageProvider: widget.imageProvider,
        onExited: () => _removeLine(line),
      );

  @override
  Widget build(BuildContext context) {
    _syncOptions();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final ready = size.width.isFinite &&
              size.height.isFinite &&
              size.width > 0 &&
              size.height > 0;
          final origin = Offset(
            widget.origin.dx * size.width,
            widget.origin.dy * size.height,
          );
          return SizedBox.expand(
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: <Widget>[
                // Effects draw only once the layer has a size.
                if (ready)
                  for (final item in _items)
                    EffectItem(
                      key: ValueKey<int>(item.id),
                      recipe: item.recipe,
                      image: item.event.gift.image,
                      size: size,
                      origin: origin,
                      theme: widget.theme,
                      pictureWaitMs: widget.pictureWaitMs,
                      pictureScale: widget.pictureScale,
                      imageProvider: widget.imageProvider,
                      onStart: () => _scheduler.started(item.id),
                      onDone: () => _scheduler.finished(item.id),
                    ),
                // The notice stack: newest line at the bottom, 6 dp apart.
                Positioned(
                  key: const ValueKey<String>('gift-notice-stack'),
                  left: 12,
                  bottom: widget.noticeBottom,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (var i = 0; i < _lines.length; i++)
                        Padding(
                          key: ValueKey<String>(
                            'gift-notice-pad-${_lines[i].data.id}',
                          ),
                          padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                          child: _noticeWidget(_lines[i], size),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
