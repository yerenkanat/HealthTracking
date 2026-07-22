/// How much weight is healthy to gain in pregnancy — the reference ranges, and
/// a gentle read of the pace the app can already measure.
///
/// PURE Dart → verified by tool/verify_pregnancy_weight_guide.dart.
///
/// WHY THIS EXISTS
///
/// "How much should I gain?" is one of the most-asked pregnancy questions, and
/// the honest answer depends on the pre-pregnancy weight — which this app does
/// not store. So the guide does two separate things and keeps them separate:
///
///   1. It SHOWS the standard ranges (the widely-used Institute of Medicine
///      bands, by pre-pregnancy BMI) as reference, for the mother to match
///      herself to. It never guesses her band.
///   2. It READS the one thing the app does have — her logged weekly gain — and
///      says, plainly and with a caveat, whether that pace sits inside the
///      typical second/third-trimester band.
///
/// Not a target and not medical advice. The clinic sets a personal goal from her
/// starting weight; this is orientation, not instruction.
library;

/// A pre-pregnancy BMI band. The mother reads which one is hers; the app does
/// not compute it (no height or starting weight is stored).
enum BmiBand { underweight, normal, overweight, obese }

/// A recommended TOTAL weight-gain range for a single (non-twin) pregnancy, in
/// kilograms, for one BMI band — the Institute of Medicine figures.
class GainRange {
  final BmiBand band;
  final double lowKg;
  final double highKg;
  const GainRange(this.band, this.lowKg, this.highKg);
}

const List<GainRange> totalGainRanges = [
  GainRange(BmiBand.underweight, 12.5, 18.0),
  GainRange(BmiBand.normal, 11.5, 16.0),
  GainRange(BmiBand.overweight, 7.0, 11.5),
  GainRange(BmiBand.obese, 5.0, 9.0),
];

/// Typical gain in the WHOLE first trimester (not per week) — small, and much
/// less than later, which surprises people who expect a steady climb.
const firstTrimesterLowKg = 0.5;
const firstTrimesterHighKg = 2.0;

/// The typical WEEKLY pace in the second and third trimesters for a normal
/// pre-pregnancy BMI. Higher and lower bands differ; these anchor the pace read
/// and the caveat says so.
const typicalWeeklyLowKg = 0.35;
const typicalWeeklyHighKg = 0.5;

/// How a measured pace sits against the typical band.
enum GainPace { slow, onTrack, fast }

/// The BMI band for a [bmi] value — pure and testable, ready for the day the
/// app knows height and starting weight. Not called from the UI yet.
BmiBand bmiBandFor(double bmi) {
  if (bmi < 18.5) return BmiBand.underweight;
  if (bmi < 25.0) return BmiBand.normal;
  if (bmi < 30.0) return BmiBand.overweight;
  return BmiBand.obese;
}

/// Read a measured [weeklyRateKg] against the typical band. Null when there is
/// no rate to read (too few entries). A small tolerance keeps a hair over or
/// under from flipping the verdict.
GainPace? assessWeeklyPace(double? weeklyRateKg, {double tolerance = 0.05}) {
  if (weeklyRateKg == null) return null;
  if (weeklyRateKg < typicalWeeklyLowKg - tolerance) return GainPace.slow;
  if (weeklyRateKg > typicalWeeklyHighKg + tolerance) return GainPace.fast;
  return GainPace.onTrack;
}
