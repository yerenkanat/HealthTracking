/// Cycle insights — analytics over the user's logged data: average cycle/period
/// length, cycles tracked, a recent-cycle history, and the moods & symptoms they
/// log most. Opened from the calendar (cycle mode). Pure presentation over the
/// verified cycle_insights logic.
library;

import 'package:flutter/material.dart' hide Flow;
import '../../app/app_controller.dart';
import '../../domain/cycle_insights.dart';
import '../../domain/cycle_log.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'notes_browser_screen.dart';
import 'symptom_days_screen.dart';

class CycleInsightsScreen extends StatelessWidget {
  final AppController controller;
  final DateTime Function()? _nowFn;
  const CycleInsightsScreen({super.key, required this.controller, DateTime Function()? now}) : _nowFn = now;

  DateTime _now() => (_nowFn ?? DateTime.now)();

  void _openSymptom(BuildContext context, List<DayLog> logs, Symptom symptom) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SymptomDaysScreen(logs: logs, symptom: symptom, controller: controller),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('cyc_insights_title'))),
        body: StreamBuilder<void>(
          stream: controller.changes,
          builder: (context, _) {
            final info = controller.cycle;
            final history = cycleHistory(controller.periodDays);
            final regularity = cycleRegularity(history);
            final lengthStats = cycleLengthStats(history);
            final logs = controller.dayLogs.values;
            final moods = moodFrequency(logs);
            final symptoms = symptomFrequency(logs);
            final since = _now().subtract(const Duration(days: 7));
            final thisWeek = symptomFrequencySince(logs, since);
            final moodsWeek = moodFrequencySince(logs, since);
            final streak = loggingStreak(logs, _now());
            final allNotes = searchNotes(logs, '');
            final notes = allNotes.take(5).toList();

            if (!info.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(l.t('cyc_insights_empty'),
                      textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                // Stats header
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Palette.rose.withValues(alpha: 0.14), Palette.violet.withValues(alpha: 0.06)],
                    ),
                    border: Border.all(color: Palette.rose.withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _Stat(value: '${info.avgCycleLength}', unit: l.t('cyc_days_short', {'n': ''}).trim(), label: l.t('cyc_avg_cycle_stat'))),
                      Container(width: 1, height: 40, color: Palette.border),
                      Expanded(child: _Stat(value: '${info.avgPeriodLength}', unit: l.t('cyc_days_short', {'n': ''}).trim(), label: l.t('cyc_avg_period_stat'))),
                      Container(width: 1, height: 40, color: Palette.border),
                      Expanded(child: _Stat(value: '${history.length}', unit: '', label: l.t('cyc_cycles_tracked'))),
                    ],
                  ),
                ),
                if (streak >= 2) ...[
                  const SizedBox(height: 14),
                  _StreakBanner(days: streak),
                ],
                if (regularity.level != CycleRegularity.insufficient) ...[
                  const SizedBox(height: 14),
                  _RegularityCard(insight: regularity),
                ],
                if (lengthStats != null && lengthStats.count >= 2) ...[
                  const SizedBox(height: 14),
                  _CycleLengthCard(stats: lengthStats),
                ],
                if (totalFlowDays(logs) > 0) ...[
                  const SizedBox(height: 14),
                  _FlowBreakdownCard(breakdown: flowBreakdown(logs), total: totalFlowDays(logs)),
                ],
                const SizedBox(height: 16),

                // Cycle history
                _SectionCard(
                  title: l.t('cyc_history'),
                  child: Column(
                    children: [
                      for (var i = 0; i < history.length && i < 8; i++) ...[
                        if (i > 0) const _ThinDivider(),
                        _CycleRow(span: history[i]),
                      ],
                    ],
                  ),
                ),

                if (thisWeek.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: l.t('cyc_this_week'),
                    child: Column(children: [
                      for (final s in thisWeek.take(4))
                        _FreqRow(
                          label: l.t('sym_${s.symptom.name}'),
                          count: s.count,
                          color: Palette.amber,
                          onTap: () => _openSymptom(context, logs.toList(), s.symptom),
                        ),
                    ]),
                  ),
                ],

                if (moodsWeek.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: l.t('cyc_mood_week'),
                    child: Column(children: [
                      for (final m in moodsWeek.take(4))
                        _FreqRow(label: l.t('mood_${m.mood.name}'), count: m.count, color: Palette.teal),
                    ]),
                  ),
                ],

                if (moodTrend(logs, _now()).any((w) => w.mood != null)) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: l.t('cyc_mood_trend'),
                    child: _MoodTrendStrip(weeks: moodTrend(logs, _now())),
                  ),
                ],

                if (symptoms.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: l.t('cyc_top_symptoms'),
                    child: Column(children: [
                      for (final s in symptoms.take(4))
                        _FreqRow(
                          label: l.t('sym_${s.symptom.name}'),
                          count: s.count,
                          color: Palette.roseDeep,
                          onTap: () => _openSymptom(context, logs.toList(), s.symptom),
                        ),
                    ]),
                  ),
                ],

                if (topSymptomPhase(logs, controller.periodDays) case final insight?) ...[
                  const SizedBox(height: 16),
                  _SymptomPhaseCard(insight: insight),
                ],

                if (moods.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: l.t('cyc_top_moods'),
                    child: Column(children: [
                      for (final m in moods.take(4))
                        _FreqRow(label: l.t('mood_${m.mood.name}'), count: m.count, color: Palette.violet),
                    ]),
                  ),
                ],

                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: l.t('cyc_recent_notes'),
                    child: Column(children: [
                      for (var i = 0; i < notes.length; i++) ...[
                        if (i > 0) const _ThinDivider(),
                        _NoteRow(log: notes[i]),
                      ],
                      const _ThinDivider(),
                      _SeeAllNotesRow(
                        label: l.t('notes_see_all', {'n': '${allNotes.length}'}),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => NotesBrowserScreen(logs: logs.toList(), controller: controller),
                        )),
                      ),
                    ]),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String unit;
  final String label;
  const _Stat({required this.value, required this.unit, required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      RichText(
        text: TextSpan(
          text: value,
          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 22, fontWeight: FontWeight.w700, color: Palette.text),
          children: [if (unit.isNotEmpty) TextSpan(text: ' $unit', style: const TextStyle(fontSize: 12, color: Palette.textDim))],
        ),
      ),
      const SizedBox(height: 3),
      Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, fontSize: 11.5)),
    ]);
  }
}

/// A motivational logging-streak banner.
class _StreakBanner extends StatelessWidget {
  final int days;
  const _StreakBanner({required this.days});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return GlassCard(
      glow: Palette.amber,
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Palette.amber, Palette.roseDeep]), shape: BoxShape.circle),
            child: const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('cyc_streak', {'n': days}), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.amber)),
                const SizedBox(height: 2),
                Text(l.t('cyc_streak_sub'), style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Your cycles are regular / vary by N days" — a plain-language read on
/// "Your cramps most often appear in the luteal phase" — a data-driven pattern
/// linking the user's most-logged symptom to the phase it clusters in.
class _SymptomPhaseCard extends StatelessWidget {
  final SymptomPhaseInsight insight;
  const _SymptomPhaseCard({required this.insight});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final phaseName = l.t('phase_${insight.phase.name}');
    final symptomName = l.t('sym_${insight.symptom.name}');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.violet.withValues(alpha: 0.10), Palette.roseDeep.withValues(alpha: 0.05)],
        ),
        border: Border.all(color: Palette.violet.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: Palette.violet.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.insights_rounded, color: Palette.violet, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('cyc_sym_phase_title').toUpperCase(),
                    style: const TextStyle(color: Palette.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                const SizedBox(height: 4),
                Text(l.t('cyc_sym_phase_body', {'symptom': symptomName, 'phase': phaseName}),
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Palette.text, height: 1.3)),
                const SizedBox(height: 3),
                Text(l.t('cyc_sym_phase_count', {'n': insight.count, 'total': insight.total}),
                    style: const TextStyle(color: Palette.textDim, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How the user's bleeding days split across light / medium / heavy — a stacked
/// bar plus per-level day counts.
class _FlowBreakdownCard extends StatelessWidget {
  final List<({Flow flow, int count})> breakdown;
  final int total;
  const _FlowBreakdownCard({required this.breakdown, required this.total});

  static Color _color(Flow f) => switch (f) {
        Flow.light => Palette.rose,
        Flow.medium => Palette.roseDeep,
        Flow.heavy => Palette.violet,
      };

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return _SectionCard(
      title: l.t('cyc_flow_title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stacked proportion bar.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (final e in breakdown)
                    if (e.count > 0) Expanded(flex: e.count, child: ColoredBox(color: _color(e.flow))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final e in breakdown)
            if (e.count > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: _color(e.flow), shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(l.t('flow_${e.flow.name}'),
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                  Text(l.t('cyc_flow_days', {'n': e.count}),
                      style: const TextStyle(fontFamily: 'JetBrainsMono', color: Palette.textDim, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
          const SizedBox(height: 6),
          Text(l.t('cyc_flow_total', {'n': total}),
              style: const TextStyle(color: Palette.textDim, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Min / average / max cycle length over the user's completed cycles.
class _CycleLengthCard extends StatelessWidget {
  final CycleLengthStats stats;
  const _CycleLengthCard({required this.stats});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return _SectionCard(
      title: l.t('cyc_length_range'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LenStat(value: '${stats.min}', label: l.t('cyc_len_shortest'), color: Palette.teal),
              _lenDivider(),
              _LenStat(value: '${stats.avg}', label: l.t('cyc_len_average'), color: Palette.roseDeep),
              _lenDivider(),
              _LenStat(value: '${stats.max}', label: l.t('cyc_len_longest'), color: Palette.violet),
            ],
          ),
          const SizedBox(height: 8),
          Text(l.t('cyc_len_based_on', {'n': stats.count}),
              style: const TextStyle(color: Palette.textDim, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _lenDivider() => Container(width: 1, height: 34, color: Palette.border);
}

class _LenStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _LenStat({required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            RichText(
              text: TextSpan(children: [
                TextSpan(text: value, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 22, fontWeight: FontWeight.w700, color: color)),
              ]),
            ),
            const SizedBox(height: 3),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, fontSize: 11.5)),
          ],
        ),
      );
}

/// consistency, coloured by level (green regular, amber variable, rose irregular).
class _RegularityCard extends StatelessWidget {
  final RegularityInsight insight;
  const _RegularityCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final (accent, icon, headline) = switch (insight.level) {
      CycleRegularity.regular => (Palette.good, Icons.check_circle_rounded, l.t('cyc_reg_regular')),
      CycleRegularity.variable => (Palette.amber, Icons.timeline_rounded, l.t('cyc_reg_variable')),
      CycleRegularity.irregular => (Palette.roseDeep, Icons.show_chart_rounded, l.t('cyc_reg_irregular')),
      CycleRegularity.insufficient => (Palette.textDim, Icons.hourglass_empty_rounded, ''),
    };
    return GlassCard(
      glow: accent,
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: accent)),
                const SizedBox(height: 2),
                Text(
                  l.t('cyc_reg_sub', {'var': insight.variationDays, 'avg': insight.avgCycle}),
                  style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _CycleRow extends StatelessWidget {
  final CycleSpan span;
  const _CycleRow({required this.span});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ml = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Palette.roseDeep, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ml.formatMediumDate(span.start), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(l.t('cyc_period_len', {'n': span.periodLength}), style: const TextStyle(color: Palette.textDim, fontSize: 12)),
              ],
            ),
          ),
          Text(
            span.cycleLength == null ? l.t('cyc_ongoing') : l.t('cyc_days_short', {'n': span.cycleLength}),
            style: TextStyle(
              fontFamily: span.cycleLength == null ? null : 'JetBrainsMono',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: span.cycleLength == null ? Palette.teal : Palette.text,
            ),
          ),
        ],
      ),
    );
  }
}

Color moodColor(Mood m) => switch (m) {
      Mood.happy => Palette.amber,
      Mood.calm => Palette.teal,
      Mood.anxious => Palette.violet,
      Mood.tired => Palette.blue,
      Mood.sad => Palette.roseDeep,
    };

/// A compact per-week mood timeline: one dot per week (oldest → newest), each
/// coloured by that week's dominant mood, with the current week ringed.
class _MoodTrendStrip extends StatelessWidget {
  final List<MoodWeek> weeks;
  const _MoodTrendStrip({required this.weeks});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < weeks.length; i++)
              _MoodDot(week: weeks[i], isCurrent: i == weeks.length - 1),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l.t('cyc_weeks_ago', {'n': weeks.length - 1}),
                style: const TextStyle(color: Palette.textDim, fontSize: 11)),
            Text(l.t('cyc_this_week_short'), style: const TextStyle(color: Palette.textDim, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class _MoodDot extends StatelessWidget {
  final MoodWeek week;
  final bool isCurrent;
  const _MoodDot({required this.week, required this.isCurrent});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final mood = week.mood;
    final color = mood == null ? Palette.border : moodColor(mood);
    return Semantics(
      label: mood == null ? null : l.t('mood_${mood.name}'),
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: mood == null ? Palette.glass : color.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: isCurrent ? color : Colors.transparent, width: 2),
        ),
        child: Center(
          child: Container(
            width: 12, height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _FreqRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final VoidCallback? onTap;
  const _FreqRow({required this.label, required this.count, required this.color, this.onTap});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
          Text(l.t('cyc_times', {'n': count}),
              style: const TextStyle(fontFamily: 'JetBrainsMono', color: Palette.textDim, fontSize: 13, fontWeight: FontWeight.w700)),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 18, color: Palette.textDim),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: row);
  }
}

class _NoteRow extends StatelessWidget {
  final DayLog log;
  const _NoteRow({required this.log});
  @override
  Widget build(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    final date = DateTime.tryParse(log.date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date == null ? log.date : ml.formatMediumDate(date),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Palette.roseDeep)),
          const SizedBox(height: 2),
          Text(log.note, style: const TextStyle(fontSize: 14, color: Palette.text, height: 1.3)),
        ],
      ),
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();
  @override
  Widget build(BuildContext context) => const Divider(height: 12, color: Palette.border);
}

class _SeeAllNotesRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SeeAllNotesRow({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const Icon(Icons.search_rounded, size: 18, color: Palette.roseDeep),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Palette.roseDeep))),
          const Icon(Icons.chevron_right_rounded, size: 20, color: Palette.roseDeep),
        ]),
      ),
    );
  }
}
