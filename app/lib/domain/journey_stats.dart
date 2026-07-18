/// Journey totals — a lifetime roll-up across everything the user has tracked,
/// for the "Your journey" summary. PURE Dart → unit-testable via
/// verify_journey.dart. Just counts over data the other domains own.
library;

import 'cycle_log.dart';
import 'cycle_predictions.dart' show periodStarts;

class JourneyTotals {
  final int daysLogged; // days with any non-empty log
  final int notes; // days carrying a free-text note
  final int cyclesTracked; // distinct period starts
  final int kickSessions;
  final int contractionSessions;
  final int appointments;
  final int weightEntries;
  final int waterGlasses; // lifetime glasses of water
  const JourneyTotals({
    required this.daysLogged,
    required this.notes,
    required this.cyclesTracked,
    required this.kickSessions,
    required this.contractionSessions,
    required this.appointments,
    required this.weightEntries,
    required this.waterGlasses,
  });

  /// Whether anything has been tracked at all.
  bool get hasAny =>
      daysLogged > 0 ||
      cyclesTracked > 0 ||
      kickSessions > 0 ||
      contractionSessions > 0 ||
      appointments > 0 ||
      weightEntries > 0 ||
      waterGlasses > 0;
}

/// Roll up lifetime totals. Session/appointment/weight counts are passed
/// directly (already lists elsewhere); logs, periods, and water are counted here.
JourneyTotals computeJourneyTotals({
  required Map<String, DayLog> dayLogs,
  required Set<DateTime> periodDays,
  required int kickSessions,
  required int contractionSessions,
  required int appointments,
  required int weightEntries,
  required Map<String, int> waterLog,
}) {
  var logged = 0, notes = 0;
  for (final l in dayLogs.values) {
    if (l.isNotEmpty) logged++;
    if (l.note.trim().isNotEmpty) notes++;
  }
  var glasses = 0;
  for (final g in waterLog.values) {
    glasses += g;
  }
  return JourneyTotals(
    daysLogged: logged,
    notes: notes,
    cyclesTracked: periodStarts(periodDays).length,
    kickSessions: kickSessions,
    contractionSessions: contractionSessions,
    appointments: appointments,
    weightEntries: weightEntries,
    waterGlasses: glasses,
  );
}
