/// The app's shared surfaces, in the Ana-Bala design system.
///
/// These four widgets are what most screens are actually built from — 60
/// `GlassCard`s across 26 files — so converting them is what moves the app to
/// the new look, rather than editing each screen. The class names are
/// deliberately unchanged: renaming them would have buried a visual change in a
/// 26-file rename, and `GlassCard` is still the app's card.
///
/// See `../design_system.dart` for the tokens and the reasoning. The two rules
/// that matter here:
///
///  * the 2px ink outline IS the elevation model — no soft shadows anywhere;
///  * the hard 4px offset means "primary", so it is opt-in, not the default.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../design_system.dart';
import '../theme.dart';

/// The app canvas: flat cream.
///
/// It used to carry two large radial tints in the corners. The design system
/// has no gradients at all (the lock screen is the single exception), and on a
/// cream ground those washes muddied the pastel cards that sit on top of them.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: Ds.cream, child: child);
  }
}

/// The app's card: white, 2px ink outline, 24px radius.
///
/// [glow] used to tint a soft drop shadow. There are no soft shadows now, so it
/// is reinterpreted rather than removed from ~60 call sites: passing any colour
/// marks the card as the primary one and gives it the hard offset step. Prefer
/// [DsCard] in new code, which says `raised: true` outright.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Any non-null value now means "this is the primary card" — see above.
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
        color: Colors.white,
        borderRadius: DsShape.card,
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        boxShadow: glow == null ? null : DsShape.hardShadow,
      ),
      child: ClipRRect(
        // Inset by the border so the ripple cannot paint over the outline.
        borderRadius: BorderRadius.circular(DsShape.radiusCard - DsShape.borderWidth),
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

/// Circular progress ring.
///
/// The sweep is a flat accent now rather than a gradient — the system has none.
/// [gradient] is kept in the signature because six call sites pass one; its
/// first colour is used and the ramp is ignored.
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
      ..color = Ds.divider
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    // Flat accent, not a sweep: take the gradient's first stop and drop the ramp.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = gradient.colors.isEmpty ? Ds.coralCta : gradient.colors.first;
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

/// A status pill: the accent at a light tint, outlined in ink.
///
/// The label is drawn in [darkenForText] of the accent rather than the accent
/// itself. These sit at 12–20% tint, exactly the case where the bright
/// swatches measure around 3:1 — the accessibility suite failed on this shape
/// across the app before the tokens grew text-safe variants.
class TonePill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const TonePill(this.label, this.color, {super.key, this.icon});
  @override
  Widget build(BuildContext context) {
    final ink = darkenForText(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: DsShape.pill,
        border: Border.all(color: Ds.ink, width: 1.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: ink), const SizedBox(width: 5)],
        Text(label, style: context.ds.micro(color: ink, size: 12).copyWith(letterSpacing: 0.2)),
      ]),
    );
  }
}
