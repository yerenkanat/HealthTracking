/// The proportional baby-size disc — a filled circle at this week's fraction of
/// newborn size, inside a faint ring drawn at term. Together they read as "this
/// is how big baby is now, and how big at birth", and the disc visibly grows
/// week to week.
///
/// The fraction is computed by [sizeVisualFraction] in domain/baby_size.dart, so
/// this widget is purely presentational; shared by the week-detail screen and
/// the main pregnancy view so the picture is the same in both places.
library;

import 'package:flutter/material.dart';

class BabySizeDisc extends StatelessWidget {
  /// 0..1, from `sizeVisualFraction(size.lengthCm)`.
  final double fraction;
  final Color colour;
  final double size;
  const BabySizeDisc({
    super.key,
    required this.fraction,
    required this.colour,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _BabySizeDiscPainter(fraction: fraction, colour: colour)),
      );
}

class _BabySizeDiscPainter extends CustomPainter {
  final double fraction;
  final Color colour;
  _BabySizeDiscPainter({required this.fraction, required this.colour});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final maxR = size.shortestSide / 2 - 1;
    // The term-size reference ring.
    canvas.drawCircle(
      centre,
      maxR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = colour.withValues(alpha: 0.30),
    );
    // This week, filled.
    canvas.drawCircle(
      centre,
      maxR * fraction.clamp(0.0, 1.0),
      Paint()..color = colour.withValues(alpha: 0.90),
    );
  }

  @override
  bool shouldRepaint(_BabySizeDiscPainter old) =>
      old.fraction != fraction || old.colour != colour;
}
