/// Screen 41 — «Магазин», and specifically «Для вашего этапа».
///
/// The spec asks the shop to show products for the stage she is at. There is no
/// stage field on a product and inventing one would be fabrication, so the
/// recommendation is DERIVED from what the app already knows: whether she is
/// pregnant, and how old her children are.
///
/// The rules below are deliberately few and each is defensible out loud. A
/// shop that recommends confidently and wrongly is worse than one that shows a
/// plain list — she is being asked for 39 000 ₸.
library;

/// What the app sells today, as far as a recommendation is concerned.
enum ShopItem {
  /// Смарт-часы — the mother's band.
  watch,

  /// Детский брелок Kid — the child's tracker.
  tracker,

  /// Both, plus the course.
  bundle,
}

/// Why this is being suggested. Shown as the section's subtitle, so the
/// suggestion always carries its own reason rather than appearing as an
/// unexplained upsell.
enum StageReason {
  /// Expecting — the band watches her, not a child.
  pregnant,

  /// A child too young to go anywhere alone. Nothing to track yet.
  babyTooYoungToTrack,

  /// Walking and out of sight sometimes: the tracker starts to earn its place.
  childOnTheMove,

  /// Nothing recorded. No honest basis for a recommendation.
  unknown,
}

extension StageReasonKeys on StageReason {
  String get l10nKey => switch (this) {
        StageReason.pregnant => 'shop_why_pregnant',
        StageReason.babyTooYoungToTrack => 'shop_why_baby',
        StageReason.childOnTheMove => 'shop_why_moving',
        StageReason.unknown => 'shop_why_unknown',
      };
}

class StageSuggestion {
  final StageReason reason;

  /// Ordered: the most relevant first. Never empty — the bundle is always a
  /// sensible thing to show — but the ORDER is the actual recommendation.
  final List<ShopItem> items;

  const StageSuggestion({required this.reason, required this.items});
}

/// Roughly when a child is walking and can be out of sight: eighteen months.
///
/// Chosen low rather than high. Suggesting a tracker to the parent of a
/// fifteen-month-old is a wasted row; failing to suggest one to the parent of
/// a two-year-old is a missed sale AND a child without a tracker, and only one
/// of those two mistakes matters.
const trackerFromMonths = 18;

/// What to put in front of her, and why.
///
/// [childAgeMonths] is the YOUNGEST child's age — a family with a toddler and
/// a newborn is still a family that needs a tracker.
StageSuggestion stageSuggestion({
  required bool pregnant,
  required List<int> childAgesMonths,
}) {
  final oldest = childAgesMonths.isEmpty
      ? null
      : childAgesMonths.reduce((a, b) => a > b ? a : b);

  // A walking child comes first, even while pregnant: the toddler is the one
  // who can already be somewhere she is not.
  if (oldest != null && oldest >= trackerFromMonths) {
    return const StageSuggestion(
      reason: StageReason.childOnTheMove,
      items: [ShopItem.tracker, ShopItem.bundle, ShopItem.watch],
    );
  }

  if (pregnant) {
    return const StageSuggestion(
      reason: StageReason.pregnant,
      items: [ShopItem.bundle, ShopItem.watch, ShopItem.tracker],
    );
  }

  if (oldest != null) {
    // A baby who cannot yet leave the room. Saying so is more honest than
    // selling a tracker for a child who never goes anywhere.
    return const StageSuggestion(
      reason: StageReason.babyTooYoungToTrack,
      items: [ShopItem.bundle, ShopItem.watch, ShopItem.tracker],
    );
  }

  return const StageSuggestion(
    reason: StageReason.unknown,
    items: [ShopItem.bundle, ShopItem.watch, ShopItem.tracker],
  );
}
