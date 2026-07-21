/// What happens when the pregnancy ends.
///
/// PURE Dart → verified by tool/verify_birth_transition.dart.
///
/// WHY THIS EXISTS
///
/// The app had exactly one way out of pregnancy mode: a "No longer pregnant?"
/// link that cleared the due date and returned to cycle tracking. One door for
/// two entirely different events.
///
/// For the overwhelmingly common one — the baby arrived — that door threw away
/// the thing the whole second half of the app needs. The development calendar,
/// the vaccination schedule and the growth chart are all keyed on a date of
/// birth the app had just been counting down to, and the mother was left to
/// add a child by hand and type that date in herself, days after giving birth.
///
/// And for the other event, a loss, the same door offered a cheerful "add your
/// baby" prompt. Which is why this is a fork rather than a flag.
library;

import 'family.dart';

/// How a pregnancy ended.
enum PregnancyOutcome {
  /// The baby arrived. Carries a birth date forward into a child record.
  born,

  /// Ended otherwise, or she simply wants tracking off. No prompt, no
  /// follow-up, nothing to celebrate — the app steps back.
  ///
  /// Deliberately one value rather than a taxonomy. The app has no business
  /// asking a woman to categorise a loss, and it does not need to know: the
  /// behaviour is identical, and the only reason to ask would be analytics.
  ended,
}

/// What the app should do about it.
class BirthTransition {
  final PregnancyOutcome outcome;

  /// The new child, when one was created. Null for [PregnancyOutcome.ended].
  final ChildProfile? child;

  const BirthTransition(this.outcome, {this.child});

  bool get createdChild => child != null;
}

/// Build the transition for a birth.
///
/// [name] may be empty — a baby often has no name for days, and blocking the
/// handover on one would mean the app stops working during the week it is most
/// wanted. The child record is created either way and the name can follow.
///
/// [birthDate] is capped at [today]: a date in the future would give a negative
/// age everywhere downstream, and every one of those screens would then have to
/// defend itself against it.
BirthTransition birthTransition({
  required String childId,
  required String name,
  required DateTime birthDate,
  required DateTime today,
  Gender? gender,
}) {
  final capped = birthDate.isAfter(today) ? today : birthDate;
  return BirthTransition(
    PregnancyOutcome.born,
    child: ChildProfile(
      id: childId,
      name: name.trim(),
      dateOfBirth: DateTime(capped.year, capped.month, capped.day),
      gender: gender,
    ),
  );
}

/// Build the transition for every other ending.
const endedTransition = BirthTransition(PregnancyOutcome.ended);

/// A sensible default for the birth-date picker.
///
/// The due date when it has passed — babies are usually registered in the app
/// within a few days of arriving, and the due date is the closest guess the app
/// holds. Today when the due date is still ahead, since a birth cannot be in
/// the future.
DateTime defaultBirthDate({required DateTime? dueDate, required DateTime today}) {
  if (dueDate == null) return today;
  return dueDate.isAfter(today) ? today : dueDate;
}
