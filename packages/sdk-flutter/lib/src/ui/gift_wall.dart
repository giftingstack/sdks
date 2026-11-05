import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/client.dart';
import '../core/error.dart';
import '../core/leaderboard.dart' show groupThousands;
import '../core/tray.dart' show asGiftingError;
import '../core/types.dart';
import '../core/wall.dart';
import 'gift_parts.dart';
import 'images.dart';
import 'labels.dart';
import 'theme.dart';

/// Size of a [GiftWall]: `sm` icon 16, text 11, chip height 20; `md` icon 20,
/// text 12.5, chip height 24.
enum GiftWallSize {
  /// Icon 16, text 11, chip height 20.
  sm,

  /// Icon 20, text 12.5, chip height 24.
  md,
}

/// What [GiftWall.renderChip] receives for one gift chip.
class WallChipContext {
  /// Creates the context.
  const WallChipContext({
    required this.gift,
    required this.count,
    required this.countText,
    required this.theme,
  });

  /// The gift.
  final GiftRef gift;

  /// The exact count.
  final int count;

  /// The count as the default chip shows it (`1.2K`).
  final String countText;

  /// The resolved theme, so your chip can match the rest.
  final GiftingTheme theme;
}

final Expando<GiftWallLoader> _loaders = Expando<GiftWallLoader>('wall');

/// One [GiftWallLoader] per client: every wall of a screen shares it, so a
/// feed makes few requests (walls asked within 50 ms go out as one call,
/// answers are kept for 60 s).
GiftWallLoader giftWallLoaderFor(GiftingClient client) =>
    _loaders[client] ??= GiftWallLoader(query: client.queryGiftWalls);

/// The minimum touch target when chips can be tapped, dp.
const double kWallTouchTarget = 44;

/// The gifts a post or a profile received, as a row of small chips: icon and
/// count (SPEC 14.5). Read-only unless you pass [onPressChip]. Nothing to show
/// (no gifts, or the request failed) draws nothing. Walls on one screen share
/// their requests.
///
/// When [onPressChip] is set, each chip sits in a cell 44 dp high (the touch
/// target), so the row is taller than the 24 dp chips.
class GiftWall extends StatefulWidget {
  /// Creates a wall.
  const GiftWall({
    required this.client,
    required this.user,
    this.reference,
    this.max = defaultWallMax,
    this.order = WallOrder.count,
    this.size = GiftWallSize.md,
    this.data,
    this.refreshKey,
    this.renderChip,
    this.onPressChip,
    this.onError,
    this.reducedMotion,
    this.theme = const GiftingTheme(),
    this.labels = const GiftLabels(),
    this.imageProvider = defaultGiftImageProvider,
    this.loader,
    super.key,
  });

  /// The API client.
  final GiftingClient client;

  /// The receiver's external id.
  final String user;

  /// Your content id, for example the post. Null: the profile wall.
  final String? reference;

  /// Chips shown, the `+37` overflow chip included. Default 6.
  final int max;

  /// `count` (default): most received first. `catalog`: the catalog's order.
  final WallOrder order;

  /// `sm` or `md` (default).
  final GiftWallSize size;

  /// Counters you already have: no request is made.
  final List<ReceivedGift>? data;

  /// Change it to fetch again, for example after the person sent a gift.
  final Object? refreshKey;

  /// Draw the inside of each gift chip yourself. The wall still loads, orders
  /// and caps the chips and keeps the chip container, its spoken label and the
  /// press. Return null to draw the default icon and count. The `+37`
  /// overflow chip is not passed here. Not called while loading.
  final Widget? Function(BuildContext context, WallChipContext chip)?
      renderChip;

  /// Makes the chips buttons. Open your gift tray here.
  final void Function(GiftRef gift)? onPressChip;

  /// Failures only arrive here: a wall never shows an error.
  final void Function(GiftingException error)? onError;

  /// Default (null): follows the OS "remove animations" setting. Reduced
  /// motion: no fade-in, a static skeleton.
  final bool? reducedMotion;

  /// Colors: `surface`, `border`, `text`, `muted`.
  final GiftingTheme theme;

  /// Texts (translations).
  final GiftLabels labels;

  /// Makes the provider for a picture URL.
  final GiftImageProviderBuilder imageProvider;

  /// Your own loader (for tests or a custom cache). Default: the shared one of
  /// [client] ([giftWallLoaderFor]).
  final GiftWallLoader? loader;

  @override
  State<GiftWall> createState() => _GiftWallState();
}

enum _Status { loading, ready, error }

class _GiftWallState extends State<GiftWall>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    value: 1,
  );
  _Status _status = _Status.loading;
  List<ReceivedGift> _gifts = const <ReceivedGift>[];
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _load(fresh: false);
  }

  @override
  void didUpdateWidget(GiftWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fresh = oldWidget.refreshKey != widget.refreshKey;
    if (fresh ||
        !identical(oldWidget.client, widget.client) ||
        !identical(oldWidget.loader, widget.loader) ||
        oldWidget.user != widget.user ||
        oldWidget.reference != widget.reference ||
        (oldWidget.data == null) != (widget.data == null)) {
      _load(fresh: fresh);
    }
  }

  @override
  void dispose() {
    _token++;
    _fade.dispose();
    super.dispose();
  }

  bool get _reduced =>
      widget.reducedMotion ??
      MediaQuery.maybeDisableAnimationsOf(context) ??
      false;

  void _load({required bool fresh}) {
    final token = ++_token;
    if (widget.data != null) return;
    final loader = widget.loader ?? giftWallLoaderFor(widget.client);
    final user = widget.user;
    final reference = widget.reference;
    if (fresh) loader.invalidate(user, reference);
    final cached = fresh ? null : loader.peek(user, reference);
    if (cached != null) {
      _status = _Status.ready;
      _gifts = cached;
      return;
    }
    _status = _Status.loading;
    _gifts = const <ReceivedGift>[];
    loader.load(user, reference).then(
      (gifts) {
        if (!mounted || token != _token) return;
        final reduced = _reduced;
        setState(() {
          _status = _Status.ready;
          _gifts = gifts;
        });
        if (reduced) {
          _fade.value = 1;
        } else {
          _fade.value = 0;
          unawaited(_fade.forward());
        }
      },
      onError: (Object err) {
        if (!mounted || token != _token) return;
        setState(() => _status = _Status.error);
        widget.onError?.call(asGiftingError(err));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final data = w.data;
    final status = data != null ? _Status.ready : _status;
    if (status == _Status.error) return const SizedBox.shrink();
    final dim = w.size == GiftWallSize.sm
        ? const _Dim(icon: 16, text: 11, height: 20)
        : const _Dim(icon: 20, text: 12.5, height: 24);
    final theme = w.theme;
    final reduced = _reduced;

    if (status == _Status.loading) {
      return ExcludeSemantics(
        child: Wrap(
          key: const ValueKey<String>('gift-wall-skeleton'),
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (var i = 0; i < 3; i++)
              Pulse(
                still: reduced,
                child: Container(
                  key: ValueKey<String>('gift-wall-skeleton-chip-$i'),
                  width: 40.0 + i * 8,
                  height: dim.height,
                  decoration: BoxDecoration(
                    color: theme.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final chips = wallChips(data ?? _gifts, max: w.max, order: w.order);
    if (chips.isEmpty) {
      return w.labels.emptyText.isEmpty
          ? const SizedBox.shrink()
          : Text(
              w.labels.emptyText,
              key: const ValueKey<String>('gift-wall-empty'),
              style: TextStyle(
                color: theme.muted,
                fontSize: dim.text,
                fontWeight: FontWeight.w600,
              ),
            );
    }

    final labels = w.labels;
    final counts =
        CountLabels(thousand: labels.thousand, million: labels.million);
    final tappable = w.onPressChip != null;

    final list = <String>[];
    WallOverflowChip? overflow;
    for (final c in chips) {
      switch (c) {
        case WallGiftChip():
          final name =
              c.count > 1 ? '${c.gift.name}${labels.plural}' : c.gift.name;
          list.add('${groupThousands(c.count)} $name');
        case WallOverflowChip():
          overflow = c;
      }
    }
    if (overflow != null) {
      list.add(
          fillLabel(labels.wallMore, {'n': groupThousands(overflow.count)}));
    }
    final summary = fillLabel(labels.wallSummary, {'list': list.join(', ')});

    Widget chip(WallChip c) {
      final render = w.renderChip;
      final custom = c is WallGiftChip && render != null
          ? render(
              context,
              WallChipContext(
                gift: c.gift,
                count: c.count,
                countText: formatCount(c.count, counts),
                theme: theme,
              ),
            )
          : null;
      final isGift = c is WallGiftChip;
      final text = switch (c) {
        WallGiftChip() => formatCount(c.count, counts),
        WallOverflowChip() => '+${formatCount(c.count, counts)}',
      };
      final body = Container(
        // A custom chip may be taller than the default 24 dp pill.
        height: custom != null ? null : dim.height,
        constraints:
            custom != null ? BoxConstraints(minHeight: dim.height) : null,
        padding: EdgeInsets.only(left: isGift ? 4 : 8, right: 8),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.border, width: 0.5),
        ),
        child: custom != null
            ? Center(widthFactor: 1, child: custom)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (c is WallGiftChip) ...<Widget>[
                    GiftPicture(
                      url: c.gift.iconUrl,
                      size: dim.icon,
                      theme: theme,
                      imageProvider: w.imageProvider,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    text,
                    style: TextStyle(
                      color: isGift ? theme.text : theme.muted,
                      fontSize: dim.text,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
      );
      final key = ValueKey<String>(
        c is WallGiftChip
            ? 'gift-wall-chip-${c.gift.id}'
            : 'gift-wall-overflow',
      );
      if (!tappable) return KeyedSubtree(key: key, child: body);
      // A touch target of at least 44 dp: the chip sits in a taller cell.
      final cell =
          (dim.height < kWallTouchTarget ? kWallTouchTarget : dim.height)
              .toDouble();
      if (c is WallOverflowChip) {
        return Semantics(
          key: key,
          container: true,
          excludeSemantics: true,
          label: fillLabel(labels.wallMore, {'n': groupThousands(c.count)}),
          child: SizedBox(
              height: cell, child: Center(widthFactor: 1, child: body)),
        );
      }
      final g = c as WallGiftChip;
      final gift = g.gift;
      return Semantics(
        key: key,
        button: true,
        container: true,
        excludeSemantics: true,
        label: fillLabel(labels.wallChip, {
          'name': gift.name,
          'count': groupThousands(g.count),
        }),
        onTap: () => w.onPressChip!(gift),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: () => w.onPressChip!(gift),
          child: SizedBox(
              height: cell, child: Center(widthFactor: 1, child: body)),
        ),
      );
    }

    final row = Wrap(
      key: const ValueKey<String>('gift-wall'),
      spacing: 6,
      runSpacing: tappable ? 0 : 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips.map(chip).toList(),
    );
    return FadeTransition(
      opacity: _fade,
      // One element for a screen reader, or a group of buttons when the chips
      // can be tapped.
      child: tappable
          ? Semantics(container: true, explicitChildNodes: true, child: row)
          : Semantics(
              container: true,
              label: summary,
              excludeSemantics: true,
              child: row,
            ),
    );
  }
}

class _Dim {
  const _Dim({required this.icon, required this.text, required this.height});

  final double icon;
  final double text;
  final double height;
}
