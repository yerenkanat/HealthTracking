/// The pregnancy hero — the top of the calendar when she is expecting.
///
/// WHAT THIS IS
///
/// A warm, illustrated header that answers the three things she opens the app
/// for: how far along am I, what does that look like, and how much is left.
/// The week number, an illustration that changes as the pregnancy does, and a
/// ring that fills toward the due date.
///
/// WHY IT IS DRAWN RATHER THAN SHIPPED AS IMAGES
///
/// Every frame here is painted from geometry. That is a deliberate choice, not
/// a limitation:
///
///   * it is OURS. The obvious shortcut for a screen like this is to lift the
///     artwork from an app that already has it, which would be someone else's
///     work in our binary;
///   * 40 weeks of raster art is megabytes of bundle for a screen most users
///     open once a day, and it has to exist at three densities;
///   * it interpolates. A drawing defined by numbers can change smoothly with
///     the week rather than snapping between 40 fixed pictures.
///
/// It is a warm, stylised silhouette — a curled figure — NOT an anatomical
/// diagram. This is a companion app, and a medical-looking rendering would
/// imply a precision no calendar-based estimate has.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/cycle_log.dart' show GestationInfo;
import '../theme.dart';

/// How the palette warms as the pregnancy progresses.
///
/// Each trimester gets its own backdrop, so the screen she opens in month
/// eight does not look identical to the one from week five. Kept close in
/// value — this sits behind text, and a hero that shouts is a hero she stops
/// reading.
({Color top, Color bottom, Color glow}) trimesterPalette(int trimester) =>
    switch (trimester) {
      1 => (top: const Color(0xFFFDF0F5), bottom: const Color(0xFFFBE7EF), glow: Palette.rose),
      2 => (top: const Color(0xFFFDEFE8), bottom: const Color(0xFFFAE6DC), glow: const Color(0xFFEE9B6E)),
      _ => (top: const Color(0xFFF3EEFC), bottom: const Color(0xFFEDE6FA), glow: Palette.violet),
    };

/// A curled figure, drawn from the week.
///
/// The proportions move with gestation rather than being 40 separate drawings:
/// the head is enormous early and settles toward a newborn's quarter-height by
/// term, and the limbs lengthen and uncurl. That is the shape of real growth,
/// and it means any week in between renders correctly without an asset for it.
class BabyPainter extends CustomPainter {
  /// Completed weeks. Clamped internally — a bad value must not throw inside a
  /// paint call, where the failure is a red screen rather than a wrong number.
  final int week;

  /// 0..1, drives the gentle breathing motion.
  final double phase;

  final Color body;
  final Color shade;

  const BabyPainter({
    required this.week,
    required this.phase,
    required this.body,
    required this.shade,
  });

  /// Head height as a share of the whole figure.
  ///
  /// About half at the start of the second month, a quarter at term. Real
  /// enough to read as growth without pretending to be a scan.
  static double headShareFor(int week) {
    final w = week.clamp(4, 40).toDouble();
    final t = ((w - 4) / 36).clamp(0.0, 1.0);
    return 0.50 - 0.22 * t;
  }

  /// How distinct the limbs are, 0 (indistinguishable from the body) to 1.
  ///
  /// This was "uncurl", straightening the limbs toward term — which is
  /// backwards. Limbs become defined through the first half and then stay
  /// FOLDED: there is less room by month eight, not more, and the splayed
  /// week-36 figure it produced looked like a starfish. What actually changes
  /// late is how filled-out the body is, which [headShareFor] carries.
  static double limbDefinitionFor(int week) {
    final w = week.clamp(4, 40).toDouble();
    return ((w - 8) / 14).clamp(0.0, 1.0);
  }

  /// The silhouette, authored once in a 100×100 box.
  ///
  /// Four parametric strokes for limbs was the first attempt and it read as
  /// two blobs — a curled figure is a single continuous contour, not a torso
  /// with sticks attached. This is that contour: crown, back, seat, folded
  /// legs, tucked arm, chin.
  ///
  /// [headShare] morphs it. The head circle scales about its own centre and the
  /// body scales against the opposite corner, so early weeks are head-dominant
  /// and later ones fill out, from one drawing rather than forty.
  /// The torso, folded legs and tucked arm — everything but the head.
  ///
  /// Separate from the head on purpose: see the note in [paint] about the
  /// notch. Kept public so a test can measure it.
  static Path bodyOnly(double headShare) {
    // 0.50 early → 0.28 at term. The first version made the head 21–24 units
    // against a body that barely grew, so the union came out as one amoeba
    // with a bump. The head is smaller and the body considerably larger now,
    // which is what gives a readable head-on-body silhouette at 190px.
    final bodyScale = 1.20 + (0.50 - headShare) * 1.85;

    // Body, drawn about a pivot just under the head so it grows downward and
    // to the right — the direction a curled figure actually extends.
    final body = Path()
      ..moveTo(52, 24) // nape
      ..cubicTo(68, 30, 76, 46, 72, 62) // back, curving right
      ..cubicTo(69, 74, 60, 82, 48, 84) // seat
      ..cubicTo(44, 85, 40, 84, 38, 81) // thigh, folding back up
      ..cubicTo(35, 76, 39, 71, 44, 69) // knee tucked in
      ..cubicTo(36, 70, 28, 66, 26, 58) // shin and heel toward the chest
      ..cubicTo(24, 51, 26, 44, 30, 40) // front of the torso
      ..close();

    // The tucked arm: a short curl in front of the chest.
    final arm = Path()
      ..moveTo(34, 48)
      ..cubicTo(42, 50, 48, 55, 47, 62)
      ..cubicTo(46, 67, 41, 68, 37, 65)
      ..cubicTo(34, 62, 33, 54, 34, 48)
      ..close();

    final m = Matrix4.identity()
      ..translate(44.0, 26.0)
      ..scale(bodyScale, bodyScale)
      ..translate(-44.0, -26.0);

    return Path.combine(PathOperation.union, body.transform(m.storage), arm.transform(m.storage));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = week.clamp(4, 40);
    final headShare = headShareFor(w);

    // Breathe: a slow rise and fall of a fraction of a percent. Enough to feel
    // alive, small enough that it never reads as a glitch.
    final breath = 1 + 0.012 * math.sin(phase * 2 * math.pi);

    final fill = Paint()
      ..color = body
      ..isAntiAlias = true;
    final shading = Paint()
      ..color = shade
      ..isAntiAlias = true;

    // The silhouette is authored in a 100x100 box; fit it to whatever we are
    // given, centred, with room for the breath.
    final side = math.min(size.width, size.height) * 0.86 * breath;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    // A curled figure lies at an angle rather than upright.
    canvas.rotate(-0.30);
    canvas.scale(side / 100);
    canvas.translate(-50, -52);

    final headR = 15.0 + 9.0 * ((headShare - 0.28) / 0.22).clamp(0.0, 1.0);
    const headC = Offset(34, 30);

    // On its own layer, so the notch below erases only the figure and lets the
    // backdrop show through. Cleared straight onto the canvas it punched a
    // white ring through the gradient.
    canvas.saveLayer(Rect.fromLTWH(-200, -200, 500, 500), Paint());

    // Body first, WITHOUT the head.
    canvas.drawPath(bodyOnly(headShare), fill);

    // Then a gap, then the head. Unioning the two into one outline was the
    // mistake behind four earlier attempts: head and torso merged into a
    // single mass and the figure read as an amoeba. A curled baby is legible
    // because the crown is separated from the shoulder — that notch is the
    // whole silhouette. Cutting it with a transparent stroke keeps the
    // separation on any backdrop.
    canvas.drawCircle(headC, headR + 2.2, Paint()..blendMode = BlendMode.clear);
    canvas.drawCircle(headC, headR, fill);

    // One soft highlight on the crown — the only shading, and enough to keep
    // the head reading as a sphere rather than a disc.
    canvas.drawCircle(headC + Offset(-headR * 0.30, -headR * 0.32), headR * 0.50, shading);

    canvas.restore(); // the notch layer

    canvas.restore();
  }
  @override
  bool shouldRepaint(BabyPainter old) =>
      old.week != week || old.phase != phase || old.body != body || old.shade != shade;
}

/// A soft radial wash behind the figure, so it sits in something rather than
/// floating on a flat panel.
class _GlowPainter extends CustomPainter {
  final Color colour;
  final double phase;
  const _GlowPainter(this.colour, this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height * 0.52);
    final r = math.min(size.width, size.height) * (0.52 + 0.015 * math.sin(phase * 2 * math.pi));
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [colour.withValues(alpha: 0.30), colour.withValues(alpha: 0.0)],
          stops: const [0.25, 1.0],
        ).createShader(Rect.fromCircle(center: centre, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.colour != colour || old.phase != phase;
}

/// The illustrated hero.
///
/// [reduceMotion] stops the loop entirely rather than slowing it. Someone who
/// has asked their phone to stop animating things is often asking because
/// motion makes them ill, and a gentler animation is still an animation.
class PregnancyHero extends StatefulWidget {
  final GestationInfo gestation;

  /// Localized strings, passed in so this widget carries no language.
  final String weekLabel; // "11 недель 3 дня"
  final String remainingLabel; // "осталось 202 дня"
  final String trimesterLabel; // "второй триместр"
  final String detailsLabel; // "Подробнее"
  final VoidCallback? onDetails;

  const PregnancyHero({
    super.key,
    required this.gestation,
    required this.weekLabel,
    required this.remainingLabel,
    required this.trimesterLabel,
    required this.detailsLabel,
    this.onDetails,
  });

  @override
  State<PregnancyHero> createState() => _PregnancyHeroState();
}

// TickerProviderStateMixin, not Single: there are two controllers here — the
// endless breath and the one-shot entry — and the single-ticker mixin asserts
// on the second.
class _PregnancyHeroState extends State<PregnancyHero> with TickerProviderStateMixin {
  /// The breath. Finite, not endless.
  ///
  /// It used to `repeat()` forever. That costs a frame every 16ms for as long
  /// as she leaves the screen open — on a screen people leave open — and it
  /// makes the widget untestable: pumpAndSettle waits for animations to finish
  /// and an endless one never does, so every existing test that settles this
  /// page hung.
  ///
  /// A handful of slow breaths on arrival says "alive" just as well as an
  /// infinite one, and then the screen is still.
  static const _breaths = 6;
  static const _breathPeriod = Duration(seconds: 6);

  late final AnimationController _loop;

  /// The ring fills once, on entry, rather than snapping to its value. The
  /// pregnancy did not happen instantly either.
  late final AnimationController _entry;

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(vsync: this, duration: _breathPeriod * _breaths);
    _entry = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in initState: MediaQuery is not available yet at
    // that point, and starting a loop we then have to stop is worse than not
    // starting it.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _loop.stop();
      _entry.value = 1;
    } else {
      if (_loop.status == AnimationStatus.dismissed) _loop.forward();
      if (_entry.status == AnimationStatus.dismissed) _entry.forward();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gestation;
    final pal = trimesterPalette(g.trimester);

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [pal.top, pal.bottom],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(
            // Wrap the content. A Column defaults to filling its parent, and
            // given loose constraints — anywhere but inside a fixed-height
            // slot — that left a tall band of empty gradient under the button
            // and overflowed when the space was short.
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 190,
                child: AnimatedBuilder(
                  animation: _loop,
                  builder: (context, _) {
                    // One controller pass covers every breath, so `t` counts
                    // whole cycles and lands back at rest when it finishes.
                    final t = _loop.value * _breaths;
                    // A slow vertical drift, in step with the breath. Eased out
                    // over the pass so the motion fades rather than stopping
                    // mid-rise.
                    final settle = 1 - Curves.easeInCubic.transform(_loop.value);
                    final dy = math.sin(t * 2 * math.pi) * 5 * settle;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: _GlowPainter(pal.glow, t)),
                        ),
                        Transform.translate(
                          offset: Offset(0, dy),
                          child: SizedBox(
                            width: 190,
                            height: 190,
                            child: CustomPaint(
                              painter: BabyPainter(
                                week: g.week,
                                phase: t,
                                body: pal.glow.withValues(alpha: 0.92),
                                shade: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.weekLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
              ),
              const SizedBox(height: 4),
              Text(
                widget.trimesterLabel,
                style: TextStyle(color: Palette.text.withValues(alpha: 0.55), fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              AnimatedBuilder(
                animation: _entry,
                builder: (context, _) => _ProgressBar(
                  fraction: g.progress * Curves.easeOutCubic.transform(_entry.value),
                  colour: pal.glow,
                  label: widget.remainingLabel,
                ),
              ),
              if (widget.onDetails != null) ...[
                const SizedBox(height: 14),
                _DetailsButton(label: widget.detailsLabel, onTap: widget.onDetails!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double fraction;
  final Color colour;
  final String label;
  const _ProgressBar({required this.fraction, required this.colour, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(color: Colors.white.withValues(alpha: 0.6)),
                FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colour,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: TextStyle(color: Palette.text.withValues(alpha: 0.6), fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _DetailsButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DetailsButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          // 48 high: the UI checklist minimum, which a pill this size is easy
          // to fall short of.
          constraints: const BoxConstraints(minHeight: 48, minWidth: 140),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Palette.text),
          ),
        ),
      ),
    );
  }
}
