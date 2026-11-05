import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/client.dart';
import '../core/component_types.dart';
import '../core/error.dart';
import '../core/leaderboard.dart';
import '../core/wall.dart' show CountLabels, formatCount;
import 'gift_parts.dart';
import 'images.dart';
import 'labels.dart';
import 'theme.dart';

/// A person as the app wants to show them.
class LeaderboardUser {
  /// Creates a display user.
  const LeaderboardUser({required this.name, this.avatarUrl});

  /// Display name.
  final String name;

  /// Picture, if any.
  final String? avatarUrl;
}

/// What [GiftLeaderboard.renderRow] receives for one ranked row.
class LeaderboardRowContext {
  /// Creates the context.
  const LeaderboardRowContext({
    required this.entry,
    required this.rank,
    required this.name,
    required this.avatarUrl,
    required this.metric,
    required this.score,
    required this.scoreText,
    required this.isMe,
    required this.theme,
  });

  /// The row as the server sent it.
  final LeaderboardEntry entry;

  /// Competition rank (equal scores share a rank).
  final int rank;

  /// The display name (from `resolveUsers`), else the id.
  final String name;

  /// The picture, if any.
  final String? avatarUrl;

  /// The metric shown.
  final LeaderboardMetric metric;

  /// The score for the shown metric: coins ([LeaderboardMetric.units]) or gifts.
  final int score;

  /// The score as the default row shows it (`54K`).
  final String scoreText;

  /// Whether this is the highlighted (signed-in) person.
  final bool isMe;

  /// The resolved theme, so your row can match the rest.
  final GiftingTheme theme;
}

/// Height of a row, dp.
const double kLeaderboardRowHeight = 52;

String _capitalise(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Top senders or top receivers: tabs for today, this week, this month and all
/// time, an optional coins / gifts switch, up to 100 rows with medals for the
/// first three, and the viewer's own position pinned underneath when they are
/// not in the rows (SPEC 16.4).
///
/// Hold a `GlobalKey<GiftLeaderboardState>` to call `refresh()` (pull to
/// refresh).
class GiftLeaderboard extends StatefulWidget {
  /// Creates a leaderboard.
  const GiftLeaderboard({
    required this.client,
    this.board = LeaderboardBoard.senders,
    this.periods = leaderboardPeriods,
    this.initialPeriod = LeaderboardPeriod.week,
    this.metric,
    this.metricToggle = false,
    this.limit = defaultLeaderboardLimit,
    this.resolveUsers,
    this.highlightUser,
    this.refreshIntervalMs = 0,
    this.renderRow,
    this.onPressUser,
    this.onError,
    this.reducedMotion,
    this.theme = const GiftingTheme(),
    this.labels = const GiftLabels(),
    this.coinName = 'coins',
    this.imageProvider = defaultGiftImageProvider,
    this.now,
    super.key,
  });

  /// The API client.
  final GiftingClient client;

  /// Senders (default) or receivers.
  final LeaderboardBoard board;

  /// Tabs, in this order. One item: no tabs.
  final List<LeaderboardPeriod> periods;

  /// Default week (or the first of [periods]).
  final LeaderboardPeriod initialPeriod;

  /// Units (default for senders) or gifts (default for receivers).
  final LeaderboardMetric? metric;

  /// Show a switch between coins and gifts. Default false.
  final bool metricToggle;

  /// Rows, 1 to 100. Default 10.
  final int limit;

  /// External ids are often not display names: map them here. Unknown ids keep
  /// the id.
  final Future<Map<String, LeaderboardUser>> Function(List<String> ids)?
      resolveUsers;

  /// Whose row is highlighted. Default: the signed-in user.
  final String? highlightUser;

  /// 0 (default): no polling. Otherwise the current tab is fetched again this
  /// often (ms, at least 5,000: a smaller number is 5,000).
  final int refreshIntervalMs;

  /// Draw the inside of each ranked row yourself. The board still loads,
  /// orders, names, highlights and pins; it keeps the row container, its
  /// spoken label and the press. Return null to draw the default rank, avatar,
  /// name and score. The pinned "You: #417" row stays the default.
  final Widget? Function(BuildContext context, LeaderboardRowContext row)?
      renderRow;

  /// Makes the rows buttons. Open a profile here.
  final void Function(String user)? onPressUser;

  /// Called for every failure (the board shows its own message).
  final void Function(GiftingException error)? onError;

  /// Default (null): follows the OS "remove animations" setting (no pulse, no
  /// spinner).
  final bool? reducedMotion;

  /// Colors: `surface`, `border`, `text`, `muted`, `accent`, `accentText`,
  /// `selected`, `coin`, `danger`, `noticeBigText` (on the medals).
  final GiftingTheme theme;

  /// Texts (translations).
  final GiftLabels labels;

  /// Name of your currency, used in labels and for screen readers.
  final String coinName;

  /// Makes the provider for a picture URL.
  final GiftImageProviderBuilder imageProvider;

  /// The clock in ms for the 30 s staleness check. Default: wall clock.
  final int Function()? now;

  @override
  State<GiftLeaderboard> createState() => GiftLeaderboardState();
}

/// The state of [GiftLeaderboard]: its public methods are the handle.
class GiftLeaderboardState extends State<GiftLeaderboard> {
  late LeaderboardController _controller;
  late void Function() _unsubscribe;
  Timer? _poll;
  Map<String, LeaderboardUser> _users = const <String, LeaderboardUser>{};
  final Set<String> _asked = <String>{};
  final Map<LeaderboardPeriod, FocusNode> _tabFocus =
      <LeaderboardPeriod, FocusNode>{};
  bool _alive = true;

  /// Fetch the shown tab again (pull to refresh).
  void refresh() => _controller.refresh();

  /// The pure controller underneath, for apps that need more.
  LeaderboardController get controller => _controller;

  LeaderboardControllerOptions _options() => LeaderboardControllerOptions(
        client: widget.client,
        board: widget.board,
        periods: widget.periods,
        initialPeriod: widget.initialPeriod,
        metric: widget.metric,
        limit: widget.limit,
        now: widget.now,
        onError: (e) => widget.onError?.call(e),
      );

  /// What decides a new controller (its tab state and cache).
  String _identity(GiftLeaderboard w) => <Object?>[
        identityHashCode(w.client),
        w.board.name,
        w.limit,
        w.initialPeriod.name,
        w.metric?.name,
        w.periods.map((p) => p.name).join(','),
      ].join('|');

  void _create() {
    _controller = LeaderboardController(_options())..start();
    // Subscribed after start: the first state is read by the build that follows
    // (no setState during initState).
    _unsubscribe = _controller.subscribe(_changed);
    _restartPoll();
  }

  void _destroy() {
    _poll?.cancel();
    _unsubscribe();
    _controller.dispose();
  }

  void _restartPoll() {
    _poll?.cancel();
    _poll = null;
    final every = leaderboardPollMs(widget.refreshIntervalMs);
    if (every > 0) {
      _poll = Timer.periodic(Duration(milliseconds: every), (_) {
        _controller.refresh();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void didUpdateWidget(GiftLeaderboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_identity(oldWidget) != _identity(widget)) {
      _destroy();
      _create();
    } else {
      _controller.setOptions(_options());
      if (oldWidget.refreshIntervalMs != widget.refreshIntervalMs) {
        _restartPoll();
      }
    }
  }

  @override
  void dispose() {
    _alive = false;
    _destroy();
    for (final n in _tabFocus.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!_alive || !mounted) return;
    setState(() {});
    _resolveNames();
  }

  void _resolveNames() {
    final resolve = widget.resolveUsers;
    if (resolve == null) return;
    final st = _controller.state;
    final ids = <String>{
      ...?st.data?.data.map((r) => r.user),
      if (st.pinned != null) st.pinned!.user,
    };
    final fresh = ids.where((id) => !_asked.contains(id)).toList();
    if (fresh.isEmpty) return;
    _asked.addAll(fresh);
    resolve(fresh).then(
      (found) {
        if (_alive && mounted) {
          setState(
              () => _users = <String, LeaderboardUser>{..._users, ...found});
        }
      },
      onError: (Object _) => _asked.removeAll(fresh),
    );
  }

  bool get _reduced =>
      widget.reducedMotion ??
      MediaQuery.maybeDisableAnimationsOf(context) ??
      false;

  FocusNode _focusFor(LeaderboardPeriod p) => _tabFocus.putIfAbsent(
        p,
        () => FocusNode(debugLabel: 'gift-lb-tab-${p.name}'),
      );

  void _selectPeriod(LeaderboardPeriod p, {bool focus = false}) {
    _controller.setPeriod(p);
    if (focus) _focusFor(p).requestFocus();
  }

  KeyEventResult _tabKey(LeaderboardPeriod p, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final periods = _controller.state.periods;
    final i = periods.indexOf(p);
    final LeaderboardPeriod? next;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      next = periods[(i + 1) % periods.length];
    } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      next = periods[(i - 1 + periods.length) % periods.length];
    } else if (e.logicalKey == LogicalKeyboardKey.home) {
      next = periods.first;
    } else if (e.logicalKey == LogicalKeyboardKey.end) {
      next = periods.last;
    } else {
      next = null;
    }
    if (next == null) return KeyEventResult.ignored;
    _selectPeriod(next, focus: true);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final st = _controller.state;
    final theme = w.theme;
    final labels = w.labels;
    final reduced = _reduced;
    final counts =
        CountLabels(thousand: labels.thousand, million: labels.million);
    final metric = st.metric;
    final unitsName = labels.metricUnits.isNotEmpty
        ? labels.metricUnits
        : _capitalise(w.coinName);
    final data = st.data;
    final highlight = w.highlightUser ?? data?.me?.user;
    String nameOf(String id) => _users[id]?.name ?? id;

    String score(int gifts, int units, {required bool spoken}) =>
        metric == LeaderboardMetric.units
            ? (spoken
                ? '${groupThousands(units)} ${w.coinName}'
                : formatCount(units, counts))
            : (spoken
                ? '${groupThousands(gifts)} ${labels.giftsWord}'
                : groupThousands(gifts));

    Widget scoreView(int gifts, int units) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              score(gifts, units, spoken: false),
              style: TextStyle(
                color: theme.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                fontFeatures: tabularFigures,
              ),
            ),
            const SizedBox(width: 5),
            if (metric == LeaderboardMetric.units)
              CoinDot(color: theme.coin, size: 11)
            else
              Text(
                labels.giftsWord,
                style: TextStyle(
                  color: theme.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        );

    Widget rowShell({
      required Key key,
      required String label,
      required String user,
      required Color? background,
      required List<Widget> children,
      Border? border,
      Widget? custom,
    }) {
      final press = w.onPressUser;
      final body = Container(
        height: custom != null ? null : kLeaderboardRowHeight,
        constraints: custom != null
            ? const BoxConstraints(minHeight: kLeaderboardRowHeight)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: border,
        ),
        child: custom != null
            ? Align(alignment: AlignmentDirectional.centerStart, child: custom)
            : Row(children: children),
      );
      return Semantics(
        key: key,
        container: true,
        excludeSemantics: true,
        label: label,
        button: press != null,
        onTap: press == null ? null : () => press(user),
        child: press == null
            ? body
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () => press(user),
                child: body,
              ),
      );
    }

    Widget row(LeaderboardEntry e) {
      final medal = e.rank >= 1 && e.rank <= 3
          ? giftColor(leaderboardRankColors['rank${e.rank}']!)
          : null;
      final name = nameOf(e.user);
      final render = w.renderRow;
      final custom = render == null
          ? null
          : render(
              context,
              LeaderboardRowContext(
                entry: e,
                rank: e.rank,
                name: name,
                avatarUrl: _users[e.user]?.avatarUrl,
                metric: metric,
                score: metric == LeaderboardMetric.units ? e.units : e.gifts,
                scoreText: score(e.gifts, e.units, spoken: false),
                isMe: e.user == highlight,
                theme: theme,
              ),
            );
      return rowShell(
        key: ValueKey<String>('gift-lb-row-${e.user}'),
        custom: custom,
        label: fillLabel(labels.rowSpoken, {
          'rank': e.rank,
          'name': name,
          'score': score(e.gifts, e.units, spoken: true),
        }),
        user: e.user,
        background: e.user == highlight ? theme.selected : null,
        children: <Widget>[
          Container(
            key: medal == null
                ? null
                : ValueKey<String>('gift-lb-medal-${e.rank}'),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: medal, shape: BoxShape.circle),
            child: Text(
              groupThousands(e.rank),
              style: TextStyle(
                color: medal != null ? theme.noticeBigText : theme.muted,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
          const SizedBox(width: 10),
          AvatarDisc(
            name: name,
            url: _users[e.user]?.avatarUrl,
            size: 32,
            theme: theme,
            imageProvider: w.imageProvider,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          scoreView(e.gifts, e.units),
        ],
      );
    }

    Widget pinnedRow(LeaderboardMe m) {
      final rankText =
          leaderboardRankLabel(m.rank, overflow: labels.rankOverflow);
      final name = nameOf(m.user);
      return rowShell(
        key: const ValueKey<String>('gift-lb-pinned'),
        label: fillLabel(labels.pinnedSpoken, {
          'rank':
              m.rank == null ? labels.rankOverflow : groupThousands(m.rank!),
          'score': score(m.gifts, m.units, spoken: true),
        }),
        user: m.user,
        background: theme.selected,
        border: Border(top: BorderSide(color: theme.border, width: 0.5)),
        children: <Widget>[
          AvatarDisc(
            name: name,
            url: _users[m.user]?.avatarUrl,
            size: 32,
            theme: theme,
            imageProvider: w.imageProvider,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fillLabel(labels.pinned, {'rank': rankText}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          scoreView(m.gifts, m.units),
        ],
      );
    }

    Widget pill({
      required Key key,
      required String label,
      required bool selected,
      required VoidCallback onTap,
      LeaderboardPeriod? tabOf,
      bool radio = false,
    }) {
      Widget inner = Semantics(
        container: true,
        excludeSemantics: true,
        button: !radio,
        selected: radio ? null : selected,
        checked: radio ? selected : null,
        inMutuallyExclusiveGroup: true,
        label: label,
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onTap,
          // The pill is 32 dp high inside a 44 dp touch target.
          child: SizedBox(
            height: 44,
            // widthFactor: shrink to the label (a Container with an
            // alignment, or a Center without it, would fill a Wrap's width).
            child: Center(
              widthFactor: 1,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? (radio ? theme.selected : theme.accent)
                      : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? (radio ? theme.text : theme.accentText)
                          : theme.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (tabOf != null) {
        inner = Focus(
          focusNode: _focusFor(tabOf),
          // Only the selected tab is in the Tab order; arrows move between them.
          skipTraversal: !selected,
          onKeyEvent: (node, e) => _tabKey(tabOf, e),
          child: inner,
        );
      }
      return KeyedSubtree(key: key, child: inner);
    }

    final Widget body;
    if (st.status == LeaderboardStatus.loading) {
      body = Semantics(
        container: true,
        excludeSemantics: true,
        label: labels.loading,
        child: Pulse(
          still: reduced,
          child: Column(
            key: const ValueKey<String>('gift-lb-skeleton'),
            children: <Widget>[
              for (var i = 0; i < w.limit; i++)
                Container(
                  key: ValueKey<String>('gift-lb-skeleton-row-$i'),
                  height: kLeaderboardRowHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: theme.border,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: theme.border,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 90.0 + ((i * 37) % 60),
                        height: 12,
                        decoration: BoxDecoration(
                          color: theme.border,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    } else if (st.status == LeaderboardStatus.error) {
      body = Padding(
        key: const ValueKey<String>('gift-lb-error'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Column(
          children: <Widget>[
            Semantics(
              liveRegion: true,
              child: Text(
                labels.error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.danger,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              button: true,
              excludeSemantics: true,
              label: labels.tryAgain,
              onTap: refresh,
              child: GestureDetector(
                key: const ValueKey<String>('gift-lb-retry'),
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: refresh,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: theme.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      labels.tryAgain,
                      style: TextStyle(
                        color: theme.accentText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else if (st.status == LeaderboardStatus.empty || data == null) {
      body = Padding(
        key: const ValueKey<String>('gift-lb-empty'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Center(
          child: Text(
            labels.emptyFor(st.period),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.muted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } else {
      body = Column(
        key: const ValueKey<String>('gift-lb-list'),
        children: data.data.map(row).toList(),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              children: <Widget>[
                if (st.periods.length > 1)
                  Expanded(
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: Wrap(
                        key: const ValueKey<String>('gift-lb-tabs'),
                        spacing: 4,
                        children: <Widget>[
                          for (final p in st.periods)
                            pill(
                              key: ValueKey<String>('gift-lb-tab-${p.name}'),
                              label: labels.tab(p),
                              selected: st.period == p,
                              onTap: () => _selectPeriod(p),
                              tabOf: p,
                            ),
                        ],
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (st.refreshing && !reduced)
                  Semantics(
                    label: labels.updating,
                    child: Spinner(
                      key: const ValueKey<String>('gift-lb-spinner'),
                      color: theme.muted,
                    ),
                  ),
              ],
            ),
          ),
          if (w.metricToggle) ...<Widget>[
            const SizedBox(height: 8),
            Semantics(
              container: true,
              explicitChildNodes: true,
              label: labels.metricSwitch,
              child: Row(
                key: const ValueKey<String>('gift-lb-metric'),
                children: <Widget>[
                  pill(
                    key: const ValueKey<String>('gift-lb-metric-units'),
                    label: unitsName,
                    selected: metric == LeaderboardMetric.units,
                    onTap: () => _controller.setMetric(LeaderboardMetric.units),
                    radio: true,
                  ),
                  const SizedBox(width: 4),
                  pill(
                    key: const ValueKey<String>('gift-lb-metric-gifts'),
                    label: labels.metricGifts,
                    selected: metric == LeaderboardMetric.gifts,
                    onTap: () => _controller.setMetric(LeaderboardMetric.gifts),
                    radio: true,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          body,
          if (st.pinned != null &&
              st.status != LeaderboardStatus.loading) ...<Widget>[
            const SizedBox(height: 8),
            pinnedRow(st.pinned!),
          ],
        ],
      ),
    );
  }
}
