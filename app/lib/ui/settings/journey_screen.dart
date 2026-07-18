/// JourneyScreen — a warm "Your journey" summary of everything tracked so far:
/// days logged, notes, cycles, kick & contraction sessions, appointments, weight
/// entries, and total water. Pure presentation over computeJourneyTotals.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../domain/journey_stats.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class JourneyScreen extends StatelessWidget {
  final AppController controller;
  const JourneyScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('journey_title'))),
        body: StreamBuilder<void>(
          stream: controller.changes,
          builder: (context, _) {
            final c = controller;
            final t = computeJourneyTotals(
              dayLogs: c.dayLogs,
              periodDays: c.periodDays,
              kickSessions: c.kickSessions.length,
              contractionSessions: c.contractionSessions.length,
              appointments: c.appointments.length,
              weightEntries: c.weights.length,
              waterLog: c.waterLog,
            );
            if (!t.hasAny) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(l.t('journey_empty'),
                      textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)),
                ),
              );
            }
            final tiles = <(IconData, Color, int, String)>[
              (Icons.check_circle_rounded, Palette.violet, t.daysLogged, l.t('journey_days')),
              (Icons.event_repeat_rounded, Palette.roseDeep, t.cyclesTracked, l.t('journey_cycles')),
              (Icons.note_alt_rounded, Palette.teal, t.notes, l.t('journey_notes')),
              (Icons.child_care_rounded, Palette.pink, t.kickSessions, l.t('journey_kicks')),
              (Icons.timer_rounded, Palette.blue, t.contractionSessions, l.t('journey_contractions')),
              (Icons.event_rounded, Palette.violet, t.appointments, l.t('journey_appointments')),
              (Icons.monitor_weight_rounded, Palette.teal, t.weightEntries, l.t('journey_weights')),
              (Icons.local_drink_rounded, Palette.blue, t.waterGlasses, l.t('journey_water')),
            ];
            return GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                for (final (icon, color, value, label) in tiles)
                  if (value > 0) _StatTile(icon: icon, color: color, value: value, label: label),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  const _StatTile({required this.icon, required this.color, required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: color, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value',
                  style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 26, fontWeight: FontWeight.w700, color: Palette.text, height: 1)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
            ],
          ),
        ],
      ),
    );
  }
}
