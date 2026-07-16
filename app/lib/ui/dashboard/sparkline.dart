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
  final bool smooth;

  const Sparkline({
    super.key,
    required this.points,
    required this.band,
    required this.color,
    this.inDanger = false,
    this.smooth = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparkPainter(points, band, color, inDanger, smooth),
      size: const Size(double.infinity, 48),
      child: const SizedBox(height: 48, width: double.infinity),
    );
  }
}

/// Build a smoothed path through [pts] using Catmull-Rom → cubic-Bézier control
/// points (tension 1/6). Anti-aliased, no overshoot spikes — the "soft wave"
/// look. Falls back to straight segments when [smooth] is false or < 3 points.
Path buildSplinePath(List<Offset> pts, {bool smooth = true}) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length < 3 || !smooth) {
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    return path;
  }
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = i == 0 ? pts[0] : pts[i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
    final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
    final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

class _SparkPainter extends CustomPainter {
  final List<SeriesPoint> points;
  final MetricBand band;
  final Color color;
  final bool inDanger;
  final bool smooth;
  _SparkPainter(this.points, this.band, this.color, this.inDanger, this.smooth);

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
    // Breathing room so the smoothed curve doesn't clip the top/bottom edge.
    final pad = (hi - lo).abs() < 1e-6 ? 1.0 : (hi - lo) * 0.12;
    lo -= pad;
    hi += pad;
    final range = (hi - lo).abs() < 1e-6 ? 1.0 : hi - lo;

    double x(int i) => size.width * i / (points.length - 1);
    double y(double v) => size.height - ((v - lo) / range) * size.height;

    // Danger band shading.
    final bandPaint = Paint()..color = const Color(0x1FE5484D);
    if (band.warnAbove != null) {
      canvas.drawRect(Rect.fromLTRB(0, 0, size.width, y(band.warnAbove!)), bandPaint);
    }
    if (band.warnBelow != null) {
      canvas.drawRect(Rect.fromLTRB(0, y(band.warnBelow!), size.width, size.height), bandPaint);
    }

    final offsets = [for (var i = 0; i < points.length; i++) Offset(x(i), y(points[i].value))];
    final path = buildSplinePath(offsets, smooth: smooth);

    // Soft area fill under the curve for a refined, premium look.
    final area = Path.from(path)
      ..lineTo(x(points.length - 1), size.height)
      ..lineTo(x(0), size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    // Latest point emphasized with a soft halo.
    final last = Offset(x(points.length - 1), y(points.last.value));
    canvas.drawCircle(last, 5, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawCircle(last, 3, Paint()..color = color);
    canvas.drawCircle(last, 1.4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.points != points || old.inDanger != inDanger || old.color != color || old.smooth != smooth;
}
