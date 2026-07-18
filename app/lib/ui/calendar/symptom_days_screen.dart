/// SymptomDaysScreen — every day a given symptom was logged, most recent first.
/// Opened by tapping a symptom on the cycle insights screen. Pure presentation
/// over the [daysWithSymptom] domain helper.
library;

import 'package:flutter/material.dart';
import '../../domain/cycle_insights.dart';
import '../../domain/cycle_log.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class SymptomDaysScreen extends StatelessWidget {
  final List<DayLog> logs;
  final Symptom symptom;
  const SymptomDaysScreen({super.key, required this.logs, required this.symptom});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final days = daysWithSymptom(logs, symptom);
    final name = l.t('sym_${symptom.name}');
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(name)),
        body: days.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(l.t('sym_days_empty'),
                      textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                    child: Text(l.t('sym_days_count', {'n': days.length}),
                        style: const TextStyle(color: Palette.textDim, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  for (var i = 0; i < days.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _DayCard(log: days[i]),
                  ],
                ],
              ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final DayLog log;
  const _DayCard({required this.log});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ml = MaterialLocalizations.of(context);
    final date = DateTime.tryParse(log.date);
    // Other symptoms logged the same day, for context.
    final others = [for (final s in log.symptoms) if (s != Symptom.allGood) l.t('sym_${s.name}')];
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Palette.roseDeep.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.calendar_today_rounded, size: 18, color: Palette.roseDeep),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date == null ? log.date : ml.formatFullDate(date),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (others.length > 1) ...[
                  const SizedBox(height: 2),
                  Text(others.join(' · '), style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                ],
                if (log.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(log.note, style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
