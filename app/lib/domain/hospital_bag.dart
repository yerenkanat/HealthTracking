/// The hospital-bag checklist — what to pack for the birth.
///
/// PURE Dart → verified by tool/verify_hospital_bag.dart.
///
/// A fixed, sensible default list grouped into three bags — for the mother, for
/// the baby, and the documents — that a woman ticks off as she packs. The ticks
/// (item ids) are persisted; this file is only the list and the maths over it.
/// Keeping the list in code means a shipped change to it never orphans her
/// ticks: an id she checked that later leaves the list simply does nothing.
///
/// Not exhaustive and not prescriptive — hospitals hand out their own lists, and
/// this is a starting point, not a rule. The screen says so.
library;

/// Which bag an item belongs in.
enum BagCategory { mother, baby, documents }

class BagItem {
  /// Stable id and l10n stem: `bag_<id>`.
  final String id;
  final BagCategory category;
  const BagItem(this.id, this.category);
}

/// The default checklist, authored by bag.
const List<BagItem> hospitalBagItems = [
  // For the mother.
  BagItem('id_documents', BagCategory.documents),
  BagItem('exchange_card', BagCategory.documents),
  BagItem('insurance', BagCategory.documents),
  BagItem('birth_plan', BagCategory.documents),

  BagItem('nightgown', BagCategory.mother),
  BagItem('robe_slippers', BagCategory.mother),
  BagItem('toiletries', BagCategory.mother),
  BagItem('maternity_pads', BagCategory.mother),
  BagItem('nursing_bra', BagCategory.mother),
  BagItem('phone_charger', BagCategory.mother),
  BagItem('snacks_water', BagCategory.mother),
  BagItem('going_home_clothes', BagCategory.mother),

  BagItem('bodysuits', BagCategory.baby),
  BagItem('sleepsuits', BagCategory.baby),
  BagItem('hat_socks', BagCategory.baby),
  BagItem('nappies', BagCategory.baby),
  BagItem('swaddle_blanket', BagCategory.baby),
  BagItem('car_seat', BagCategory.baby),
];

/// The items in one bag, in authored order.
List<BagItem> itemsInCategory(BagCategory category) =>
    [for (final i in hospitalBagItems) if (i.category == category) i];

/// How many of the default items are ticked. Ids in [checked] that are not in
/// the list are ignored, so a stale tick never inflates the count.
int packedCount(Set<String> checked) =>
    hospitalBagItems.where((i) => checked.contains(i.id)).length;

/// Total items in the default list.
int get hospitalBagTotal => hospitalBagItems.length;

/// Fraction packed, 0..1. Zero when the list is somehow empty.
double packedFraction(Set<String> checked) =>
    hospitalBagTotal == 0 ? 0 : packedCount(checked) / hospitalBagTotal;

/// Whether everything on the default list is ticked.
bool isFullyPacked(Set<String> checked) => packedCount(checked) == hospitalBagTotal;

/// The gestational week from which the checklist is worth surfacing — a few
/// weeks before term, matching the "pack your bag" note in the pregnancy guide.
const hospitalBagFromWeek = 32;
