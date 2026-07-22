/// When a child is unwell — what helps at home, and the signs that mean call
/// now.
///
/// PURE Dart → verified by tool/verify_child_illness.dart.
///
/// WHY THIS EXISTS
///
/// Fever and minor illness are the commonest reason a parent panics at 2am, and
/// the commonest reason they hesitate when they should not. The app already
/// tracks the well child — growth, development, vaccines; this is the short,
/// clear reference for the unwell one: a handful of comfort measures, and an
/// unmissable list of red flags that point straight to a clinic.
///
/// WHAT IT IS NOT
///
/// Not a diagnosis and not a dosing guide. It names no medicine and no dose —
/// those depend on weight and age and belong to a pharmacist or doctor. The one
/// number it does carry is the age below which a fever is always urgent, because
/// that single fact changes what a parent should do.
library;

/// Below this age in months, ANY fever warrants prompt medical review — a very
/// young baby's fever is treated with far more caution than an older child's.
const feverUrgentUnderMonths = 3;

/// The temperature, in whole °C, generally called a fever. Shown for reference,
/// not as a threshold the app measures against.
const feverThresholdC = 38;

/// Comfort measures for a mild illness at home. Each is an l10n stem
/// `ill_care_<id>`.
const List<String> illnessCare = [
  'fluids', // keep feeds/fluids up — dehydration is the real risk
  'rest', // rest, and don't overwrap
  'light_clothing', // light clothing, comfortable room
  'medicine', // fever medicine only by age and a professional's guidance
  'watch', // keep watching, and the signs below
];

/// Signs that always mean contact a clinic or emergency services now, whatever
/// the age. Each is an l10n stem `ill_warn_<id>`. Never softened.
const List<String> illnessWarnings = [
  'breathing', // fast, laboured or grunting breathing
  'colour', // very pale, blue or grey skin or lips
  'rash', // a rash that does not fade when pressed
  'stiff_neck', // stiff neck, bulging soft spot, dislike of light
  'seizure', // a fit / convulsion
  'unrousable', // floppy, hard to wake, unusually drowsy
  'dehydration', // no wet nappies, no tears, sunken eyes
  'persistent', // a high fever that will not come down or lasts
];

/// Whether a fever in a child this age should be treated as urgent on age
/// alone — the under-three-months rule.
bool feverIsUrgentForAge(int ageMonths) => ageMonths < feverUrgentUnderMonths;
