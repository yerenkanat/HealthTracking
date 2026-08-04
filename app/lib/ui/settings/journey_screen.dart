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
            // Rows sized to their contents, not a grid with a fixed aspect
            // ratio.
            //
            // GridView.count decides tile HEIGHT from the screen WIDTH, so the
            // same tile got shorter on a narrower phone: 133px at 402dp, 117 at
            // 360dp, for contents that need about 150 — and a tile that does
            // not fit paints the striped overflow bar rather than clipping.
            //
            // Predicting the needed height instead was a dead end. It is not a
            // multiple of the font scale: at 130% the label wraps onto a second
            // line, which adds a whole line at one particular threshold. Two
            // guesses at that formula were wrong by 19px and then by 21px,
            // which is what a formula for something the framework can simply
            // measure looks like. IntrinsicHeight measures it.
            final shown = [
              for (final t in tiles)
                if (t.$3 > 0) t,
            ];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                for (var i = 0; i < shown.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 12),
                  IntrinsicHeight(
                    // stretch, so the two tiles in a row match the taller one
                    // and the grid still reads as a grid.
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: StatTile(
                            icon: shown[i].$1,
                            color: shown[i].$2,
                            value: '${shown[i].$3}',
                            label: shown[i].$4,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: i + 1 < shown.length
                              ? StatTile(
                                  icon: shown[i + 1].$1,
                                  color: shown[i + 1].$2,
                                  value: '${shown[i + 1].$3}',
                                  label: shown[i + 1].$4,
                                )
                              // An odd number of tiles leaves a hole rather
                              // than a stretched final tile.
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
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

