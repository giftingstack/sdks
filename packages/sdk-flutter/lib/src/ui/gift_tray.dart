import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart';

import '../core/scrim.dart';
import '../core/sheet.dart';
import '../core/tray.dart';
import '../core/types.dart';
import 'effect_timeline.dart' show outCubic;
import 'gift_tray_notifier.dart';
import 'images.dart';
import 'theme.dart';

/// en-US grouping (`1,234`), whatever the device locale (as the reference).
String formatCoins(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A press becomes a drag of the sheet after this much mostly vertical
/// movement (SPEC 9.1, "Slop").
const double kSheetSlop = 6;

/// Shared between the gestures and the grid's scroll physics: while the sheet
/// owns a gesture the grid must not scroll or fling.
class _Gate {
  bool sheetOwns = false;
}

class _GridPhysics extends ClampingScrollPhysics {
  const _GridPhysics(this.gate, {super.parent});

  final _Gate gate;

  @override
  _GridPhysics applyTo(ScrollPhysics? ancestor) =>
      _GridPhysics(gate, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      gate.sheetOwns ? 0 : super.applyPhysicsToUserOffset(position, offset);

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) =>
      gate.sheetOwns
          ? null
          : super.createBallisticSimulation(position, velocity);
}

/// A tray of gifts with the balance and a Send button. Presentational: you pass
/// data and callbacks, or just your `GiftTrayNotifier` as [tray]
/// (`GiftTray(tray: tray)`): the tray then takes the gifts, the balance, Send
/// and the "Test mode" badge from it and rebuilds when it changes.
///
/// By default the tray is a bottom sheet the person drags between three
/// states (SPEC 9.1): `peek` (handle, header and the Send bar), the default
/// (two rows of gifts) and `expanded` (90 % of the container, the grid scrolls
/// inside). It fills its parent, so put it in a `Stack` over the screen (the
/// area above the sheet still gets touches). `sheet: false` keeps the old
/// fixed-height tray.
class GiftTray extends StatefulWidget {
  /// Creates the tray.
  const GiftTray({
    this.tray,
    this.gifts,
    this.balance,
    this.onSend,
    this.onTopUp,
    this.title = 'Send a gift',
    this.testMode,
    this.testModeLabel = 'Test mode',
    this.coinName = 'coins',
    this.sendLabel = 'Send',
    this.notEnoughLabel = 'Not enough coins',
    this.getCoinsLabel = 'Get coins',
    this.columns = 4,
    this.gridMaxHeight = 230,
    this.defaultSelectedId,
    this.disabled = false,
    this.theme = const GiftingTheme(),
    this.imageProvider = defaultGiftImageProvider,
    this.padding = const EdgeInsets.all(14),
    this.sheet = true,
    this.initialSnap = SheetSnap.standard,
    this.snaps = const <SheetSnap, double?>{},
    this.onSnapChange,
    this.onInsetChange,
    this.containerHeight,
    this.bottomInset = 0,
    this.reducedMotion,
    this.onSelect,
    this.collapseOnSelect = false,
    this.open,
    this.scrim = false,
    this.scrimTap = ScrimTap.lower,
    this.onDismiss,
    super.key,
  }) : assert(
          tray != null || (gifts != null && balance != null && onSend != null),
          'Pass a tray, or gifts, balance and onSend.',
        );

  /// Your `GiftTrayNotifier`. The tray takes [gifts], [balance], [onSend] and
  /// [testMode] from it unless you pass them yourself, and rebuilds when it
  /// changes.
  final GiftTrayNotifier? tray;

  /// The gifts to show, in order. Default: `tray.gifts`.
  final List<Gift>? gifts;

  /// The balance; changes count up or down. Default: `tray.balance`.
  final int? balance;

  /// Called when the person taps Send. Tap again for a combo. Default:
  /// `tray.send`.
  final FutureOr<void> Function(Gift gift)? onSend;

  /// Shows "+ Coins" and, when the balance is too low, a "Get coins" button.
  final VoidCallback? onTopUp;

  /// Title of the sheet.
  final String title;

  /// The "Test mode" badge after the title. Default (null): `tray.testMode`
  /// (true when the server says the token was made with a test key; no badge
  /// without a [tray]). `true` forces it on, `false` forces it off.
  final bool? testMode;

  /// Text of the test mode badge (shown in capitals).
  final String testModeLabel;

  /// Name of your currency, used in labels for screen readers.
  final String coinName;

  /// Label of the send button.
  final String sendLabel;

  /// Label when the balance is too low and there is no top-up.
  final String notEnoughLabel;

  /// Label when the balance is too low and [onTopUp] is given.
  final String getCoinsLabel;

  /// Gifts per row.
  final int columns;

  /// Fixed tray only (`sheet: false`): the grid scrolls beyond this height.
  final double gridMaxHeight;

  /// Id of the gift selected first. Default: the first gift.
  final String? defaultSelectedId;

  /// Turn off sending, for example while a request is running.
  final bool disabled;

  /// Colors. Try `darkTheme`, `lightTheme` or `themeFromAccent('#ff4f9a')`.
  final GiftingTheme theme;

  /// Makes the provider for a picture URL.
  final GiftImageProviderBuilder imageProvider;

  /// Fixed tray only: padding of the tray (add the bottom safe area here).
  final EdgeInsetsGeometry padding;

  /// Default `true`: a draggable bottom sheet that fills its parent. `false`:
  /// the old fixed-height tray in the normal layout flow. Read once, when the
  /// tray is created.
  final bool sheet;

  /// Sheet only: the state it opens in. Default [SheetSnap.standard].
  final SheetSnap initialSnap;

  /// Sheet only: snap heights as fractions of the container height (0 = fit
  /// the content). Defaults: peek 0, default 0, expanded 0.9.
  final Map<SheetSnap, double?> snaps;

  /// Sheet only: the settled state changed (release, tap, accessibility
  /// action).
  final void Function(SheetSnap snap)? onSnapChange;

  /// Sheet only: the sheet's top edge, in logical pixels from the container's
  /// bottom: live during a drag and the TARGET when it snaps. Keep the notice
  /// above it: `noticeBottom: inset + 16`.
  final void Function(double inset)? onInsetChange;

  /// Sheet only: the container's height, if you know it. Default: measured.
  final double? containerHeight;

  /// Sheet only: extra space under the Send button, for example the safe-area
  /// bottom inset.
  final double bottomInset;

  /// Sheet only: picking a gift in the grid lowers the sheet to peek (the
  /// picked gift and Send), so what is behind it stays in sight, for example
  /// a live stream. The handle (or a drag up) brings the grid back. To lower
  /// or open it from your code, use a `GlobalKey<GiftTrayWidgetState>` and
  /// `snapTo`. Default false.
  final bool collapseOnSelect;

  /// Sheet only: the tray is shown or hidden. Default (null): `tray.isOpen`
  /// when you pass a [tray], else true. While false the sheet and the scrim are
  /// invisible and take no touches; opening shows it again at [initialSnap]
  /// (SPEC 9.4).
  final bool? open;

  /// Sheet only (SPEC 9.4): a dim behind the sheet over the whole box the tray
  /// fills. It fades in over 200 ms (at once with reduced motion) once the
  /// sheet is placed, is hidden while the sheet is at peek (what is behind it
  /// stays in sight) and takes the touches above the sheet while it shows.
  /// Needs a bounded parent. Default false: no dim.
  final bool scrim;

  /// What a tap on the scrim does. [ScrimTap.lower] (default): lowers the sheet
  /// to peek (the dim goes away), and from peek dismisses. [ScrimTap.dismiss]:
  /// dismisses from every state. A dismissal calls `tray.close()` (when [open]
  /// is not given) and then [onDismiss].
  final ScrimTap scrimTap;

  /// Sheet only: a scrim tap asked to close. With a [tray] it is already
  /// closed when this runs.
  final VoidCallback? onDismiss;

  /// The person picked another gift (not called for the first selection).
  /// Handy for a debug control such as "incoming: same as tray".
  final void Function(Gift gift)? onSelect;

  /// Sheet only: jump to a state instead of animating. Default (null): follows
  /// the OS "remove animations" setting.
  final bool? reducedMotion;

  @override
  State<GiftTray> createState() => GiftTrayWidgetState();
}

/// The state of a [GiftTray]. Keep a `GlobalKey<GiftTrayWidgetState>` to move the
/// sheet from your code with [snapTo].
class GiftTrayWidgetState extends State<GiftTray>
    with TickerProviderStateMixin {
  String? _selectedId;
  late final AnimationController _count;
  int _lastBalance = 0;

  List<Gift> get _gifts => widget.gifts ?? widget.tray?.gifts ?? const <Gift>[];
  int get _balance => widget.balance ?? widget.tray?.balance ?? 0;
  bool get _testMode => widget.testMode ?? widget.tray?.testMode ?? false;
  FutureOr<void> Function(Gift gift)? get _onSend =>
      widget.onSend ?? widget.tray?.send;

  double _from = 0;
  double _to = 0;
  List<Gift>? _warmedGifts;
  String? _warmedBig;

  // ---- sheet
  late final TraySheetController _sheet;
  late final void Function() _unsubscribe;
  late final AnimationController _y;
  final ScrollController _gridScroll = ScrollController();
  final _Gate _gate = _Gate();
  final GlobalKey _bodyKey = GlobalKey();
  final GlobalKey _gridKey = GlobalKey();
  final GlobalKey _rowKey = GlobalKey();
  final GlobalKey _footerKey = GlobalKey();
  double _containerHeight = 0;
  double _footerHeight = 0;
  String _layoutSignature = '';
  bool _hasLayout = false;

  /// The sheet is drawn only once its layout has settled (a few frames after the first
  /// measurement): until then every move is a jump, so it never slides about behind a
  /// footer that is already in place.
  bool _shown = false;
  bool _measureQueued = false;
  double _shownOffset = 0;
  double? _lastInset;
  int? _pointer;
  Offset _downAt = Offset.zero;
  Offset _lastAt = Offset.zero;
  bool _downOnGrid = false;
  bool _decided = false;
  bool _sheetDrag = false;
  bool _suppressTap = false;
  bool _gridLive = false;
  VelocityTracker? _velocity;

  @override
  void initState() {
    super.initState();
    _selectedId =
        widget.defaultSelectedId ?? (_gifts.isEmpty ? null : _gifts.first.id);
    _lastBalance = _balance;
    _from = _to = _balance.toDouble();
    _wasOpen = _open;
    widget.tray?.addListener(_onTray);
    _count = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _sheet = TraySheetController(
      initialSnap: widget.initialSnap,
      layout: SheetLayout(
        containerHeight: widget.containerHeight ?? 0,
        snaps: widget.snaps,
      ),
      onSnapChange: (snap) => widget.onSnapChange?.call(snap),
    );
    _shownOffset = _sheet.state.offset;
    _lastExpanded = _sheet.state.heights.expanded;
    _y = AnimationController.unbounded(vsync: this, value: _shownOffset);
    _unsubscribe = _sheet.subscribe(_onSheetChanged);
  }

  bool get _open => widget.open ?? widget.tray?.isOpen ?? true;
  bool _wasOpen = true;

  /// The tray opened or closed (SPEC 9.4). Closing puts the sheet back at its
  /// first state with a jump (it is invisible), so opening shows it where it
  /// started; the inset is 0 while closed.
  void _syncOpen() {
    final now = _open;
    if (now == _wasOpen) return;
    _wasOpen = now;
    if (!now) _sheet.snapTo(widget.initialSnap);
    _reportInset();
    if (mounted) setState(() {});
  }

  void _reportInset() {
    final inset = _open ? _sheet.state.visibleHeight : 0.0;
    if (_lastInset == inset) return;
    _lastInset = inset;
    widget.onInsetChange?.call(inset);
  }

  /// A tap on the scrim (SPEC 9.4).
  void _tapScrim() {
    final outcome = scrimTapOutcome(
      scrim: widget.scrim,
      scrimTap: widget.scrimTap,
      open: _open,
      snap: _sheet.state.snap,
    );
    if (outcome == ScrimTapOutcome.lower) {
      _sheet.snapTo(SheetSnap.peek);
    } else if (outcome == ScrimTapOutcome.dismiss) {
      // The open prop, when given, is the host's to change.
      if (widget.open == null) widget.tray?.close();
      widget.onDismiss?.call();
    }
  }

  /// The number on screen right now.
  double get _shownBalance => _from + (_to - _from) * outCubic(_count.value);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmUp();
  }

  @override
  void didUpdateWidget(GiftTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tray, widget.tray)) {
      oldWidget.tray?.removeListener(_onTray);
      widget.tray?.addListener(_onTray);
    }
    _syncBalance();
    _warmUp();
    // Not now: this runs while the parent builds, and the callbacks it may
    // cause (the inset) belong to the parent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncOpen();
    });
  }

  /// The notifier changed (catalog, balance, test mode, open): redraw.
  void _onTray() {
    if (!mounted) return;
    setState(() {
      _syncBalance();
      _warmUp();
    });
    _syncOpen();
  }

  void _syncBalance() {
    final balance = _balance;
    if (balance == _lastBalance) return;
    _lastBalance = balance;
    // Count from what is shown now, not from the old target.
    _from = _shownBalance;
    _to = balance.toDouble();
    unawaited(_count.forward(from: 0));
  }

  /// Sheet only: moves the sheet to [snap] (animated unless reduced motion).
  void snapTo(SheetSnap snap) {
    if (widget.sheet) _sheet.snapTo(snap);
  }

  Gift? get _selected {
    for (final g in _gifts) {
      if (g.id == _selectedId) return g;
    }
    return _gifts.isEmpty ? null : _gifts.first;
  }

  /// Warm the pictures: small icons for the whole tray whenever the gifts
  /// change, the big picture of the selected gift whenever the selection does.
  void _warmUp() {
    if (!identical(_warmedGifts, _gifts)) {
      _warmedGifts = _gifts;
      for (final g in _gifts) {
        _precache(g.iconUrl);
      }
    }
    final selected = _selected;
    final big = selected?.animationUrl ?? selected?.iconUrl;
    if (big != _warmedBig) {
      _warmedBig = big;
      _precache(big);
    }
  }

  void _precache(String? url) {
    if (url == null) return;
    unawaited(
      precacheImage(
        widget.imageProvider(url),
        context,
        onError: (Object _, StackTrace? __) {},
      ).catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    widget.tray?.removeListener(_onTray);
    _unsubscribe();
    _y.dispose();
    _gridScroll.dispose();
    _count.dispose();
    super.dispose();
  }

  void _select(String id) {
    if (_suppressTap) return; // the end of a drag is not a tap
    setState(() => _selectedId = id);
    _warmUp(); // the big picture of the newly selected gift
    if (widget.collapseOnSelect) snapTo(SheetSnap.peek);
    for (final g in _gifts) {
      if (g.id == id) widget.onSelect?.call(g);
    }
  }

  void _press(SendButtonState button) {
    final selected = _selected;
    if (selected == null) return;
    if (button.action == SendButtonAction.topUp) {
      widget.onTopUp?.call();
    } else if (button.action == SendButtonAction.send) {
      final onSend = _onSend;
      if (onSend != null) unawaited(Future<void>.sync(() => onSend(selected)));
    }
  }

  // ------------------------------------------------------------ sheet logic

  bool get _reduced =>
      widget.reducedMotion ??
      MediaQuery.maybeDisableAnimationsOf(context) ??
      false;

  /// The controller changed: move the body (a jump while dragging, a critically
  /// damped spring otherwise), tell the app the inset, redraw.
  void _onSheetChanged() {
    final st = _sheet.state;
    if (st.dragging || _reduced || !_shown || !_open) {
      _y.stop();
      _y.value = st.offset;
    } else if (st.offset != _shownOffset) {
      // The offset is measured from the top of the sheet's box, and the box is as tall as the
      // expanded state. When the box grows or shrinks (the gifts arrived after the tray opened),
      // move the start by the same amount, so the sheet leaves from where it is drawn instead
      // of from a place that only made sense for the old box (it flashed at the top).
      final grew = st.heights.expanded - _lastExpanded;
      if (grew != 0) {
        _y.stop();
        _y.value += grew;
      }
      // Stiffness 320, damping 36, mass 1: no overshoot (as the RN sheet).
      unawaited(
        _y.animateWith(
          SpringSimulation(
            const SpringDescription(mass: 1, stiffness: 320, damping: 36),
            _y.value,
            st.offset,
            0,
          ),
        ),
      );
    }
    _shownOffset = st.offset;
    _lastExpanded = st.heights.expanded;
    _reportInset();
    if (mounted) setState(() {});
  }

  /// The expanded height (the sheet box's height) when the body was last moved.
  double _lastExpanded = 0;

  void _queueMeasure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (mounted) _measure();
    });
  }

  /// Content floors, measured after layout (SPEC 9.1): the block above the
  /// grid plus the footer, one grid row, the footer.
  void _measure() {
    if (!widget.sheet) return;
    final body = _bodyKey.currentContext?.findRenderObject();
    final grid = _gridKey.currentContext?.findRenderObject();
    final footer = _footerKey.currentContext?.findRenderObject();
    final row = _rowKey.currentContext?.findRenderObject();
    if (body is! RenderBox ||
        grid is! RenderBox ||
        footer is! RenderBox ||
        !body.hasSize ||
        !grid.hasSize ||
        !footer.hasSize) {
      return;
    }
    final rowHeight = row is RenderBox && row.hasSize ? row.size.height : 0.0;
    final gridTop = grid.localToGlobal(Offset.zero, ancestor: body).dy;
    final footerHeight = footer.size.height;
    final peek = gridTop + footerHeight;
    final rows = (_gifts.length / math.max(1, widget.columns)).ceil();
    final layout = SheetLayout(
      containerHeight: widget.containerHeight ?? _containerHeight,
      snaps: widget.snaps,
      peekMinHeight: peek,
      defaultMinHeight: peek + math.min(2, rows) * rowHeight,
      contentHeight: peek + rows * rowHeight,
    );
    final signature = <Object?>[
      layout.containerHeight,
      layout.peekMinHeight,
      layout.defaultMinHeight,
      layout.contentHeight,
      for (final s in SheetSnap.values) layout.snaps[s],
    ].join('|');
    final footerChanged = footerHeight != _footerHeight;
    if (signature == _layoutSignature && !footerChanged) return;
    _layoutSignature = signature;
    _footerHeight = footerHeight;
    // The first real measurement: a row to measure, or no gifts at all (an empty
    // catalog has no row; waiting for one left the sheet invisible forever, as
    // the web, React Native and Android trays never do: they place it once the
    // container, the block above the grid and the footer are measured).
    final first = !_hasLayout && (rowHeight > 0 || _gifts.isEmpty);
    if (first) {
      _hasLayout = true;
      // Two frames later the measurements have settled: show the sheet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _shown = true);
        });
        WidgetsBinding.instance.scheduleFrame();
      });
      WidgetsBinding.instance.scheduleFrame();
    }
    _sheet.setLayout(layout);
    if (first) {
      // The first real measurement: show the sheet where it belongs at once.
      _y.stop();
      _y.value = _sheet.state.offset;
      _shownOffset = _sheet.state.offset;
    }
    if (footerChanged && mounted) setState(() {});
  }

  void _pointerDown(PointerDownEvent e) {
    if (_pointer != null) return; // one finger drives the sheet
    _pointer = e.pointer;
    _downAt = _lastAt = e.position;
    _decided = false;
    _sheetDrag = false;
    _suppressTap = false;
    _velocity = VelocityTracker.withKind(e.kind)
      ..addPosition(e.timeStamp, e.position);
    final grid = _gridKey.currentContext?.findRenderObject();
    _downOnGrid = grid is RenderBox &&
        grid.hasSize &&
        grid.size.contains(grid.globalToLocal(e.position));
  }

  void _pointerMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _velocity?.addPosition(e.timeStamp, e.position);
    if (!_decided) {
      final total = e.position - _downAt;
      if (total.dy.abs() > kSheetSlop && total.dy.abs() > total.dx.abs()) {
        _decided = true;
        final gridTop = _gridScroll.hasClients ? _gridScroll.offset : 0.0;
        final owner = !_downOnGrid ||
            _sheet.scrollOwner(total.dy, gridTop) == ScrollOwner.sheet;
        if (owner) {
          _sheetDrag = true;
          _suppressTap = true;
          _gate.sheetOwns = true;
          _sheet
            ..dragStart()
            // The slop already travelled is applied now, so the sheet does
            // not lag behind the finger.
            ..drag(total.dy);
          _lastAt = e.position;
        }
      }
    } else if (_sheetDrag) {
      _sheet.drag(e.position.dy - _lastAt.dy);
      _lastAt = e.position;
    }
  }

  void _pointerUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _velocity?.addPosition(e.timeStamp, e.position);
    final v = _velocity?.getVelocity().pixelsPerSecond.dy ?? 0;
    final wasDrag = _sheetDrag;
    _endPointer();
    if (wasDrag) _sheet.release(v);
    if (mounted) setState(() {}); // the grid's physics may change now
  }

  void _pointerCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    final wasDrag = _sheetDrag;
    _endPointer();
    if (wasDrag) _sheet.cancel();
    if (mounted) setState(() {});
  }

  void _endPointer() {
    _pointer = null;
    _sheetDrag = false;
    _decided = false;
    _velocity = null;
    // The scroll view has seen the end of the gesture by now (it is deeper in
    // the tree), so it no longer needs the gate.
    _gate.sheetOwns = false;
  }

  // ------------------------------------------------------------ pieces

  TextStyle _style(
    Color color,
    double size,
    FontWeight weight, {
    bool tabular = false,
  }) =>
      TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        decoration: TextDecoration.none,
        fontFeatures:
            tabular ? const <FontFeature>[FontFeature.tabularFigures()] : null,
      );

  Widget _coin(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: widget.theme.coin,
          shape: BoxShape.circle,
        ),
      );

  Widget _head() {
    final theme = widget.theme;
    return Row(
      children: <Widget>[
        Expanded(
          // One line, ends with "…" (SPEC 9): a long or translated title never
          // changes the peek height.
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: _style(theme.text, 15, FontWeight.w700),
          ),
        ),
        if (_testMode) ...<Widget>[
          const SizedBox(width: 10),
          Container(
            key: const ValueKey<String>('gift-test-mode'),
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5A524),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.testModeLabel.toUpperCase(),
              style: _style(const Color(0xFF1A1300), 11, FontWeight.w800)
                  .copyWith(letterSpacing: 0.4),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Semantics(
          label: 'Balance: ${formatCoins(_balance)} ${widget.coinName}',
          excludeSemantics: true,
          child: Container(
            key: const ValueKey<String>('gift-balance'),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
            decoration: BoxDecoration(
              color: theme.background,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _coin(14),
                const SizedBox(width: 6),
                AnimatedBuilder(
                  animation: _count,
                  builder: (context, _) => Text(
                    formatCoins(_shownBalance.round()),
                    key: const ValueKey<String>('gift-balance-text'),
                    style: _style(
                      theme.text,
                      13,
                      FontWeight.w700,
                      tabular: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.onTopUp != null) ...<Widget>[
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Get more ${widget.coinName}',
            excludeSemantics: true,
            child: GestureDetector(
              key: const ValueKey<String>('gift-topup'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTopUp,
              child: Text(
                '+ Coins',
                style: _style(theme.coin, 13, FontWeight.w700),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _grid(Gift? selected) => LayoutBuilder(
        builder: (context, constraints) {
          final cell = constraints.maxWidth / widget.columns;
          return Wrap(
            children: <Widget>[
              for (var i = 0; i < _gifts.length; i++)
                SizedBox(
                  key: i == 0 ? _rowKey : null,
                  width: cell,
                  child: _cell(_gifts[i], selected, cell),
                ),
            ],
          );
        },
      );

  Widget _sendButton(
    SendButtonState button,
    String label,
    Gift? selected, {
    required bool inFooter,
  }) {
    final theme = widget.theme;
    final pressable = button.pressable;
    final coinStyle = button.broke && pressable;
    final child = Semantics(
      button: true,
      enabled: pressable,
      label: selected == null ? label : '$label: ${selected.name}',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey<String>('gift-send'),
        behavior: HitTestBehavior.opaque,
        onTap: pressable ? () => _press(button) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: pressable
                ? (button.broke ? theme.coin : theme.accent)
                : theme.border,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: _style(
              coinStyle ? theme.coinText : theme.accentText,
              15,
              FontWeight.w700,
            ),
          ),
        ),
      ),
    );
    return inFooter ? Expanded(child: child) : child;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final canTopUp = widget.onTopUp != null;
    final button = sendButtonState(
      gifts: _gifts,
      selectedId: _selectedId,
      balance: _balance,
      disabled: widget.disabled,
      canTopUp: canTopUp,
    );
    final label = switch (button.label) {
      SendButtonLabel.send => widget.sendLabel,
      SendButtonLabel.getCoins => widget.getCoinsLabel,
      SendButtonLabel.notEnough => widget.notEnoughLabel,
    };
    if (widget.sheet) return _buildSheet(selected, button, label);
    return _buildFixed(selected, button, label);
  }

  Widget _buildFixed(Gift? selected, SendButtonState button, String label) {
    final theme = widget.theme;
    return Container(
      key: const ValueKey<String>('gift-tray'),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: theme.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _head(),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.gridMaxHeight),
            child: SingleChildScrollView(child: _grid(selected)),
          ),
          const SizedBox(height: 12),
          _sendButton(button, label, selected, inFooter: false),
        ],
      ),
    );
  }

  Widget _buildSheet(Gift? selected, SendButtonState button, String label) {
    final theme = widget.theme;
    final edge = BorderSide(color: theme.border, width: 0.5);
    return LayoutBuilder(
      builder: (context, constraints) {
        _containerHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        _queueMeasure();
        final st = _sheet.state;
        final bodyHeight = math.max(0.0, st.heights.expanded - _footerHeight);
        final settledPeek = st.snap == SheetSnap.peek && !st.dragging;
        // The grid's physics change only between gestures.
        if (_pointer == null) _gridLive = st.gridScrollable;
        final ScrollPhysics physics = _gridLive
            ? _GridPhysics(_gate)
            : const NeverScrollableScrollPhysics();

        final body = Container(
          key: _bodyKey,
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: edge, left: edge, right: edge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _handle(st),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _head(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ExcludeSemantics(
                  excluding: settledPeek,
                  child: Padding(
                    key: _gridKey,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: SingleChildScrollView(
                      key: const ValueKey<String>('gift-grid'),
                      controller: _gridScroll,
                      physics: physics,
                      child: _grid(selected),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        final footer = Container(
          key: _footerKey,
          padding: EdgeInsets.fromLTRB(14, 10, 14, 14 + widget.bottomInset),
          decoration: BoxDecoration(
            color: theme.surface,
            border: Border(left: edge, right: edge),
          ),
          child: Row(
            children: <Widget>[
              if (selected != null) _picked(selected),
              _sendButton(button, label, selected, inFooter: true),
            ],
          ),
        );

        // Drawn from the first measured layout on, so the sheet never shows its unmeasured
        // guess and then jumps: it fades in where it belongs.
        final sheetLayer = AnimatedOpacity(
          opacity: _shown && _open ? 1 : 0,
          duration: Duration(milliseconds: _reduced ? 0 : 200),
          curve: Curves.easeOut,
          child: AnimatedSlide(
            offset: _shown ? Offset.zero : const Offset(0, 0.03),
            duration: Duration(milliseconds: _reduced ? 0 : 220),
            curve: Curves.easeOutCubic,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                key: const ValueKey<String>('gift-sheet'),
                height: st.heights.expanded,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: bodyHeight,
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _pointerDown,
                        onPointerMove: _pointerMove,
                        onPointerUp: _pointerUp,
                        onPointerCancel: _pointerCancel,
                        child: AnimatedBuilder(
                          animation: _y,
                          builder: (context, child) => Transform.translate(
                            offset: Offset(0, _y.value),
                            child: child,
                          ),
                          child: KeyedSubtree(
                            key: const ValueKey<String>('gift-tray'),
                            child: body,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: KeyedSubtree(
                        key: const ValueKey<String>('gift-footer'),
                        child: footer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // Closed: invisible, no touches, nothing for screen readers (SPEC 9.4).
        final sheetPart = IgnorePointer(
          ignoring: !_open,
          child: ExcludeSemantics(excluding: !_open, child: sheetLayer),
        );
        if (!widget.scrim) return sheetPart;
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(child: _scrimLayer(placed: _shown, snap: st.snap)),
            Positioned.fill(child: sheetPart),
          ],
        );
      },
    );
  }

  /// The dim behind the sheet (SPEC 9.4): black at 0.4, fades over 200 ms (0
  /// with reduced motion). It takes touches in every state, peek included (the
  /// dim stays hidden there, a tap closes the tray).
  Widget _scrimLayer({required bool placed, required SheetSnap snap}) {
    final on = scrimVisible(
      scrim: widget.scrim,
      open: _open,
      snap: snap,
      placed: placed,
    );
    final active = scrimTakesTouches(
      scrim: widget.scrim,
      open: _open,
      placed: placed,
    );
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: Semantics(
          button: true,
          label: 'Close gift tray',
          excludeSemantics: true,
          child: GestureDetector(
            key: const ValueKey<String>('tray-scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: _tapScrim,
            child: AnimatedOpacity(
              opacity: on ? kScrimOpacity : 0,
              duration: Duration(milliseconds: scrimFadeMs(_reduced)),
              curve: Curves.easeOut,
              child: const ColoredBox(color: Color(0xFF000000)),
            ),
          ),
        ),
      ),
    );
  }

  /// The drag handle: a button with the state as its value, tap to toggle,
  /// increase/decrease and two custom actions for screen readers.
  Widget _handle(TraySheetState st) => Semantics(
        button: true,
        label: 'Gift tray',
        hint: 'Drag up or down to see more or fewer gifts',
        value: st.snap.wireName,
        // Screen readers announce the state a step leads to (the ends stay).
        increasedValue: _neighbour(st.snap, 1).wireName,
        decreasedValue: _neighbour(st.snap, -1).wireName,
        expanded: st.snap != SheetSnap.peek,
        onTap: _sheet.toggle,
        onIncrease: () => _sheet.step(1),
        onDecrease: () => _sheet.step(-1),
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          const CustomSemanticsAction(label: 'Show more gifts'): () =>
              _sheet.step(1),
          const CustomSemanticsAction(label: 'Show fewer gifts'): () =>
              _sheet.step(-1),
        },
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey<String>('gift-handle'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (!_suppressTap) _sheet.toggle();
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
              child: Opacity(
                opacity: 0.7,
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: widget.theme.muted,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  SheetSnap _neighbour(SheetSnap s, int d) =>
      SheetSnap.values[(s.index + d).clamp(0, SheetSnap.values.length - 1)];

  /// The selected gift beside the Send button (at most 45 % of the width).
  Widget _picked(Gift g) {
    final theme = widget.theme;
    final icon = g.iconUrl;
    return Flexible(
      flex: 0,
      child: LayoutBuilder(
        builder: (context, _) => ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.45,
          ),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: icon == null
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.border,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          )
                        : Image(
                            image: widget.imageProvider(icon),
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            excludeFromSemantics: true,
                            errorBuilder: (_, __, ___) => const SizedBox(),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          g.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          key: const ValueKey<String>('gift-picked-name'),
                          style: _style(theme.text, 12.5, FontWeight.w700),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _coin(9),
                            const SizedBox(width: 3),
                            Text(
                              formatCoins(g.price),
                              style: _style(
                                theme.text,
                                11.5,
                                FontWeight.w700,
                                tabular: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(Gift g, Gift? selected, double cellWidth) {
    final theme = widget.theme;
    final isSelected = g.id == selected?.id;
    final icon = g.iconUrl;
    // As the web tray: min(72, 78 % of the cell's content width).
    final iconSize = math.min(72.0, 0.78 * math.max(0, cellWidth - 8 - 3));
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: isSelected,
      selected: isSelected,
      label: '${g.name}, ${formatCoins(g.price)} ${widget.coinName}',
      excludeSemantics: true,
      onTap: () => _select(g.id),
      child: GestureDetector(
        key: ValueKey<String>('gift-${g.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(g.id),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? theme.selected : theme.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? theme.accent : const Color(0x00000000),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: icon == null
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.border,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        )
                      : Image(
                          image: widget.imageProvider(icon),
                          width: iconSize,
                          height: iconSize,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                          errorBuilder: (_, __, ___) => DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.border,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _coin(9),
                    const SizedBox(width: 3),
                    Text(
                      formatCoins(g.price),
                      style: _style(
                        theme.text,
                        11.5,
                        FontWeight.w700,
                        tabular: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
