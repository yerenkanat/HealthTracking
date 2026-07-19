/// Dart-side cross-language contract test (run with `flutter test` / `dart test`).
/// Loads the SAME golden vectors the Node server runs and asserts identical
/// verdicts. Mirrors packages/shared/src/__tests__/contract.test.ts.
library;
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

import 'package:fcs_app/core/triage.dart';

Map<String, dynamic> _read(String rel) => jsonDecode(
    File('${Directory.current.path}/../packages/contract/$rel').readAsStringSync())
    as Map<String, dynamic>;

void main() {
  final th = _read('triage_thresholds.json');
  final vectors = _read('triage_vectors.json');

  group('thresholds match shared JSON contract', () {
    final bp = th['bloodPressure'] as Map<String, dynamic>;
    test('bp', () {
      expect(TriageThresholds.bpSystolicEmergency, bp['systolicEmergency']);
      expect(TriageThresholds.bpDiastolicSevere, bp['diastolicSevere']);
    });
    test('temp/spo2/hr', () {
      expect(TriageThresholds.feverEmergencyC, th['temperatureC']['feverEmergency']);
      expect(TriageThresholds.spo2Warning, th['spo2Pct']['warning']);
      expect(TriageThresholds.hrBradyEmergency, th['heartRateBpm']['bradyEmergency']);
    });
  });

  group('golden vectors → identical verdicts', () {
    for (final raw in vectors['cases'] as List) {
      final c = raw as Map<String, dynamic>;
      test(c['name'] as String, () {
        final r = assessTelemetry(
            BandTelemetry.fromJson((c['input'] as Map).cast<String, dynamic>()));
        expect(severityToString(r.severity), c['severity']);
        expect(r.forceEmergencyScreen, c['forceEmergencyScreen']);
        if (c['topCode'] != null) {
          expect(r.findings.first.code, c['topCode']);
        }
      });
    }
  });
}
