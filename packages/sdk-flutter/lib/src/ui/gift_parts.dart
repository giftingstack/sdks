import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'images.dart';
import 'theme.dart';

/// The first letter of a name, upper case: the avatar's initial.
String initialOf(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : String.fromCharCode(t.runes.first).toUpperCase();
}

/// Digits of equal width, so counts do not jiggle.
const List<FontFeature> tabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// A gift picture that never breaks the layout: a neutral disc while it is
/// missing or cannot load. Not announced to screen readers (the label carries
/// the name).
class GiftPicture extends StatelessWidget {
  /// Creates the picture.
  const GiftPicture({
    required this.url,
    required this.size,
    required this.theme,
    required this.imageProvider,
    super.key,
  });

  /// The picture, or null for the disc.
  final String? url;

  /// Width and height, dp.
  final double size;

  /// Colors.
  final GiftingTheme theme;

  /// Makes the provider for [url].
  final GiftImageProviderBuilder imageProvider;

  @override
  Widget build(BuildContext context) {
    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: theme.border, shape: BoxShape.circle),
    );
    final u = url;
    if (u == null || u.isEmpty) return ExcludeSemantics(child: disc);
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Image(
          image: imageProvider(u),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => disc,
        ),
      ),
    );
  }
}

/// A round avatar: the picture when there is one, else the initial on the
/// accent colour.
class AvatarDisc extends StatelessWidget {
  /// Creates the avatar.
  const AvatarDisc({
    required this.name,
    required this.size,
    required this.theme,
    required this.imageProvider,
    this.url,
    super.key,
  });

  /// Display name: its first letter is the fallback.
  final String name;

  /// The picture, if any.
  final String? url;

  /// Width and height, dp.
  final double size;

  /// Colors.
  final GiftingTheme theme;

  /// Makes the provider for [url].
  final GiftImageProviderBuilder imageProvider;

  @override
  Widget build(BuildContext context) {
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
      child: Text(
        initialOf(name),
        style: TextStyle(
          color: theme.accentText,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final u = url;
    return ExcludeSemantics(
      child: (u == null || u.isEmpty)
          ? letter
          : ClipOval(
              child: SizedBox(
                width: size,
                height: size,
                child: Image(
                  image: imageProvider(u),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => letter,
                ),
              ),
            ),
    );
  }
}

/// A small coin disc, like the tray's.
class CoinDot extends StatelessWidget {
  /// Creates the disc.
  const CoinDot({required this.color, required this.size, super.key});

  /// Fill.
  final Color color;

  /// Width and height, dp.
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );
}

/// A placeholder block that pulses gently, or is fully static when [still]
/// (reduced motion): no shimmer for people who asked for none.
class Pulse extends StatefulWidget {
  /// Creates the pulse around [child].
  const Pulse({required this.still, required this.child, super.key});

  /// No animation at all.
  final bool still;

  /// What pulses.
  final Widget child;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.still) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(Pulse old) {
    super.didUpdateWidget(old);
    if (widget.still && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    } else if (!widget.still && !_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.still
      ? widget.child
      : FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0.55)
              .chain(CurveTween(curve: Curves.easeInOut))
              .animate(_c),
          child: widget.child,
        );
}

/// A small turning arc ("updating"). Draw it only when motion is allowed.
class Spinner extends StatefulWidget {
  /// Creates the spinner.
  const Spinner({required this.color, this.size = 16, super.key});

  /// Colour of the arc.
  final Color color;

  /// Width and height, dp.
  final double size;

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _c,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _ArcPainter(widget.color),
        ),
      );
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      (Offset.zero & size).deflate(1.5),
      0,
      math.pi * 1.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}
