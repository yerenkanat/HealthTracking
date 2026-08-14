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
/// Circular progress ring, in a flat accent.
///
/// This took a [Gradient] and swept it around the arc. The design system has no
/// gradients, so the parameter is a plain [color] — keeping a Gradient argument
/// that only ever contributed its first stop would have been a lie in the API.
class MetricRing extends StatelessWidget {
  /// How much of the ring is filled, 0..1 — or NULL for «there was nothing to
  /// measure this against».
  ///
  /// Nullable on a clinical ruling, and the type is the ruling. The health
  /// dashboard computed `withData == 0 ? 1.0 : healthy / withData`, so a day on
  /// which NOTHING could be graded drew a complete ring: the most confident
  /// shape the screen owns, asserting that everything checked is fine, on a day
  /// when nothing was checked. That 1.0 looked like a display default and was
  /// an assertion. A default that must be chosen is a default that will be
  /// chosen wrong again, so "nothing to grade" is now a state in the type
  /// rather than a number that happens to mean it — a caller cannot fall into
  /// it by accident, it has to say `null`.
  ///
  /// Null paints the track and NO arc, in no accent at all. Not a grey full
  /// ring: a full ring is still read as "all good" at a glance, on a small
  /// screen, by a frightened reader. The words that explain it belong to the
  /// caller, in the semantics tree as well as in paint.
  final double? fraction;
  final Color color;
  final double size;
  final double stroke;
  final Widget? center;
  const MetricRing({
    super.key,
    required this.fraction,
    required this.color,
    this.size = 120,
    this.stroke = 10,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    final f = fraction;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(f?.clamp(0.0, 1.0), color, stroke),
        child: Center(child: center),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  /// Null = draw the track only. See [MetricRing.fraction].
  final double? fraction;
  final Color color;
  final double stroke;
  _RingPainter(this.fraction, this.color, this.stroke);

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

    // Nothing to grade → the empty track and nothing else. Returning before the
    // arc is what makes "no data" unpaintable as a reassurance: there is no
    // fraction to round up, and no accent on screen to read a verdict off.
    final f = fraction;
    if (f == null) return;

    // Flat accent, not a sweep: take the gradient's first stop and drop the ramp.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * f,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
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
