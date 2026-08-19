/// Chart-ready data prep for the health dashboard. Pure Dart → unit-testable,
/// so the UI just renders what this computes. Owned by the dataviz/UX specialists.
///
/// Turns raw telemetry samples into per-metric series with downsampling (so a week
/// of minute-data doesn't choke a sparkline), summary stats, and danger bands
/// derived from the SAME triage thresholds the alerts use — the chart's red zone
/// and the emergency alert can never disagree.
library;

import '../core/triage.dart' show BandTelemetry, ReadingSource, TriageThresholds;
import 'health_monitor.dart' show latestTelemetryMaxAge;

export '../core/triage.dart' show ReadingSource;

class HealthSample {
  final DateTime at;
  final double? heartRate;
  final double? spo2;
  final double? systolic;
  final double? diastolic;

  /// The temperature reading, in °C.
  ///
  /// The name predates provenance and is now only half true: for a
  /// [ReadingSource.manual] sample it is a thermometer reading, for a
  /// [ReadingSource.sensor] one it is a DEVICE ESTIMATE — either the OEM band's
  /// converted skin reading or the watch's uncalibrated `deviceTempC`. Nothing
  /// may say anything about her body from this field without reading [source]
  /// first; see health_advisor.dart.
  final double? coreTemp;
  /// The blood-sugar reading.
  ///
  /// Like [coreTemp], the meaning of this field depends on [source] and the
  /// name is only half true. For a [ReadingSource.manual] sample it is mmol/L
  /// off a glucometer, which states its unit — that one is graded, and it is
  /// the only blood sugar this product may act on. For a
  /// [ReadingSource.sensor] one it is an optical estimate whose vendor
  /// documents it as `当前血糖（0.1）` — a decimal place, not a unit — so it is
  /// CARRIED AND NEVER GRADED: no advisory, no band, no colour, no unit label.
  /// See health_advisor.dart. Never a triage/emergency vital from either
  /// source.
  final double? glucose;
  final bool duringSleep;

  /// Where the numbers came from — a sensor on her wrist, or a measurement she
  /// took and typed in.
  ///
  /// Defaults to [ReadingSource.manual] for the same reason [BandTelemetry]
  /// does: the only hand-built samples in the app are the typed ones, and every
  /// device path states its provenance explicitly (pinned by test). [fromJson]
  /// deliberately defaults the other way.
  final ReadingSource source;

  const HealthSample({
    required this.at,
    this.heartRate,
    this.spo2,
    this.systolic,
    this.diastolic,
    this.coreTemp,
    this.glucose,
    this.duringSleep = false,
    this.source = ReadingSource.manual,
  });

  /// True when nothing here was measured by her — so no card may assert what
  /// her body is doing on the strength of it.
  bool get isDeviceEstimate => source != ReadingSource.manual;

  /// Mirrors [fromJson]'s wire names so a persisted sample reads back identically.
  /// Null metrics are omitted — a reading rarely carries every field.
  Map<String, dynamic> toJson() => {
        'recordedAt': at.toIso8601String(),
        if (heartRate != null) 'heartRateBpm': heartRate,
        if (spo2 != null) 'spo2Pct': spo2,
        if (systolic != null) 'systolicMmHg': systolic,
        if (diastolic != null) 'diastolicMmHg': diastolic,
        if (coreTemp != null) 'coreTempC': coreTemp,
        if (glucose != null) 'glucoseMmol': glucose,
        if (duringSleep) 'duringSleep': true,
        // Always written, never conditional: an absent key means "unknown", and
        // that has to keep meaning what it means below.
        'source': BandTelemetry.sourceToWire(source),
      };

  /// A row with no `source` predates the field, and cannot be shown to have
  /// come off a thermometer — so it is read as a device estimate, which neither
  /// escalates nor reassures. Assuming manual would restore the exact defect
  /// this field was added to remove, on every stored row at once.
  factory HealthSample.fromJson(Map<String, dynamic> j) => HealthSample(
        at: DateTime.parse(j['recordedAt'] as String),
        heartRate: (j['heartRateBpm'] as num?)?.toDouble(),
        spo2: (j['spo2Pct'] as num?)?.toDouble(),
        systolic: (j['systolicMmHg'] as num?)?.toDouble(),
        diastolic: (j['diastolicMmHg'] as num?)?.toDouble(),
        coreTemp: (j['coreTempC'] as num?)?.toDouble(),
        glucose: (j['glucoseMmol'] as num?)?.toDouble(),
        duringSleep: (j['duringSleep'] as bool?) ?? false,
        source: BandTelemetry.sourceFromWire(j['source']),
      );
}

class SeriesPoint {
  final DateTime t;
  final double value;
  const SeriesPoint(this.t, this.value);
}

enum Trend { up, down, flat }

class SeriesStats {
  final double latest;
  final double min;
  final double max;
  final double mean;
  final double delta; // latest - first
  final Trend trend;
  const SeriesStats(this.latest, this.min, this.max, this.mean, this.delta, this.trend);
}

/// warnAbove/warnBelow mark the danger zone the chart shades. Pulled from the
/// canonical thresholds so UI and alerts stay consistent.
class MetricBand {
  final double? warnAbove;
  final double? warnBelow;
  const MetricBand({this.warnAbove, this.warnBelow});
}

const metricKeys = ['hr', 'spo2', 'systolic', 'diastolic', 'temp'];

/// Casual (non-fasting) blood-glucose bands in mmol/L, pregnancy-aware. These
/// grade a wellness estimate (band optical sensor or a typed glucometer value) —
/// they are NOT diagnostic and deliberately never trigger the emergency triage.
class GlucoseThresholds {
  static const elevatedMmol = 7.8; // GDM screening flag for a random / 2-hour reading
  static const highMmol = 11.1; // diabetes-range random reading
  static const lowMmol = 3.9; // hypoglycaemia
  static const severeLowMmol = 3.0; // severe hypoglycaemia
}

/// Where the number a card is about to draw for [metric] came from: the
/// provenance of the NEWEST sample carrying it, which is the one every surface
/// prints as "latest".
///
/// [ReadingSource.manual] when nothing carries the metric — there is no number
/// to grade in that case, and the caller renders a dash.
///
/// This exists because the series layer throws provenance away: [buildSeries]
/// yields bare (t, value) pairs, so by the time a screen holds a temperature it
/// can no longer tell a thermometer reading from a wrist estimate. Every
/// surface that grades, colours or announces a value has to ask this first.
///
/// health_advisor.dart keeps its own copy (`_latestTempIsDeviceEstimate`) whose
/// EMPTY case is the opposite of this one, on purpose: with nothing to go on the
/// advisor must stay silent, so it answers "device". Do not fold the two
/// together — that swap would let an empty list earn a reassurance.
ReadingSource latestSourceFor(List<HealthSample> samples, String metric) {
  HealthSample? latest;
  for (final s in samples) {
    if (_pick(s, metric) == null) continue;
    if (latest == null || !s.at.isBefore(latest.at)) latest = s;
  }
  return latest?.source ?? ReadingSource.manual;
}

/// WHEN [metric] was last measured — the timestamp of the newest sample
/// CARRYING it, which is not the newest sample.
///
/// This is the whole of backlog 1.1 in one function. Freshness was computed per
/// SAMPLE, and the watch sends a frame every couple of minutes with `tempRaw = 0`
/// for anything it did not measure — so the newest SAMPLE could be two minutes
/// old while the newest TEMPERATURE was nine hours old, and the screen said
/// «2 мин назад» over last night's 36.9. The age shown belonged to a different
/// reading than the number shown.
///
/// Null when nothing carries the metric; the caller then has no number either.
DateTime? latestAtFor(List<HealthSample> samples, String metric) {
  DateTime? latest;
  for (final s in samples) {
    if (_pick(s, metric) == null) continue;
    if (latest == null || s.at.isAfter(latest)) latest = s.at;
  }
  return latest;
}

/// How current a metric's newest reading is, on the ladder
/// docs/CLINICAL-REVIEW-WATCH.md sets PER METRIC.
///
/// «A step count from nine hours ago is a complete fact about a finished period.
/// A blood pressure from nine hours ago is a claim about a body that has since
/// moved, eaten and slept. One ladder for both is a category error.»
enum MetricFreshness {
  /// Full colour. The reading may be graded, coloured, announced as out of
  /// range, and counted toward a reassurance.
  current,

  /// Grey, with the age stated. The number is still drawn — it is a true fact
  /// about a finished moment — but nothing may present it as how she is NOW,
  /// and it may not raise a healthy fraction.
  aging,

  /// Not shown as current. Same rendering as [aging] today; kept a separate
  /// tier because the two have different reasons and the review states them
  /// separately, and because a later surface may want to fold these away.
  stale,
}

/// ACOG's repeat-reading interval.
///
/// NOT a new number: it is the interval `emergency_confirmation.dart`'s header
/// cites («ACOG diagnoses gestational hypertension on two elevated readings at
/// least four hours apart»), and the freshness table names it as the source of
/// the blood-pressure column. There was no CONSTANT to reuse — that file states
/// it in prose and models it with a 30-minute confirmation window, which is a
/// different mechanism — so this is the first, and every surface reads it here.
const bpRepeatInterval = Duration(hours: 4);

/// The far end of the grey band for blood pressure, and for the telemetry
/// metrics (heart rate, SpO2).
///
/// Both are read off the freshness table in docs/CLINICAL-REVIEW-WATCH.md
/// rather than derived, and they are constants here so that a surface which
/// disagrees with the table has to change this line and not its own copy of a
/// number. Their full-colour counterparts are [bpRepeatInterval] and
/// [latestTelemetryMaxAge], neither of which is restated.
const bpAgingCeiling = Duration(hours: 12);
const telemetryAgingCeiling = Duration(hours: 24);

/// The freshness tier for one metric, given how old its newest reading is.
///
/// [source] and [bpCalibrationStale] exist for the blood-pressure row, which is
/// the only one with a second condition: «≤ 4 h AND calibration ≤ 8 days …
/// always [not current] when calibration is stale». The calibration is a
/// property of the DEVICE estimate — a cuff reading she typed in has no offset
/// to expire — so it is asked about only for a sensor reading. The eight days
/// are NOT restated here: the caller answers the question with
/// `bpCalibrationIsStale`, which owns `bpCalibrationMaxAgeDays`.
///
/// A timestamp from the future is clamped to zero, matching what the freshness
/// line has always done with a disagreeing clock; the label beside it comes from
/// `L10n.agoIfKnown`, which refuses to describe such a reading at all.
MetricFreshness metricFreshness(
  String metric,
  Duration age, {
  ReadingSource source = ReadingSource.manual,
  bool bpCalibrationStale = true,
}) {
  final a = age.isNegative ? Duration.zero : age;
  switch (metric) {
    case 'systolic':
    case 'diastolic':
      if (source != ReadingSource.manual && bpCalibrationStale) {
        return MetricFreshness.stale;
      }
      if (a <= bpRepeatInterval) return MetricFreshness.current;
      if (a <= bpAgingCeiling) return MetricFreshness.aging;
      return MetricFreshness.stale;
    default:
      // Heart rate and SpO2 by the table; temperature and blood sugar fall here
      // too, and for them this answer drives only the AGE line and the
      // reassurance filter, never a colour — see [currentReadingsOnly] and the
      // note at the tile. `latestTelemetryMaxAge` is the app's own definition of
      // "a reading that still describes how she is now", which is exactly the
      // question this tier answers.
      if (a <= latestTelemetryMaxAge) return MetricFreshness.current;
      if (a <= telemetryAgingCeiling) return MetricFreshness.aging;
      return MetricFreshness.stale;
  }
}

/// Every metric a surface may grade, colour or reassure from. Wider than
/// [metricKeys], which is the vitals GRID; blood sugar is carried and never
/// graded, and it has to be filtered here anyway so that no future surface can
/// reassure from a three-day-old one.
const _filterableMetrics = ['hr', 'spo2', 'systolic', 'diastolic', 'temp', 'glucose'];

/// The readings a surface may compute a claim about NOW from.
///
/// THE ABSORBER RULE, applied to staleness (docs/CLINICAL-REVIEW-WATCH.md,
/// 2026-08-14): «a reassurance may claim no more than the reading it was
/// computed from». «Всё стабильно» — now `ADV_NOTHING_UNUSUAL` — was rendering
/// over readings the app knew were old: a present-tense claim from an
/// out-of-date basis.
///
/// The fix is to change what the sentence is computed FROM rather than what it
/// says. Its title is already scoped to the readings rather than to her body,
/// and its body already says the app sees only what was measured; what neither
/// can carry is a tense. Restricting the input makes the approved sentence true
/// as written — every reading behind it is current on its own metric's ladder —
/// and needs no new medical copy, which a stale-flavoured rewording would.
///
/// A metric is dropped WHOLE (from every sample) or not at all, because the
/// tier is decided by its newest reading; so the value a caller then reads as
/// "latest" is either the same one it would have read, or absent. That is what
/// makes it safe to compose with the warning path: this filter can never invent
/// a finding, only withhold one.
///
/// A sample left carrying nothing is DROPPED, not kept as an empty shell —
/// otherwise `generateAdvisories` sees enough samples to clear its `minSamples`
/// gate, finds no series in any of them, and falls through to the
/// nothing-unusual reassurance computed from no readings at all. That is the
/// worst outcome available here, and it is one line away from the best one:
/// with the empty shells gone the count drops and the fall-through is
/// `ADV_GATHERING`, which claims nothing.
List<HealthSample> currentReadingsOnly(
  List<HealthSample> samples, {
  required DateTime now,
  bool bpCalibrationStale = true,
}) {
  final drop = <String>{};
  for (final k in _filterableMetrics) {
    final at = latestAtFor(samples, k);
    if (at == null) continue;
    final f = metricFreshness(k, now.difference(at),
        source: latestSourceFor(samples, k),
        bpCalibrationStale: bpCalibrationStale);
    if (f != MetricFreshness.current) drop.add(k);
  }
  if (drop.isEmpty) return samples;
  final out = <HealthSample>[];
  for (final s in samples) {
    final hr = drop.contains('hr') ? null : s.heartRate;
    final spo2 = drop.contains('spo2') ? null : s.spo2;
    final sys = drop.contains('systolic') ? null : s.systolic;
    final dia = drop.contains('diastolic') ? null : s.diastolic;
    final temp = drop.contains('temp') ? null : s.coreTemp;
    final glu = drop.contains('glucose') ? null : s.glucose;
    if (hr == null &&
        spo2 == null &&
        sys == null &&
        dia == null &&
        temp == null &&
        glu == null) {
      continue;
    }
    out.add(HealthSample(
      at: s.at,
      heartRate: hr,
      spo2: spo2,
      systolic: sys,
      diastolic: dia,
      coreTemp: temp,
      glucose: glu,
      duringSleep: s.duringSleep,
      source: s.source,
    ));
  }
  return out;
}

/// The danger zone the chart shades for [metric].
///
/// [source] is read for temperature and blood sugar, and it removes the band. A
/// device temperature is never coloured (docs/CLINICAL-REVIEW-WATCH.md,
/// freshness table): a red zone painted behind a wrist estimate makes the same
/// claim the red number makes, in graphical form. A device blood sugar is
/// worse than uncoloured — the shaded band is drawn at 3.9 and 7.8 mmol/L, and
/// the vendor's raw value is documented only as `当前血糖（0.1）`, a decimal place
/// and not a unit, so the band and the line are not on the same axis. Two
/// different quantities in one picture is not a chart.
MetricBand bandFor(String metric, {ReadingSource source = ReadingSource.manual}) {
  if ((metric == 'temp' || metric == 'glucose') &&
      source != ReadingSource.manual) {
    return const MetricBand();
  }
  switch (metric) {
    case 'hr':
      return MetricBand(warnAbove: TriageThresholds.hrTachyWarning.toDouble());
    case 'spo2':
      return MetricBand(warnBelow: TriageThresholds.spo2Warning.toDouble());
    case 'systolic':
      return MetricBand(warnAbove: TriageThresholds.bpSystolicEmergency.toDouble());
    case 'diastolic':
      return MetricBand(warnAbove: TriageThresholds.bpDiastolicEmergency.toDouble());
    case 'temp':
      return const MetricBand(warnAbove: TriageThresholds.feverWarningC);
    case 'glucose':
      return const MetricBand(warnAbove: GlucoseThresholds.elevatedMmol, warnBelow: GlucoseThresholds.lowMmol);
    default:
      return const MetricBand();
  }
}

double? _pick(HealthSample s, String metric) => switch (metric) {
      'hr' => s.heartRate,
      'spo2' => s.spo2,
      'systolic' => s.systolic,
      'diastolic' => s.diastolic,
      'temp' => s.coreTemp,
      'glucose' => s.glucose,
      _ => null,
    };

/// Build one metric's series (chronological, nulls dropped).
List<SeriesPoint> buildSeries(List<HealthSample> samples, String metric) {
  final pts = <SeriesPoint>[];
  for (final s in samples) {
    final v = _pick(s, metric);
    if (v != null) pts.add(SeriesPoint(s.at, v));
  }
  pts.sort((a, b) => a.t.compareTo(b.t));
  return pts;
}

/// Bucket into at most [maxPoints] mean-averaged points (time-uniform buckets).
/// Keeps sparklines cheap and readable without dropping outliers wholesale.
List<SeriesPoint> downsampleMean(List<SeriesPoint> pts, int maxPoints) {
  if (maxPoints <= 0) return const [];
  if (pts.length <= maxPoints) return pts;
  final startMs = pts.first.t.millisecondsSinceEpoch;
  final endMs = pts.last.t.millisecondsSinceEpoch;
  final span = (endMs - startMs).clamp(1, 1 << 62);
  final bucketMs = span / maxPoints;

  final sums = List<double>.filled(maxPoints, 0);
  final counts = List<int>.filled(maxPoints, 0);
  final firstMs = List<int>.filled(maxPoints, 0);
  for (final p in pts) {
    var idx = ((p.t.millisecondsSinceEpoch - startMs) / bucketMs).floor();
    if (idx >= maxPoints) idx = maxPoints - 1;
    if (counts[idx] == 0) firstMs[idx] = p.t.millisecondsSinceEpoch;
    sums[idx] += p.value;
    counts[idx]++;
  }
  final out = <SeriesPoint>[];
  for (var i = 0; i < maxPoints; i++) {
    // An empty bucket contributes no point, so the chart draws straight from
    // the last reading to the next. Fine for a sparkline, whose job is the
    // trend — but it means a gap reads as a smooth line rather than as an
    // absence. Worth revisiting if these ever become a chart someone reads a
    // specific value off.
    if (counts[i] == 0) continue;
    out.add(SeriesPoint(
      // CAUTION: forced to UTC while the inputs are local. Harmless today
      // because nothing formats these — they position points on an axis, and
      // every point shifts by the same offset, so the shape is unchanged.
      // The moment anyone labels that axis, these read hours wrong (+5 or +6
      // for Kazakhstan). Drop isUtc, or convert back, before doing that.
      DateTime.fromMillisecondsSinceEpoch(firstMs[i], isUtc: true),
      sums[i] / counts[i],
    ));
  }
  return out;
}

SeriesStats? statsFor(List<SeriesPoint> pts, {double flatEps = 0.5}) {
  if (pts.isEmpty) return null;
  var min = pts.first.value, max = pts.first.value, sum = 0.0;
  for (final p in pts) {
    if (p.value < min) min = p.value;
    if (p.value > max) max = p.value;
    sum += p.value;
  }
  final latest = pts.last.value;
  final delta = latest - pts.first.value;
  final trend = delta.abs() <= flatEps ? Trend.flat : (delta > 0 ? Trend.up : Trend.down);
  return SeriesStats(latest, min, max, sum / pts.length, delta, trend);
}

/// Is the latest value in the danger zone? Drives the tile's alert styling.
/// [source] is forwarded to [bandFor], so a device temperature and a device
/// blood sugar — neither of which has a band — are never in danger.
bool latestInDanger(String metric, SeriesStats? stats,
    {ReadingSource source = ReadingSource.manual}) {
  if (stats == null) return false;
  final b = bandFor(metric, source: source);
  if (b.warnAbove != null && stats.latest >= b.warnAbove!) return true;
  if (b.warnBelow != null && stats.latest < b.warnBelow!) return true;
  return false;
}

/// Health grade for a single reading, so the UI can render a value in green
/// (normal), amber (worth watching), or red (needs attention) at a glance.
/// Thresholds mirror the advisor and triage layers so every surface agrees:
/// "watch" is the below-emergency band the advisor nudges on; "danger" is the
/// triage cutoff that forces the Emergency screen. NOT a diagnosis.
enum MetricStatus {
  /// Graded, and on the right side of every band this product cites. Rendered
  /// in the healthy teal — it is a CLAIM, and it may only be made about a
  /// reading the product is entitled to reassure from.
  normal,

  /// NO GRADE WAS MADE. Not "fine", and not "old": the app is not judging this
  /// reading at all, because its source is one the review bars from a positive
  /// claim — a device temperature, a device blood sugar, a device blood
  /// pressure below the bands it warns on.
  ///
  /// It exists because the grade was removed and THE COLOUR SURVIVED IT: the
  /// device-temperature ruling collapsed "ungraded" onto [normal], on the
  /// reasoning that normal is what the surfaces render as "no claim" — and
  /// `_statusColor(MetricStatus.normal)` returned the palette's teal, so a
  /// wrist estimate went on being drawn in the same green as a healthy heart
  /// rate. A fourth state is the only way for the type to carry the difference.
  ///
  /// Renders in ordinary body ink, and deliberately NOT in the dim ink that
  /// means stale — that would say "old" about a reading two minutes fresh.
  ungraded,

  /// Worth watching: the below-emergency band the advisor nudges on.
  watch,

  /// The triage cutoff. A WARNING, and warnings are never gated on provenance
  /// — see the absorber rule's corollary.
  danger,
}

/// Is this grade a warning — the two tiers a surface may raise a step for,
/// announce as out of range, or draw away from ordinary ink?
///
/// Written as an allow-list because the call sites used to say
/// `status != MetricStatus.normal`, and the moment [MetricStatus.ungraded]
/// existed that phrasing turned every ungraded reading into a raised card
/// announced as «вне безопасного диапазона» — the exact claim the grade's
/// removal was meant to withdraw.
extension MetricStatusClaim on MetricStatus {
  bool get isWarning =>
      this == MetricStatus.watch || this == MetricStatus.danger;
}

/// Grade one reading. [source] is read for temperature, blood sugar and blood
/// pressure — see those branches — and defaults to [ReadingSource.manual] for
/// the same reason every other default in this vocabulary does: the hand-built
/// values in this app are the typed ones, and every device path states its
/// provenance (pinned by `device_temperature_test.dart`). Pass
/// [latestSourceFor]'s answer whenever the metric can be one of those four; a
/// scan test fails the build if a call site forgets.
MetricStatus metricStatus(String metric, double v,
    {ReadingSource source = ReadingSource.manual}) {
  switch (metric) {
    // ---- Blood pressure ------------------------------------------------------
    //
    // THE TWO WARNING BANDS COME FIRST, AND THEY FIRE FROM EVERY SOURCE. That
    // order is the ruling, not a formatting choice: «gate the positives, never
    // the warnings». A wrist estimate at 165/112 may be drawn in danger red —
    // the product already escalates a device blood pressure there, since
    // `assessTelemetry` has no source check — and it may pull the peace ring
    // down. What it may NOT do is come out `normal` and be painted teal, which
    // is refused sentence #23: a device blood pressure counted as healthy.
    //
    // The ring beside the tile has done this correctly since 2026-08-14; the
    // tile called `metricStatus('systolic', …)` with no source at all, so a
    // fresh, calibrated wrist 118/76 was drawn in mint. That is the reassurance
    // removed from `ADV_BP_STEADY` re-entering as a colour.
    //
    // Unlike temperature this branch is NOT an early return, because the
    // temperature ruling barred the device path from every tier including
    // emergency, and the blood-pressure one deliberately did not.
    //
    // THERE IS NO WATCH TIER HERE ANY MORE, and its absence is the ruling of
    // 2026-08-19 (docs/CLINICAL-REVIEW-WATCH.md, «135/85 stopped grading»;
    // docs/TODO.md §2.1). It used to read `if (v >= 135) return watch` and
    // `if (v >= 85) return watch`. Those two numbers appear in NO source this
    // product cites — not packages/contract/triage_thresholds.json, not the RK
    // MOH protocol in docs/Антенатальный уход.docx, not any WHO or national
    // guideline the gate could name — and the gate could not source them.
    // health_advisor.dart already said so in a comment («135/85 fire the card
    // and appear in NO source this product cites, which is why no user-facing
    // string may state either of them») and medical_copy_tokens_test enforces
    // it on the copy. The colour was the hole in that rule: amber on a tile,
    // plus «, вне безопасного диапазона» in the semantics tree, PUBLISHES the
    // band to the reader as a verdict just as surely as printing «135» would.
    // A number that grades must carry a citation or stop grading; this one
    // could not, so it stopped.
    //
    // What did NOT change, deliberately:
    //   · 140/90 still forces danger from every source — cited to ACOG in
    //     packages/shared/src/triage.ts and pinned in the contract. Removing an
    //     uncited warning tier is not permission to touch the cited one.
    //   · health_advisor.dart still FIRES ADV_BP_ELEVATED / ADV_BP_DEVICE_HIGH
    //     at 135/85. That is a trigger for describing, not a verdict: the cards
    //     name no threshold but 140/90, and deleting them would delete the only
    //     sub-emergency blood-pressure warning a wrist reading can raise. That
    //     is a removal of clinical content, i.e. an OB-GYN's call, not this
    //     layer's. So the reading below 140/90 is now UNSAID by the tile and
    //     still SPOKEN ABOUT by the card, which is the right way round.
    //   · a device reading below the cutoff stays `ungraded`, unchanged.
    //
    // LATENT, and recorded rather than silently fixed: a cuff reading she typed
    // in at 137/88 now comes out `normal` — on the right side of the only band
    // this product cites, which is exactly what `normal` means here — while
    // ADV_BP_ELEVATED says «близки к 140/90». Hand entry is currently removed
    // (docs/TODO.md §1.2, §2.5), so nothing reaches that pair today; if it
    // returns, the tile and the card must be settled together, with §1.1.
    case 'systolic':
      if (v >= TriageThresholds.bpSystolicEmergency) return MetricStatus.danger;
      if (source != ReadingSource.manual) return MetricStatus.ungraded;
      return MetricStatus.normal;
    case 'diastolic':
      if (v >= TriageThresholds.bpDiastolicEmergency) return MetricStatus.danger;
      if (source != ReadingSource.manual) return MetricStatus.ungraded;
      return MetricStatus.normal;
    case 'hr':
      if (v >= TriageThresholds.hrTachyEmergency || v <= TriageThresholds.hrBradyEmergency) {
        return MetricStatus.danger;
      }
      if (v >= TriageThresholds.hrTachyWarning || v <= TriageThresholds.hrBradyWarning) {
        return MetricStatus.watch;
      }
      return MetricStatus.normal;
    case 'spo2':
      if (v < TriageThresholds.spo2Emergency) return MetricStatus.danger;
      if (v < TriageThresholds.spo2Warning) return MetricStatus.watch;
      return MetricStatus.normal;
    case 'temp':
      // A device temperature is never coloured, at any freshness
      // (docs/CLINICAL-REVIEW-WATCH.md, freshness table). Red is a claim about
      // her body, and the error term the conversion would have to correct for —
      // the room, the bedding, the strap — is not one of its inputs. The
      // semantic label is the same claim said out loud: `db_outside_range`
      // announces «вне безопасного диапазона» to someone who cannot see the
      // colour, and it hangs off this grade. Both go together, or neither.
      //
      // [MetricStatus.ungraded], and this is the correction of 2026-08-17. It
      // used to answer `normal`, on the reasoning that normal is what the
      // surfaces already render as "no claim" — plain ink, no raised step, no
      // suffix. Two of those three held. The ink did not: `_statusColor` drew
      // `normal` in the palette's teal, so the grade was removed and the GREEN
      // SURVIVED IT, and a wrist estimate went on being painted in the same
      // colour as a healthy heart rate. The reading is still drawn, in ordinary
      // ink, and the qualifier next to it says what it is. A thermometer
      // reading she typed in is graded exactly as before.
      if (source != ReadingSource.manual) return MetricStatus.ungraded;
      if (v >= TriageThresholds.feverEmergencyC) return MetricStatus.danger;
      if (v >= TriageThresholds.feverWarningC) return MetricStatus.watch;
      return MetricStatus.normal;
    case 'glucose':
      // Graded only for a glucometer reading she typed in, on the same shape as
      // `temp` above and for a sharper reason: these three constants are
      // mmol/L, and the device number's own vendor documentation states no unit
      // for it at all. Grading a raw index against a mmol/L threshold is not an
      // imprecise judgement, it is a judgement about a different quantity.
      //
      // [MetricStatus.ungraded], for the same reason as temperature and by the
      // same correction: `normal` was rendered in teal, so "no claim" was
      // painted as an all-clear. Today nothing in the app grades a device blood
      // sugar — the wellness tile that did was removed with this ruling — so
      // this branch is the guard that keeps it that way when a new surface
      // arrives, and it now hands that surface a state it cannot draw green.
      if (source != ReadingSource.manual) return MetricStatus.ungraded;
      if (v >= GlucoseThresholds.highMmol || v < GlucoseThresholds.severeLowMmol) return MetricStatus.danger;
      if (v >= GlucoseThresholds.elevatedMmol || v < GlucoseThresholds.lowMmol) return MetricStatus.watch;
      return MetricStatus.normal;
    case 'stress':
      // Proprietary 0–100 band index; ~66+ is the "relaxation recommended" zone
      // on the OEM bands. A soft wellness cue, so it never escalates to danger.
      if (v >= 66) return MetricStatus.watch;
      return MetricStatus.normal;
    case 'breathRate':
      // Resting respiratory rate (breaths/min). Pregnancy runs a little higher;
      // flag clearly out-of-range as watch only — a wrist estimate, never triaged.
      if (v < 10 || v > 22) return MetricStatus.watch;
      return MetricStatus.normal;
    default:
      return MetricStatus.normal;
  }
}

/// The most severe status across several readings — for a combined card like
/// blood pressure, where systolic and diastolic each carry their own grade.
///
/// AN UNGRADED HALF MAKES THE PAIR UNGRADED. «118 / 76» is ONE reading, so a
/// pair containing a half the product may not judge cannot come out `normal` and
/// be painted teal — that is refused sentence #23 arriving through the back
/// door, on a card whose two halves are graded separately.
///
/// This used to be `s.index > worst.index`, which cannot express that: the enum
/// index is a declaration order, and any order that put a new state next to
/// `normal` would have made the pair normal again. So the ranking is written
/// down explicitly below and does not depend on how the enum is declared.
/// A warning still wins over an ungraded half, in either position — silence
/// about one number never suppresses a warning about the other.
MetricStatus worstStatus(Iterable<MetricStatus> xs) {
  var worst = MetricStatus.normal;
  for (final s in xs) {
    if (_rank(s) > _rank(worst)) worst = s;
  }
  return worst;
}

int _rank(MetricStatus s) => switch (s) {
      MetricStatus.normal => 0,
      MetricStatus.ungraded => 1,
      MetricStatus.watch => 2,
      MetricStatus.danger => 3,
    };
