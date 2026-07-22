/// Teething — roughly when the teeth come, what it looks like, what helps, and
/// the one misconception worth correcting.
///
/// PURE Dart → verified by tool/verify_teething.dart.
///
/// Complements the development calendar's single "first tooth" milestone with
/// the fuller picture parents actually ask about: the order teeth tend to
/// arrive, the signs, the soothing, and — importantly — what teething is NOT.
/// A high fever gets blamed on teething and a real illness is missed; this says
/// plainly that teething does not cause one.
///
/// Every age here is a wide RANGE, like the development milestones: teeth arrive
/// on their own schedule and both ends are ordinary.
library;

/// One group of teeth and the rough age window it erupts in, in months.
class ToothGroup {
  /// Stable id and l10n stem `teeth_<id>`.
  final String id;
  final int fromMonth;
  final int toMonth;
  const ToothGroup(this.id, this.fromMonth, this.toMonth);
}

/// The usual order of eruption, earliest first. Ranges overlap — real teeth do.
const List<ToothGroup> teethingTimeline = [
  ToothGroup('lower_central', 6, 10),
  ToothGroup('upper_central', 8, 12),
  ToothGroup('upper_lateral', 9, 13),
  ToothGroup('lower_lateral', 10, 16),
  ToothGroup('first_molars', 13, 19),
  ToothGroup('canines', 16, 22),
  ToothGroup('second_molars', 25, 33),
];

/// Signs a tooth may be coming. Each is an l10n stem `teeth_sign_<id>`.
const List<String> teethingSigns = ['drool', 'chewing', 'irritable', 'sore_gums', 'sleep'];

/// What helps. Each is an l10n stem `teeth_soothe_<id>`.
const List<String> teethingSoothe = ['teething_ring', 'gum_massage', 'cool_food', 'wipe_drool'];

/// Things wrongly blamed on teething that are NOT it — see a doctor instead.
/// Each is an l10n stem `teeth_not_<id>`.
const List<String> teethingNot = ['high_fever', 'diarrhoea'];

/// The tooth group most likely erupting around [ageMonths] — the one whose
/// window contains it, or null when none does (before the first or between
/// gaps). For a "your baby may be working on…" line.
ToothGroup? toothGroupForAge(int ageMonths) {
  for (final g in teethingTimeline) {
    if (ageMonths >= g.fromMonth && ageMonths <= g.toMonth) return g;
  }
  return null;
}

/// The age from which the teething guide is worth surfacing (a little before the
/// first tooth usually shows) through the end of the timeline.
const teethingFromMonth = 3;
int get teethingToMonth => teethingTimeline.last.toMonth;
