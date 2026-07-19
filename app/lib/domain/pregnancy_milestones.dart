/// Pregnancy milestones — NON-medical, purely calendar-based markers of the
/// pregnancy timeline (trimester transitions, the halfway point, full term, the
/// due week). No medical claims about development; just where you are on the
/// 40-week clock. PURE Dart → unit-testable via verify_milestones.dart.
///
/// Each milestone carries a CODE the UI localizes (MS_*). Weeks follow standard
/// obstetric convention (0-based completed weeks).
library;

typedef Milestone = ({int week, String code});

const List<Milestone> pregnancyMilestoneTable = [
  (week: 0, code: 'MS_FIRST_TRIMESTER'),
  (week: 13, code: 'MS_SECOND_TRIMESTER'),
  (week: 20, code: 'MS_HALFWAY'),
  (week: 27, code: 'MS_THIRD_TRIMESTER'),
  (week: 37, code: 'MS_FULL_TERM'),
  (week: 40, code: 'MS_DUE'),
];

/// The milestone the pregnancy is currently in (the last one whose week ≤ [week]).
Milestone currentMilestone(int week) {
  var current = pregnancyMilestoneTable.first;
  for (final m in pregnancyMilestoneTable) {
    if (m.week > week) break;
    current = m;
  }
  return current;
}

/// The next upcoming milestone (first whose week > [week]), or null past the due
/// week.
Milestone? nextMilestone(int week) {
  for (final m in pregnancyMilestoneTable) {
    if (m.week > week) return m;
  }
  return null;
}

/// Weeks until [next] from [week] (0 if already reached).
int weeksUntil(int week, Milestone next) => next.week - week < 0 ? 0 : next.week - week;
