/// The mother's own recovery after birth.
///
/// PURE Dart → verified by tool/verify_postpartum.dart.
///
/// WHY THIS EXISTS
///
/// The app follows a woman through pregnancy, and at the birth it hands her a
/// newborn log and a child calendar — everything about the baby. Her own body
/// has just been through the largest event it will ever go through, and the app
/// says nothing about it. The weeks after birth are when serious things are
/// most often missed: heavy bleeding, infection, a clot, and — the most
/// under-recognised of all — postnatal depression. A companion app that goes
/// quiet exactly here is failing the person it was built for.
///
/// WHAT THIS IS, AND IS NOT
///
/// It is two things: gentle, ordinary "what is normal around now" recovery
/// notes keyed to how many days it has been, and a SHORT, unmissable list of
/// signs that always mean "call your clinic now". It is not a diagnosis, not a
/// substitute for the six-week check, and not a reason to wait: the warning
/// signs point OUTWARD, to a real person, deliberately.
///
/// The tone of the recovery notes is calm on purpose. Most of recovery is slow
/// and unremarkable, and a mother reading this at 3am does not need alarm; she
/// needs to know what is ordinary and what is not.
library;

import 'cycle_log.dart' show daysBetween;

/// Which thread a recovery note belongs to, so the screen can group them and a
/// mother can follow the one she is worried about.
enum RecoveryArea {
  /// Bleeding and discharge (lochia) — the one most mothers are unsure about.
  bleeding,

  /// The body: pain, stitches, a caesarean wound, pelvic floor.
  body,

  /// Mood and mind: the baby blues, and the line past which it is more.
  emotional,

  /// Rest, feeding herself, hydration — the basics that get dropped.
  care,
}

/// One "what is normal around now" note, relevant across a window of days.
class RecoveryNote {
  /// Stable id, and the l10n stem: `pp_note_<id>` for the line.
  final String id;
  final RecoveryArea area;

  /// The window since birth, in days, inclusive, during which this is the
  /// "now" note. Windows may overlap — several things are true in week one.
  final int fromDay;
  final int toDay;

  const RecoveryNote({
    required this.id,
    required this.area,
    required this.fromDay,
    required this.toDay,
  });

  bool coversDay(int day) => day >= fromDay && day <= toDay;
}

/// The recovery notes, authored in rough time order. Windows overlap by design.
///
/// Days, not weeks, because the first week changes fast and "week 1" would be
/// too coarse for it.
const List<RecoveryNote> recoveryNotes = [
  // First two weeks.
  RecoveryNote(id: 'lochia_early', area: RecoveryArea.bleeding, fromDay: 0, toDay: 13),
  RecoveryNote(id: 'rest', area: RecoveryArea.care, fromDay: 0, toDay: 13),
  RecoveryNote(id: 'soreness', area: RecoveryArea.body, fromDay: 0, toDay: 20),
  RecoveryNote(id: 'blues', area: RecoveryArea.emotional, fromDay: 2, toDay: 13),
  RecoveryNote(id: 'hydrate', area: RecoveryArea.care, fromDay: 0, toDay: 41),

  // Weeks two to six.
  RecoveryNote(id: 'lochia_fading', area: RecoveryArea.bleeding, fromDay: 14, toDay: 41),
  RecoveryNote(id: 'pelvic_floor', area: RecoveryArea.body, fromDay: 14, toDay: 120),
  RecoveryNote(id: 'gentle_moving', area: RecoveryArea.body, fromDay: 14, toDay: 41),
  RecoveryNote(id: 'mood_check', area: RecoveryArea.emotional, fromDay: 14, toDay: 120),

  // After the six-week check.
  RecoveryNote(id: 'clearance', area: RecoveryArea.body, fromDay: 42, toDay: 120),
  RecoveryNote(id: 'contraception', area: RecoveryArea.care, fromDay: 42, toDay: 120),
];

/// The postnatal check, in days after birth. The single most important date in
/// this whole file: the standard review where a clinician checks recovery,
/// mood, and contraception. Everything the app cannot do, this appointment can.
const postnatalCheckDay = 42;

/// The signs that always mean "contact your clinic now", whatever the day.
///
/// NOT time-windowed and NOT reassured away: these are the postpartum red flags
/// that are dangerous to sit on — haemorrhage, infection, pre-eclampsia (which
/// can arrive AFTER birth), a possible clot, a wound turning bad, and thoughts
/// of harm. Each is an l10n stem `pp_warn_<id>`.
const List<String> warningSigns = [
  'bleeding', // soaking a pad an hour, or large clots
  'fever', // 38°C or over
  'discharge', // foul-smelling
  'headache', // severe, or changes in vision
  'calf', // one red, swollen, painful leg
  'wound', // a tear or caesarean wound hot, swollen or leaking
  'harm', // thoughts of harming herself or the baby
];

/// How many days since the birth. Never negative.
int daysSinceBirth(DateTime birthDate, DateTime now) {
  final d = daysBetween(birthDate, now);
  return d < 0 ? 0 : d;
}

/// How long the app keeps offering this. Recovery does not end at a date, but a
/// permanent "postpartum" surface would follow her for years; four months
/// covers the window where these notes and signs are what matters.
const postpartumWindowDays = 120;

/// Whether the postpartum surface is worth showing for a birth this many days
/// ago.
bool isPostpartumWindow(int day) => day >= 0 && day <= postpartumWindowDays;

/// The notes whose window contains [day], in authored order.
List<RecoveryNote> notesNow(int day) =>
    [for (final n in recoveryNotes) if (n.coversDay(day)) n];

/// Days until the postnatal check, or null once it has passed (there is nothing
/// left to count down to).
int? daysUntilCheck(int day) {
  final left = postnatalCheckDay - day;
  return left > 0 ? left : null;
}
