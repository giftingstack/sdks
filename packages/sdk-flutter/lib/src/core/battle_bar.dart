/// What the battle bar (SPEC 18.7) shows, as plain data: the split, the clock,
/// the winner, the words and the two side colours. Pure Dart, no UI. Port of
/// `packages/sdk-js/src/core/battleBar.ts`; fixture `battle-bar.json`.
library;

import 'dart:math' as math;

import 'leaderboard.dart' show groupThousands;
import 'rooms.dart' show BattleView, RoomScoreEntry;
import 'theme_tokens.dart' show GiftThemeTokens, contrastRatio, parseHex;
import 'wall.dart' show CountLabels, formatCount;

/// Every word of the bar. `{name}`, `{a}`, `{b}` mark a place a value goes.
class BattleBarLabels {
  /// Creates labels; every one has the English default.
  const BattleBarLabels({
    this.vs = 'VS',
    this.finalText = 'Final',
    this.wins = '{name} wins the round',
    this.draw = 'Draw: nobody wins this round',
    this.spoken = '{a}, {b}',
    this.side = '{name} {score}',
    this.thousand = 'K',
    this.million = 'M',
  });

  /// The small "VS" over the clock.
  final String vs;

  /// The clock when the round has ended.
  final String finalText;

  /// Below the bar when a side won.
  final String wins;

  /// Below the bar when the round ended level.
  final String draw;

  /// The spoken summary: `{a}, {b}`, each side [side].
  final String spoken;

  /// One side, spoken: `{name} {score}`.
  final String side;

  /// Count suffix, as in `formatCount`.
  final String thousand;

  /// Count suffix, as in `formatCount`.
  final String million;
}

String _fill(String template, Map<String, String> values) =>
    template.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (m) => values[m[1]] ?? m[0]!,
    );

/// Seconds left on the clock at which it turns urgent.
const int battleUrgentSeconds = 10;

/// The boundary never leaves this band, so both sides stay visible (percent of
/// the bar).
const double battleMinSharePct = 6;

/// A score for the bar: `9,999` in full, then `10K`, `1.2M`.
String formatBattleScore(
  int n, [
  BattleBarLabels labels = const BattleBarLabels(),
]) =>
    n >= 10000
        ? formatCount(
            n,
            CountLabels(thousand: labels.thousand, million: labels.million),
          )
        : groupThousands(math.max(0, n));

int _ceilSeconds(int ms) => (ms / 1000).ceil();

/// `m:ss`, rounded up like a countdown.
String formatBattleClock(int remainingMs) {
  final secs = math.max(0, _ceilSeconds(remainingMs));
  return '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
}

/// One side of the bar.
class BattleBarSide {
  /// Creates a side.
  const BattleBarSide({
    required this.id,
    required this.name,
    required this.units,
    required this.score,
    required this.spoken,
    required this.leads,
    required this.won,
    required this.lost,
  });

  /// The receiver's id.
  final String id;

  /// The display name (the id when unknown).
  final String name;

  /// The full score.
  final int units;

  /// The short form (`135K`).
  final String score;

  /// Spoken: `Mia 1,800`.
  final String spoken;

  /// This side leads while the round is open, or won it.
  final bool leads;

  /// The round ended and this side led.
  final bool won;

  /// The round ended and the other side led.
  final bool lost;
}

/// The bar for one [BattleView].
class BattleBarModel {
  /// Creates the model.
  const BattleBarModel({
    required this.sides,
    required this.pct,
    required this.clock,
    required this.urgent,
    required this.isFinal,
    required this.winner,
    required this.banner,
    required this.spoken,
  });

  /// The two sides, in the server's order.
  final List<BattleBarSide> sides;

  /// The first side's part of the bar, percent, kept inside the visible band.
  final double pct;

  /// `m:ss`, or the `final` label once the round ended.
  final String clock;

  /// Under [battleUrgentSeconds] and still open.
  final bool urgent;

  /// The round has ended.
  final bool isFinal;

  /// The winning receiver once ended, else null (also null for a draw).
  final String? winner;

  /// The line under the bar once the round ended; empty before.
  final String banner;

  /// One sentence for a screen reader: both sides and their scores.
  final String spoken;
}

/// The bar for [view], or null when it has fewer than two sides (a round with
/// one receiver has nothing to compare). Extra sides beyond two are ignored:
/// the bar is a versus.
BattleBarModel? battleBarModel(
  BattleView? view, {
  String Function(String id)? nameOf,
  BattleBarLabels labels = const BattleBarLabels(),
}) {
  if (view == null || view.sides.length < 2) return null;
  final name = nameOf ?? (String id) => id;
  final isFinal = !view.open;
  BattleBarSide side(RoomScoreEntry s) {
    final n = name(s.id);
    return BattleBarSide(
      id: s.id,
      name: n,
      units: s.units,
      score: formatBattleScore(s.units, labels),
      spoken: _fill(labels.side, <String, String>{
        'name': n,
        'score': groupThousands(s.units),
      }),
      leads: view.leader == s.id,
      won: isFinal && view.leader == s.id,
      lost: isFinal && view.leader != null && view.leader != s.id,
    );
  }

  final a = side(view.sides[0]);
  final b = side(view.sides[1]);
  final secs = _ceilSeconds(view.remainingMs);
  final winner = isFinal ? view.leader : null;
  return BattleBarModel(
    sides: <BattleBarSide>[a, b],
    pct: math.min(
      100 - battleMinSharePct,
      math.max(battleMinSharePct, view.sides[0].share * 100),
    ),
    clock: isFinal ? labels.finalText : formatBattleClock(view.remainingMs),
    urgent: !isFinal && secs <= battleUrgentSeconds,
    isFinal: isFinal,
    winner: winner,
    banner: !isFinal
        ? ''
        : winner != null
            ? _fill(labels.wins, <String, String>{
                'name': winner == a.id ? a.name : b.name,
              })
            : labels.draw,
    spoken: _fill(labels.spoken, <String, String>{
      'a': a.spoken,
      'b': b.spoken,
    }),
  );
}

/// A colour and the text colour that reads on it, both as `#rrggbb` strings
/// (the colour is as given).
class SideColor {
  /// Creates the pair.
  const SideColor(this.color, this.text);

  /// The side colour.
  final String color;

  /// Text on [color].
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SideColor && other.color == color && other.text == text;

  @override
  int get hashCode => Object.hash(color, text);
}

/// White or black, whichever contrasts more with [hex]; an unreadable colour
/// string counts as white.
String battleReadableOn(String hex) => parseHex(hex) == null ||
        contrastRatio('#ffffff', hex) >= contrastRatio('#000000', hex)
    ? '#ffffff'
    : '#000000';

/// The two side colours: the theme's accent against its coin colour (each with
/// the theme's own text colour on it, already 4.5:1 in both presets), or
/// [override] (text picked by contrast).
List<SideColor> battleSideColors(
  GiftThemeTokens theme, [
  List<String>? override,
]) {
  if (override != null) {
    return <SideColor>[
      SideColor(override[0], battleReadableOn(override[0])),
      SideColor(override[1], battleReadableOn(override[1])),
    ];
  }
  return <SideColor>[
    SideColor(theme.accent, theme.accentText),
    SideColor(theme.coin, theme.coinText),
  ];
}

/// Which sides gained score since [before] (to pulse them). [before] null:
/// nobody pulses.
List<bool> battleGains(List<int>? before, List<int> after) => <bool>[
      for (var i = 0; i < after.length; i++)
        before != null && after[i] > (i < before.length ? before[i] : after[i]),
    ];
