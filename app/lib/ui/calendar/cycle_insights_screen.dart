/// Cycle insights — analytics over the user's logged data: average cycle/period
/// length, cycles tracked, a recent-cycle history, and the moods & symptoms they
/// log most. Opened from the calendar (cycle mode). Pure presentation over the
/// verified cycle_insights logic.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../domain/cycle_insights.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class CycleInsightsScreen extends StatelessWidget {
  final AppController controller;
  const CycleInsightsScreen({super.key, required this.controller});

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
            final logs = controller.dayLogs.values;
            final moods = moodFrequency(logs);
            final symptoms = symptomFrequency(logs);

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

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();
  @override
  Widget build(BuildContext context) => const Divider(height: 12, color: Palette.border);
}
