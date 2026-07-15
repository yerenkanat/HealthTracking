/// Lightweight sparkline (CustomPainter, no external chart dependency).
/// Renders a metric series with an optional shaded danger band and an emphasized
/// latest point. dataviz principles: one hue per series, danger in a muted red so
/// it reads as "zone" not "alarm", latest point highlighted for glanceability.
library;

import 'package:flutter/material.dart';
import '../../domain/health_series.dart';

class Sparkline extends StatelessWidget {
  final List<SeriesPoint> points;
  final MetricBand band;
  final Color color;
  final bool inDanger;

  const Sparkline({
    super.key,
    required this.points,
    required this.band,
    required this.color,
    this.inDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparkPainter(points, band, color, inDanger),
      size: const Size(double.infinity, 48),
      child: const SizedBox(height: 48, width: double.infinity),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<SeriesPoint> points;
  final MetricBand band;
  final Color color;
  final bool inDanger;
  _SparkPainter(this.points, this.band, this.color, this.inDanger);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    var lo = points.first.value, hi = points.first.value;
    for (final p in points) {
      if (p.value < lo) lo = p.value;
      if (p.value > hi) hi = p.value;
    }
    // Include danger threshold in the range so the band is visible.
    if (band.warnAbove != null) hi = hi > band.warnAbove! ? hi : band.warnAbove!;
    if (band.warnBelow != null) lo = lo < band.warnBelow! ? lo : band.warnBelow!;
    final range = (hi - lo).abs() < 1e-6 ? 1.0 : hi - lo;

    double x(int i) => size.width * i / (points.length - 1);
    double y(double v) => size.height - ((v - lo) / range) * size.height;

    // Danger band shading.
    final bandPaint = Paint()..color = const Color(0x22E5484D);
    if (band.warnAbove != null) {
      canvas.drawRect(Rect.fromLTRB(0, 0, size.width, y(band.warnAbove!)), bandPaint);
    }
    if (band.warnBelow != null) {
      canvas.drawRect(Rect.fromLTRB(0, y(band.warnBelow!), size.width, size.height), bandPaint);
    }

    // Line.
    final path = Path()..moveTo(x(0), y(points[0].value));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(x(i), y(points[i].value));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    // Latest point emphasized (red if in danger).
    final last = Offset(x(points.length - 1), y(points.last.value));
    canvas.drawCircle(last, 3.5, Paint()..color = inDanger ? const Color(0xFFE5484D) : color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.points != points || old.inDanger != inDanger || old.color != color;
}
