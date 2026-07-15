/// Reusable high-tech visual components: glass cards, gradient backdrop, a metric
/// ring gauge, and a glowing sparkline. Shared across the redesigned screens.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// A soft space-gradient background with faint colored glows — the app backdrop.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Palette.bg),
      child: Stack(
        children: [
          Positioned(top: -120, left: -80, child: _glow(Palette.violet, 300)),
          Positioned(top: 120, right: -100, child: _glow(Palette.pink, 260)),
          Positioned(bottom: -140, left: -40, child: _glow(Palette.teal, 280)),
          child,
        ],
      ),
    );
  }

  Widget _glow(Color c, double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c.withValues(alpha: 0.22), c.withValues(alpha: 0.0)]),
          ),
        ),
      );
}

/// Frosted glass card: translucent fill, hairline border, rounded, optional glow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? glow;
  final VoidCallback? onTap;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.glow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.glass,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Palette.border),
        boxShadow: glow == null
            ? null
            : [BoxShadow(color: glow!.withValues(alpha: 0.25), blurRadius: 28, spreadRadius: -6)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Circular progress ring with a gradient sweep — for a single metric.
class MetricRing extends StatelessWidget {
  final double fraction; // 0..1
  final Gradient gradient;
  final double size;
  final double stroke;
  final Widget? center;
  const MetricRing({
    super.key,
    required this.fraction,
    required this.gradient,
    this.size = 120,
    this.stroke = 10,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(fraction.clamp(0, 1), gradient, stroke),
        child: Center(child: center),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Gradient gradient;
  final double stroke;
  _RingPainter(this.fraction, this.gradient, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.width - stroke) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Palette.border
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = gradient.createShader(rect);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction;
}

/// A pill badge (status/tone).
class TonePill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const TonePill(this.label, this.color, {super.key, this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 5)],
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}
