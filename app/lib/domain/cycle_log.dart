/// Women's-health day logging + gestation math. PURE Dart (no Flutter) so the
/// calendar's data layer is unit-testable via `dart run tool/verify_cycle.dart`.
///
/// A [DayLog] is one calendar day's self-reported entry: a mood, a set of
/// symptoms, and a running fetal kick count. The UI (Flo-style bottom sheet)
/// only renders and edits these; all the date keying, merging, and gestation-week
/// arithmetic lives here where it can be verified. Enum names are stable storage
/// keys AND localization keys (mood_happy, sym_cramps, …), so no language leaks
/// into the model.
library;

/// Self-reported mood. `name` doubles as the persisted value and the l10n suffix.
enum Mood { happy, calm, anxious, tired, sad }

/// Self-reported symptom. `allGood` is the mutually-exclusive "nothing to report"
/// entry — selecting it clears the others (handled in [DayLog.toggleSymptom]).
enum Symptom { allGood, cramps, spotting, headache, nausea, swelling }

/// Menstrual flow intensity for a day (null = no period logged that day).
enum Flow { light, medium, heavy }

Flow? flowFromName(String? s) {
  for (final f in Flow.values) {
    if (f.name == s) return f;
  }
  return null;
}

Mood? moodFromName(String? s) {
  for (final m in Mood.values) {
    if (m.name == s) return m;
  }
  return null;
}

Symptom? symptomFromName(String? s) {
  for (final v in Symptom.values) {
    if (v.name == s) return v;
  }
  return null;
}

/// Canonical yyyy-MM-dd key for a day (local calendar date, time-of-day dropped).
String dateKey(DateTime d) {
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

/// Parse a yyyy-MM-dd key back to a midnight DateTime (returns null if malformed).
DateTime? dateFromKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// True when [a] and [b] fall on the same calendar day.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class DayLog {
  final String date; // yyyy-MM-dd
  final Mood? mood;
  final Set<Symptom> symptoms;
  final int kicks;
  final Flow? flow; // menstrual flow logged that day (null = none)
  final String note; // free-text note for the day

  const DayLog({
    required this.date,
    this.mood,
    this.symptoms = const {},
    this.kicks = 0,
    this.flow,
    this.note = '',
  });

  /// A day with no mood, symptoms, kicks, flow, or note contributes no calendar dot.
  bool get isEmpty => mood == null && symptoms.isEmpty && kicks == 0 && flow == null && note.isEmpty;
  bool get isNotEmpty => !isEmpty;
  bool get hasPeriod => flow != null;

  DayLog copyWith({
    Mood? mood,
    Set<Symptom>? symptoms,
    int? kicks,
    Flow? flow,
    String? note,
    bool clearMood = false,
    bool clearFlow = false,
  }) =>
      DayLog(
        date: date,
        mood: clearMood ? null : (mood ?? this.mood),
        symptoms: symptoms ?? this.symptoms,
        kicks: kicks ?? this.kicks,
        flow: clearFlow ? null : (flow ?? this.flow),
        note: note ?? this.note,
      );

  /// Set (or clear, with '') the day's note.
  DayLog withNote(String value) => copyWith(note: value.trim());

  /// Toggle [f] — tapping the already-selected flow clears it.
  DayLog withFlowToggled(Flow f) => flow == f ? copyWith(clearFlow: true) : copyWith(flow: f);

  /// Toggle [mood] — tapping the already-selected mood clears it.
  DayLog withMoodToggled(Mood m) =>
      mood == m ? copyWith(clearMood: true) : copyWith(mood: m);

  /// Toggle a symptom. "All good" is exclusive: choosing it clears everything
  /// else, and choosing any real symptom clears "all good".
  DayLog toggleSymptom(Symptom s) {
    final next = Set<Symptom>.from(symptoms);
    if (s == Symptom.allGood) {
      return copyWith(symptoms: next.contains(Symptom.allGood) ? <Symptom>{} : {Symptom.allGood});
    }
    next.remove(Symptom.allGood);
    if (next.contains(s)) {
      next.remove(s);
    } else {
      next.add(s);
    }
    return copyWith(symptoms: next);
  }

  DayLog addKick([int by = 1]) => copyWith(kicks: (kicks + by).clamp(0, 999));
  DayLog resetKicks() => copyWith(kicks: 0);

  Map<String, dynamic> toJson() => {
        'date': date,
        if (mood != null) 'mood': mood!.name,
        if (symptoms.isNotEmpty) 'symptoms': [for (final s in symptoms) s.name],
        if (kicks > 0) 'kicks': kicks,
        if (flow != null) 'flow': flow!.name,
        if (note.isNotEmpty) 'note': note,
      };

  factory DayLog.fromJson(Map<String, dynamic> j) => DayLog(
        date: j['date'] as String,
        mood: moodFromName(j['mood'] as String?),
        symptoms: {
          for (final s in (j['symptoms'] as List? ?? const []))
            if (symptomFromName(s as String?) != null) symptomFromName(s)!
        },
        kicks: (j['kicks'] as num?)?.toInt() ?? 0,
        flow: flowFromName(j['flow'] as String?),
        note: (j['note'] as String?) ?? '',
      );
}

/// Gestational age derived from an estimated due date (EDD). Obstetric convention:
/// a term pregnancy is 280 days (40 weeks) from the last menstrual period, and
/// EDD = LMP + 280d. So gestational age today = 280 − (days until EDD).
/// Displayed as "Week {week}, Day {day}" (completed weeks + remaining days).
class GestationInfo {
  final int totalDays; // clamped gestational age in days
  final int week;
  final int dayOfWeek; // 0..6
  final int daysUntilDue; // negative if overdue

  const GestationInfo(this.totalDays, this.week, this.dayOfWeek, this.daysUntilDue);

  /// Progress toward 40 weeks (0..1), for the header ring/bar.
  double get progress => (totalDays / 280.0).clamp(0.0, 1.0);

  /// Roughly which trimester (1..3), for copy/theming.
  int get trimester => week < 13 ? 1 : (week < 27 ? 2 : 3);
}

/// Compute gestation from [dueDate] relative to [today]. Returns null if no due
/// date is set. Clamped to a sane [0, 300]-day range so a mistyped date can't
/// produce "Week 900".
GestationInfo? gestationFor(DateTime? dueDate, DateTime today) {
  if (dueDate == null) return null;
  final t = DateTime(today.year, today.month, today.day);
  final d = DateTime(dueDate.year, dueDate.month, dueDate.day);
  final daysUntilDue = d.difference(t).inDays;
  final gestDays = (280 - daysUntilDue).clamp(0, 300);
  return GestationInfo(gestDays, gestDays ~/ 7, gestDays % 7, daysUntilDue);
}

/// (De)serialize a whole logbook (dateKey → DayLog) for persistence.
/// Empty logs are skipped, mirroring [dayLogsFromJson] which discards them on
/// read. Writing them meant every save carried entries the next load threw away
/// — and they showed up in the user's export file as meaningless `{"date":...}`
/// stubs. Skipping here also makes encode→decode→encode idempotent.
Map<String, dynamic> dayLogsToJson(Map<String, DayLog> logs) => {
      for (final e in logs.entries)
        if (e.value.isNotEmpty) e.key: e.value.toJson(),
    };

Map<String, DayLog> dayLogsFromJson(Map<String, dynamic>? j) {
  if (j == null) return {};
  final out = <String, DayLog>{};
  j.forEach((k, v) {
    if (v is Map) {
      final log = DayLog.fromJson(v.cast<String, dynamic>());
      if (log.isNotEmpty) out[k] = log;
    }
  });
  return out;
}
