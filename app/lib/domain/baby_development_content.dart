/// Week-by-week baby-development calendar content — the WHO weight/height ranges
/// and the motor / speech / cognition milestones for each week of the first
/// year, in ru + kk.
///
/// PURE Dart (parse + lookup) → verified by tool/verify_baby_development_contract.dart.
///
/// The data is the shared contract (packages/contract/baby_development.json), the
/// same file the backend serves at GET /child/development and the admin panel
/// renders. The app bundles a copy as an asset so the screen works offline; the
/// verify runner asserts the copy matches the contract so they cannot drift.
///
/// The calendar carries ru + kk only (the source spreadsheet). For the app's
/// third language (en) we fall back to ru, since a blank milestone is worse than
/// a Russian sentence a bilingual user can still read.
library;

import 'cycle_log.dart' show daysBetween;

class ChildDevSkills {
  final String motor;
  final String speech;
  final String cognition;
  const ChildDevSkills({required this.motor, required this.speech, required this.cognition});

  factory ChildDevSkills.fromJson(Map<String, dynamic> j) => ChildDevSkills(
        motor: (j['motor'] as String?)?.trim() ?? '',
        speech: (j['speech'] as String?)?.trim() ?? '',
        cognition: (j['cognition'] as String?)?.trim() ?? '',
      );

  bool get isEmpty => motor.isEmpty && speech.isEmpty && cognition.isEmpty;
}

class ChildDevWeek {
  final int week;
  final String weightKg; // free text range: "6,1–9,3"
  final String heightCm; // free text range: "61,8–70,1"
  final ChildDevSkills ru;
  final ChildDevSkills kk;

  const ChildDevWeek({
    required this.week,
    required this.weightKg,
    required this.heightCm,
    required this.ru,
    required this.kk,
  });

  factory ChildDevWeek.fromJson(Map<String, dynamic> j) => ChildDevWeek(
        week: (j['week'] as num).toInt(),
        weightKg: (j['weightKg'] as String?)?.trim() ?? '',
        heightCm: (j['heightCm'] as String?)?.trim() ?? '',
        ru: ChildDevSkills.fromJson((j['ru'] as Map).cast<String, dynamic>()),
        kk: ChildDevSkills.fromJson((j['kk'] as Map).cast<String, dynamic>()),
      );

  /// The skills for a locale code ('ru' | 'kk' | 'en'), en → ru fallback.
  ChildDevSkills skillsFor(String localeCode) => localeCode == 'kk' ? kk : ru;
}

/// The whole parsed calendar: the weeks plus the paediatrician disclaimer note.
class ChildDevCalendar {
  final List<ChildDevWeek> weeks;
  final String noteRu;
  final String noteKk;
  const ChildDevCalendar({required this.weeks, this.noteRu = '', this.noteKk = ''});

  static const empty = ChildDevCalendar(weeks: []);

  bool get isEmpty => weeks.isEmpty;

  /// The disclaimer note for a locale code, en → ru fallback.
  String noteFor(String localeCode) => localeCode == 'kk' ? noteKk : noteRu;

  /// The content for [week], clamped into the covered range so a newborn (week
  /// 0) or a past-one-year child still returns the nearest real entry. Null only
  /// for an empty calendar.
  ChildDevWeek? weekContentFor(int week) {
    if (weeks.isEmpty) return null;
    final lo = weeks.first.week, hi = weeks.last.week;
    final w = week < lo ? lo : (week > hi ? hi : week);
    for (final e in weeks) {
      if (e.week == w) return e;
    }
    return weeks.first;
  }
}

/// Parse the whole calendar file. Tolerant per-week: a malformed week is skipped
/// rather than losing the file — the same "one bad field costs that field, not
/// everything" rule the app uses for persistence.
ChildDevCalendar parseChildDevelopment(Map<String, dynamic> json) {
  final raw = (json['weeks'] as List?) ?? const [];
  final out = <ChildDevWeek>[];
  for (final w in raw) {
    if (w is! Map) continue;
    try {
      out.add(ChildDevWeek.fromJson(w.cast<String, dynamic>()));
    } catch (_) {
      // skip a bad row
    }
  }
  out.sort((a, b) => a.week.compareTo(b.week));
  final note = (json['note'] as Map?)?.cast<String, dynamic>() ?? const {};
  return ChildDevCalendar(
    weeks: out,
    noteRu: (note['ru'] as String?)?.trim() ?? '',
    noteKk: (note['kk'] as String?)?.trim() ?? '',
  );
}

/// A child's age in completed weeks from a birth date to [now], floored at 0.
/// Used to pick the calendar row for a child. Counts calendar days (via
/// [daysBetween]) rather than elapsed time, so a DST change never shifts the
/// week the way `now.difference(birth).inDays` would.
int childAgeWeeks(DateTime birthDate, DateTime now) {
  final days = daysBetween(birthDate, now);
  return days <= 0 ? 0 : days ~/ 7;
}
