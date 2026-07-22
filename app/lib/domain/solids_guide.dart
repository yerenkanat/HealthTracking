/// Starting solids — introducing the baby to food, from around six months.
///
/// PURE Dart → verified by tool/verify_solids_guide.dart.
///
/// WHY THIS EXISTS
///
/// Weaning is one of the first big "am I doing this right?" moments of
/// parenthood, and it is full of small, specific, easy-to-miss facts: not
/// before four months, no honey before one year, introduce the common allergens
/// early rather than late. The child calendar already tracks growth and
/// development; this is the feeding thread that belongs beside them.
///
/// WHAT IT IS, AND IS NOT
///
/// Three short lists — the signs a baby is READY, what to offer at each STAGE,
/// and what to AVOID for now — plus the one date that matters (around six
/// months, not before four). Illustrative and general, keyed to the average
/// baby; a paediatrician knows the particular one.
///
/// Each entry carries a CODE the UI localizes (`sol_*`). Ages are in months.
library;

/// Around when to start — the headline figure. Guidance is "about six months".
const solidsStartMonth = 6;

/// The floor: solids are not recommended before this age.
const solidsNotBeforeMonth = 4;

/// The window over which this guidance is worth showing — from a little before
/// the earliest sensible start to past the first birthday, when the baby is
/// eating family food and the guide has done its job.
const solidsFromMonth = 4;
const solidsToMonth = 14;

/// The signs a baby is ready — all of them, roughly, rather than any one.
/// Each is an l10n stem `sol_ready_<id>`.
const List<String> readinessSigns = [
  'sits', // sits with support, steady head
  'interest', // watches food, reaches for it
  'mouth', // can bring things to the mouth
  'reflex', // the tongue-thrust reflex has faded
];

/// One stage of textures, relevant across a window of months. Windows overlap.
class SolidsStage {
  /// l10n stem `sol_stage_<id>`.
  final String id;
  final int fromMonth;
  final int toMonth;
  const SolidsStage({required this.id, required this.fromMonth, required this.toMonth});

  bool coversMonth(int month) => month >= fromMonth && month <= toMonth;
}

/// The stages, authored in age order, windows overlapping by design.
const List<SolidsStage> solidsStages = [
  SolidsStage(id: 'first_foods', fromMonth: 6, toMonth: 7),
  SolidsStage(id: 'allergens', fromMonth: 6, toMonth: 14),
  SolidsStage(id: 'textures', fromMonth: 7, toMonth: 9),
  SolidsStage(id: 'family', fromMonth: 9, toMonth: 14),
];

/// What to avoid for now. Each is an l10n stem `sol_avoid_<id>`.
const List<String> avoidFoods = [
  'honey', // botulism risk before 12 months
  'choking', // whole nuts, whole grapes, hard chunks
  'salt', // immature kidneys
  'sugar', // added sugar and sweet drinks
];

/// The stages whose window contains [month], in authored order.
List<SolidsStage> stagesForMonth(int month) =>
    [for (final s in solidsStages) if (s.coversMonth(month)) s];

/// Whether the solids guide is worth showing at [ageMonths].
bool isSolidsWindow(int ageMonths) =>
    ageMonths >= solidsFromMonth && ageMonths <= solidsToMonth;

/// Months until solids are around due, or null once at/past the start age — a
/// baby already six months old has arrived, not a countdown.
int? monthsUntilSolids(int ageMonths) {
  final left = solidsStartMonth - ageMonths;
  return left > 0 ? left : null;
}
