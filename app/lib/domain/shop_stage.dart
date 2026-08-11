/// Screen 41 — «Магазин», and specifically «Для вашего этапа».
///
/// The spec asks the shop to show products for the stage she is at. For a long
/// time there was no stage field on a product and inventing one would have been
/// fabrication, so the recommendation was DERIVED from what the app already
/// knows: whether she is pregnant, and how old her children are.
///
/// Migration 033 gave a product a `stage` and a child age band, and frame 08a
/// gave an operator a screen to set them. So there are now two sources, and
/// they are ranked in that order:
///
/// 1. What an operator SAID this product is for — [rankForStage].
/// 2. Where an operator said nothing — the heuristic below, unchanged.
///
/// The fallback is not a courtesy. Most of the catalogue is untagged, a null
/// stage means "nobody has decided yet", and treating it as a mismatch would
/// have replaced a defensible guess with an empty section.
///
/// The rules below are deliberately few and each is defensible out loud. A
/// shop that recommends confidently and wrongly is worse than one that shows a
/// plain list — she is being asked for 39 000 ₸.
library;

import 'shop_catalogue.dart';

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

// ---------------------------------------------------------------------------
// Ranking the LIVE catalogue (frame 08a — «Персонализация»)
// ---------------------------------------------------------------------------

/// The product ids the heuristic above knows by name.
///
/// These are the ids in the catalogue itself (migration 021 seeds them), not
/// invented labels. A product the heuristic has never heard of returns null and
/// is ordered by the catalogue's own `sort` — which is the honest answer: the
/// heuristic has no opinion about a product it was written before.
ShopItem? shopItemForProductId(String id) => switch (id) {
      watchProductId => ShopItem.watch,
      trackerProductId => ShopItem.tracker,
      bundleProductId => ShopItem.bundle,
      _ => null,
    };

/// Where a child of [months] is, in the catalogue's stage vocabulary.
///
/// Boundaries kept coarse on purpose — these are the states the app can already
/// tell apart from a date of birth. A child older than [toddlerUntilMonths] is
/// deliberately NOT mapped to a stage: «toddler» would be false and there is no
/// truer value to use, so nothing is claimed and the age band decides instead.
ProductStage? stageOfChildMonths(int months) {
  if (months < 0) return null;
  if (months < newbornUntilMonths) return ProductStage.newborn;
  if (months < infantUntilMonths) return ProductStage.infant;
  if (months < toddlerUntilMonths) return ProductStage.toddler;
  return null;
}

/// A newborn, for the first three months.
const newbornUntilMonths = 3;

/// «Грудничок» — up to a year.
const infantUntilMonths = 12;

/// A toddler, to four years. Past that the app says nothing about a stage.
const toddlerUntilMonths = 48;

/// Every stage she is at, at once.
///
/// A set, not a value: a woman expecting her second while raising a toddler is
/// both, and a product for either one suits her. Collapsing that to a single
/// stage would hide half the catalogue from the family that needs the most.
///
/// [ProductStage.planning] is never returned. The app does not ask whether she
/// is trying to conceive, and guessing it from an absence of children would put
/// a claim about her fertility on a shop screen.
Set<ProductStage> viewerStages({
  required bool pregnant,
  required List<int> childAgesMonths,
}) {
  final out = <ProductStage>{};
  if (pregnant) out.add(ProductStage.pregnancy);
  for (final m in childAgesMonths) {
    final s = stageOfChildMonths(m);
    if (s != null) out.add(s);
  }
  return out;
}

/// Why a product was put where it was, so the screen can say it per product
/// rather than printing one unexplained order.
enum StageMatch {
  /// An operator said this product is for the stage she is at.
  stage,

  /// An operator said this product suits a child the age of one of hers.
  ageBand,

  /// An operator said «any» — for everyone, which includes her.
  everyone,

  /// Nobody has said anything about who this is for. Ordered by the heuristic.
  untagged,

  /// An operator said who this is for, and it is not her.
  notForYou,
}

/// How well [p] matches her, and why.
StageMatch matchFor(
  CatalogueProduct p, {
  required bool pregnant,
  required List<int> childAgesMonths,
}) {
  if (!p.hasPersonalisation) return StageMatch.untagged;

  final ages = childAgesMonths.where((m) => m >= 0);
  if (ages.any(p.coversAgeMonths)) return StageMatch.ageBand;

  final stage = p.stage;
  if (stage != null) {
    if (stage == ProductStage.any) return StageMatch.everyone;
    if (viewerStages(pregnant: pregnant, childAgesMonths: childAgesMonths)
        .contains(stage)) {
      return StageMatch.stage;
    }
  }
  return StageMatch.notForYou;
}

/// Higher sorts first. `untagged` sits ABOVE `notForYou`: "nobody has decided"
/// is a weaker signal than "this is for her", but a stronger one than "an
/// operator decided this is for somebody else".
int _weight(StageMatch m) => switch (m) {
      StageMatch.stage => 4,
      StageMatch.ageBand => 4,
      StageMatch.everyone => 2,
      StageMatch.untagged => 1,
      StageMatch.notForYou => 0,
    };

/// A product and its place in «Для вашего этапа».
class RankedProduct {
  final CatalogueProduct product;
  final StageMatch match;
  const RankedProduct(this.product, this.match);
}

/// Order the live catalogue for her, keeping every product.
///
/// Nothing is hidden. A product that is not for her stage is moved DOWN, not
/// removed: a mother of a toddler may still want the watch, and a shop that
/// quietly conceals two thirds of its stock because of an operator's dropdown
/// is a worse failure than a suboptimal order.
///
/// [products] is expected in the catalogue's own order (the server sorts it),
/// and that order breaks every tie — including the tie between two untagged
/// products the heuristic also has no opinion about.
List<RankedProduct> rankForStage(
  List<CatalogueProduct> products, {
  required bool pregnant,
  required List<int> childAgesMonths,
}) {
  final heuristic = stageSuggestion(
    pregnant: pregnant,
    childAgesMonths: childAgesMonths,
  );
  int heuristicRank(String id) {
    final item = shopItemForProductId(id);
    if (item == null) return heuristic.items.length;
    final i = heuristic.items.indexOf(item);
    return i < 0 ? heuristic.items.length : i;
  }

  final ranked = [
    for (var i = 0; i < products.length; i++)
      (
        i,
        RankedProduct(
          products[i],
          matchFor(products[i],
              pregnant: pregnant, childAgesMonths: childAgesMonths),
        ),
      ),
  ];

  ranked.sort((a, b) {
    final byMatch = _weight(b.$2.match).compareTo(_weight(a.$2.match));
    if (byMatch != 0) return byMatch;
    // Then the old heuristic, which is still the best answer for the products
    // nobody has tagged — and a harmless tie-break for the ones somebody has.
    final byHeuristic = heuristicRank(a.$2.product.id)
        .compareTo(heuristicRank(b.$2.product.id));
    if (byHeuristic != 0) return byHeuristic;
    return a.$1.compareTo(b.$1); // catalogue order — stable, and the operator's
  });

  return [for (final r in ranked) r.$2];
}
