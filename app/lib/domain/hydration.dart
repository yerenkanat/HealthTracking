/// Daily water intake — pure helpers so the ring, the goal badge, and any advice
/// all agree. Count = glasses logged today; goal = the daily target. PURE Dart →
/// unit-testable via verify_water.dart.
library;

import 'cycle_log.dart' show addDays, dateKey;

const int defaultWaterGoal = 8; // glasses/day
const int minWaterGoal = 4;
const int maxWaterGoal = 16;

/// Progress toward the goal, clamped to 0..1 (a ring never overfills).
double hydrationFraction(int count, int goal) {
  if (goal <= 0 || count <= 0) return 0;
  final f = count / goal;
  return f > 1 ? 1 : f;
}

/// Whether today's target has been reached.
bool hydrationGoalMet(int count, int goal) => goal > 0 && count >= goal;

/// Clamp a user-chosen goal into the supported range.
int clampWaterGoal(int goal) =>
    goal < minWaterGoal ? minWaterGoal : (goal > maxWaterGoal ? maxWaterGoal : goal);

typedef WaterDay = ({DateTime day, int glasses});

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The last [n] days ending at [today], oldest-first, with each day's glasses
/// (0 when nothing was logged). [log] is keyed by dateKey.
List<WaterDay> lastNDays(Map<String, int> log, DateTime today, int n) {
  final t = _dayOnly(today);
  return [
    for (var i = n - 1; i >= 0; i--)
      (day: addDays(t, -i), glasses: log[dateKey(addDays(t, -i))] ?? 0),
  ];
}

/// Consecutive days meeting [goal], counting back from [today]. A not-yet-met
/// today doesn't break the streak — it's counted from yesterday (the day is still
/// in progress); a missed earlier day ends it.
int waterStreak(Map<String, int> log, DateTime today, int goal) {
  if (goal <= 0) return 0;
  bool met(DateTime d) => (log[dateKey(d)] ?? 0) >= goal;
  final t = _dayOnly(today);
  var day = met(t) ? t : addDays(t, -1);
  var streak = 0;
  while (met(day)) {
    streak++;
    day = addDays(day, -1);
  }
  return streak;
}
