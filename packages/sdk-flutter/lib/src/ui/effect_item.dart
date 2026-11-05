import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/effect_recipe.dart';
import 'effect_timeline.dart';
import 'images.dart';
import 'theme.dart';

class _Spark {
  const _Spark(this.dx, this.dy, this.size, this.color);
  final double dx;
  final double dy;
  final double size;
  final Color color;
}

class _Coin {
  const _Coin(this.x, this.size, this.start, this.fall);
  final double x;
  final double size;

  /// Fractions of the rain: when the coin starts and how long it falls.
  final double start;
  final double fall;
}

/// Plays one gift from start to finish and calls [onDone].
///
/// Waits for its picture first (up to [pictureWaitMs]) so the dim, the notice
/// and the gift appear together. One [AnimationController] drives everything;
/// sparks, coins, rays and the dim are painted by one [CustomPainter] that
/// repaints without rebuilding widgets, the picture moves with a transform and
/// an opacity only.
class EffectItem extends StatefulWidget {
  /// Creates an effect item.
  const EffectItem({
    required this.recipe,
    required this.image,
    required this.size,
    required this.origin,
    required this.theme,
    required this.pictureWaitMs,
    required this.imageProvider,
    required this.onStart,
    required this.onDone,
    this.pictureScale,
    super.key,
  });

  /// What to play.
  final EffectRecipe recipe;

  /// The big picture, or null for a coin-colored disc.
  final String? image;

  /// Size of the layer.
  final Size size;

  /// Where the gift starts, in layer coordinates.
  final Offset origin;

  /// Colors.
  final GiftingTheme theme;

  /// Longest wait for the picture, ms.
  final int pictureWaitMs;

  /// Makes the provider for [image].
  final GiftImageProviderBuilder imageProvider;

  /// The effect really starts now (picture ready or the wait ran out).
  final VoidCallback onStart;

  /// The animation ran to its end.
  final VoidCallback onDone;

  /// Replaces the automatic picture scale (see [pictureScale]); null: automatic.
  final double? pictureScale;

  @override
  State<EffectItem> createState() => _EffectItemState();
}

class _EffectItemState extends State<EffectItem>
    with SingleTickerProviderStateMixin {
  late final EffectTimeline _timeline = EffectTimeline(widget.recipe);
  late final AnimationController _controller;
  late final Offset _stage;

  /// The recipe's peak scale and spark spread times the layer's picture scale.
  late final double _peak;
  late final double _spread;
  late final List<_Spark> _sparks;
  late final List<_Coin> _coins;
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Timer? _waitTimer;
  bool _started = false;
  bool _startQueued = false;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    final recipe = widget.recipe;
    final random = math.Random();
    final w = widget.size.width;
    final h = widget.size.height;
    // The picture, the burst and the glow grow together in a wide layer; times
    // and counts stay the same (as the web layer's pictureScale).
    final k = pictureScale(w, h, recipe.peakScale, widget.pictureScale);
    _peak = recipe.peakScale * k;
    _spread = recipe.sparkSpread * k;
    _stage = recipe.stage == EffectStage.center
        ? Offset(w / 2, h * 0.38)
        : Offset(
            widget.origin.dx + (random.nextDouble() - 0.5) * 0.2 * w,
            widget.origin.dy - 0.32 * h,
          );
    _sparks = List<_Spark>.generate(recipe.sparks, (i) {
      final angle = i / math.max(1, recipe.sparks) * math.pi * 2 +
          random.nextDouble() * 0.6;
      final dist = _spread * (0.4 + random.nextDouble() * 0.8);
      return _Spark(
        math.cos(angle) * dist,
        math.sin(angle) * dist,
        5 + random.nextDouble() * 6,
        i % 3 == 0 ? widget.theme.accent : widget.theme.glow,
      );
    });
    _coins = List<_Coin>.generate(
      recipe.coins,
      (_) => _Coin(
        random.nextDouble() * w,
        10 + random.nextDouble() * 8,
        random.nextDouble() * 0.35,
        0.45 + random.nextDouble() * 0.2,
      ),
    );
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _timeline.totalMs),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      });
    final image = widget.image;
    if (image == null || widget.pictureWaitMs <= 0) {
      _queueStart();
    } else {
      _provider = widget.imageProvider(image);
      _waitTimer = Timer(
        Duration(milliseconds: widget.pictureWaitMs),
        _queueStart,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = _provider;
    if (provider == null || _resolved || _started) return;
    _resolved = true;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _stream = stream;
    _listener = ImageStreamListener(
      (ImageInfo _, bool __) => _queueStart(),
      onError: (Object _, StackTrace? __) => _queueStart(),
    );
    stream.addListener(_listener!);
  }

  /// Starts exactly once. Never inside a build: a cached picture reports
  /// synchronously while the tree is being built.
  void _queueStart() {
    if (_startQueued || !mounted) return;
    _startQueued = true;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      _start();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  void _start() {
    if (_started || !mounted) return;
    _started = true;
    _waitTimer?.cancel();
    _waitTimer = null;
    _detach();
    widget.onStart();
    if (mounted) unawaited(_controller.forward());
  }

  void _detach() {
    final l = _listener;
    if (l != null) _stream?.removeListener(l);
    _listener = null;
    _stream = null;
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _detach();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _timeline.totalMs.toDouble();
    final image = widget.image;
    final picture = SizedBox(
      width: kEffectPictureSize,
      height: kEffectPictureSize,
      child: image != null
          ? Image(
              image: _provider ?? widget.imageProvider(image),
              width: kEffectPictureSize,
              height: kEffectPictureSize,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.theme.coin,
              ),
            ),
    );
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CustomPaint(
                painter: _FxPainter(
                  repaint: _controller,
                  timeline: _timeline,
                  totalMs: totalMs,
                  stage: _stage,
                  sparks: _sparks,
                  coins: _coins,
                  theme: widget.theme,
                ),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: AnimatedBuilder(
                  animation: _controller,
                  child: picture,
                  builder: (context, child) {
                    final f = _timeline.at(_controller.value * totalMs);
                    final cx = widget.origin.dx +
                        (_stage.dx - widget.origin.dx) * f.fly;
                    final cy = widget.origin.dy +
                        (_stage.dy - widget.origin.dy) * f.fly +
                        -0.07 * widget.size.height * f.leave;
                    final scale = interpolate(
                          f.fly,
                          const <double>[0, 1],
                          <double>[0.3, _peak],
                        ) *
                        (1 - 0.45 * f.leave);
                    final appear = interpolate(
                      f.fly,
                      const <double>[0, 0.06, 1],
                      const <double>[0, 1, 1],
                      clamp: true,
                    );
                    const half = kEffectPictureSize / 2;
                    return Opacity(
                      opacity: (appear * (1 - f.leave)).clamp(0.0, 1.0),
                      child: Transform(
                        transform: Matrix4(
                          scale, 0, 0, 0, //
                          0, scale, 0, 0, //
                          0, 0, 1, 0, //
                          cx - half * scale, cy - half * scale, 0, 1,
                        ),
                        child: child,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dim, rays, glow, sparks and coins, back to front. Repaints on every tick of
/// the controller without rebuilding any widget.
class _FxPainter extends CustomPainter {
  _FxPainter({
    required Animation<double> repaint,
    required this.timeline,
    required this.totalMs,
    required this.stage,
    required this.sparks,
    required this.coins,
    required this.theme,
  })  : _repaint = repaint,
        super(repaint: repaint);

  final Animation<double> _repaint;
  final EffectTimeline timeline;
  final double totalMs;
  final Offset stage;
  final List<_Spark> sparks;
  final List<_Coin> coins;
  final GiftingTheme theme;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final recipe = timeline.recipe;
    final f = timeline.at(_repaint.value * totalMs);

    if (recipe.dim && f.dim > 0) {
      _paint.color = Color.fromRGBO(0, 0, 0, 0.62 * f.dim);
      canvas.drawRect(Offset.zero & size, _paint);
    }

    if (recipe.rays) {
      final fade = interpolate(
        f.spin,
        const <double>[0, 0.1, 0.85, 1],
        const <double>[0, 1, 1, 0],
      );
      final r = math.min(size.width, size.height) * 1.6;
      _rays(canvas, r, 12, r * 0.075, 0.34 * fade, 60 * f.spin);
      _rays(canvas, r, 12, r * 0.028, 0.42 * fade, 15 - 50 * f.spin);
      final grow =
          interpolate(f.fly, const <double>[0, 1], const <double>[0.4, 1]);
      for (final k in const <double>[1, 0.78, 0.58, 0.4, 0.24]) {
        _paint.color = theme.glow.withValues(alpha: 0.16 * fade);
        canvas.drawCircle(stage, 340 * k / 2 * grow, _paint);
      }
    }

    if (sparks.isNotEmpty && f.burst > 0) {
      final b = f.burst;
      final opacity = interpolate(
        b,
        const <double>[0, 0.12, 1],
        const <double>[0, 1, 0],
      );
      if (opacity > 0) {
        final scale = 1 - 0.8 * b;
        for (final s in sparks) {
          _paint.color = s.color.withValues(alpha: opacity);
          canvas.drawCircle(
            Offset(stage.dx + s.dx * b, stage.dy + s.dy * b),
            s.size / 2 * scale,
            _paint,
          );
        }
      }
    }

    if (coins.isNotEmpty) {
      final p = f.rain;
      for (final c in coins) {
        final opacity = interpolate(
          p,
          <double>[0, c.start, c.start + 0.02, 1],
          const <double>[0, 0, 1, 1],
        );
        if (opacity <= 0) continue;
        final fallY = interpolate(
          p,
          <double>[c.start, math.min(1, c.start + c.fall)],
          <double>[0, size.height + 48],
          clamp: true,
        );
        _paint.color = theme.coin.withValues(alpha: opacity);
        canvas.drawCircle(
          Offset(c.x + c.size / 2, -24 + fallY + c.size / 2),
          c.size / 2,
          _paint,
        );
      }
    }
  }

  /// [n] thin triangles from the stage centre out to radius `r / 2`.
  void _rays(
    Canvas canvas,
    double r,
    int n,
    double halfWidth,
    double opacity,
    double turnDeg,
  ) {
    if (opacity <= 0) return;
    _paint.color = theme.glow.withValues(alpha: opacity);
    for (var i = 0; i < n; i++) {
      final angle = (i * 360 / n + turnDeg) * math.pi / 180;
      canvas
        ..save()
        ..translate(stage.dx, stage.dy)
        ..rotate(angle)
        ..drawPath(
          Path()
            ..moveTo(0, 0)
            ..lineTo(-halfWidth, -r / 2)
            ..lineTo(halfWidth, -r / 2)
            ..close(),
          _paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_FxPainter oldDelegate) => false;
}
