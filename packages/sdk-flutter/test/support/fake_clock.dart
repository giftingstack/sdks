// A virtual clock with timers for the rooms tests (same rules as the
// component fixtures' clock in components_conformance_test.dart).

/// [advance] fires every timer due up to the new time, in due order (ties: the
/// order they were set), with the clock set to each timer's due time.
class FakeRoomClock {
  int now = 0;
  int _seq = 0;
  final List<({int id, int due, void Function() fn})> _timers =
      <({int id, int due, void Function() fn})>[];

  /// Number of timers waiting.
  int get pending => _timers.length;

  Object? setTimeout(void Function() fn, int ms) {
    final id = ++_seq;
    _timers.add((id: id, due: now + (ms < 0 ? 0 : ms), fn: fn));
    return id;
  }

  void clearTimeout(Object? id) => _timers.removeWhere((t) => t.id == id);

  ({int id, int due, void Function() fn})? _next(int limit) {
    ({int id, int due, void Function() fn})? best;
    for (final t in _timers) {
      if (t.due <= limit &&
          (best == null ||
              t.due < best.due ||
              (t.due == best.due && t.id < best.id))) {
        best = t;
      }
    }
    return best;
  }

  /// Fires the timers due now.
  void runDue() {
    for (var t = _next(now); t != null; t = _next(now)) {
      clearTimeout(t.id);
      t.fn();
    }
  }

  void advance(int ms) {
    final target = now + ms;
    for (var t = _next(target); t != null; t = _next(target)) {
      now = t.due;
      clearTimeout(t.id);
      t.fn();
    }
    now = target;
  }

  /// Lets pending asynchronous work run, then fires timers that became due,
  /// until nothing changes.
  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        await Future<void>.delayed(Duration.zero);
      }
      runDue();
    }
  }
}
