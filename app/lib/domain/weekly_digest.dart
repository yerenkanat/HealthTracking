/// Weekly digest — a small end-of-week roll-up over the last 7 days: how many
/// days were logged, water drunk (glasses + days the goal was met), and average
/// sleep. PURE Dart → unit-testable via verify_weekly_digest.dart. Aggregates
/// data the other domains own; holds no logic of its own beyond counting.
library;

import 'cycle_log.dart';
import 'hydration.dart' show hydrationGoalMet;
import 'sleep.dart';

class WeeklyDigest {
  final int daysLogged; // days in the window with any non-empty day log
  final int waterGlasses; // total glasses over the window
  final int waterGoalDays; // days the water goal was met
  final int avgSleepMin; // average asleep minutes over nights in the window (0 if none)
  final int sleepNights; // nights of sleep data in the window
  const WeeklyDigest({
    required this.daysLogged,
    required this.waterGlasses,
    required this.waterGoalDays,
    required this.avgSleepMin,
    required this.sleepNights,
  });

  /// Whether there's anything worth showing.
  bool get hasData => daysLogged > 0 || waterGlasses > 0 || sleepNights > 0;
}

/// Roll up the last [days] (default 7) ending at [today].
WeeklyDigest computeWeeklyDigest(
  Map<String, DayLog> dayLogs,
  Map<String, int> waterLog,
  List<SleepSummary> sleepNights,
  DateTime today, {
  int days = 7,
  int waterGoal = 8,
}) {
  final t = DateTime(today.year, today.month, today.day);
  final windowKeys = <String>{
    for (var i = 0; i < days; i++) dateKey(t.subtract(Duration(days: i))),
  };

  var logged = 0;
  for (final k in windowKeys) {
    final l = dayLogs[k];
    if (l != null && l.isNotEmpty) logged++;
  }

  var glasses = 0, goalDays = 0;
  for (final k in windowKeys) {
    final g = waterLog[k] ?? 0;
    glasses += g;
    if (hydrationGoalMet(g, waterGoal)) goalDays++;
  }

  var sleepSum = 0, nights = 0;
  for (final n in sleepNights) {
    if (windowKeys.contains(dateKey(n.night))) {
      sleepSum += n.asleepMin;
      nights++;
    }
  }

  return WeeklyDigest(
    daysLogged: logged,
    waterGlasses: glasses,
    waterGoalDays: goalDays,
    avgSleepMin: nights == 0 ? 0 : (sleepSum / nights).round(),
    sleepNights: nights,
  );
}
