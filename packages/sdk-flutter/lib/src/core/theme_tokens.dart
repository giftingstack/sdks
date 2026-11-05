/// Theme tokens as plain strings, two ready palettes and `themeFromAccent`,
/// which builds a whole readable theme from one brand colour (SPEC 9.2).
/// Pure Dart: the UI turns the tokens into `Color`s (`GiftingTheme`).
/// Port of `packages/sdk-js/src/core/theme.ts`.
library;

import 'dart:math' as math;

/// Dark or light derivation for [themeTokensFromAccent].
enum GiftThemeMode {
  /// Dark surfaces.
  dark,

  /// Light surfaces.
  light,
}

/// The 17 colour tokens of the tray and the notice, as `#rrggbb` strings (the
/// notice background is `rgba(r, g, b, a)`).
class GiftThemeTokens {
  /// Creates tokens; every one has the 1.0 default.
  const GiftThemeTokens({
    this.background = '#14141f',
    this.surface = '#1e1e2e',
    this.border = '#2d2d44',
    this.text = '#f4f2ff',
    this.muted = '#a3a1c2',
    this.accent = '#8b7bff',
    this.accentText = '#ffffff',
    this.coin = '#ffd27a',
    this.coinText = '#2a1600',
    this.selected = '#221f45',
    this.danger = '#ff8fa3',
    this.noticeBackground = 'rgba(123, 107, 255, 0.92)',
    this.noticeText = '#ffffff',
    this.comboText = '#fff3c4',
    this.noticeBigBackground = '#e8a93a',
    this.noticeBigText = '#2a1600',
    this.glow = '#ffdc8c',
  });

  /// Cells and the balance pill.
  final String background;

  /// The tray.
  final String surface;

  /// Tray border, disabled button, icon placeholder.
  final String border;

  /// Title and numbers.
  final String text;

  /// Secondary text, the handle.
  final String muted;

  /// Send button, selected cell, avatar, sparks.
  final String accent;

  /// Text on [accent].
  final String accentText;

  /// Coin discs, "+ Coins", the Get coins button, coin rain.
  final String coin;

  /// Text on [coin] (the Get coins label).
  final String coinText;

  /// Background of the selected cell.
  final String selected;

  /// Reserved.
  final String danger;

  /// The notice pill.
  final String noticeBackground;

  /// Text of the notice.
  final String noticeText;

  /// The combo counter on a small or medium notice.
  final String comboText;

  /// The large-gift notice.
  final String noticeBigBackground;

  /// Text of the large-gift notice.
  final String noticeBigText;

  /// Rays, glow and most sparks.
  final String glow;

  /// The tokens by their SPEC names, for the fixtures and tooling.
  Map<String, String> toMap() => <String, String>{
        'background': background,
        'surface': surface,
        'border': border,
        'text': text,
        'muted': muted,
        'accent': accent,
        'accentText': accentText,
        'coin': coin,
        'coinText': coinText,
        'selected': selected,
        'danger': danger,
        'noticeBackground': noticeBackground,
        'noticeText': noticeText,
        'comboText': comboText,
        'noticeBigBackground': noticeBigBackground,
        'noticeBigText': noticeBigText,
        'glow': glow,
      };

  /// A copy with some tokens replaced.
  GiftThemeTokens copyWith({
    String? accent,
    String? noticeBackground,
  }) =>
      GiftThemeTokens(
        background: background,
        surface: surface,
        border: border,
        text: text,
        muted: muted,
        accent: accent ?? this.accent,
        accentText: accentText,
        coin: coin,
        coinText: coinText,
        selected: selected,
        danger: danger,
        noticeBackground: noticeBackground ?? this.noticeBackground,
        noticeText: noticeText,
        comboText: comboText,
        noticeBigBackground: noticeBigBackground,
        noticeBigText: noticeBigText,
        glow: glow,
      );
}

/// The original look, unchanged since 1.0.
const GiftThemeTokens defaultThemeTokens = GiftThemeTokens();

/// The dark preset: the default with a deeper accent so the white Send label
/// reaches 4.5:1 (white on `#8b7bff` is only 3.3:1).
const GiftThemeTokens darkThemeTokens = GiftThemeTokens(
  accent: '#6d5cf0',
  noticeBackground: 'rgba(109, 92, 240, 0.92)',
);

/// A light preset. Every text pair is at least 4.5:1.
const GiftThemeTokens lightThemeTokens = GiftThemeTokens(
  background: '#f1eff8',
  surface: '#ffffff',
  border: '#dcd8ea',
  text: '#1c1a2e',
  muted: '#5f5b78',
  accent: '#6a54e8',
  accentText: '#ffffff',
  coin: '#9a6300',
  coinText: '#ffffff',
  selected: '#e6e1ff',
  danger: '#c4204a',
  noticeBackground: 'rgba(106, 84, 232, 0.94)',
  noticeText: '#ffffff',
  comboText: '#fff3c4',
  noticeBigBackground: '#e8a93a',
  noticeBigText: '#2a1600',
  glow: '#ffcf66',
);

// ------------------------------------------------------------------ arithmetic

final RegExp _hex = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$');

/// `#rgb` or `#rrggbb` (any case) to 0..255 channels; anything else is null.
List<int>? parseHex(String hex) {
  final m = _hex.firstMatch(hex.trim());
  if (m == null) return null;
  var h = m.group(1)!;
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  return <int>[
    for (var i = 0; i < 6; i += 2) int.parse(h.substring(i, i + 2), radix: 16),
  ];
}

/// `0.5` rounds up (every value here is >= 0).
int _round(double v) => (v + 0.5).floor();

/// `#rrggbb` (lower case) from three channels, clamped to 0..255.
String toHex(List<double> rgb) {
  final b = StringBuffer('#');
  for (final v in rgb) {
    b.write(
        _round(v.clamp(0, 255).toDouble()).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

/// WCAG 2 relative luminance of an opaque colour, 0 (black) to 1 (white).
double relativeLuminance(String hex) {
  final rgb = parseHex(hex);
  if (rgb == null) throw FormatException('Not a hex colour: $hex');
  double lin(int v) {
    final c = v / 255;
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2]);
}

/// WCAG 2 contrast ratio of two opaque colours, 1 to 21.
double contrastRatio(String a, String b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [a] moved towards [b] by [t] (0 = a, 1 = b), channel by channel.
String mixHex(String a, String b, double t) {
  final x = parseHex(a)!;
  final y = parseHex(b)!;
  return toHex(<double>[
    for (var i = 0; i < 3; i++) x[i] + (y[i] - x[i]) * t,
  ]);
}

/// [fg] itself if it reaches [min] against [bg]; otherwise [fg] moved step by
/// step (5 %) towards white or black, whichever is further from [bg], until it
/// does (pure white or black at the end).
String ensureContrast(String fg, String bg, double min) {
  if (contrastRatio(fg, bg) >= min) return fg;
  final target = relativeLuminance(bg) > 0.18 ? '#000000' : '#ffffff';
  for (var t = 0.05; t < 1; t += 0.05) {
    final c = mixHex(fg, target, t);
    if (contrastRatio(c, bg) >= min) return c;
  }
  return target;
}

/// White or black, whichever contrasts more with [bg].
String readableOn(String bg) =>
    contrastRatio('#ffffff', bg) >= contrastRatio('#000000', bg)
        ? '#ffffff'
        : '#000000';

/// A whole theme from one brand colour (SPEC 9.2). The accent is used as given
/// (normalised to lower-case `#rrggbb`); every other token is derived so that
/// text stays readable (4.5:1). Throws [FormatException] for anything but
/// `#rgb` / `#rrggbb`.
GiftThemeTokens themeTokensFromAccent(
  String accent, [
  GiftThemeMode mode = GiftThemeMode.dark,
]) {
  final rgb = parseHex(accent);
  if (rgb == null) {
    throw FormatException('themeFromAccent: not a hex colour: $accent');
  }
  final a = toHex(rgb.map((v) => v.toDouble()).toList());
  final dark = mode == GiftThemeMode.dark;
  final surface = dark ? mixHex('#17171f', a, 0.1) : '#ffffff';
  final background =
      dark ? mixHex('#0d0d14', a, 0.06) : mixHex('#f4f4f7', a, 0.06);
  final selected = dark ? mixHex(surface, a, 0.22) : mixHex('#ffffff', a, 0.16);
  // Text must read on the surface, the background and the selected cell.
  String fit(String fg) => <String>[surface, background, selected]
      .fold(fg, (c, bg) => ensureContrast(c, bg, 4.5));
  final text =
      fit(dark ? mixHex('#ffffff', a, 0.05) : mixHex('#16151f', a, 0.08));
  final muted =
      fit(dark ? mixHex('#b0afc0', a, 0.15) : mixHex('#5c5b6b', a, 0.15));
  final coin = dark ? '#ffd27a' : fit('#9a6300');
  final accentText = readableOn(a);
  return GiftThemeTokens(
    background: background,
    surface: surface,
    border: dark ? mixHex('#2a2a35', a, 0.25) : mixHex('#dedee6', a, 0.2),
    text: text,
    muted: muted,
    accent: a,
    accentText: accentText,
    coin: coin,
    coinText: readableOn(coin),
    selected: selected,
    danger: dark ? '#ff8fa3' : '#c4204a',
    noticeBackground: 'rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, 0.92)',
    noticeText: accentText,
    comboText: accentText == '#ffffff' ? '#fff3c4' : accentText,
    noticeBigBackground: '#e8a93a',
    noticeBigText: '#2a1600',
    glow: '#ffdc8c',
  );
}
