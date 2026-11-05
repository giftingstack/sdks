import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/client.dart';
import '../core/error.dart';
import '../core/inbox.dart';
import '../core/timers.dart' show wallClockMs;
import '../core/tray.dart' show asGiftingError;
import 'gift_away_summary.dart' show AwayUser;
import 'gift_parts.dart';
import 'images.dart';
import 'labels.dart';
import 'theme.dart';

/// Height of a row, dp (at least).
const double _rowHeight = 52;

/// How many placeholder rows the loading state shows.
const int _skeletonRows = 4;

enum _InboxStatus { loading, ready, error }

/// Who sent the signed-in user which gift in the last 24 hours (SPEC 19.3):
/// one row per gift, newest first, each with the sender's initial avatar,
/// "Name sent you Gift" (with "xN" above one), the gift picture and how long
/// ago. Loads the first page itself, shows "Show more" while older gifts
/// exist, and shows an empty state and an error with "Try again". Reversed
/// gifts are hidden. Read only: the app keeps the time of the newest row it
/// showed and counts a badge with `inboxUnread`.
///
/// Hold a `GlobalKey<GiftInboxState>` to call `refresh()` (pull to refresh,
/// or when the tab opens).
class GiftInbox extends StatefulWidget {
  /// Creates the inbox.
  const GiftInbox({
    required this.client,
    this.resolveUsers,
    this.pageSize = 20,
    this.onLoaded,
    this.onError,
    this.reducedMotion,
    this.theme = const GiftingTheme(),
    this.labels = const GiftLabels(),
    this.imageProvider = defaultGiftImageProvider,
    this.now,
    super.key,
  });

  /// The API client.
  final GiftingClient client;

  /// External ids are often not display names: map them here. Unknown ids keep
  /// the id.
  final Future<Map<String, AwayUser>> Function(List<String> ids)? resolveUsers;

  /// Rows per page, 1 to 100. Default 20.
  final int pageSize;

  /// Called after every page that arrived (the first one, "Show more" and
  /// `refresh()`) with every gift loaded so far, newest first, reversed ones
  /// included (so `inboxUnread` sees the same list the server sent).
  final void Function(List<InboxItem> items)? onLoaded;

  /// Called for every failure (the inbox shows its own message).
  final void Function(GiftingException error)? onError;

  /// Default (null): follows the OS "remove animations" setting (no pulse, no
  /// spinner).
  final bool? reducedMotion;

  /// Colors: `surface`, `border`, `text`, `muted`, `accent`, `accentText`,
  /// `danger`.
  final GiftingTheme theme;

  /// Texts (translations).
  final GiftLabels labels;

  /// Makes the provider for a picture URL.
  final GiftImageProviderBuilder imageProvider;

  /// The clock in ms for the time labels. Default: wall clock.
  final int Function()? now;

  @override
  State<GiftInbox> createState() => GiftInboxState();
}

/// The state of [GiftInbox]: its public methods are the handle.
class GiftInboxState extends State<GiftInbox> {
  _InboxStatus _status = _InboxStatus.loading;
  List<InboxItem> _items = const <InboxItem>[];
  bool _hasMore = false;
  String? _cursor;
  bool _loadingMore = false;
  int _generation = 0;
  Map<String, AwayUser> _users = const <String, AwayUser>{};
  final Set<String> _asked = <String>{};

  /// Load again from the first page. The list stays until the answer arrives.
  void refresh() {
    if (_status != _InboxStatus.ready) {
      setState(() => _status = _InboxStatus.loading);
    }
    unawaited(_loadFirst());
  }

  Future<void> _loadFirst() async {
    final generation = ++_generation;
    _loadingMore = false;
    try {
      final page = await widget.client.getInbox(limit: widget.pageSize);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = List<InboxItem>.of(page.data);
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _status = _InboxStatus.ready;
      });
      _afterPage();
    } on Object catch (err) {
      if (!mounted || generation != _generation) return;
      widget.onError?.call(asGiftingError(err));
      if (_status != _InboxStatus.ready) {
        setState(() => _status = _InboxStatus.error);
      }
    }
  }

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (_loadingMore || !_hasMore || cursor == null) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.client.getInbox(
        cursor: cursor,
        limit: widget.pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = <InboxItem>[..._items, ...page.data];
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _loadingMore = false;
      });
      _afterPage();
    } on Object catch (err) {
      if (!mounted || generation != _generation) return;
      setState(() => _loadingMore = false);
      widget.onError?.call(asGiftingError(err));
    }
  }

  void _afterPage() {
    widget.onLoaded?.call(List<InboxItem>.unmodifiable(_items));
    _resolveNames();
  }

  void _resolveNames() {
    final resolve = widget.resolveUsers;
    if (resolve == null) return;
    final fresh = <String>{
      for (final i in _items)
        if (i.sender != null && !_asked.contains(i.sender)) i.sender!,
    }.toList();
    if (fresh.isEmpty) return;
    _asked.addAll(fresh);
    unawaited(
      resolve(fresh).then(
        (found) {
          if (mounted) {
            setState(() => _users = <String, AwayUser>{..._users, ...found});
          }
        },
        onError: (Object _) => _asked.removeAll(fresh),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadFirst());
  }

  @override
  void didUpdateWidget(GiftInbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client) ||
        oldWidget.pageSize != widget.pageSize) {
      _items = const <InboxItem>[];
      _hasMore = false;
      _cursor = null;
      _status = _InboxStatus.loading;
      unawaited(_loadFirst());
    }
  }

  bool get _reduced =>
      widget.reducedMotion ??
      MediaQuery.maybeDisableAnimationsOf(context) ??
      false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final theme = w.theme;
    final labels = w.labels;
    final reduced = _reduced;
    final now = (w.now ?? wallClockMs)();
    final names = <String, String>{
      for (final e in _users.entries) e.key: e.value.name,
    };

    String qtyText(InboxRow row) => fillLabel(
          labels.inboxQuantity,
          <String, Object>{'n': row.quantity},
        );

    List<InlineSpan> sentence(InboxRow row) {
      final template = labels.inboxSent;
      final at = template.indexOf('{name}');
      String fill(String s) => fillLabel(s, <String, Object>{
            'gift': row.giftName,
            'name': row.senderName,
          });
      final nameStyle = TextStyle(
        color: theme.text,
        fontWeight: FontWeight.w700,
      );
      final spans = <InlineSpan>[];
      if (at < 0) {
        spans.add(TextSpan(text: fill(template)));
      } else {
        final before = fill(template.substring(0, at));
        final after = fill(template.substring(at + '{name}'.length));
        if (before.isNotEmpty) spans.add(TextSpan(text: before));
        spans.add(TextSpan(text: row.senderName, style: nameStyle));
        if (after.isNotEmpty) spans.add(TextSpan(text: after));
      }
      if (row.quantity > 1) {
        spans.add(TextSpan(text: ' ${qtyText(row)}', style: nameStyle));
      }
      return spans;
    }

    String spoken(InboxRow row) {
      final plain = fillLabel(labels.inboxSent, <String, Object>{
        'name': row.senderName,
        'gift': row.giftName,
      });
      final text = row.quantity > 1 ? '$plain ${qtyText(row)}' : plain;
      return fillLabel(labels.inboxRowSpoken, <String, Object>{
        'sentence': text,
        'time': row.time,
      });
    }

    Widget rowView(InboxRow row) => Semantics(
          key: ValueKey<String>('gift-inbox-row-${row.id}'),
          container: true,
          excludeSemantics: true,
          label: spoken(row),
          child: Container(
            constraints: const BoxConstraints(minHeight: _rowHeight),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: <Widget>[
                AvatarDisc(
                  name: row.senderName,
                  url: _users[row.sender]?.avatarUrl,
                  size: 36,
                  theme: theme,
                  imageProvider: w.imageProvider,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: sentence(row)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GiftPicture(
                  url: row.iconUrl,
                  size: 32,
                  theme: theme,
                  imageProvider: w.imageProvider,
                ),
                const SizedBox(width: 10),
                Text(
                  row.time,
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
          ),
        );

    Widget pillButton({
      required Key key,
      required String label,
      required VoidCallback onTap,
      required bool filled,
    }) =>
        Semantics(
          button: true,
          excludeSemantics: true,
          label: label,
          onTap: onTap,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: onTap,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: filled ? theme.accent : const Color(0x00000000),
                borderRadius: BorderRadius.circular(999),
                border: filled
                    ? null
                    : Border.all(color: theme.border, width: 0.5),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    color: filled ? theme.accentText : theme.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        );

    final Widget body;
    if (_status == _InboxStatus.loading) {
      body = Semantics(
        container: true,
        excludeSemantics: true,
        label: labels.loading,
        child: Pulse(
          still: reduced,
          child: Column(
            key: const ValueKey<String>('gift-inbox-skeleton'),
            children: <Widget>[
              for (var i = 0; i < _skeletonRows; i++)
                Container(
                  key: ValueKey<String>('gift-inbox-skeleton-row-$i'),
                  height: _rowHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: theme.border,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 110.0 + ((i * 37) % 70),
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
    } else if (_status == _InboxStatus.error) {
      body = Padding(
        key: const ValueKey<String>('gift-inbox-error'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Column(
          children: <Widget>[
            Semantics(
              liveRegion: true,
              child: Text(
                labels.inboxError,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.danger,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            pillButton(
              key: const ValueKey<String>('gift-inbox-retry'),
              label: labels.tryAgain,
              onTap: refresh,
              filled: true,
            ),
          ],
        ),
      );
    } else {
      final rows = inboxRows(_items, now, names);
      final Widget more = !_hasMore
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: _loadingMore
                    ? SizedBox(
                        height: 44,
                        child: Center(
                          child: reduced
                              ? const SizedBox.shrink()
                              : Semantics(
                                  label: labels.updating,
                                  child: Spinner(
                                    key: const ValueKey<String>(
                                      'gift-inbox-spinner',
                                    ),
                                    color: theme.muted,
                                  ),
                                ),
                        ),
                      )
                    : pillButton(
                        key: const ValueKey<String>('gift-inbox-more'),
                        label: labels.inboxShowMore,
                        onTap: () => unawaited(_loadMore()),
                        filled: false,
                      ),
              ),
            );
      if (rows.isEmpty && !_hasMore) {
        body = Padding(
          key: const ValueKey<String>('gift-inbox-empty'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
          child: Center(
            child: Text(
              labels.inboxEmpty,
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
          key: const ValueKey<String>('gift-inbox-list'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[...rows.map(rowView), more],
        );
      }
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.border, width: 0.5),
      ),
      child: body,
    );
  }
}
