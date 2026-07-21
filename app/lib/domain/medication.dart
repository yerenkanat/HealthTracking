/// Medications & supplements — the prenatal vitamins, iron, folic acid etc. the
/// user takes daily, and a per-day record of doses actually taken. PURE Dart +
/// JSON round-trip → unit-testable via verify_medication.dart.
///
/// NON-medical: the app stores what the user tells it and counts doses. It does
/// not recommend, schedule, or reason about medicines — dosing is between the
/// user and their provider.
library;

import 'cycle_log.dart' show addDays, dateKey;

const int maxDosesPerDay = 6;

class Medication {
  final String id;
  final String name;
  final String dose; // free text as written on the box, e.g. "400 mcg"
  final int perDay; // doses per day (1..maxDosesPerDay)

  const Medication({required this.id, required this.name, this.dose = '', this.perDay = 1});

  /// Clamp a raw per-day count into the supported range.
  static int clampPerDay(int v) => v < 1 ? 1 : (v > maxDosesPerDay ? maxDosesPerDay : v);

  Medication copyWith({String? name, String? dose, int? perDay}) => Medication(
        id: id,
        name: name ?? this.name,
        dose: dose ?? this.dose,
        perDay: clampPerDay(perDay ?? this.perDay),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (dose.isNotEmpty) 'dose': dose,
        'perDay': perDay,
      };

  factory Medication.fromJson(Map<String, dynamic> j) => Medication(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        dose: (j['dose'] as String?) ?? '',
        perDay: clampPerDay((j['perDay'] as num?)?.toInt() ?? 1),
      );
}

/// Doses taken, keyed by dateKey then medication id.
typedef MedLog = Map<String, Map<String, int>>;

/// Doses of [medId] taken on [day].
int dosesTaken(MedLog log, DateTime day, String medId) => log[dateKey(day)]?[medId] ?? 0;

/// Record one more dose of [medId] on [day], capped at that medication's
/// [Medication.perDay]. Returns a new log.
MedLog takeDose(MedLog log, DateTime day, Medication med) {
  final key = dateKey(day);
  final forDay = Map<String, int>.from(log[key] ?? const {});
  final next = (forDay[med.id] ?? 0) + 1;
  forDay[med.id] = next > med.perDay ? med.perDay : next;
  return {...log, key: forDay};
}

/// Undo one dose of [medId] on [day] (never below zero). Returns a new log.
MedLog undoDose(MedLog log, DateTime day, String medId) {
  final key = dateKey(day);
  final forDay = Map<String, int>.from(log[key] ?? const {});
  final next = (forDay[medId] ?? 0) - 1;
  if (next <= 0) {
    forDay.remove(medId);
  } else {
    forDay[medId] = next;
  }
  final out = {...log, key: forDay};
  if (forDay.isEmpty) out.remove(key); // don't keep empty days around
  return out;
}

/// Doses taken vs planned across all [meds] on [day].
({int taken, int planned}) dayProgress(List<Medication> meds, MedLog log, DateTime day) {
  var taken = 0, planned = 0;
  for (final m in meds) {
    planned += m.perDay;
    final t = dosesTaken(log, day, m.id);
    taken += t > m.perDay ? m.perDay : t;
  }
  return (taken: taken, planned: planned);
}

/// Every planned dose taken on [day]. False when nothing is planned.
bool dayComplete(List<Medication> meds, MedLog log, DateTime day) {
  if (meds.isEmpty) return false;
  final p = dayProgress(meds, log, day);
  return p.planned > 0 && p.taken >= p.planned;
}

/// Consecutive fully-complete days ending at [today]. A today that isn't
/// finished yet doesn't break the streak — it counts from yesterday, since the
/// day is still in progress.
int adherenceStreak(List<Medication> meds, MedLog log, DateTime today) {
  if (meds.isEmpty) return 0;
  final t = DateTime(today.year, today.month, today.day);
  var day = dayComplete(meds, log, t) ? t : addDays(t, -1);
  var streak = 0;
  while (dayComplete(meds, log, day)) {
    streak++;
    day = addDays(day, -1);
  }
  return streak;
}

/// Share of planned doses actually taken over the last [days] ending at [today],
/// clamped 0..1. Returns null when nothing was planned in the window.
///
/// An unfinished TODAY is left out, exactly as [adherenceStreak] leaves it out.
/// Counting it charged her for doses the day had not yet reached: with three a
/// day and none taken by nine in the morning, a woman who has never missed one
/// saw 86% — and it climbed back to 100% only by bedtime. Every single day
/// opened by telling her she was slipping.
///
/// Once today IS complete it counts, so finishing the day is visible
/// immediately rather than waiting for midnight.
double? adherenceRate(List<Medication> meds, MedLog log, DateTime today, {int days = 7}) {
  if (meds.isEmpty) return null;
  final t = DateTime(today.year, today.month, today.day);
  var taken = 0, planned = 0;
  for (var i = 0; i < days; i++) {
    final day = addDays(t, -i);
    if (i == 0 && !dayComplete(meds, log, day)) continue;
    final p = dayProgress(meds, log, day);
    taken += p.taken;
    planned += p.planned;
  }
  if (planned == 0) return null;
  final r = taken / planned;
  return r > 1 ? 1 : r;
}

/// One day's dose record, for the history view.
typedef MedDay = ({DateTime day, int taken, int planned});

/// Per-day dose records over the last [days] ending at [today], oldest first.
/// Planned counts come from the CURRENT medication list, so a day predating a
/// medication still shows it as planned — the history reflects today's regimen.
List<MedDay> adherenceHistory(List<Medication> meds, MedLog log, DateTime today, {int days = 14}) {
  final t = DateTime(today.year, today.month, today.day);
  return [
    for (var i = days - 1; i >= 0; i--)
      () {
        final d = addDays(t, -i);
        final p = dayProgress(meds, log, d);
        return (day: d, taken: p.taken, planned: p.planned);
      }(),
  ];
}

/// Total doses ever recorded — for the journey totals.
int totalDosesLogged(MedLog log) {
  var n = 0;
  for (final day in log.values) {
    for (final c in day.values) {
      n += c;
    }
  }
  return n;
}

MedLog medLogFromJson(Map<String, dynamic> j) => {
      for (final e in j.entries)
        e.key: {
          for (final d in (e.value as Map).entries) '${d.key}': (d.value as num).toInt(),
        },
    };

Map<String, dynamic> medLogToJson(MedLog log) => {
      for (final e in log.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
