/// Dependency-free conformance runner: `dart run tool/verify_core.dart`.
/// Verifies the Dart safety core (1) matches the shared JSON thresholds,
/// (2) produces the exact golden-vector verdicts (same file the Node server runs),
/// and (3) that geofence hysteresis / parsers / calibration behave.
/// No package: imports → runs without `flutter pub get`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/core/triage.dart';
import '../lib/core/geofence.dart';
import '../lib/ble/parsers/band_parser.dart';
import '../lib/ble/parsers/beacon_parser.dart';
import '../lib/ble/calibration.dart';

int _pass = 0, _fail = 0;
void _chk(String name, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $name');
}

Map<String, dynamic> _readJson(String rel) {
  final uri = Platform.script.resolve(rel);
  return jsonDecode(File.fromUri(uri).readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  // ---- 1. Thresholds match the shared contract ----
  final th = _readJson('../../packages/contract/triage_thresholds.json');
  final bp = th['bloodPressure'] as Map<String, dynamic>;
  _chk('threshold systolicEmergency==140',
      TriageThresholds.bpSystolicEmergency == bp['systolicEmergency']);
  _chk('threshold diastolicSevere==110',
      TriageThresholds.bpDiastolicSevere == bp['diastolicSevere']);
  _chk('threshold feverEmergency==38.5',
      TriageThresholds.feverEmergencyC == th['temperatureC']['feverEmergency']);
  _chk('threshold spo2Warning==95',
      TriageThresholds.spo2Warning == th['spo2Pct']['warning']);
  _chk('threshold hrBradyEmergency==40',
      TriageThresholds.hrBradyEmergency == th['heartRateBpm']['bradyEmergency']);

  // ---- 2. Golden vectors → identical verdicts to the Node server ----
  final vectors = _readJson('../../packages/contract/triage_vectors.json');
  for (final raw in vectors['cases'] as List) {
    final c = raw as Map<String, dynamic>;
    final t = BandTelemetry.fromJson((c['input'] as Map).cast<String, dynamic>());
    final r = assessTelemetry(t);
    final sevOk = severityToString(r.severity) == c['severity'];
    final emgOk = r.forceEmergencyScreen == c['forceEmergencyScreen'];
    final codeOk = c['topCode'] == null ||
        (r.findings.isNotEmpty && r.findings.first.code == c['topCode']);
    _chk('vector ${c['name']}', sevOk && emgOk && codeOk);
  }

  // ---- 3. Geofence geometry + hysteresis ----
  final school = Geofence.circle(
      'school', 'School', const Coordinates(43.238949, 76.889709), 100);
  final far = const Coordinates(43.245, 76.9);
  final inside = school.center!;
  _chk('geo center inside', checkGeofenceBoundary(inside, school).inside);
  _chk('geo far outside', !checkGeofenceBoundary(far, school).inside);
  _chk('geo haversine >100m',
      haversineM(const Coordinates(43.238949, 76.889709),
              const Coordinates(43.239949, 76.889709)) >
          100);

  final tracker = GeofenceTracker(
      [school], const HysteresisConfig(bufferM: 30, confirmations: 2, maxAccuracyM: 100));
  _chk('geo establish outside no emit', tracker.update(far, 10).isEmpty);
  _chk('geo 1st confirm no emit', tracker.update(inside, 10).isEmpty);
  final ev = tracker.update(inside, 10);
  _chk('geo 2nd confirm emits ONE enter',
      ev.length == 1 && ev.first.transition == GeofenceTransition.enter);
  _chk('geo staying inside no re-fire (jitter)', tracker.update(inside, 10).isEmpty);
  _chk('geo low-accuracy fix ignored',
      GeofenceTracker([school]).update(inside, 500).isEmpty);

  // ---- 4. Band parser (build a valid HR frame with XOR checksum) ----
  final hrFrame = _frame(BandCmd.heartRate, [82]); // 82 bpm
  final pr = parseBandFrame(hrFrame, validateChecksum: true);
  _chk('band HR frame parses to 82', pr.ok && pr.frame.heartRateBpm == 82);
  final tempFrame = _frame(BandCmd.temperature, [0x0E, 0x42]); // 3650 => 36.50C skin
  final tr = parseBandFrame(tempFrame, validateChecksum: true);
  _chk('band temp skin 36.5 => core computed',
      tr.ok && tr.frame.skinTempC == 36.5 && (tr.frame.coreTempC ?? 0) > 36.5);
  _chk('band rejects bad header',
      !parseBandFrame(Uint8List.fromList([0x00, 0x15, 0, 1, 82, 0])).ok);

  // ---- 5. Calibration ----
  final cbp = applyBpCalibration(120, 80,
      BpCalibration(8, -3, DateTime.parse('2026-07-14T00:00:00Z')),
      now: DateTime.parse('2026-07-15T00:00:00Z'));
  _chk('calib applies offset 120+8/80-3', cbp.systolic == 128 && cbp.diastolic == 77);
  _chk('calib fresh not stale', !cbp.calibrationStale);
  _chk('calib skin->core clamps sane', skinToCoreTempC(30) >= 34.0);

  // ---- 6. Beacon distance smoother (median kills a spike) ----
  final sm = DistanceSmoother(5);
  sm.push(2);
  sm.push(2);
  sm.push(50); // one bad spike
  sm.push(2);
  sm.push(2);
  _chk('beacon smoother median ~2 despite spike', sm.push(2) <= 2.0);

  // ---- A zone must be enterable at any radius ----
  // "Inside" requires being inside by at least the hysteresis buffer, and the
  // deepest you can be inside a circle is its radius. A fence no bigger than the
  // buffer was therefore impossible to enter — a permanently silent safe-zone.
  // The UI's 50m minimum only masked this; imported backups carry any radius.
  const spot = Coordinates(43.238949, 76.889709);
  bool entersAtCentre(double radiusM) {
    final t = GeofenceTracker([Geofence.circle('z', 'Z', spot, radiusM)]);
    for (var i = 0; i < 5; i++) {
      if (t.update(spot).any((h) => h.transition == GeofenceTransition.enter)) return true;
    }
    return false;
  }

  _chk('a tiny zone can still be entered', entersAtCentre(15));
  _chk('a zone the size of the buffer can be entered', entersAtCentre(30));
  _chk('an ordinary zone can be entered', entersAtCentre(100));
  // Normal zones keep the full configured buffer — the clamp must not loosen
  // drift protection where it was already working.
  final drifty = GeofenceTracker([Geofence.circle('z', 'Z', spot, 100)]);
  drifty.update(spot);
  drifty.update(spot); // now confirmed inside
  // ~120m north of centre: 20m past a 100m edge, i.e. still inside the 30m band.
  final justOutsideBuffer = Coordinates(spot.lat + 120 / 111320, spot.lng);
  var flapped = false;
  for (var i = 0; i < 5; i++) {
    if (drifty.update(justOutsideBuffer).isNotEmpty) flapped = true;
  }
  _chk('drift inside the buffer band does not flap a normal zone', !flapped);

  // ---- Malformed-frame safety ----
  // Frames arrive from an external device, so the parsers must REJECT bad input
  // rather than throw. The band frame states its own payload length, which a
  // truncated frame can overstate — that used to reach sublistView and blow up.
  var bandThrew = 0, beaconThrew = 0, checked = 0;
  for (var len = 0; len <= 40; len++) {
    for (final cmd in [0x01, 0x02, 0x03, 0x04, 0x05, 0x10, 0xFF]) {
      for (final plen in [0, 1, 2, 3, 4, 5, 200, 65535]) {
        final b = Uint8List(len);
        if (len > 0) b[0] = 0xAB; // header-shaped
        if (len > 1) b[1] = cmd;
        if (len > 2) b[2] = (plen >> 8) & 0xFF;
        if (len > 3) b[3] = plen & 0xFF;
        for (var i = 4; i < len; i++) {
          b[i] = 70;
        }
        checked++;
        try {
          parseBandFrame(b);
        } catch (_) {
          bandThrew++;
        }
      }
    }
    final r = Uint8List(len);
    for (var i = 0; i < len; i++) {
      r[i] = (i * 37 + 11) & 0xFF;
    }
    if (len > 1) {
      r[0] = 0x4C;
      r[1] = 0x00; // Apple company id, so it gets past the early return
    }
    if (len > 3) {
      r[2] = 0x02;
      r[3] = 0x15;
    }
    try {
      parseIBeacon(r, -60, DateTime(2026));
    } catch (_) {
      beaconThrew++;
    }
  }
  _chk('malformed band frames never throw ($checked cases)', bandThrew == 0);
  _chk('truncated beacon adverts never throw', beaconThrew == 0);
  // A frame claiming more payload than it carries is rejected, not trusted.
  final overstated = Uint8List.fromList([0xAB, 0x01, 0x00, 0x40, 70]);
  _chk('overstated payload length is refused', !parseBandFrame(overstated).ok);

  // ---- Triage boundary invariants ----
  // The golden vectors pin specific readings; these pin the SHAPE of the rules
  // across every value in range, which is where an inverted comparison or a
  // mis-copied threshold hides — and this is the logic that decides whether a
  // pregnant user is shown an emergency screen.
  int rank(TriageSeverity s) => switch (s) {
        TriageSeverity.ok => 0,
        TriageSeverity.info => 1,
        TriageSeverity.warning => 2,
        TriageSeverity.emergency => 3,
      };

  // Severity must never fall as a reading gets more dangerous.
  bool monotone(Iterable<BandTelemetry> worsening) {
    var prev = -1;
    for (final t in worsening) {
      final r = rank(assessTelemetry(t).severity);
      if (r < prev) return false;
      prev = r;
    }
    return true;
  }

  _chk('rising systolic never gets less severe',
      monotone([for (var s = 80; s <= 220; s++) BandTelemetry(systolicMmHg: s, diastolicMmHg: 70)]));
  _chk('rising diastolic never gets less severe',
      monotone([for (var d = 40; d <= 140; d++) BandTelemetry(systolicMmHg: 110, diastolicMmHg: d)]));
  _chk('rising temperature never gets less severe',
      monotone([for (var i = 350; i <= 420; i++) BandTelemetry(coreTempC: i / 10.0)]));
  _chk('falling SpO2 never gets less severe',
      monotone([for (var p = 100; p >= 50; p--) BandTelemetry(spo2Pct: p)]));
  _chk('rising heart rate never gets less severe',
      monotone([for (var h = 75; h <= 220; h++) BandTelemetry(heartRateBpm: h)]));
  _chk('falling heart rate never gets less severe',
      monotone([for (var h = 75; h >= 20; h--) BandTelemetry(heartRateBpm: h)]));

  // More information must never make a reading look SAFER.
  var reducedBySecondMetric = 0;
  for (var s = 90; s <= 200; s += 5) {
    for (var h = 30; h <= 200; h += 5) {
      final alone = rank(assessTelemetry(BandTelemetry(systolicMmHg: s, diastolicMmHg: 70)).severity);
      final withHr = rank(
          assessTelemetry(BandTelemetry(systolicMmHg: s, diastolicMmHg: 70, heartRateBpm: h)).severity);
      if (withHr < alone) reducedBySecondMetric++;
    }
  }
  _chk('adding a second reading never lowers severity', reducedBySecondMetric == 0);

  // Every finding must name the metric it actually measured and genuinely cross
  // the threshold it cites — otherwise the emergency screen shows a wrong number.
  var inconsistent = 0;
  void checkFindings(BandTelemetry t) {
    for (final f in assessTelemetry(t).findings) {
      final v = f.value, th = f.threshold;
      if (v == null || th == null) continue;
      final actual = switch (f.metric) {
        'systolicMmHg' => t.systolicMmHg,
        'diastolicMmHg' => t.diastolicMmHg,
        'coreTempC' => t.coreTempC,
        'spo2Pct' => t.spo2Pct,
        'heartRateBpm' => t.heartRateBpm,
        _ => null,
      };
      if (actual != null && actual != v) {
        inconsistent++;
        continue;
      }
      final crosses = f.code.startsWith('HYPOXIA')
          ? v < th
          : f.code.startsWith('BRADY')
              ? v <= th
              : v >= th;
      if (!crosses) inconsistent++;
    }
  }

  for (var s = 0; s <= 240; s += 3) {
    for (var d = 0; d <= 160; d += 3) {
      checkFindings(BandTelemetry(systolicMmHg: s, diastolicMmHg: d));
    }
    checkFindings(BandTelemetry(systolicMmHg: s)); // partial BP: the other half is null
  }
  for (var d = 0; d <= 160; d++) {
    checkFindings(BandTelemetry(diastolicMmHg: d));
  }
  for (var i = 300; i <= 440; i++) {
    checkFindings(BandTelemetry(coreTempC: i / 10.0));
  }
  for (var p = 0; p <= 100; p++) {
    checkFindings(BandTelemetry(spo2Pct: p));
    checkFindings(BandTelemetry(spo2Pct: p, duringSleep: true));
  }
  for (var h = 0; h <= 260; h++) {
    checkFindings(BandTelemetry(heartRateBpm: h));
  }
  _chk('every finding names its own metric and crosses its threshold', inconsistent == 0);

  // An emergency must always raise the screen, and no reading at all is not one.
  var unforced = 0;
  for (var s = 60; s <= 240; s += 3) {
    for (var i = 340; i <= 430; i += 7) {
      final r = assessTelemetry(BandTelemetry(systolicMmHg: s, coreTempC: i / 10.0));
      if (r.severity == TriageSeverity.emergency && !r.forceEmergencyScreen) unforced++;
    }
  }
  _chk('an emergency severity always forces the emergency screen', unforced == 0);
  final none = assessTelemetry(const BandTelemetry());
  _chk('telemetry with no readings is not an emergency',
      none.severity == TriageSeverity.ok && none.findings.isEmpty && !none.forceEmergencyScreen);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}

/// Build a DaFit-style frame: [0xCD, cmd, lenHi, lenLo, ...payload, xorChecksum].
Uint8List _frame(int cmd, List<int> payload) {
  final body = <int>[0xCD, cmd, (payload.length >> 8) & 0xFF, payload.length & 0xFF, ...payload];
  var xor = 0;
  for (final b in body) {
    xor ^= b;
  }
  return Uint8List.fromList([...body, xor]);
}
