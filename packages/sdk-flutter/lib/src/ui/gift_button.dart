import 'package:flutter/widgets.dart';

import 'gift_tray_notifier.dart';
import 'theme.dart';

/// The fixed sizes of [GiftButton] (SPEC 20.4): the circle's diameter is
/// 32, 36 or 44 logical pixels; the host cannot pick another one.
enum GiftButtonSize {
  /// 32 circle, 19.6 glyph box.
  small(32),

  /// 36 circle, 22 glyph box (the default).
  medium(36),

  /// 44 circle, 26.9 glyph box.
  large(44);

  const GiftButtonSize(this.diameter);

  /// The circle's diameter.
  final double diameter;

  /// The glyph box's side: `22 * diameter / 36`.
  double get glyphBox => 22 * diameter / 36;
}

/// A small round button with a gift glyph for the app's message bar, next to
/// its text field or emoji button (SPEC 20.4).
///
/// With a [tray], a press is `tray.toggle()`: with a bound text field
/// (`GiftTrayNotifier(input: focusNode)`) the keyboard goes down and the tray
/// opens in its place, and a second press brings the keyboard back. The button
/// shows the tray's state (active while it is open) and rebuilds when it
/// changes.
///
/// ```dart
/// final field = FocusNode();
/// final tray = GiftTrayNotifier(client: client, receiver: 'mert', input: field);
/// Row(children: [
///   Expanded(child: TextField(focusNode: field)),
///   GiftButton(tray: tray),
/// ]);
/// ```
class GiftButton extends StatefulWidget {
  /// Creates the button.
  const GiftButton({
    super.key,
    this.tray,
    this.onPressed,
    this.label = 'Send a gift',
    this.filled = false,
    this.size = GiftButtonSize.medium,
    this.icon,
    this.disabled = false,
    this.theme = const GiftingTheme(),
  });

  /// The tray it toggles; its `isOpen` makes the button active.
  final GiftTrayNotifier? tray;

  /// Called after the toggle; without a [tray] it is the only action.
  final VoidCallback? onPressed;

  /// The accessibility label.
  final String label;

  /// Background `accent` with an `accentText` glyph; default: no background
  /// and an `accent` glyph (like an emoji button).
  final bool filled;

  /// One of three fixed sizes (32 / 36 / 44). The touch target is at least
  /// 44 x 44.
  final GiftButtonSize size;

  /// A custom glyph that replaces the gift glyph. It is centred in the fixed
  /// glyph box and fitted into it: scaled down (never up), aspect ratio kept,
  /// overflow clipped, so it can never change the button's size. It gets the
  /// colour the glyph would have (`accent`, or `accentText` when [filled]).
  final Widget Function(BuildContext context, Color color)? icon;

  /// Half transparent, no presses.
  final bool disabled;

  /// The tray's theme.
  final GiftingTheme theme;

  @override
  State<GiftButton> createState() => _GiftButtonState();
}

class _GiftButtonState extends State<GiftButton> {
  bool _pressed = false;

  void _press() {
    widget.tray?.toggle();
    widget.onPressed?.call();
  }

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  Widget _build(BuildContext context) {
    final tray = widget.tray;
    final theme = widget.theme;
    final active = tray?.isOpen ?? false;
    final background = active
        ? theme.selected
        : widget.filled
            ? theme.accent
            : const Color(0x00000000);
    final glyph = active
        ? theme.accent
        : widget.filled
            ? theme.accentText
            : theme.accent;
    final size = widget.size.diameter;
    final box = widget.size.glyphBox;
    final custom = widget.icon;
    final target = size < 44 ? 44.0 : size;
    final enabled = !widget.disabled;

    Widget circle = Container(
      key: const ValueKey<String>('gift-button-circle'),
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: custom == null
          ? CustomPaint(
              key: const ValueKey<String>('gift-button-glyph'),
              size: Size.square(box),
              painter: GiftGlyphPainter(glyph),
            )
          : SizedBox(
              key: const ValueKey<String>('gift-button-icon'),
              width: box,
              height: box,
              child: ClipRect(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: custom(context, glyph),
                  ),
                ),
              ),
            ),
    );
    // Pressed: a short dim, the widgets layer's own feedback.
    circle = AnimatedOpacity(
      opacity: _pressed ? 0.6 : 1,
      duration: const Duration(milliseconds: 100),
      child: circle,
    );

    Widget button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? _press : null,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      excludeFromSemantics: true,
      child: SizedBox(
        width: target,
        height: target,
        child: Center(child: circle),
      ),
    );
    if (widget.disabled) button = Opacity(opacity: 0.5, child: button);

    button = Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.label,
      expanded: tray == null ? null : active,
      selected: tray == null ? null : active,
      onTap: enabled ? _press : null,
      child: ExcludeSemantics(child: button),
    );
    // A tap on the button is not a tap outside the bound text field: the tray
    // takes the focus away itself, in the SPEC's order (blur, then open).
    if (tray != null && tray.inputBound) {
      button = TextFieldTapRegion(child: button);
    }
    return button;
  }

  @override
  Widget build(BuildContext context) {
    final tray = widget.tray;
    if (tray == null) return _build(context);
    return ListenableBuilder(
      listenable: tray,
      builder: (context, _) => _build(context),
    );
  }
}

/// The gift glyph of [GiftButton] (SPEC 20.4): strokes of width 1.8 with round
/// joins and caps, no fill, drawn in a 24 x 24 box scaled to the paint size.
class GiftGlyphPainter extends CustomPainter {
  /// Creates the painter.
  const GiftGlyphPainter(this.color);

  /// The stroke colour.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawRect(const Rect.fromLTRB(4, 11, 20, 21), paint);
    canvas.drawRect(const Rect.fromLTRB(3, 7, 21, 11), paint);
    canvas.drawLine(const Offset(12, 7), const Offset(12, 21), paint);
    final bows = Path()
      ..moveTo(12, 7)
      ..cubicTo(10, 7, 8, 6, 8, 4.5)
      ..cubicTo(8, 3, 10, 3, 12, 7)
      ..moveTo(12, 7)
      ..cubicTo(14, 7, 16, 6, 16, 4.5)
      ..cubicTo(16, 3, 14, 3, 12, 7);
    canvas.drawPath(bows, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(GiftGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
