import 'dart:async';

import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';

import '../core/away.dart';
import '../core/client.dart';
import '../core/component_types.dart';
import '../core/error.dart';
import '../core/leaderboard.dart' show groupThousands;
import '../core/recipes.dart';
import '../core/wall.dart' show CountLabels, formatCount;
import 'effect_timeline.dart' show outCubic;
import 'gift_effect_controller.dart';
import 'gift_parts.dart';
import 'images.dart';
import 'labels.dart';
import 'theme.dart';

/// A sender as the app wants to show them.
class AwayUser {
  /// Creates a display user.
  const AwayUser({required this.name, this.avatarUrl});

  /// Display name.
  final String name;

  /// Picture, if any.
  final String? avatarUrl;
}

/// One top sender in [AwaySummaryContext.senders].
class AwaySenderInfo {
  /// Creates the info.
  const AwaySenderInfo({
    required this.user,
    required this.name,
    required this.avatarUrl,
    required this.count,
  });

  /// External id; null for an anonymous sender.
  final String? user;

  /// The display name (from `resolveUsers`), else the id.
  final String name;

  /// The picture, if any.
  final String? avatarUrl;

  /// Gifts received from this sender.
  final int count;
}

/// What [GiftAwaySummary.renderSummary] receives: the data the card would
/// show, already computed, and callbacks.
class AwaySummaryContext {
  /// Creates the context.
  const AwaySummaryContext({
    required this.summary,
    required this.title,
    required this.headline,
    required this.gifts,
    required this.people,
    required this.senders,
    required this.dismiss,
    required this.ack,
    required this.theme,
  });

  /// The summary as the server sent it.
  final AwaySummary summary;

  /// The card title, from the labels.
  final String title;

  /// `37 gifts from 12 people`, as the default card shows it.
  final String headline;

  /// `37 gifts` (`2,000+ gifts` when the count was capped).
  final String gifts;

  /// `12 people`.
  final String people;

  /// Top senders (the default card shows three), names from `resolveUsers`
  /// or the id.
  final List<AwaySenderInfo> senders;

  /// Close the card. Your own buttons call this: a tap on custom content does
  /// not dismiss.
  final VoidCallback dismiss;

  /// `ackOn: manual`: mark the summary as seen.
  final Future<void> Function() ack;

  /// The resolved theme, so your card can match the rest.
  final GiftingTheme theme;
}

/// The longest the card waits for `resolveUsers`, ms.
const int awayResolveWaitMs = 1500;

/// The summary line and the spoken line of the card.
({String line, String announce, String gifts, String people}) awayTexts(
  AwaySummary summary,
  GiftLabels labels,
) {
  final gifts =
      summary.truncated ? '2,000+' : groupThousands(summary.totalGifts);
  final giftsText = fillLabel(
    summary.totalGifts == 1 ? labels.giftOne : labels.giftOther,
    {'n': gifts},
  );
  final people = groupThousands(summary.senderCount);
  final peopleText = fillLabel(
    summary.senderCount == 1 ? labels.personOne : labels.personOther,
    {'n': people},
  );
  final line =
      fillLabel(labels.awaySummary, {'gifts': giftsText, 'people': peopleText});
  return (
    line: line,
    announce: fillLabel(labels.awayAnnounce, {'summary': line}),
    gifts: giftsText,
    people: peopleText,
  );
}

/// "While you were away: 37 gifts from 12 people". Checks once when the app
/// opens (and when it comes back to the foreground), shows a card with the top
/// senders and the gifts, replays the biggest gift groups through your
/// `GiftEffectLayer`, then goes away by itself or on a tap. Nothing new, or any
/// failure: draws nothing. Put it in a `Stack` above your screen and below the
/// effect layer; it fills the stack and only the card takes touches.
///
/// Hold a `GlobalKey<GiftAwaySummaryState>` to call `check()`, `ack()` and
/// `dismiss()`.
class GiftAwaySummary extends StatefulWidget {
  /// Creates the card.
  const GiftAwaySummary({
    required this.client,
    this.effects,
    this.resolveUsers,
    this.autoCheck = true,
    this.ackOn = AwayAckOn.shown,
    this.maxGroups,
    this.maxEffects = defaultAwayMaxEffects,
    this.budgetMs = defaultAwayBudgetMs,
    this.thresholds = const TierThresholds(),
    this.quality = EffectQuality.high,
    this.focusOnShow = false,
    this.renderSummary,
    this.onShow,
    this.onDone,
    this.onError,
    this.reducedMotion,
    this.theme = const GiftingTheme(),
    this.labels = const GiftLabels(),
    this.imageProvider = defaultGiftImageProvider,
    super.key,
  });

  /// The API client.
  final GiftingClient client;

  /// The effect layer's controller (the one you give `GiftEffectLayer`). Null:
  /// card only.
  final GiftEffectController? effects;

  /// External ids are often not display names: map them here. Waits up to
  /// 1.5 s before the card shows; ids it does not answer keep the id itself.
  final Future<Map<String, AwayUser>> Function(List<String> ids)? resolveUsers;

  /// `true` (default): check on mount and when the app returns to the
  /// foreground (once a minute).
  final bool autoCheck;

  /// When the cursor moves on: `shown` (default), `finished`, or `manual`
  /// (call `ack()` on the state).
  final AwayAckOn ackOn;

  /// Sent as `max_groups` when given (server default 5, at most 10).
  final int? maxGroups;

  /// Gift groups replayed at most. Default 5.
  final int maxEffects;

  /// The replay ends within this many ms. Default 8000.
  final int budgetMs;

  /// Tier thresholds, as the layer's.
  final TierThresholds thresholds;

  /// Effect quality, as the layer's.
  final EffectQuality quality;

  /// Ask for keyboard / screen reader focus on the card when it appears.
  /// Default false.
  final bool focusOnShow;

  /// Draw the body of the card yourself. The card still checks, names the
  /// senders, keeps its container, the spoken announcement, the slide-in, the
  /// effect replay and the acknowledgement. Return null to draw the default
  /// body. With your body a tap does not dismiss and there is no close button:
  /// call [AwaySummaryContext.dismiss].
  final Widget? Function(BuildContext context, AwaySummaryContext summary)?
      renderSummary;

  /// The card appeared.
  final void Function(AwaySummary summary)? onShow;

  /// The card went away.
  final VoidCallback? onDone;

  /// Failures never show: they arrive here and the next check tries again.
  final void Function(GiftingException error)? onError;

  /// Default (null): follows the OS "remove animations" setting (no replay,
  /// no slide-in).
  final bool? reducedMotion;

  /// Colors: `surface`, `border`, `text`, `muted`, `accent`, `accentText`,
  /// `background`.
  final GiftingTheme theme;

  /// Texts (translations).
  final GiftLabels labels;

  /// Makes the provider for a picture URL.
  final GiftImageProviderBuilder imageProvider;

  @override
  State<GiftAwaySummary> createState() => GiftAwaySummaryState();
}

/// The state of [GiftAwaySummary]: its public methods are the handle.
class GiftAwaySummaryState extends State<GiftAwaySummary>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AwayController _controller;
  late final void Function() _unsubscribe;
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  final FocusNode _focus = FocusNode(debugLabel: 'gift-away-card');
  Map<String, AwayUser> _users = const <String, AwayUser>{};
  AwaySummary? _shownFor;
  AwaySummary? _preparing;
  Timer? _resolveTimer;
  bool _slidFor = false;
  bool _startQueued = false;
  bool _alive = true;

  /// False during initState: the first state is read by the build after it.
  bool _initialised = false;

  /// Ask the server now.
  Future<void> check() => _controller.check();

  /// For `ackOn: manual`: mark the card as seen.
  Future<void> ack() => _controller.ack();

  /// Close the card.
  void dismiss() => _controller.dismiss();

  AwayControllerOptions _options() => AwayControllerOptions(
        client: widget.client,
        effects: () {
          final fx = widget.effects;
          return fx != null && fx.isAttached ? fx : null;
        },
        reducedMotion: () => _reduced,
        ackOn: widget.ackOn,
        maxGroups: widget.maxGroups,
        maxEffects: widget.maxEffects,
        budgetMs: widget.budgetMs,
        thresholds: widget.thresholds,
        quality: widget.quality,
        resolveName: (u) => _users[u]?.name ?? u,
        labels: AwaySenderLabels(someone: widget.labels.someone),
        onShow: (s) => widget.onShow?.call(s),
        onDone: () => widget.onDone?.call(),
        onError: (e) => widget.onError?.call(e),
      );

  bool get _reduced =>
      widget.reducedMotion ??
      MediaQuery.maybeDisableAnimationsOf(context) ??
      false;

  @override
  void initState() {
    super.initState();
    _controller = AwayController(_options());
    _unsubscribe = _controller.subscribe(_changed);
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoCheck) unawaited(_controller.check());
    _initialised = true;
  }

  @override
  void didUpdateWidget(GiftAwaySummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.setOptions(_options());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.autoCheck) {
      unawaited(_controller.foreground());
    }
  }

  @override
  void dispose() {
    _alive = false;
    WidgetsBinding.instance.removeObserver(this);
    _resolveTimer?.cancel();
    _unsubscribe();
    _controller.dispose();
    _slide.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_alive || !mounted || !_initialised) return;
    final summary = _controller.state.summary;
    if (summary != null && !identical(summary, _preparing)) _prepare(summary);
    setState(() {});
  }

  /// The card shows once the names are in (or 1.5 s passed), so it never
  /// redraws its senders.
  void _prepare(AwaySummary summary) {
    _preparing = summary;
    // The card starts from the hidden end of its slide (or fully in under
    // reduced motion); this runs from the controller's listener, not a build.
    _slidFor = false;
    _slide.value = _reduced ? 1 : 0;
    final ids = <String>{
      for (final t in summary.topSenders)
        if (t.user != null) t.user!,
      for (final g in summary.groups)
        for (final s in g.senders)
          if (s.user != null) s.user!,
    }.toList();
    final resolve = widget.resolveUsers;
    if (resolve == null || ids.isEmpty) {
      _shownFor = summary;
      return;
    }
    _resolveTimer?.cancel();
    _resolveTimer = Timer(const Duration(milliseconds: awayResolveWaitMs), () {
      if (_alive && identical(_preparing, summary)) {
        setState(() => _shownFor = summary);
      }
    });
    resolve(ids).then(
      (found) {
        if (!_alive || !identical(_preparing, summary)) return;
        _resolveTimer?.cancel();
        setState(() {
          _users = <String, AwayUser>{..._users, ...found};
          _shownFor = summary;
        });
      },
      onError: (Object _) {
        if (!_alive || !identical(_preparing, summary)) return;
        _resolveTimer?.cancel();
        setState(() => _shownFor = summary);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = _controller.state;
    final summary = st.summary;
    final visible = summary != null &&
        identical(_shownFor, summary) &&
        (st.status == AwayStatus.ready || st.status == AwayStatus.playing);
    if (!visible) return const SizedBox.shrink();
    // The card is on screen: start the replay and the countdown (once).
    if (st.status == AwayStatus.ready && !_startQueued) {
      _startQueued = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _startQueued = false;
        if (_alive) _controller.start();
      });
    }
    if (!_slidFor) {
      _slidFor = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_alive) return;
        if (!_reduced) unawaited(_slide.forward());
        if (widget.focusOnShow) _focus.requestFocus();
      });
    }

    final theme = widget.theme;
    final labels = widget.labels;
    final counts =
        CountLabels(thousand: labels.thousand, million: labels.million);
    String nameOf(String? u) =>
        u == null ? labels.someone : (_users[u]?.name ?? u);
    final texts = awayTexts(summary, labels);
    final senders = summary.topSenders.take(3).toList();
    final render = widget.renderSummary;
    final custom = render == null
        ? null
        : render(
            context,
            AwaySummaryContext(
              summary: summary,
              title: labels.awayTitle,
              headline: texts.line,
              gifts: texts.gifts,
              people: texts.people,
              senders: <AwaySenderInfo>[
                for (final s in summary.topSenders)
                  AwaySenderInfo(
                    user: s.user,
                    name: nameOf(s.user),
                    avatarUrl:
                        s.user == null ? null : _users[s.user!]?.avatarUrl,
                    count: s.count,
                  ),
              ],
              dismiss: dismiss,
              ack: ack,
              theme: theme,
            ),
          );

    final card = Container(
      key: const ValueKey<String>('gift-away-card'),
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.border, width: 0.5),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: custom != null
          ? Semantics(
              container: true,
              liveRegion: true,
              explicitChildNodes: true,
              label: texts.announce,
              child: KeyedSubtree(
                key: const ValueKey<String>('gift-away-custom'),
                child: custom,
              ),
            )
          : Stack(
              children: <Widget>[
                GestureDetector(
                  key: const ValueKey<String>('gift-away-body'),
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: dismiss,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 52, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Semantics(
                          container: true,
                          liveRegion: true,
                          label: texts.announce,
                          excludeSemantics: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                labels.awayTitle,
                                style: TextStyle(
                                  color: theme.text,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                texts.line,
                                key: const ValueKey<String>('gift-away-line'),
                                style: TextStyle(
                                  color: theme.muted,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (senders.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 14,
                            runSpacing: 8,
                            children: <Widget>[
                              for (final (i, s) in senders.indexed)
                                _sender(i, s, nameOf(s.user), counts),
                            ],
                          ),
                        ],
                        if (summary.groups.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              for (final g in summary.groups) _group(g, counts),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Semantics(
                    button: true,
                    label: labels.dismiss,
                    excludeSemantics: true,
                    onTap: dismiss,
                    child: GestureDetector(
                      key: const ValueKey<String>('gift-away-dismiss'),
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTap: dismiss,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Text(
                            '×',
                            style: TextStyle(
                              color: theme.muted,
                              fontSize: 26,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );

    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Focus(
            focusNode: _focus,
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: AnimatedBuilder(
                animation: _slide,
                builder: (context, child) {
                  final t = outCubic(_slide.value);
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - t)),
                      child: child,
                    ),
                  );
                },
                child: card,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sender(int i, AwayTopSender s, String name, CountLabels counts) {
    final theme = widget.theme;
    final labels = widget.labels;
    final avatar = s.user == null ? null : _users[s.user!]?.avatarUrl;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$name, ${fillLabel(
        s.count == 1 ? labels.giftOne : labels.giftOther,
        {'n': groupThousands(s.count)},
      )}',
      child: ConstrainedBox(
        key: ValueKey<String>('gift-away-sender-$i'),
        constraints: const BoxConstraints(minWidth: 56, maxWidth: 88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AvatarDisc(
              name: name,
              url: avatar,
              size: 36,
              theme: theme,
              imageProvider: widget.imageProvider,
            ),
            const SizedBox(height: 3),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              formatCount(s.count, counts),
              style: TextStyle(
                color: theme.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(AwayGroup g, CountLabels counts) {
    final theme = widget.theme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${g.gift.name}, ${groupThousands(g.count)}',
      child: Container(
        key: ValueKey<String>('gift-away-group-${g.gift.id}'),
        padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GiftPicture(
              url: g.gift.iconUrl,
              size: 28,
              theme: theme,
              imageProvider: widget.imageProvider,
            ),
            const SizedBox(width: 6),
            Text(
              formatCount(g.count, counts),
              style: TextStyle(
                color: theme.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
