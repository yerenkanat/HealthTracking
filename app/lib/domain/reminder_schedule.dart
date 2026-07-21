/// When a daily reminder should next fire.
///
/// Split out of NotificationService so the rule can be tested without a
/// notification plugin, a device, or a real clock — see verify_reminder_schedule.
/// The `timezone` package is pure Dart, so a tool runner can exercise the same
/// code the app runs.
library;

import 'package:timezone/timezone.dart' as tz;

/// The next time the wall clock reads [hour]:[minute], at or after [now].
///
/// The obvious version of this — take today at that time, and if it has passed
/// add `Duration(days: 1)` — is wrong twice a year anywhere that observes
/// daylight saving. A Duration is an exact span of 24 hours, and the day a
/// clock springs forward is 23 hours long. On the night of 29 March 2026 in
/// Berlin, "tomorrow at 09:00" computed that way is 10:00:
///
///     TZDateTime(Berlin, 2026, 3, 28, 9, 0).add(Duration(days: 1))
///       → 2026-03-29 10:00 +0200
///
/// so the reminder to take her folic acid arrives an hour late in spring and,
/// by the same arithmetic, an hour early in autumn.
///
/// Constructing tomorrow's date instead asks for a wall-clock time rather than
/// an elapsed span, which is what "every day at nine" means. TZDateTime
/// normalises the overflow, so day 32 of January is 1 February and day 32 of
/// December is 1 January of the next year.
///
/// Kazakhstan has had no daylight saving since 2005, which is why this could
/// sit here unnoticed — but the app ships in three languages and the timezone
/// is read from the device, not from the market.
tz.TZDateTime nextDailyOccurrence(tz.TZDateTime now, int hour, int minute) {
  final today = tz.TZDateTime(now.location, now.year, now.month, now.day, hour, minute);
  if (today.isAfter(now)) return today;
  // Not `+ Duration(days: 1)`: see above.
  return tz.TZDateTime(now.location, now.year, now.month, now.day + 1, hour, minute);
}
