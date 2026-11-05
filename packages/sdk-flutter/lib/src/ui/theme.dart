import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

import '../core/theme_tokens.dart';

/// Colors used by the tray and the effect notices. Override any of them.
///
/// The defaults are the 1.0 look. [darkTheme] and [lightTheme] are ready
/// palettes whose text is at least 4.5:1; [themeFromAccent] builds one from a
/// brand colour.
@immutable
class GiftingTheme {
  /// Creates a theme; every color has a default.
  const GiftingTheme({
    this.background = const Color(0xFF14141F),
    this.surface = const Color(0xFF1E1E2E),
    this.border = const Color(0xFF2D2D44),
    this.text = const Color(0xFFF4F2FF),
    this.muted = const Color(0xFFA3A1C2),
    this.accent = const Color(0xFF8B7BFF),
    this.accentText = const Color(0xFFFFFFFF),
    this.coin = const Color(0xFFFFD27A),
    this.coinText = const Color(0xFF2A1600),
    this.selected = const Color(0xFF221F45),
    this.danger = const Color(0xFFFF8FA3),
    this.noticeBackground = const Color.fromRGBO(123, 107, 255, 0.92),
    this.noticeText = const Color(0xFFFFFFFF),
    this.comboText = const Color(0xFFFFF3C4),
    this.noticeBigBackground = const Color(0xFFE8A93A),
    this.noticeBigText = const Color(0xFF2A1600),
    this.glow = const Color(0xFFFFDC8C),
  });

  /// The theme for [tokens] (see `themeFromAccent` in the pure core).
  factory GiftingTheme.fromTokens(GiftThemeTokens tokens) => GiftingTheme(
        background: giftColor(tokens.background),
        surface: giftColor(tokens.surface),
        border: giftColor(tokens.border),
        text: giftColor(tokens.text),
        muted: giftColor(tokens.muted),
        accent: giftColor(tokens.accent),
        accentText: giftColor(tokens.accentText),
        coin: giftColor(tokens.coin),
        coinText: giftColor(tokens.coinText),
        selected: giftColor(tokens.selected),
        danger: giftColor(tokens.danger),
        noticeBackground: giftColor(tokens.noticeBackground),
        noticeText: giftColor(tokens.noticeText),
        comboText: giftColor(tokens.comboText),
        noticeBigBackground: giftColor(tokens.noticeBigBackground),
        noticeBigText: giftColor(tokens.noticeBigText),
        glow: giftColor(tokens.glow),
      );

  /// Balance pill, cells.
  final Color background;

  /// The tray.
  final Color surface;

  /// Tray border, disabled button, icon placeholder.
  final Color border;

  /// Title, numbers.
  final Color text;

  /// Reserved.
  final Color muted;

  /// Send button, selected cell, avatar, sparks.
  final Color accent;

  /// Text on [accent].
  final Color accentText;

  /// Coin discs, "+ Coins", Get coins button, coin rain.
  final Color coin;

  /// Text on [coin] (the Get coins label).
  final Color coinText;

  /// Background of the selected cell.
  final Color selected;

  /// Reserved.
  final Color danger;

  /// The notice.
  final Color noticeBackground;

  /// Text of the notice.
  final Color noticeText;

  /// The combo counter ("x3") on a small or medium notice.
  final Color comboText;

  /// Large-gift notice.
  final Color noticeBigBackground;

  /// Text of the large-gift notice.
  final Color noticeBigText;

  /// Rays, glow and most sparks.
  final Color glow;

  /// A copy with some colors replaced.
  GiftingTheme copyWith({
    Color? background,
    Color? surface,
    Color? border,
    Color? text,
    Color? muted,
    Color? accent,
    Color? accentText,
    Color? coin,
    Color? coinText,
    Color? selected,
    Color? danger,
    Color? noticeBackground,
    Color? noticeText,
    Color? comboText,
    Color? noticeBigBackground,
    Color? noticeBigText,
    Color? glow,
  }) =>
      GiftingTheme(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        border: border ?? this.border,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        accent: accent ?? this.accent,
        accentText: accentText ?? this.accentText,
        coin: coin ?? this.coin,
        coinText: coinText ?? this.coinText,
        selected: selected ?? this.selected,
        danger: danger ?? this.danger,
        noticeBackground: noticeBackground ?? this.noticeBackground,
        noticeText: noticeText ?? this.noticeText,
        comboText: comboText ?? this.comboText,
        noticeBigBackground: noticeBigBackground ?? this.noticeBigBackground,
        noticeBigText: noticeBigText ?? this.noticeBigText,
        glow: glow ?? this.glow,
      );
}

final RegExp _rgba = RegExp(
  r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([0-9.]+)\s*)?\)$',
);

/// A token string (`#rgb`, `#rrggbb` or `rgba(r, g, b, a)`) as a [Color].
Color giftColor(String value) {
  final rgb = parseHex(value);
  if (rgb != null) return Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
  final m = _rgba.firstMatch(value.trim());
  if (m == null) throw FormatException('Not a colour: $value');
  return Color.fromRGBO(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    m.group(4) == null ? 1 : double.parse(m.group(4)!),
  );
}

/// The dark preset: the default look with a deeper accent, so the white Send
/// label reaches 4.5:1. (`const GiftingTheme()` keeps the 1.0 look.)
final GiftingTheme darkTheme = GiftingTheme.fromTokens(darkThemeTokens);

/// A light preset; every text pair is at least 4.5:1.
final GiftingTheme lightTheme = GiftingTheme.fromTokens(lightThemeTokens);

/// A whole readable theme from one brand colour: `#rgb` or `#rrggbb` (anything
/// else throws a [FormatException]). The accent is kept as given; text, muted,
/// coin and the labels on the accent and on the coin are at least 4.5:1.
GiftingTheme themeFromAccent(
  String accent, [
  GiftThemeMode mode = GiftThemeMode.dark,
]) =>
    GiftingTheme.fromTokens(themeTokensFromAccent(accent, mode));
