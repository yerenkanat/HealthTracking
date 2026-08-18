/// What the Ма!Ма! course and the комплект cost — screen 34's price card, and
/// the hero of screen 41.
///
/// One place, because these numbers appear on the landing page, in the shop and
/// on the paywall, and three copies of a price is three chances to sell
/// something at the wrong one. [separatelyMinor] is DERIVED rather than typed
/// so it cannot drift from the parts it is the sum of.
///
/// The offer only works if it is stated whole: the комплект includes the entire
/// course and costs LESS than buying the same three things separately. That is
/// not a trick, it is the reason the bundle exists — and a price card that
/// showed only one number would hide it.
///
/// Since frame 08a these numbers are OWNED BY AN OPERATOR. [coursePricesFrom]
/// reads them off the live catalogue and the constants below became a fallback
/// for a phone that has never reached the server — which is why every instance
/// now carries [pricedAt] and the screens say which they are showing.
library;

import 'shop_catalogue.dart';

class CoursePrices {
  /// Смарт-часы Ana-Bala.
  final int watchMinor;

  /// Детский брелок Kid.
  final int trackerMinor;

  /// The course bought on its own.
  ///
  /// **Always a constant, and that is not an oversight.** There is no
  /// course-only PRODUCT in the catalogue — the course is what the комплект
  /// grants, and 018_landing_prices explains why it is sold that way — so there
  /// is no row an operator could edit and nothing to read. It is the published
  /// landing figure, used to state what buying the three things separately
  /// would cost.
  final int courseOnlyMinor;

  /// «Комплект «Мама и ребёнок»» — both devices AND the whole course.
  final int bundleMinor;

  /// When the catalogue behind these numbers was read. Null when none of them
  /// came from one.
  ///
  /// **Not on its own a claim that [bundleMinor] is live** — a catalogue can
  /// contain the watch and not the комплект. [bundleIsLive] is what says where
  /// the headline number came from.
  final DateTime? pricedAt;

  /// True when [pricedAt] is the moment a CACHED payload was originally
  /// fetched, not a live read — so the screen can name the date.
  final bool fromCache;

  /// Whether [bundleMinor] was read from the catalogue rather than being the
  /// compile-time constant.
  final bool bundleIsLive;

  /// Whether the shop is offering the комплект at all.
  ///
  /// False when a catalogue WAS read and did not contain it — an operator has
  /// withdrawn the set, and every screen must then stop quoting it and stop
  /// offering a button that orders it. True on the constants path, where
  /// nothing has been fetched and the app knows nothing about what is on sale:
  /// the honest fallback there is the offer this build shipped with, labelled
  /// approximate.
  final bool bundleAvailable;

  const CoursePrices({
    required this.watchMinor,
    required this.trackerMinor,
    required this.courseOnlyMinor,
    required this.bundleMinor,
    this.pricedAt,
    this.fromCache = false,
    this.bundleIsLive = false,
    this.bundleAvailable = true,
  });

  /// The same three things, bought one at a time.
  int get separatelyMinor => watchMinor + trackerMinor + courseOnlyMinor;

  /// What the комплект saves.
  ///
  /// Can be zero or NEGATIVE now that an operator sets the bundle price: a set
  /// priced above its parts is a legitimate thing to do and the app must not
  /// argue with it. Use [savingIsReal] before showing this — printing «Выгода
  /// −3 000 ₸» is the failure mode.
  int get savingMinor => separatelyMinor - bundleMinor;

  /// Whether there is a saving worth claiming. When false the «экономия» line
  /// is not shown at all — the price still is.
  ///
  /// [bundleAvailable] is part of it because a saving is a comparison, and
  /// comparing live part prices against a комплект price the shop no longer
  /// charges produces a number nobody can honour.
  bool get savingIsReal => bundleAvailable && savingMinor > 0;

  /// [bundleMinor] is the compile-time constant, not a price anybody has
  /// confirmed — and every screen quoting it owes the reader that fact.
  ///
  /// It is the комплект's price specifically, because that is the number both
  /// screens lead with; the course-only figure is a constant by design and
  /// says so where it is printed.
  bool get isApproximate => !bundleIsLive;
}

/// Kazakhstani tenge, in minor units (tiyn), matching ana-bala.kz.
///
/// The fallback, not the source. Correct on the day it was written and correct
/// only until somebody changes a price in the back office, which is exactly
/// what [CoursePrices.isApproximate] exists to admit.
const coursePrices = CoursePrices(
  watchMinor: 2490000, // 24 900 ₸
  trackerMinor: 490000, //  4 900 ₸
  courseOnlyMinor: 9900000, // 99 000 ₸
  bundleMinor: 3900000, // 39 000 ₸
);

/// The live prices, falling back per-product to the constants above.
///
/// Per-product rather than all-or-nothing: a catalogue that has the комплект
/// but not the watch (one product withdrawn, say) should still quote the
/// комплект live. [CoursePrices.pricedAt] is set as soon as ANY of them came
/// from the catalogue, because the card is then no longer purely a guess.
///
/// The one thing that is NOT per-product is whether the комплект is on sale.
/// A catalogue that was read and does not contain it means an operator has
/// withdrawn the set — `PATCH /admin/shop/products/combo {active:false}`, and
/// the storefront then omits the row. Falling back to the constant there would
/// quote 39 000 ₸, with an order button, for something the shop will not sell;
/// [CoursePrices.bundleAvailable] is false instead and the screens drop it.
/// Only a catalogue that could not be read at all (empty: no network and no
/// cache) keeps the built-in offer, because then nothing is known either way.
CoursePrices coursePricesFrom(ShopCatalogue c) {
  final watch = c.byId(watchProductId);
  final tracker = c.byId(trackerProductId);
  final bundle = c.byId(bundleProductId);
  final anyLive = watch != null || tracker != null || bundle != null;
  return CoursePrices(
    watchMinor: watch?.priceMinor ?? coursePrices.watchMinor,
    trackerMinor: tracker?.priceMinor ?? coursePrices.trackerMinor,
    // No product to read. See the field's own note.
    courseOnlyMinor: coursePrices.courseOnlyMinor,
    bundleMinor: bundle?.priceMinor ?? coursePrices.bundleMinor,
    pricedAt: anyLive ? c.fetchedAt : null,
    fromCache: anyLive && c.fromCache,
    bundleIsLive: bundle != null,
    bundleAvailable: bundle != null || c.isEmpty,
  );
}
