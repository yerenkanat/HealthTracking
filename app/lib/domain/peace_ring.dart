/// What the peace ring on the home screen is entitled to say about today.
///
/// THE RULE THIS FILE EXISTS FOR: a shape may claim no more than the readings
/// it was computed from. The ring is the most confident register the home
/// screen owns — a closed circle in the healthy accent is read as «today was
/// fine» in a glance, at night, by someone frightened — so the arithmetic
/// behind it belongs in a type that can be tested, not in a widget's build
/// method where it was.
///
/// It was in a build method, and it produced two claims nobody decided:
///
///  1. `withData == 0 ? 1.0 : …` — a FULL ring on a day when nothing could be
///     graded. Fixed already: the fraction is nullable and null means «nothing
///     to grade» (see [PeaceRing.fraction] and `MetricRing.fraction`).
///  2. **The same defect one step milder, and still live:** `healthy /
///     withData` over a pool the loop had already thinned. A metric the
///     product may not grade — a wrist temperature, a wrist blood pressure
///     below the warning bands — and a metric whose readings are too old were
///     `continue`d, which removed them from the numerator AND the denominator.
///     A day of band-only readings has TWO gradeable cards out of four, so the
///     everyday state of this product was a complete green circle drawn from
///     half the grid. The golden `home_dashboard.png` was a photograph of it.
///
/// So the ring now carries coverage as well as verdict. Every card of the
/// vitals grid gets a [RingGrade]; nothing leaves silently. What cannot be
/// assessed occupies its share of the circle in the not-assessed treatment
/// (`MetricRing.assessed`) instead of vanishing from the pool it was in.
///
/// The vocabulary is deliberately the one the TILES already use.
/// `MetricStatus.ungraded` was added by the same ruling for the same reason —
/// a device temperature that kept the healthy colour after its grade was
/// removed — and a second name for that idea on the same screen would be a
/// second visual language for it. Ungraded here means what ungraded means
/// there: the app is not judging this reading, which is neither an alarm nor
/// an all-clear.
library;

import 'health_series.dart';

/// The cards of the vitals grid, in the order the grid draws them.
///
/// FOUR, not the five entries of [metricKeys]: the grid draws blood pressure as
/// ONE card with two halves, and a ring whose denominator is 5 cannot be
/// checked by a reader who counts what is on her screen. It also stops blood
/// pressure occupying most of the pool on its own — a cuff day was `systolic` +
/// `diastolic` + `hr`, so two thirds of the fraction were one instrument.
enum RingCard {
  hr(['hr']),
  spo2(['spo2']),
  temp(['temp']),
  bp(['systolic', 'diastolic']);

  final List<String> metrics;
  const RingCard(this.metrics);
}

/// What the ring may say about ONE card.
enum RingGrade {
  /// Current, from a source this product may reassure from, and on the right
  /// side of every band it cites. The only grade that fills the arc.
  healthy,

  /// The latest reading is in a danger band. Counted whatever its source and
  /// whatever its age — a wrist estimate and an old reading may both pull the
  /// ring DOWN, and only never push it up. Dropping a stale 165/110 would take
  /// it out of the numerator and the denominator together and push the fraction
  /// UP, which is a reassurance arriving by arithmetic off the very reading
  /// that is not fine.
  concerning,

  /// There IS a reading and the app is not judging it: a device temperature or
  /// a device blood pressure below the warning bands (both barred from a
  /// positive claim by the clinical review), or a reading too old to describe
  /// how she is now.
  ///
  /// Not «fine» and not «old» — the same distinction [MetricStatus.ungraded]
  /// draws on the tile.
  ungraded,

  /// No reading for this card at all. Distinct from [ungraded] in the type
  /// because the tile prints a dash for one and a number for the other; the
  /// ring treats both as not-assessed, and says so once.
  missing,
}

/// Today's ring: one grade per card, and the arithmetic that may be drawn.
class PeaceRing {
  final Map<RingCard, RingGrade> cards;
  const PeaceRing(this.cards);

  int get total => cards.length;

  int _count(RingGrade g) => cards.values.where((v) => v == g).length;

  /// Cards that carry a verdict — the pool the [fraction] is over.
  int get assessed => _count(RingGrade.healthy) + _count(RingGrade.concerning);

  int get healthy => _count(RingGrade.healthy);

  /// Whether she has readings AT ALL on the cards this ring is about.
  ///
  /// Separate from [assessed] because the two absences need different
  /// sentences: readings that may not be graded get one, no readings at all get
  /// `ADV_GATHERING` in the advisory beside the ring and must not get a second
  /// explanation of a different absence.
  bool get anyReading => cards.values.any((v) => v != RingGrade.missing);

  /// How much of what was assessed is healthy — or NULL when nothing was.
  ///
  /// Nullable on a clinical ruling and the type IS the ruling: a default that
  /// must be chosen is a default that will be chosen wrong again.
  double? get fraction => assessed == 0 ? null : healthy / assessed;

  /// How much of the ring the [fraction] speaks for, 0..1.
  ///
  /// The rest of the circle is drawn as not-assessed rather than as empty
  /// track, so the arc cannot close on a partial pool. A closed circle now
  /// means all four cards were assessed and all four are healthy, which is what
  /// a closed circle looks like it means.
  double get assessedShare => assessed / total;

  /// Every card assessed. The only state in which the ring may draw a complete
  /// circle.
  bool get complete => assessed == total;

  /// Some cards assessed and some not — the state that used to be drawn as if
  /// it were [complete].
  bool get partial => assessed > 0 && !complete;
}

/// Grade every card of the vitals grid for the ring.
///
/// The three gates are the clinical review's, applied here rather than at four
/// call sites, and each one is asymmetric IN THE SAME DIRECTION: a reading that
/// cannot support a positive claim may still support a warning.
///
///  * provenance — a device temperature and a device blood pressure may not be
///    called healthy (refused sentence #23), but a device blood pressure at
///    165/112 is still danger, because `triage.dart` escalates it with no
///    source check;
///  * freshness — an old reading may not be counted healthy, because a fraction
///    is a present-tense claim, but an old reading in a danger band stays in;
///  * absence — a card with no reading is [RingGrade.missing] and is never
///    silently dropped from the denominator.
PeaceRing gradePeaceRing(
  List<HealthSample> samples, {
  required DateTime now,
  bool bpCalibrationStale = true,
}) {
  final out = <RingCard, RingGrade>{};
  for (final card in RingCard.values) {
    var present = false, danger = false, gradeable = false;
    for (final m in card.metrics) {
      final s = statsFor(buildSeries(samples, m));
      if (s == null) continue;
      present = true;
      final source = latestSourceFor(samples, m);
      if (latestInDanger(m, s, source: source)) danger = true;
      // A wellness estimate may not be called healthy. `bandFor` gives a device
      // temperature no bands at all, so it could never be `danger` either — it
      // simply carries no verdict.
      final mayReassure = switch (m) {
        'temp' || 'systolic' || 'diastolic' => source == ReadingSource.manual,
        _ => true,
      };
      final at = latestAtFor(samples, m);
      final fresh = at != null &&
          metricFreshness(m, now.difference(at),
                  source: source, bpCalibrationStale: bpCalibrationStale) ==
              MetricFreshness.current;
      if (mayReassure && fresh) gradeable = true;
    }
    out[card] = !present
        ? RingGrade.missing
        : danger
            ? RingGrade.concerning
            : gradeable
                ? RingGrade.healthy
                : RingGrade.ungraded;
  }
  return PeaceRing(out);
}
