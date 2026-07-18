/// Reminders overview — a tiny pure model backing the Reminders centre, where
/// every scheduled reminder (period, fertile window, daily water) is toggled in
/// one place. PURE Dart → unit-testable via verify_reminders.dart.
library;

/// The reminders the app can schedule.
enum ReminderKind { period, fertile, water }

/// How many reminders are currently on.
int activeReminderCount({required bool period, required bool fertile, required bool water}) =>
    (period ? 1 : 0) + (fertile ? 1 : 0) + (water ? 1 : 0);

/// Format a minutes-of-day value as 24-hour "H:MM" (e.g. 1230 → "20:30").
/// Values are wrapped into a single day and negatives are clamped to 0.
String minutesToHhmm(int minutesOfDay) {
  final m = minutesOfDay < 0 ? 0 : minutesOfDay % (24 * 60);
  final h = m ~/ 60;
  final mm = (m % 60).toString().padLeft(2, '0');
  return '$h:$mm';
}
