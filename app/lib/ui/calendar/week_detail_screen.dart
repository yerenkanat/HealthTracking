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
import '../../domain/pregnancy_guide.dart';
import '../../domain/pregnancy_milestones.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import 'baby_size_disc.dart';
import 'pregnancy_hero.dart' show BabyPainter, trimesterPalette;
import 'pregnancy_warnings.dart';

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
                children: [
                  // A disc that grows week to week against a faint ring at
                  // newborn size — the visceral "how big now" the fruit name
                  // alone can't give, and a picture of the journey's progress.
                  BabySizeDisc(fraction: sizeVisualFraction(size.lengthCm), colour: pal.glow),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.t(size.code),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l.t('bsize_length', {'cm': size.lengthCm.toStringAsFixed(1)}),
                          style: const TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Palette.violet),
                        ),
                      ],
                    ),
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

          // Everything above is about the baby. This is about HER: what she
          // might be feeling this week, and the signs that mean call now.
          _ExpectCard(week: g.week),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: PregnancyWarningsCard(),
          ),

          // The one thing this screen says in its own voice, and it says the
          // same thing every other estimate in the app says.
          Padding(
            padding: const EdgeInsets.only(top: 12),
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

IconData _areaIcon(PregnancyArea area) => switch (area) {
      PregnancyArea.body => Icons.self_improvement_outlined,
      PregnancyArea.comfort => Icons.spa_outlined,
      PregnancyArea.movement => Icons.child_care_outlined,
      PregnancyArea.mind => Icons.favorite_outline,
    };

Color _areaColour(PregnancyArea area) => switch (area) {
      PregnancyArea.body => Palette.teal,
      PregnancyArea.comfort => Palette.rose,
      PregnancyArea.movement => Palette.violet,
      PregnancyArea.mind => Palette.roseDeep,
    };

String _areaLabel(dynamic l, PregnancyArea area) => switch (area) {
      PregnancyArea.body => l.t('preg_area_body'),
      PregnancyArea.comfort => l.t('preg_area_comfort'),
      PregnancyArea.movement => l.t('preg_area_movement'),
      PregnancyArea.mind => l.t('preg_area_mind'),
    };

/// "How you may feel" — the stage notes for this week, badged by thread.
class _ExpectCard extends StatelessWidget {
  final int week;
  const _ExpectCard({required this.week});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final notes = notesForWeek(week);
    if (notes.isEmpty) return const SizedBox.shrink();
    return _Card(
      title: l.t('preg_expect_title'),
      child: Column(
        children: [
          for (var i = 0; i < notes.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _NoteRow(note: notes[i]),
          ],
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  final StageNote note;
  const _NoteRow({required this.note});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final colour = _areaColour(note.area);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_areaIcon(note.area), size: 17, color: colour),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_areaLabel(l, note.area),
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: colour)),
              const SizedBox(height: 2),
              Text(l.t('preg_note_${note.id}'),
                  style: const TextStyle(fontSize: 13, height: 1.42)),
            ],
          ),
        ),
      ],
    );
  }
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
