/// Hand-entered sleep — the band-less path into the sleep history.
/// PURE Dart, verified by `dart run tool/verify_sleep.dart`.
///
/// A person can time when they went to bed and when they woke, and can roughly
/// say how long they lay awake. Nobody can report their own REM or deep sleep,
/// so a manual night carries no stage breakdown at all and is assessed on what
/// it actually knows — see [SleepSource] and `assessSleep`.
library;

import 'cycle_log.dart' show addDays;

/// Why an entry can't be validated.
enum SleepEntryError {
  /// Bed and wake time are the same instant — no night at all.
  empty,

  /// Longer than [maxInBedMin]; almost certainly an am/pm slip.
  tooLong,

  /// More time awake than was ever spent in bed.
  awakeExceedsInBed,

  /// Awake for the whole night, leaving nothing asleep to record.
  noSleep,
}

/// Longest night we'll accept — 18h. Long lie-ins are real; a 30-hour "night"
/// is a mis-set am/pm, and silently storing it would skew every average.
const int maxInBedMin = 18 * 60;

/// A night as the user describes it: when they got into bed, when they got up,
/// and roughly how long they were awake in between.
class SleepEntry {
  final DateTime bedAt;
  final DateTime wokeAt;
  final int awakeMin;
  const SleepEntry({required this.bedAt, required this.wokeAt, this.awakeMin = 0});

  /// Total time in bed. Crossing midnight is the normal case, so this is simply
  /// the elapsed time between the two instants.
  int get inBedMin => wokeAt.difference(bedAt).inMinutes;

  int get asleepMin => inBedMin - awakeMin;
}

/// Validate a hand-entered night, or null if it's usable.
SleepEntryError? validateSleepEntry(SleepEntry e) {
  final inBed = e.inBedMin;
  if (inBed <= 0) return SleepEntryError.empty;
  if (inBed > maxInBedMin) return SleepEntryError.tooLong;
  if (e.awakeMin < 0 || e.awakeMin > inBed) return SleepEntryError.awakeExceedsInBed;
  if (inBed - e.awakeMin <= 0) return SleepEntryError.noSleep;
  return null;
}

bool sleepEntryIsValid(SleepEntry e) => validateSleepEntry(e) == null;

/// Turn two clock times into the night they describe.
///
/// Bedtime and wake time are clock values — 23:00 and 07:00 — and say nothing
/// about which day. The sheet anchored both to TODAY and pushed the wake time
/// forward when it fell before the bedtime, which reads correctly and is wrong
/// for the ordinary case: she wakes at seven and logs the night at eight.
/// Anchored to today, "bed 23:00" was tonight, still hours away, and the night
/// was filed under TOMORROW. Her night vanished from "last night", and a
/// future-dated night sat in the history skewing the averages.
///
/// The fix is to anchor the WAKE time instead: a night has ended, so its
/// morning is the most recent occurrence of that clock time at or before now.
/// The bedtime is then the occurrence immediately before that morning.
SleepEntry sleepEntryFromClockTimes({
  required DateTime now,
  required int bedHour,
  required int bedMinute,
  required int wokeHour,
  required int wokeMinute,
  int awakeMin = 0,
}) {
  var woke = DateTime(now.year, now.month, now.day, wokeHour, wokeMinute);
  if (woke.isAfter(now)) woke = addDays(woke, -1);

  var bed = DateTime(woke.year, woke.month, woke.day, bedHour, bedMinute);
  if (!bed.isBefore(woke)) bed = addDays(bed, -1);

  return SleepEntry(bedAt: bed, wokeAt: woke, awakeMin: awakeMin);
}

/// The wake date a manual entry belongs to. Summaries are keyed by the morning
/// the night ended, so an entry is filed under when the user got up — which is
/// what makes "last night" mean the same thing for band and manual nights.
DateTime sleepEntryNight(SleepEntry e) =>
    DateTime(e.wokeAt.year, e.wokeAt.month, e.wokeAt.day);
