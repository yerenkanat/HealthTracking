/// Appointments / reminders — the mother's dated reminders (prenatal visits,
/// ultrasounds, lab work…). PURE Dart + JSON round-trip → unit-testable via
/// verify_appointments.dart. The UI localizes labels; nothing here is language-
/// or Flutter-specific.
library;

class Appointment {
  final String id;
  final String title;
  final DateTime at;
  final String note;

  const Appointment({required this.id, required this.title, required this.at, this.note = ''});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'at': at.toIso8601String(),
        if (note.isNotEmpty) 'note': note,
      };

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        at: DateTime.parse(j['at'] as String),
        note: (j['note'] as String?) ?? '',
      );
}

/// Split into (upcoming, past) relative to [now]. Upcoming is soonest-first; past
/// is most-recent-first. "Now" counts as upcoming (an appointment starting this
/// minute hasn't passed).
({List<Appointment> upcoming, List<Appointment> past}) splitAppointments(
  List<Appointment> all,
  DateTime now,
) {
  final upcoming = <Appointment>[];
  final past = <Appointment>[];
  for (final a in all) {
    (a.at.isBefore(now) ? past : upcoming).add(a);
  }
  upcoming.sort((a, b) => a.at.compareTo(b.at));
  past.sort((a, b) => b.at.compareTo(a.at));
  return (upcoming: upcoming, past: past);
}

/// Appointments whose title or note matches [query] (case-insensitive
/// substring; an empty query matches everything), order preserved.
List<Appointment> searchAppointments(List<Appointment> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  return [
    for (final a in all)
      if (a.title.toLowerCase().contains(q) || a.note.toLowerCase().contains(q)) a,
  ];
}

/// The soonest upcoming appointment, or null when none remain.
Appointment? nextAppointment(List<Appointment> all, DateTime now) {
  final up = splitAppointments(all, now).upcoming;
  return up.isEmpty ? null : up.first;
}

/// Whole days from [now] to the appointment (0 = today, negative = past).
int daysUntil(Appointment a, DateTime now) {
  final d0 = DateTime(now.year, now.month, now.day);
  final d1 = DateTime(a.at.year, a.at.month, a.at.day);
  return d1.difference(d0).inDays;
}

/// How imminent an appointment is, for copy + accent colour on the countdown
/// card. Buckets the whole-day distance: today, tomorrow, within a week, later.
enum ApptWhen { today, tomorrow, soon, later }

ApptWhen appointmentWhen(int daysUntil) => daysUntil <= 0
    ? ApptWhen.today
    : daysUntil == 1
        ? ApptWhen.tomorrow
        : daysUntil <= 7
            ? ApptWhen.soon
            : ApptWhen.later;
