import 'dart:convert';

import 'spec_data.g.dart';

final Stopwatch _clock = Stopwatch()..start();

/// A monotonic clock in milliseconds, used when no `now` is given.
int monotonicNowMs() => _clock.elapsedMilliseconds;

/// Counts the same gift sent again and again by the same person ("x2, x3").
/// A pause of [windowMs] or more starts a new run. Every (sender, gift) pair keeps
/// its own run, so several people can combo at the same time.
/// Runs remembered at once (the oldest is dropped beyond this).
const int maxComboRuns = 64;

class _Run {
  const _Run(this.count, this.at);

  final int count;
  final int at;
}

class ComboTracker {
  /// Creates a tracker. [windowMs] defaults to 2500.
  ComboTracker([this.windowMs = kComboWindowMs]);

  /// The gap that still continues a run (strictly less than this). May change
  /// between hits (remote recipes, SPEC 13).
  int windowMs;

  final Map<String, _Run> _runs = <String, _Run>{};

  /// Registers one more send and returns how many in a row this is (from 1).
  /// [now] is in milliseconds; default: a monotonic clock.
  int hit(String sender, String giftId, [int? now]) {
    final t = now ?? monotonicNowMs();
    // A run that paused for the window or more is over.
    _runs.removeWhere((_, run) => t - run.at >= windowMs);
    final key = jsonEncode(<String>[sender, giftId]);
    final count = (_runs.remove(key)?.count ?? 0) + 1;
    _runs[key] = _Run(count, t);
    if (_runs.length > maxComboRuns) _runs.remove(_runs.keys.first);
    return count;
  }

  /// Forgets every run.
  void reset() {
    _runs.clear();
  }
}
