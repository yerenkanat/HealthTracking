/// What the Ма!Ма! course and the комплект cost — screen 34's price card.
///
/// One place, because these numbers appear on the landing page, in the shop and
/// now on the paywall, and three copies of a price is three chances to sell
/// something at the wrong one. The landing is the published source; these match
/// it, and [separatelyMinor] is DERIVED rather than typed so it cannot drift
/// from the parts it is the sum of.
///
/// The offer only works if it is stated whole: the комплект includes the entire
/// course and costs LESS than buying the same three things separately. That is
/// not a trick, it is the reason the bundle exists — and a price card that
/// showed only one number would hide it.
library;

class CoursePrices {
  /// Смарт-часы Ana-Bala.
  final int watchMinor;

  /// Детский брелок Kid.
  final int trackerMinor;

  /// The course bought on its own.
  final int courseOnlyMinor;

  /// «Комплект «Мама и ребёнок»» — both devices AND the whole course.
  final int bundleMinor;

  const CoursePrices({
    required this.watchMinor,
    required this.trackerMinor,
    required this.courseOnlyMinor,
    required this.bundleMinor,
  });

  /// The same three things, bought one at a time.
  int get separatelyMinor => watchMinor + trackerMinor + courseOnlyMinor;

  /// What the комплект saves. Positive, or the offer makes no sense.
  int get savingMinor => separatelyMinor - bundleMinor;
}

/// Kazakhstani tenge, in minor units (tiyn), matching ana-bala.kz.
const coursePrices = CoursePrices(
  watchMinor: 2490000, // 24 900 ₸
  trackerMinor: 490000, //  4 900 ₸
  courseOnlyMinor: 4000000, // 40 000 ₸
  bundleMinor: 3900000, // 39 000 ₸
);
