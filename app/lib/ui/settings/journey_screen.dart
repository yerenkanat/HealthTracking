/// JourneyScreen — a warm "Your journey" summary of everything tracked so far:
/// days logged, notes, cycles, kick & contraction sessions, appointments, weight
/// entries, doses taken, and total water. Pure presentation over computeJourneyTotals.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../domain/journey_stats.dart';
import '../../domain/medication.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/stat_tile.dart';

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
              doses: totalDosesLogged(c.medLog),
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
              (Icons.medication_rounded, Palette.violet, t.doses, l.t('journey_doses')),
            ];
            return GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                for (final (icon, color, value, label) in tiles)
                  if (value > 0) StatTile(icon: icon, color: color, value: '$value', label: label),
              ],
            );
          },
        ),
      ),
    );
  }
}

