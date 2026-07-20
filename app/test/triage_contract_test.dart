/// Dart-side cross-language contract test (run with `flutter test` / `dart test`).
/// Loads the SAME golden vectors the Node server runs and asserts identical
/// verdicts. Mirrors packages/shared/src/__tests__/contract.test.ts.
library;
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

import 'package:fcs_app/ble/calibration.dart' show maxSystolicOffset, maxDiastolicOffset;
import 'package:fcs_app/core/triage.dart';

Map<String, dynamic> _read(String rel) => jsonDecode(
    File('${Directory.current.path}/../packages/contract/$rel').readAsStringSync())
    as Map<String, dynamic>;

void main() {
  final th = _read('triage_thresholds.json');
  final vectors = _read('triage_vectors.json');

  group('thresholds match shared JSON contract', () {
    // EXHAUSTIVE on purpose. This used to spot-check five of the twelve values,
    // which meant seven — including bpDiastolicEmergency, the one that decides
    // whether a 90 diastolic raises preeclampsia — could drift from the contract
    // with nothing failing. Every constant is listed, and the count is asserted
    // so adding one to the contract without checking it here fails too.
    final expected = <String, Object>{
      'bloodPressure.systolicEmergency': TriageThresholds.bpSystolicEmergency,
      'bloodPressure.diastolicEmergency': TriageThresholds.bpDiastolicEmergency,
      'bloodPressure.systolicSevere': TriageThresholds.bpSystolicSevere,
      'bloodPressure.diastolicSevere': TriageThresholds.bpDiastolicSevere,
      'temperatureC.feverEmergency': TriageThresholds.feverEmergencyC,
      'temperatureC.feverWarning': TriageThresholds.feverWarningC,
      'spo2Pct.emergency': TriageThresholds.spo2Emergency,
      'spo2Pct.warning': TriageThresholds.spo2Warning,
      'heartRateBpm.tachyWarning': TriageThresholds.hrTachyWarning,
      'heartRateBpm.tachyEmergency': TriageThresholds.hrTachyEmergency,
      'heartRateBpm.bradyWarning': TriageThresholds.hrBradyWarning,
      'heartRateBpm.bradyEmergency': TriageThresholds.hrBradyEmergency,
      'bpCalibration.maxSystolicOffset': maxSystolicOffset,
      'bpCalibration.maxDiastolicOffset': maxDiastolicOffset,
    };

    for (final e in expected.entries) {
      test(e.key, () {
        final parts = e.key.split('.');
        final section = (th[parts[0]] as Map).cast<String, dynamic>();
        expect(section[parts[1]], isNotNull,
            reason: '${e.key} is missing from the contract');
        expect(e.value, section[parts[1]]);
      });
    }

    test('every value in the contract is covered by a check', () {
      // Without this, adding a threshold to the JSON and forgetting to pin it
      // in Dart would pass silently — which is exactly how drift starts.
      final inContract = <String>{};
      for (final section in th.entries) {
        if (section.key.startsWith('_') || section.value is! Map) continue;
        for (final k in (section.value as Map).keys) {
          if ('$k'.startsWith('_')) continue;
          inContract.add('${section.key}.$k');
        }
      }
      expect(inContract.difference(expected.keys.toSet()), isEmpty,
          reason: 'contract values with no Dart assertion');
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
