/// A home-safety (babyproofing) checklist that grows with the child.
///
/// PURE Dart → verified by tool/verify_home_safety.dart.
///
/// WHY IT IS AGE-TRIGGERED
///
/// Babyproofing is not one job done once — each new ability opens a new hazard.
/// A newborn needs a safe sleep space and a working smoke alarm; a baby who has
/// started to roll needs small objects and blind cords out of reach; a crawler
/// needs outlet covers, cupboard locks and a stair gate; one pulling to stand
/// needs the tall furniture anchored. So every task carries the age (in months)
/// from which it becomes relevant, and the list a parent sees is the tasks that
/// matter for THIS child now — not a wall of things, most of which do not apply
/// yet.
///
/// The done-state is a set of task ids, persisted household-wide (you childproof
/// the home once, not once per child). The list lives in code, so a shipped
/// change never orphans a tick — an id that leaves the list is simply ignored.
///
/// General guidance, not a guarantee: a checklist cannot make a home safe, only
/// prompt the obvious steps. The screen says so.
library;

/// The rough developmental stage a task belongs to — for grouping the list into
/// "from birth", "once they move", and so on rather than a flat wall.
enum SafetyStage { birth, rolling, crawling, standing }

/// The age in months at which each stage's hazards begin to apply.
int stageFromMonth(SafetyStage s) => switch (s) {
      SafetyStage.birth => 0,
      SafetyStage.rolling => 4,
      SafetyStage.crawling => 6,
      SafetyStage.standing => 10,
    };

class SafetyTask {
  /// Stable id and l10n stem `hs_<id>`.
  final String id;
  final SafetyStage stage;
  const SafetyTask(this.id, this.stage);

  int get fromMonth => stageFromMonth(stage);
}

/// The checklist, authored in stage order.
const List<SafetyTask> homeSafetyTasks = [
  // From birth.
  SafetyTask('safe_sleep_space', SafetyStage.birth),
  SafetyTask('smoke_alarm', SafetyStage.birth),
  SafetyTask('water_temp', SafetyStage.birth),
  SafetyTask('never_alone_high', SafetyStage.birth),

  // Once they roll and reach (~4 months).
  SafetyTask('small_objects', SafetyStage.rolling),
  SafetyTask('blind_cords', SafetyStage.rolling),
  SafetyTask('hot_drinks', SafetyStage.rolling),

  // Once they crawl (~6 months).
  SafetyTask('outlet_covers', SafetyStage.crawling),
  SafetyTask('cupboard_locks', SafetyStage.crawling),
  SafetyTask('stair_gates', SafetyStage.crawling),
  SafetyTask('sharp_corners', SafetyStage.crawling),
  SafetyTask('chemicals_high', SafetyStage.crawling),
  SafetyTask('medicines_locked', SafetyStage.crawling),

  // Once they pull to stand and climb (~10 months).
  SafetyTask('furniture_anchored', SafetyStage.standing),
  SafetyTask('window_locks', SafetyStage.standing),
  SafetyTask('water_supervision', SafetyStage.standing),
];

/// The tasks relevant for a child of [ageMonths] — those whose stage has begun.
List<SafetyTask> tasksForAge(int ageMonths) =>
    [for (final t in homeSafetyTasks) if (t.fromMonth <= ageMonths) t];

/// The relevant tasks in one stage, for grouping. Empty when the stage has not
/// begun for [ageMonths].
List<SafetyTask> tasksInStage(SafetyStage stage, int ageMonths) =>
    [for (final t in homeSafetyTasks) if (t.stage == stage && t.fromMonth <= ageMonths) t];

/// How many of the RELEVANT tasks are done. Ticks for tasks not yet relevant
/// (or no longer in the list) do not count, so the fraction reflects what
/// applies now.
int homeSafetyDoneCount(Set<String> done, int ageMonths) =>
    tasksForAge(ageMonths).where((t) => done.contains(t.id)).length;

/// Total tasks relevant at [ageMonths].
int homeSafetyRelevantTotal(int ageMonths) => tasksForAge(ageMonths).length;

/// Fraction of the relevant tasks done, 0..1. Zero when nothing is relevant yet.
double homeSafetyFraction(Set<String> done, int ageMonths) {
  final total = homeSafetyRelevantTotal(ageMonths);
  return total == 0 ? 0 : homeSafetyDoneCount(done, ageMonths) / total;
}
