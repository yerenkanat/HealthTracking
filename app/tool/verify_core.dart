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
