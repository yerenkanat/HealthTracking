/// The childhood vaccination schedule.
///
/// PURE Dart → verified by tool/verify_vaccination.dart.
///
/// WHAT THIS IS
///
/// The national immunisation calendar of Kazakhstan, which is the app's market:
/// a fixed list of vaccines at fixed ages, given free at the polyclinic. Unlike
/// the development milestones, these ARE a schedule — the ages are set by the
/// health ministry, not by how a particular child is growing.
///
/// That difference drives the whole design. A development milestone missed by a
/// month is ordinary and the app says so; a vaccination missed by a month is a
/// real thing to catch up on, and the app should say THAT.
///
/// WHAT IT IS NOT
///
/// Not medical advice, and not a record of what the child has actually had.
/// The app cannot know that — nothing here reads a clinic record. It shows the
/// schedule and where the child is on it, so a parent can ask the right
/// question at the right visit and spot a gap before it becomes a long one.
///
/// A schedule changes by order of the health ministry. [scheduleRevision] is
/// here so a stale build is identifiable rather than silently authoritative.
library;

/// When this table was last checked against the published order.
///
/// Not a version number for the code — a date for the DATA. A parent using a
/// two-year-old build should be able to find out that its schedule is two
/// years old, and so should whoever next edits this file.
const scheduleRevision = '2026-07';

/// Which country's schedule. One today; named so that adding a second is a
/// data change rather than a rewrite.
enum VaccineRegion { kz }

class Vaccine {
  /// Stable id, and the l10n key stem: `vac_<id>` for the name and
  /// `vac_<id>_note` for what it protects against.
  final String id;

  /// Age in completed MONTHS at which it is due. 0 means the first days of
  /// life, in the maternity hospital.
  final int atMonth;

  /// Which dose this is, when a vaccine is given more than once. 1-based; null
  /// for single-dose vaccines.
  final int? dose;

  const Vaccine({required this.id, required this.atMonth, this.dose});
}

/// The Kazakhstan national calendar, ordered by age.
///
/// Doses of the same vaccine share an id and differ by [dose], so the UI can
/// say "ОПВ, доза 2" without a separate string per dose.
const List<Vaccine> kzSchedule = [
  // In the maternity hospital, first days.
  Vaccine(id: 'hepb', atMonth: 0, dose: 1),
  Vaccine(id: 'bcg', atMonth: 0),

  Vaccine(id: 'pentavalent', atMonth: 2, dose: 1),
  Vaccine(id: 'opv', atMonth: 2, dose: 1),
  Vaccine(id: 'pcv', atMonth: 2, dose: 1),

  Vaccine(id: 'pentavalent', atMonth: 3, dose: 2),
  Vaccine(id: 'opv', atMonth: 3, dose: 2),

  Vaccine(id: 'pentavalent', atMonth: 4, dose: 3),
  Vaccine(id: 'opv', atMonth: 4, dose: 3),
  Vaccine(id: 'pcv', atMonth: 4, dose: 2),

  Vaccine(id: 'mmr', atMonth: 12, dose: 1),

  Vaccine(id: 'dtp', atMonth: 18, dose: 4),
  Vaccine(id: 'opv', atMonth: 18, dose: 4),
  Vaccine(id: 'hib', atMonth: 18, dose: 4),

  Vaccine(id: 'mmr', atMonth: 72, dose: 2),
  Vaccine(id: 'adt', atMonth: 72),
];

/// Where a vaccine sits relative to a child of [ageMonths].
enum VaccineStatus {
  /// Not yet due.
  upcoming,

  /// Due now — within [dueWindowMonths] of its scheduled age.
  due,

  /// Its age has passed. Worth checking it was given, and catching up if not.
  ///
  /// NOT "missed": the app has no idea what the child has received. The word
  /// matters, and the UI wording follows it.
  passed,
}

/// How long a vaccine reads as "due now" rather than "passed".
///
/// A month, because that is roughly the appointment cadence: something due at
/// 4 months is still the thing to ask about at a visit a few weeks later.
const dueWindowMonths = 1;

VaccineStatus vaccineStatus(Vaccine v, int ageMonths) {
  if (ageMonths < v.atMonth) return VaccineStatus.upcoming;
  if (ageMonths <= v.atMonth + dueWindowMonths) return VaccineStatus.due;
  return VaccineStatus.passed;
}

/// The schedule grouped by age, oldest first, for a timeline.
///
/// A Map preserves insertion order in Dart, and [kzSchedule] is authored in age
/// order, so the groups come out in order without a sort — but the runner
/// asserts that rather than trusting it, because the day someone inserts a
/// vaccine in the wrong place the screen silently reorders.
Map<int, List<Vaccine>> scheduleByAge([List<Vaccine> schedule = kzSchedule]) {
  final out = <int, List<Vaccine>>{};
  for (final v in schedule) {
    (out[v.atMonth] ??= []).add(v);
  }
  return out;
}

/// Vaccines due around [ageMonths] now.
List<Vaccine> vaccinesDue(int ageMonths, [List<Vaccine> schedule = kzSchedule]) =>
    [for (final v in schedule) if (vaccineStatus(v, ageMonths) == VaccineStatus.due) v];

/// A stable key for one injection — id plus dose — used to record that a parent
/// has marked it done. Matches the uniqueness the schedule guards.
String vaccineKey(Vaccine v) => '${v.id}/${v.dose}';

/// The vaccines whose age has PASSED but the parent has not marked done — the
/// real "catch up" list. A passed vaccine already recorded is not a gap; one
/// that is neither due nor recorded is exactly what a parent should ask about.
///
/// [done] is the set of [vaccineKey]s she has ticked.
List<Vaccine> vaccinesToCatchUp(int ageMonths, Set<String> done,
        [List<Vaccine> schedule = kzSchedule]) =>
    [
      for (final v in schedule)
        if (vaccineStatus(v, ageMonths) == VaccineStatus.passed && !done.contains(vaccineKey(v))) v
    ];

/// How many of the whole schedule the parent has recorded as done.
int vaccinesDoneCount(Set<String> done, [List<Vaccine> schedule = kzSchedule]) =>
    schedule.where((v) => done.contains(vaccineKey(v))).length;

/// The next appointment's worth of vaccines: everything at the soonest age
/// still ahead of [ageMonths].
///
/// Grouped rather than "the next vaccine", because they are given together —
/// telling a parent about one of the three due at 4 months would have them
/// arrive expecting one injection.
List<Vaccine> nextVisit(int ageMonths, [List<Vaccine> schedule = kzSchedule]) {
  int? soonest;
  for (final v in schedule) {
    if (v.atMonth > ageMonths && (soonest == null || v.atMonth < soonest)) {
      soonest = v.atMonth;
    }
  }
  if (soonest == null) return const [];
  return [for (final v in schedule) if (v.atMonth == soonest) v];
}

/// Months until the next visit, or null when the schedule is complete.
int? monthsUntilNextVisit(int ageMonths, [List<Vaccine> schedule = kzSchedule]) {
  final next = nextVisit(ageMonths, schedule);
  return next.isEmpty ? null : next.first.atMonth - ageMonths;
}

/// When to remind a parent about the next visit.
///
/// The morning the child reaches the next scheduled age, since the birthday of
/// a month is the day the visit becomes due. Null when the schedule is complete
/// or the date would already be in the past — a reminder that fires in the past
/// never arrives, so there is nothing to schedule.
///
/// [dob] is a date; the reminder is stamped at [hour] local time so it lands
/// during the day rather than at midnight.
DateTime? nextVaccinationReminderAt({
  required DateTime dob,
  required DateTime now,
  int hour = 10,
  List<Vaccine> schedule = kzSchedule,
}) {
  final ageMonths = _wholeMonths(dob, now);
  final next = nextVisit(ageMonths, schedule);
  if (next.isEmpty) return null;

  // The date the child turns next.first.atMonth months old.
  final dueDate = DateTime(dob.year, dob.month + next.first.atMonth, dob.day, hour);
  // A visit whose age has already arrived (a late catch-up) is not scheduled in
  // the past; the screen already shows it as due.
  if (!dueDate.isAfter(now)) return null;
  return dueDate;
}

/// Completed months between [dob] and [now], by the calendar.
int _wholeMonths(DateTime dob, DateTime now) {
  var months = (now.year - dob.year) * 12 + (now.month - dob.month);
  if (now.day < dob.day) months--;
  return months < 0 ? 0 : months;
}
