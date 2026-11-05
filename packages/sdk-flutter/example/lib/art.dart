import 'dart:math';

import 'package:flutter/material.dart';

import 'demo_data.dart';

/// The pictures of the demo posts: gradients and a few shapes, painted, no
/// network. Demo only, not part of the SDK.
class PostArtView extends StatelessWidget {
  /// Creates the picture of [art].
  const PostArtView(this.art, {super.key});

  /// Which drawing.
  final PostArt art;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _ArtPainter(art),
        child: const SizedBox.expand(),
      );
}

class _ArtPainter extends CustomPainter {
  const _ArtPainter(this.art);

  final PostArt art;

  @override
  bool shouldRepaint(_ArtPainter old) => old.art != art;

  Paint _fill(Color c) => Paint()..color = c;

  Paint _gradient(Rect r, List<Color> colors, [List<double>? stops]) => Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    ).createShader(r);

  void _stars(Canvas canvas, Size s, int n, int seed, double maxY) {
    final r = Random(seed);
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(
        Offset(r.nextDouble() * s.width, r.nextDouble() * maxY * s.height),
        0.5 + r.nextDouble() * 1.2,
        _fill(Colors.white.withValues(alpha: 0.4 + r.nextDouble() * 0.6)),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size s) {
    final all = Offset.zero & s;
    // Work in a 400 x 300 drawing, scaled to fill (a little is cropped).
    canvas
      ..clipRect(all)
      ..save();
    final k = max(s.width / 400, s.height / 300);
    canvas.translate((s.width - 400 * k) / 2, (s.height - 300 * k) / 2);
    canvas.scale(k);
    const w = Size(400, 300);
    const r = Rect.fromLTWH(0, 0, 400, 300);
    switch (art) {
      case PostArt.sunset:
        canvas
          ..drawRect(
            r,
            _gradient(
              r,
              const [Color(0xFF3B2A7A), Color(0xFFE0457B), Color(0xFFFFB457)],
              const [0, 0.45, 0.8],
            ),
          )
          ..drawCircle(
            const Offset(200, 170),
            70,
            _fill(const Color(0x2EFFE3A3)),
          )
          ..drawCircle(
            const Offset(200, 170),
            46,
            _fill(const Color(0xFFFFE3A3)),
          );
        const sea = Rect.fromLTWH(0, 180, 400, 120);
        canvas.drawRect(
          sea,
          _gradient(sea, const [Color(0xFFF08A5D), Color(0xFF2A1B4D)]),
        );
        final glint = Paint()
          ..color = const Color(0xBFFFE3A3)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        for (final (i, half) in [40.0, 30.0, 22.0, 14.0].indexed) {
          final y = 192.0 + i * 11;
          canvas.drawLine(Offset(200 - half, y), Offset(200 + half, y), glint);
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(40, 168, 150, 7),
            const Radius.circular(2),
          ),
          _fill(const Color(0xFF1B1033)),
        );
        for (final x in [52.0, 92.0, 132.0, 172.0]) {
          canvas.drawRect(
            Rect.fromLTWH(x, 170, 4, 40),
            _fill(const Color(0xFF1B1033)),
          );
        }
      case PostArt.city:
        canvas.drawRect(
          r,
          _gradient(r, const [Color(0xFF0D1033), Color(0xFF5B3B9A)]),
        );
        _stars(canvas, w, 40, 7, 0.43);
        canvas
          ..drawCircle(
            const Offset(320, 60),
            20,
            _fill(const Color(0xFFF6F1D6)),
          )
          ..drawCircle(
            const Offset(328, 55),
            18,
            _fill(const Color(0x801A1450)),
          );
        const towers = [
          Rect.fromLTWH(10, 150, 60, 150),
          Rect.fromLTWH(80, 110, 50, 190),
          Rect.fromLTWH(140, 170, 70, 130),
          Rect.fromLTWH(220, 90, 56, 210),
          Rect.fromLTWH(286, 140, 48, 160),
          Rect.fromLTWH(344, 120, 56, 180),
        ];
        final lit = Random(11);
        for (final t in towers) {
          canvas.drawRect(t, _fill(const Color(0xFF171244)));
          for (var y = t.top + 14; y < 290; y += 30) {
            for (var x = t.left + 10; x < t.right - 10; x += 20) {
              if (lit.nextDouble() > 0.45) {
                canvas.drawRect(
                  Rect.fromLTWH(x, y, 8, 12),
                  _fill(const Color(0xFFFFD27A)),
                );
              }
            }
          }
        }
      case PostArt.ocean:
        canvas.drawRect(
          r,
          _gradient(
            r,
            const [Color(0xFF8FD3F4), Color(0xFFD9F4FF), Color(0xFF1C7FB8)],
            const [0, 0.5, 0.5],
          ),
        );
        canvas.drawCircle(
          const Offset(300, 70),
          28,
          _fill(const Color(0xFFFFF1B8)),
        );
        for (var i = 0; i < 5; i++) {
          final y = 160.0 + i * 28;
          final path = Path()..moveTo(0, y);
          for (var x = 0.0; x <= 400; x += 10) {
            path.lineTo(x, y + sin((x + i * 40) / 22) * (5 + i * 1.5));
          }
          path
            ..lineTo(400, 300)
            ..lineTo(0, 300)
            ..close();
          canvas.drawPath(
            path,
            _fill(
              Color.lerp(
                const Color(0xFF2A9BD6),
                const Color(0xFF0B3C6B),
                i / 4,
              )!,
            ),
          );
        }
        canvas.drawPath(
          Path()
            ..moveTo(60, 150)
            ..lineTo(80, 118)
            ..lineTo(100, 150)
            ..close(),
          _fill(Colors.white),
        );
      case PostArt.aurora:
        canvas.drawRect(
          r,
          _gradient(r, const [Color(0xFF040B1E), Color(0xFF0E2B4F)]),
        );
        _stars(canvas, w, 60, 3, 0.7);
        for (final (i, c) in const [
          Color(0x6634E8A5),
          Color(0x557B61FF),
          Color(0x4429C7E8),
        ].indexed) {
          final path = Path()..moveTo(0, 150.0 + i * 20);
          for (var x = 0.0; x <= 400; x += 10) {
            path.lineTo(x, 90.0 + i * 25 + sin(x / 40 + i) * 28);
          }
          path
            ..lineTo(400, 210.0 + i * 20)
            ..lineTo(0, 230.0 + i * 20)
            ..close();
          canvas.drawPath(path, _fill(c));
        }
        final hills = Path()
          ..moveTo(0, 300)
          ..lineTo(0, 250)
          ..lineTo(90, 215)
          ..lineTo(170, 245)
          ..lineTo(260, 205)
          ..lineTo(340, 240)
          ..lineTo(400, 225)
          ..lineTo(400, 300)
          ..close();
        canvas.drawPath(hills, _fill(const Color(0xFF05070F)));
    }
    canvas.restore();
  }
}
