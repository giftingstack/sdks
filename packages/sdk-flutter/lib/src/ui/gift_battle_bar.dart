import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/battle_bar.dart';
import '../core/rooms.dart' show BattleSide, BattleView;
import 'gift_parts.dart';
import 'gift_room.dart' show GiftRoom;
import 'images.dart';
import 'theme.dart';

/// A person as the bar shows them.
class BattleBarUser {
  /// Creates a display user.
  const BattleBarUser({required this.name, this.avatarUrl});

  /// Display name.
  final String name;

  /// Picture, if any.
  final String? avatarUrl;
}

const double _avatar = 40;
const Color _gold = Color(0xFFFFC83D);
const Duration _slide = Duration(milliseconds: 800);
const Duration _count = Duration(milliseconds: 650);

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The battle bar of a versus round (SPEC 18.7): both receivers with their
/// scores, a countdown, and a split bar whose boundary slides as gifts
/// arrive. It draws `battleView` data only; your server starts and ends
/// rounds. Hidden (zero size) while the room has no round with two sides. A
/// screen reader gets one element: both scores and the result.
///
/// ```dart
/// GiftBattleBar(
///   room: room,
///   users: {'ava': BattleBarUser(name: 'Ava'), 'mateo': BattleBarUser(name: 'Mateo')},
/// )
/// ```
class GiftBattleBar extends StatefulWidget {
  /// Creates the bar. Follow a [room], or pass a [view] yourself.
  const GiftBattleBar({
    this.room,
    this.view,
    this.users = const <String, BattleBarUser>{},
    this.sideColors,
    this.reducedMotion,
    this.tickMs = 1000,
    this.theme = const GiftingTheme(),
    this.labels = const BattleBarLabels(),
    this.imageProvider = defaultGiftImageProvider,
    super.key,
  });

  /// The room you joined: the bar follows its battle by itself (scores
  /// frames and a clock tick). Ignored when [view] is given.
  final GiftRoom? room;

  /// A round to draw (null with no [room]: nothing is drawn).
  final BattleView? view;

  /// Names and pictures of the receivers by id. Fallback: the id.
  final Map<String, BattleBarUser> users;

  /// Override the side colours, one per side in order (default: the theme's
  /// accent, its coin colour, then teal and pink, then the same again). A
  /// shorter list keeps the default for the sides it does not name. Give the
  /// room the same list (`GiftRoom(sideColors:)`).
  final List<Color>? sideColors;

  /// Default (null): follows the OS "remove animations" setting. Reduced
  /// motion: no sliding, counting or pulse.
  final bool? reducedMotion;

  /// How often the clock refreshes while a round is open, ms (with [room]).
  /// 0 = never.
  final int tickMs;

  /// Colors: `background`, `border`, `text`, `muted`, `accent`, `accentText`,
  /// `coin`, `coinText`, `danger`.
  final GiftingTheme theme;

  /// Texts (translations).
  final BattleBarLabels labels;

  /// Makes the provider for a picture URL.
  final GiftImageProviderBuilder imageProvider;

  @override
  State<GiftBattleBar> createState() => _GiftBattleBarState();
}

class _GiftBattleBarState extends State<GiftBattleBar> {
  BattleView? _view;
  Timer? _timer;
  String? _round;
  List<int>? _last;
  final List<int> _pulse = <int>[0, 0];

  /// The colour of every side: the app's, else the default palette (SPEC
  /// 18.7).
  List<({Color color, Color text})> _palette(GiftingTheme theme, int count) {
    final over = widget.sideColors;
    final defaults = <({Color color, Color text})>[
      (color: theme.accent, text: theme.accentText),
      (color: theme.coin, text: theme.coinText),
      for (final c in battleExtraColors)
        (
          color: giftColor(c),
          text: battleReadableOn(c) == '#ffffff'
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF000000),
        ),
    ];
    return <({Color color, Color text})>[
      for (var i = 0; i < count; i++)
        if (over != null && i < over.length)
          (
            color: over[i],
            text: battleReadableOn(_hex(over[i])) == '#ffffff'
                ? const Color(0xFFFFFFFF)
                : const Color(0xFF000000),
          )
        else
          defaults[i % defaults.length],
    ];
  }

  @override
  void initState() {
    super.initState();
    _follow();
    _apply();
  }

  @override
  void didUpdateWidget(GiftBattleBar old) {
    super.didUpdateWidget(old);
    if (old.room != widget.room ||
        old.tickMs != widget.tickMs ||
        (old.view == null) != (widget.view == null)) {
      _unfollow(old.room);
      _follow();
    }
    _apply();
  }

  @override
  void dispose() {
    _unfollow(widget.room);
    super.dispose();
  }

  BattleView? _read() => widget.view ?? widget.room?.battleView;

  void _follow() {
    final room = widget.room;
    if (room == null || widget.view != null) return;
    room.addListener(_refresh);
    if (widget.tickMs > 0) {
      _timer = Timer.periodic(Duration(milliseconds: widget.tickMs), (_) {
        // The clock only needs a frame while a round is open.
        if (_view?.open ?? false) _refresh();
      });
    }
  }

  void _unfollow(GiftRoom? room) {
    room?.removeListener(_refresh);
    _timer?.cancel();
    _timer = null;
  }

  /// Reads the round again; which sides gained since the last frame of this
  /// round decides the pulse.
  void _refresh() {
    if (mounted) setState(_apply);
  }

  void _apply() {
    final v = _read();
    final units = <int>[
      for (final s in (v?.sides ?? const <BattleSide>[])) s.units,
    ];
    while (_pulse.length < units.length) {
      _pulse.add(0);
    }
    final same = v != null && _round == v.round ? _last : null;
    final gains = battleGains(same, units);
    for (var i = 0; i < gains.length; i++) {
      if (gains[i]) _pulse[i]++;
    }
    _round = v?.round;
    _last = v == null ? null : units;
    _view = v;
  }

  bool get _reduced =>
      widget.reducedMotion ??
      MediaQuery.maybeDisableAnimationsOf(context) ??
      false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final labels = w.labels;
    final theme = w.theme;
    final model = battleBarModel(
      _view,
      nameOf: (id) => w.users[id]?.name ?? id,
      labels: labels,
    );
    if (model == null) return const SizedBox.shrink();
    final still = _reduced;
    final colors = _palette(theme, model.sides.length);
    final multi = model.sides.length > 2;
    final clockFill = model.isFinal ? theme.accent : theme.background;
    final clockBorder = model.isFinal
        ? const Color(0x00000000)
        : (model.urgent ? theme.danger : theme.border);
    final clockText = model.isFinal
        ? theme.accentText
        : (model.urgent ? theme.danger : theme.text);

    Widget side(int i) => Expanded(
          child: _SideView(
            side: model.sides[i],
            index: i,
            right: !multi && i == 1,
            cell: multi ? (model.sides.length > 4 ? 30 : 36) : null,
            color: colors[i],
            user: w.users[model.sides[i].id],
            pulse: _pulse[i],
            still: still,
            theme: theme,
            labels: labels,
            imageProvider: w.imageProvider,
          ),
        );

    final clockColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          labels.vs,
          style: TextStyle(
            color: theme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          constraints: const BoxConstraints(minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: clockFill,
            border: Border.all(color: clockBorder),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            model.clock,
            key: const ValueKey<String>('gift-battle-clock'),
            style: TextStyle(
              color: clockText,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
      ],
    );

    final spoken = <String>[model.spoken, model.banner]
        .where((s) => s.isNotEmpty)
        .join('. ');
    return Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: spoken,
      child: Column(
        key: const ValueKey<String>('gift-battle-bar'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (multi) ...<Widget>[
            // Three or more sides (SPEC 18.7): the clock, a row of cells, a
            // bar of proportional segments.
            Center(child: clockColumn),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (var i = 0; i < model.sides.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 6),
                  side(i),
                ],
              ],
            ),
            const SizedBox(height: 10),
            _MultiBar(
              pcts: model.pcts,
              colors: <Color>[for (final c in colors) c.color],
              border: theme.border,
              still: still,
            ),
          ] else ...<Widget>[
            Row(
              children: <Widget>[
                side(0),
                const SizedBox(width: 8),
                clockColumn,
                const SizedBox(width: 8),
                side(1),
              ],
            ),
            const SizedBox(height: 10),
            _SplitBar(
              pct: model.pct,
              colorA: colors[0].color,
              colorB: colors[1].color,
              border: theme.border,
              glow: theme.accent,
              sparkOpacity: model.isFinal ? 0.5 : 1,
              still: still,
            ),
          ],
          if (model.banner.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              model.banner,
              key: const ValueKey<String>('gift-battle-banner'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.text,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The 16 px bar of three or more sides: one segment per side, side `i` in
/// `colors[i]` with the width `pcts[i]` percent, 2 px white lines between
/// them. Every width slides (800 ms, ease out cubic) unless [still].
class _MultiBar extends StatelessWidget {
  const _MultiBar({
    required this.pcts,
    required this.colors,
    required this.border,
    required this.still,
  });

  final List<double> pcts;
  final List<Color> colors;
  final Color border;
  final bool still;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey<String>('gift-battle-track'),
        height: 16,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: LayoutBuilder(
            // The segments animate from their old widths: after a resize or a
            // turn of the phone they may be wider than the bar for a moment,
            // so the row is clipped, never an overflow error.
            builder: (context, box) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: <Widget>[
                  for (var i = 0; i < pcts.length; i++)
                    AnimatedContainer(
                      key: ValueKey<String>('gift-battle-segment-$i'),
                      width: box.maxWidth * pcts[i] / 100,
                      duration: still ? Duration.zero : _slide,
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: colors[i],
                        border: i == 0
                            ? null
                            : const Border(
                                left: BorderSide(
                                  color: Color(0xFFFFFFFF),
                                  width: 2,
                                ),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// The 16 px bar: side B colour as the base, side A from the left up to
/// [pct], and the spark on the boundary. The boundary slides (800 ms, ease
/// out cubic) unless [still].
class _SplitBar extends StatelessWidget {
  const _SplitBar({
    required this.pct,
    required this.colorA,
    required this.colorB,
    required this.border,
    required this.glow,
    required this.sparkOpacity,
    required this.still,
  });

  final double pct;
  final Color colorA;
  final Color colorB;
  final Color border;
  final Color glow;
  final double sparkOpacity;
  final bool still;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: pct),
        duration: still ? Duration.zero : _slide,
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => SizedBox(
          key: const ValueKey<String>('gift-battle-track'),
          height: 16,
          child: LayoutBuilder(
            builder: (context, box) {
              final x = box.maxWidth * v / 100;
              return Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorB,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: border),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: x,
                    child: DecoratedBox(
                      key: const ValueKey<String>('gift-battle-fill'),
                      decoration: BoxDecoration(
                        color: colorA,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(7),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: x - 2,
                    top: -5,
                    width: 4,
                    height: 26,
                    child: Opacity(
                      opacity: sparkOpacity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFFFF),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: glow.withValues(alpha: 0.9),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
}

/// One receiver: avatar in a ring (gold with a crown for the winner), name
/// over a score that counts up, the loser at half opacity, a short pulse
/// when [pulse] changes.
class _SideView extends StatefulWidget {
  const _SideView({
    required this.side,
    required this.index,
    required this.right,
    required this.color,
    this.cell,
    required this.user,
    required this.pulse,
    required this.still,
    required this.theme,
    required this.labels,
    required this.imageProvider,
  });

  final BattleBarSide side;
  final int index;
  final bool right;

  /// Three or more sides: the avatar's size; the side is a centred cell
  /// (avatar over name over score). Null: the versus layout.
  final double? cell;
  final ({Color color, Color text}) color;
  final BattleBarUser? user;
  final int pulse;
  final bool still;
  final GiftingTheme theme;
  final BattleBarLabels labels;
  final GiftImageProviderBuilder imageProvider;

  @override
  State<_SideView> createState() => _SideViewState();
}

class _SideViewState extends State<_SideView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  static final Animatable<double> _scale = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 1.07),
        weight: 200,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.07, end: 1),
        weight: 300,
      ),
    ],
  );

  @override
  void didUpdateWidget(_SideView old) {
    super.didUpdateWidget(old);
    if (widget.pulse != old.pulse && !widget.still) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final side = w.side;
    final theme = w.theme;
    final url = w.user?.avatarUrl;
    final ring = side.won ? _gold : w.color.color;
    final cell = w.cell;
    final size = cell ?? _avatar;
    final disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: w.color.color, shape: BoxShape.circle),
      child: Text(
        initialOf(side.name),
        style: TextStyle(
          color: w.color.text,
          fontSize: cell == null ? 18 : size * 0.45,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final picture = (url == null || url.isEmpty)
        ? disc
        : ClipOval(
            child: Container(
              width: size,
              height: size,
              color: theme.border,
              child: Image(
                image: w.imageProvider(url),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => disc,
              ),
            ),
          );
    final avatar = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 2),
          ),
          child: picture,
        ),
        if (side.won)
          Positioned(
            top: -14,
            left: cell != null ? 0 : (w.right ? null : 2),
            right: cell != null ? 0 : (w.right ? 2 : null),
            child: const Text(
              '♛',
              textAlign: TextAlign.center,
              style: TextStyle(color: _gold, fontSize: 18, height: 1),
            ),
          ),
      ],
    );
    final crowded = cell != null && cell < 36;
    final who = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: cell != null
          ? CrossAxisAlignment.center
          : (w.right ? CrossAxisAlignment.end : CrossAxisAlignment.start),
      children: <Widget>[
        Text(
          side.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.text,
            fontSize: cell == null ? 13 : (crowded ? 11 : 12),
            fontWeight: FontWeight.w700,
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: side.units.toDouble()),
          duration: w.still ? Duration.zero : _count,
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Text(
            formatBattleScore(v.round(), w.labels),
            key: ValueKey<String>('gift-battle-score-${w.index}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.text,
              fontSize: cell == null ? 20 : (crowded ? 14 : 17),
              fontWeight: FontWeight.w800,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
      ],
    );
    final row = cell != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              avatar,
              const SizedBox(height: 4),
              who,
            ],
          )
        : Row(
            textDirection: w.right ? TextDirection.rtl : TextDirection.ltr,
            children: <Widget>[
              avatar,
              const SizedBox(width: 8),
              Flexible(child: who),
            ],
          );
    return Opacity(
      opacity: side.lost ? 0.5 : 1,
      child: ScaleTransition(scale: _c.drive(_scale), child: row),
    );
  }
}
