/// Daily water intake — pure helpers so the ring, the goal badge, and any advice
/// all agree. Count = glasses logged today; goal = the daily target. PURE Dart →
/// unit-testable via verify_water.dart.
library;

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
