/// The tray as a draggable bottom sheet, without a UI (SPEC section 9.1): three
/// snap states, the drag, the release with a velocity bias, tap and keyboard
/// steps, and who owns a drag that starts on the gift grid.
/// Port of `packages/sdk-js/src/core/sheet.ts`.
///
/// Geometry: the sheet is laid out once at its tallest (the `expanded` height)
/// and moved down by `offset` (a translateY). `offset` 0 shows the whole
/// expanded sheet; the visible height is `heights.expanded - offset`. All
/// lengths are logical pixels; velocity is logical pixels per second, positive
/// = finger moving down.
library;

import 'dart:math' as math;

/// The three snap states, from the most closed to the most open.
enum SheetSnap { peek, standard, expanded }

/// The wire names of the snaps (`default` is a Dart keyword, so the enum value
/// is [SheetSnap.standard]).
extension SheetSnapName on SheetSnap {
  /// `peek`, `default` or `expanded`, as in the SPEC and the fixtures.
  String get wireName => this == SheetSnap.standard ? 'default' : name;

  /// The snap for a wire name, or null.
  static SheetSnap? fromWireName(String? name) {
    for (final s in SheetSnap.values) {
      if (s.wireName == name) return s;
    }
    return null;
  }
}

/// A release at least this fast (logical px per second) moves one state in the
/// direction of the flick.
const double kSheetFlickVelocity = 600;

/// Default snap heights as fractions of the container height. 0 means "as tall
/// as the content needs" (the floor the UI measures).
const Map<SheetSnap, double> kSheetDefaultFractions = <SheetSnap, double>{
  SheetSnap.peek: 0,
  SheetSnap.standard: 0,
  SheetSnap.expanded: 0.9,
};

/// The snap heights (whole numbers unless a measured floor is fractional).
/// Always `0 <= peek <= standard <= expanded <= container`.
class SheetHeights {
  /// Creates heights.
  const SheetHeights(this.peek, this.standard, this.expanded);

  /// Height in peek.
  final double peek;

  /// Height in the default state.
  final double standard;

  /// Height fully open.
  final double expanded;

  /// The height of [snap].
  double of(SheetSnap snap) => switch (snap) {
        SheetSnap.peek => peek,
        SheetSnap.standard => standard,
        SheetSnap.expanded => expanded,
      };

  @override
  bool operator ==(Object other) =>
      other is SheetHeights &&
      other.peek == peek &&
      other.standard == standard &&
      other.expanded == expanded;

  @override
  int get hashCode => Object.hash(peek, standard, expanded);

  @override
  String toString() => 'SheetHeights($peek, $standard, $expanded)';
}

/// What the UI measured and the app asked for.
class SheetLayout {
  /// Creates a layout. Missing fractions and floors are "not given".
  const SheetLayout({
    required this.containerHeight,
    this.snaps = const <SheetSnap, double?>{},
    this.peekMinHeight,
    this.defaultMinHeight,
    this.contentHeight,
  });

  /// Height of the area the sheet sits in (usually the screen).
  final double containerHeight;

  /// Snap heights as fractions of [containerHeight], each clamped to 0..1.
  /// A null value means "not given".
  final Map<SheetSnap, double?> snaps;

  /// Content that must show in peek: handle, header and the Send bar.
  final double? peekMinHeight;

  /// Content of the default state: peek plus up to two rows of gifts.
  final double? defaultMinHeight;

  /// The sheet's natural height with every row of gifts; caps `expanded`
  /// (never below default).
  final double? contentHeight;
}

bool _finite(double? v) => v != null && v.isFinite;
double _positive(double? v) => _finite(v) && v! > 0 ? v : 0;

/// `floor(x + 0.5)`: round half up (Dart's `round` rounds half away from zero,
/// which differs for negatives only; every product here is >= 0).
double _roundHalfUp(double v) => (v + 0.5).floorToDouble();

/// The three snap heights for a layout (SPEC 9.1).
SheetHeights resolveSheetHeights(SheetLayout layout) {
  final h = _positive(layout.containerHeight);
  double fraction(SheetSnap s) {
    final f = layout.snaps[s];
    return _finite(f)
        ? math.min(1.0, math.max(0.0, f!))
        : kSheetDefaultFractions[s]!;
  }

  final peek = math.max(
    _roundHalfUp(fraction(SheetSnap.peek) * h),
    _positive(layout.peekMinHeight),
  );
  final def = math.max(
    math.max(
      _roundHalfUp(fraction(SheetSnap.standard) * h),
      _positive(layout.defaultMinHeight),
    ),
    peek,
  );
  var expanded = _roundHalfUp(fraction(SheetSnap.expanded) * h);
  final content = _positive(layout.contentHeight);
  if (content > 0) expanded = math.min(expanded, content);
  expanded = math.max(expanded, def);
  return SheetHeights(
    math.min(peek, h),
    math.min(def, h),
    math.min(expanded, h),
  );
}

/// The controller's state. Observers are told only when a field changes.
class TraySheetState {
  /// Creates a state.
  const TraySheetState({
    required this.snap,
    required this.offset,
    required this.visibleHeight,
    required this.dragging,
    required this.heights,
    required this.gridScrollable,
  });

  /// The settled state, or the one the sheet is moving to. Stays the old one
  /// during a drag.
  final SheetSnap snap;

  /// How far the sheet is moved down from fully open. 0 = expanded.
  final double offset;

  /// `heights.expanded - offset`: the sheet's top edge, measured from the
  /// container's bottom.
  final double visibleHeight;

  /// A drag is running.
  final bool dragging;

  /// The snap heights.
  final SheetHeights heights;

  /// The grid scrolls by itself only when the sheet is fully open and not
  /// being dragged.
  final bool gridScrollable;
}

/// Who takes a drag that starts on the gift grid.
enum ScrollOwner { sheet, grid }

/// Pure sheet logic. No Flutter imports; `GiftTray` draws what it says.
class TraySheetController {
  /// Creates a controller. [initialSnap] defaults to [SheetSnap.standard].
  TraySheetController({
    SheetSnap initialSnap = SheetSnap.standard,
    SheetLayout? layout,
    void Function(SheetSnap snap)? onSnapChange,
  })  : _snap = initialSnap,
        _onSnapChange = onSnapChange,
        _heights = resolveSheetHeights(
          layout ?? const SheetLayout(containerHeight: 0),
        ) {
    _offset = offsetOf(_snap);
    _state = _build();
  }

  SheetHeights _heights;
  SheetSnap _snap;
  late double _offset;
  bool _dragging = false;

  /// The unclamped drag position, so the sheet stays under the finger after an
  /// over-drag.
  double _raw = 0;
  late TraySheetState _state;
  final List<void Function()> _listeners = <void Function()>[];
  void Function(SheetSnap snap)? _onSnapChange;

  /// Replaces the settle callback.
  // ignore: use_setters_to_change_properties
  void setOnSnapChange(void Function(SheetSnap snap)? callback) =>
      _onSnapChange = callback;

  /// The current state.
  TraySheetState get state => _state;

  /// Calls [listener] after every change. Returns the function that stops it.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// The offset at which [snap] is fully shown.
  double offsetOf(SheetSnap snap) => _heights.expanded - _heights.of(snap);

  /// New measurements. Keeps the state; during a drag the position is clamped
  /// again.
  void setLayout(SheetLayout layout) {
    _heights = resolveSheetHeights(layout);
    _offset = _dragging ? _clamp(_raw) : offsetOf(_snap);
    _emit();
  }

  /// A drag begins (no-op while one runs).
  void dragStart() {
    if (_dragging) return;
    _dragging = true;
    _raw = _offset;
    _emit();
  }

  /// The finger moved [dy] (positive = down). Starts a drag if none runs.
  void drag(double dy) {
    if (!_dragging) dragStart();
    _raw += dy;
    _offset = _clamp(_raw);
    _emit();
  }

  /// The finger lifted with [velocity] (px/s, positive = down). Picks the state
  /// and moves there. Without a running drag nothing changes and the current
  /// state is returned.
  SheetSnap release([double velocity = 0]) {
    if (!_dragging) return _snap;
    _dragging = false;
    final target = _pick(velocity);
    _settle(target);
    return target;
  }

  /// The drag was interrupted: back to the state it started from. Does not
  /// call the snap callback.
  void cancel() {
    if (!_dragging) return;
    _dragging = false;
    _offset = offsetOf(_snap);
    _emit();
  }

  /// Ends any drag and settles on [snap].
  void snapTo(SheetSnap snap) {
    _dragging = false;
    _settle(snap);
  }

  /// Tap on the handle: default closes to peek; peek and expanded go to
  /// default.
  SheetSnap toggle() {
    final next =
        _snap == SheetSnap.standard ? SheetSnap.peek : SheetSnap.standard;
    snapTo(next);
    return next;
  }

  /// Keyboard or accessibility step: +1 opens one state, -1 closes one.
  SheetSnap step(int direction) {
    final at = SheetSnap.values.indexOf(_snap);
    final i = math.min(
      SheetSnap.values.length - 1,
      math.max(0, at + (direction > 0 ? 1 : -1)),
    );
    final next = SheetSnap.values[i];
    snapTo(next);
    return next;
  }

  /// A drag that starts on the gift grid moved [dy] first (positive = down).
  /// Who takes it, the sheet or the grid? Decide once per gesture.
  ScrollOwner scrollOwner(double dy, double gridScrollTop) {
    if (_dragging || _offset > 0) return ScrollOwner.sheet;
    if (dy > 0 && gridScrollTop <= 0) return ScrollOwner.sheet;
    return ScrollOwner.grid;
  }

  double _clamp(double v) =>
      math.min(offsetOf(SheetSnap.peek), math.max(0.0, v));

  /// Flick (|velocity| >= 600): the nearest state beyond the current position
  /// in the flick's direction; if there is none, the nearest state. Otherwise
  /// the nearest state. Ties go to the more open state.
  SheetSnap _pick(double velocity) {
    // Most open first: ties keep the more open one.
    final open = SheetSnap.values.reversed.toList();
    final o = _offset;
    if (velocity.abs() >= kSheetFlickVelocity) {
      final up = velocity < 0;
      SheetSnap? best;
      for (final s in open) {
        final so = offsetOf(s);
        if (up ? so >= o : so <= o) continue;
        if (best == null || (up ? so > offsetOf(best) : so < offsetOf(best))) {
          best = s;
        }
      }
      if (best != null) return best;
    }
    var best = open.first;
    for (final s in open) {
      if ((offsetOf(s) - o).abs() < (offsetOf(best) - o).abs()) best = s;
    }
    return best;
  }

  void _settle(SheetSnap snap) {
    final changed = snap != _snap;
    _snap = snap;
    _offset = offsetOf(snap);
    _emit();
    if (changed) _onSnapChange?.call(snap);
  }

  TraySheetState _build() => TraySheetState(
        snap: _snap,
        offset: _offset,
        visibleHeight: _heights.expanded - _offset,
        dragging: _dragging,
        heights: _heights,
        gridScrollable: _offset == 0 && !_dragging,
      );

  void _emit() {
    final prev = _state;
    final next = _build();
    if (prev.snap == next.snap &&
        prev.offset == next.offset &&
        prev.dragging == next.dragging &&
        prev.heights == next.heights) {
      return;
    }
    _state = next;
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }
}
