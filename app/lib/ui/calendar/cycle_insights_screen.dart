/// Cycle insights — analytics over the user's logged data: average cycle/period
/// length, cycles tracked, a recent-cycle history, and the moods & symptoms they
/// log most. Opened from the calendar (cycle mode). Pure presentation over the
/// verified cycle_insights logic.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../domain/cycle_insights.dart';
import '../../domain/cycle_log.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class CycleInsightsScreen extends StatelessWidget {
  final AppController controller;
  final DateTime Function()? _nowFn;
  const CycleInsightsScreen({super.key, required this.controller, DateTime Function()? now}) : _nowFn = now;

  DateTime _now() => (_nowFn ?? DateTime.now)();

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
            final logs = controller.dayLogs.values;
            final moods = moodFrequency(logs);
            final symptoms = symptomFrequency(logs);
            final since = _now().subtract(const Duration(days: 7));
            final thisWeek = symptomFrequencySince(logs, since);
            final moodsWeek = moodFrequencySince(logs, since);
            final streak = loggingStreak(logs, _now());
            final notes = recentNotes(logs);

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
                        _FreqRow(label: l.t('sym_${s.symptom.name}'), count: s.count, color: Palette.amber),
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

                if (symptoms.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: l.t('cyc_top_symptoms'),
                    child: Column(children: [
                      for (final s in symptoms.take(4))
                        _FreqRow(label: l.t('sym_${s.symptom.name}'), count: s.count, color: Palette.roseDeep),
                    ]),
                  ),
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

class _FreqRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _FreqRow({required this.label, required this.count, required this.color});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
          Text(l.t('cyc_times', {'n': count}),
              style: const TextStyle(fontFamily: 'JetBrainsMono', color: Palette.textDim, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
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
