/// One week of the pregnancy, in detail.
///
/// The destination for "Подробнее" on the hero. Everything the app already
/// knows about this week, in one place: how big the baby is, where she is on
/// the 40-week clock, what milestone is next, and the content the back-office
/// published for this stage.
///
/// Deliberately assembled from what exists rather than inventing new medical
/// copy. The size comparison, the milestone table and the timeline catalogue
/// are each already owned, tested and localized elsewhere; a screen that
/// restated them in its own words would be a fourth source of truth about the
/// same week.
library;

import 'package:flutter/material.dart';

import '../../domain/baby_size.dart';
import '../../domain/cycle_log.dart' show GestationInfo;
import '../../domain/pregnancy_milestones.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import 'pregnancy_hero.dart' show BabyPainter, trimesterPalette;

class WeekDetailScreen extends StatelessWidget {
  final GestationInfo gestation;
  const WeekDetailScreen({super.key, required this.gestation});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final g = gestation;
    final pal = trimesterPalette(g.trimester);
    final size = babySizeFor(g.week);
    final current = currentMilestone(g.week);
    final next = nextMilestone(g.week);

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        title: Text(l.t('gest_week', {'w': g.week, 'd': g.dayOfWeek})),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // The same figure as the hero, at rest. Repeating it is deliberate:
          // it is how she knows this screen is about the same thing she tapped.
          Container(
            height: 170,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [pal.top, pal.bottom],
              ),
            ),
            child: Center(
              child: SizedBox(
                width: 150,
                height: 150,
                child: CustomPaint(
                  painter: BabyPainter(
                    week: g.week,
                    phase: 0,
                    body: pal.glow.withValues(alpha: 0.92),
                    shade: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (size != null)
            _Card(
              title: l.t('bsize_title'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      l.t(size.code),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    l.t('bsize_length', {'cm': size.lengthCm.toStringAsFixed(1)}),
                    style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Palette.violet),
                  ),
                ],
              ),
            ),

          _Card(
            title: l.t('gest_trimester', {'n': g.trimester}),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t(current.code),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                _Progress(fraction: g.progress, colour: pal.glow),
                const SizedBox(height: 8),
                Text(
                  g.daysUntilDue >= 0
                      ? l.t('gest_days_left', {'n': g.daysUntilDue})
                      : l.t('gest_overdue'),
                  style: const TextStyle(color: Palette.textDim, fontSize: 13),
                ),
              ],
            ),
          ),

          if (next != null)
            _Card(
              title: l.t('ms_next'),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Palette.violet.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.flag_outlined, size: 19, color: Palette.violet),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.t(next.code),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          l.t('ms_in_weeks', {'n': weeksUntil(g.week, next)}),
                          style: const TextStyle(color: Palette.textDim, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // The one thing this screen says in its own voice, and it says the
          // same thing every other estimate in the app says.
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.t('gest_estimate_note'),
              style: const TextStyle(color: Palette.textDim, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    color: Palette.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );
}

class _Progress extends StatelessWidget {
  final double fraction;
  final Color colour;
  const _Progress({required this.fraction, required this.colour});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          height: 8,
          child: Stack(children: [
            Container(color: Palette.glass),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(color: colour),
            ),
          ]),
        ),
      );
}
