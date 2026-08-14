/// Chart-ready data prep for the health dashboard. Pure Dart → unit-testable,
/// so the UI just renders what this computes. Owned by the dataviz/UX specialists.
///
/// Turns raw telemetry samples into per-metric series with downsampling (so a week
/// of minute-data doesn't choke a sparkline), summary stats, and danger bands
/// derived from the SAME triage thresholds the alerts use — the chart's red zone
/// and the emergency alert can never disagree.
library;

import '../core/triage.dart' show BandTelemetry, ReadingSource, TriageThresholds;

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

/// Three-tier health grade for a single reading, so the UI can render a value in
/// green (normal), amber (worth watching), or red (needs attention) at a glance.
/// Thresholds mirror the advisor and triage layers so every surface agrees:
/// "watch" is the below-emergency band the advisor nudges on; "danger" is the
/// triage cutoff that forces the Emergency screen. NOT a diagnosis.
enum MetricStatus { normal, watch, danger }

/// Grade one reading. [source] is read for temperature and blood sugar — see
/// those two branches — and defaults to [ReadingSource.manual] for the same reason every
/// other default in this vocabulary does: the hand-built values in this app are
/// the typed ones, and every device path states its provenance (pinned by
/// `device_temperature_test.dart`). Pass [latestSourceFor]'s answer whenever the
/// metric can be temperature; a scan test fails the build if a call site
/// forgets.
MetricStatus metricStatus(String metric, double v,
    {ReadingSource source = ReadingSource.manual}) {
  switch (metric) {
    case 'systolic':
      if (v >= TriageThresholds.bpSystolicEmergency) return MetricStatus.danger;
      if (v >= 135) return MetricStatus.watch;
      return MetricStatus.normal;
    case 'diastolic':
      if (v >= TriageThresholds.bpDiastolicEmergency) return MetricStatus.danger;
      if (v >= 85) return MetricStatus.watch;
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
      // Normal, not a fourth "ungraded" tier: normal is what the surfaces
      // already render as "no claim" — plain ink, no raised step, no suffix.
      // The reading is still drawn, and the qualifier next to it says what it
      // is. A thermometer reading she typed in is graded exactly as before.
      if (source != ReadingSource.manual) return MetricStatus.normal;
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
      // Normal, not a fourth "ungraded" tier, for the same reason as
      // temperature: normal is what every surface already renders as "no
      // claim". Today nothing in the app grades a device blood sugar — the
      // wellness tile that did was removed with this ruling — so this branch is
      // the guard that keeps it that way when a new surface arrives.
      if (source != ReadingSource.manual) return MetricStatus.normal;
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
MetricStatus worstStatus(Iterable<MetricStatus> xs) {
  var worst = MetricStatus.normal;
  for (final s in xs) {
    if (s.index > worst.index) worst = s;
  }
  return worst;
}
