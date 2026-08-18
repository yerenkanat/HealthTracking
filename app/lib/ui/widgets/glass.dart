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

  /// How much of the circle the [fraction] was computed over, 0..1 — or NULL
  /// when the ring is not a coverage ring (the water goal, the kick count:
  /// those have one denominator and it is never in doubt).
  ///
  /// THE SECOND HALF OF THE SAME RULING. Making the fraction nullable stopped
  /// the ring claiming a verdict on a day with NO gradeable metric; it did
  /// nothing about the day with SOME. `healthy / withData` over a pool the
  /// caller had already thinned still drew a complete circle from two cards of
  /// four — the everyday state of a band user, because a wrist temperature and
  /// a wrist blood pressure may not be graded at all. A ring computed from two
  /// of four and drawn as if from four is the same false completeness, one step
  /// milder and shipped far more often.
  ///
  /// So the share below 1.0 is painted as NOT ASSESSED — a dashed arc in
  /// ordinary ink — and the accent can only close the circle when everything
  /// was assessed. Ink and not [Palette.textDim] on the tiles' precedent:
  /// `MetricStatus.ungraded` renders in body ink exactly because dim ink is the
  /// STALE appearance, and «old» is a different claim from «not judged». Dashes
  /// and not a second colour: a solid second accent would be a verdict, and
  /// this is the absence of one.
  ///
  /// 0.0 dashes the whole circle. That is deliberately NOT the same picture as
  /// `fraction: 0.0`, which is every card assessed and every card concerning —
  /// before this the two drew an identical empty ring and differed only by the
  /// colour of the badge in the middle.
  final double? assessed;
  final Color color;
  final double size;
  final double stroke;
  final Widget? center;
  const MetricRing({
    super.key,
    required this.fraction,
    required this.color,
    this.assessed,
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
        painter: _RingPainter(
            f?.clamp(0.0, 1.0), color, stroke, assessed?.clamp(0.0, 1.0)),
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

  /// Null = the whole circle is assessed, which is what every ring that is not
  /// a health verdict wants. See [MetricRing.assessed].
  final double? assessed;
  _RingPainter(this.fraction, this.color, this.stroke, this.assessed);

  /// The arc starts at twelve o'clock and runs clockwise, so the assessed share
  /// is measured from there and whatever is left over is the not-assessed one.
  static const _twelve = -math.pi / 2;

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

    // The share of the circle nothing may be claimed about, drawn before the
    // accent so a rounded arc cap laps over the first dash rather than under
    // it.
    final cover = assessed;
    if (cover != null && cover < 1) {
      _dashes(canvas, center, radius, _twelve + 2 * math.pi * cover,
          2 * math.pi * (1 - cover));
    }

    // Nothing to grade → the track, the dashes, and no arc. Returning before
    // the accent is what makes "no data" unpaintable as a reassurance: there is
    // no fraction to round up, and no accent on screen to read a verdict off.
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
      _twelve,
      // Over the assessed share of the circle, not over the whole of it: the
      // arithmetic that made a partial pool look complete was doing exactly
      // this multiplication with `cover` silently equal to 1.
      2 * math.pi * f * (cover ?? 1),
      false,
      arc,
    );
  }

  /// «Not assessed», as a texture rather than a colour.
  ///
  /// A dash roughly every 9dp of circumference: short enough to read as broken
  /// at the 74dp the peace ring is drawn at, long enough not to turn into a
  /// grey haze on a low-density screen. Butt caps, because a round cap on a
  /// 4dp dash is a dot.
  void _dashes(
      Canvas canvas, Offset center, double radius, double from, double sweep) {
    if (radius <= 0 || sweep <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      // Body ink, the colour this app uses when it is NOT judging — the same
      // reasoning as `MetricStatus.ungraded` on the tiles, which is deliberately
      // not the dim ink that means stale.
      ..color = Palette.text;
    final dash = 5 / radius, gap = 4 / radius;
    for (var a = from; a < from + sweep; a += dash + gap) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), a,
          math.min(dash, from + sweep - a), false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.assessed != assessed;
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
