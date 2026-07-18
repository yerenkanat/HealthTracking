/// Weekly baby size-comparison — the familiar "this week, baby is about the size
/// of a …" fruit/veg analogy. PURELY illustrative and non-medical: an
/// approximate length and a everyday-object comparison keyed to the pregnancy
/// week. PURE Dart → unit-testable via verify_baby_size.dart. Each entry carries
/// a CODE the UI localizes (bsize_*). Weeks are 0-based completed weeks.
library;

typedef BabySize = ({int week, String code, double lengthCm});

/// Curated comparisons from week 4 to term. `babySizeFor` snaps any week to the
/// most recent entry, so gaps (e.g. week 15 → the week-14 entry) are fine.
const List<BabySize> babySizeTable = [
  (week: 4, code: 'bsize_poppyseed', lengthCm: 0.1),
  (week: 5, code: 'bsize_sesame', lengthCm: 0.2),
  (week: 6, code: 'bsize_lentil', lengthCm: 0.5),
  (week: 7, code: 'bsize_blueberry', lengthCm: 1.0),
  (week: 8, code: 'bsize_raspberry', lengthCm: 1.6),
  (week: 9, code: 'bsize_grape', lengthCm: 2.3),
  (week: 10, code: 'bsize_strawberry', lengthCm: 3.1),
  (week: 11, code: 'bsize_fig', lengthCm: 4.1),
  (week: 12, code: 'bsize_lime', lengthCm: 5.4),
  (week: 13, code: 'bsize_lemon', lengthCm: 7.4),
  (week: 14, code: 'bsize_peach', lengthCm: 8.7),
  (week: 16, code: 'bsize_avocado', lengthCm: 11.6),
  (week: 18, code: 'bsize_bellpepper', lengthCm: 14.2),
  (week: 20, code: 'bsize_banana', lengthCm: 25.6),
  (week: 22, code: 'bsize_papaya', lengthCm: 27.8),
  (week: 24, code: 'bsize_corn', lengthCm: 30.0),
  (week: 26, code: 'bsize_lettuce', lengthCm: 35.6),
  (week: 28, code: 'bsize_eggplant', lengthCm: 37.6),
  (week: 30, code: 'bsize_cabbage', lengthCm: 39.9),
  (week: 32, code: 'bsize_squash', lengthCm: 42.4),
  (week: 34, code: 'bsize_cantaloupe', lengthCm: 45.0),
  (week: 36, code: 'bsize_honeydew', lengthCm: 47.4),
  (week: 38, code: 'bsize_pumpkin', lengthCm: 49.8),
  (week: 40, code: 'bsize_watermelon', lengthCm: 51.2),
];

/// The size comparison for [week] — the last entry whose week ≤ [week]. Null
/// before the first entry (very early weeks have no meaningful comparison).
BabySize? babySizeFor(int week) {
  if (week < babySizeTable.first.week) return null;
  var current = babySizeTable.first;
  for (final s in babySizeTable) {
    if (s.week > week) break;
    current = s;
  }
  return current;
}
