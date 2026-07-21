/// Pure-Dart verification of HealthMonitor — the orchestration brain that
/// decides what a reading causes: a sync, an escalation, and what the assistant
/// is told about her current state.
/// `dart run tool/verify_health_monitor.dart`
library;

import 'dart:async';
import 'dart:io';
import '../lib/core/triage.dart';
import '../lib/domain/health_monitor.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

/// A reading the triage rules treat as an emergency.
const _critical = BandTelemetry(systolicMmHg: 175, diastolicMmHg: 118);
const _calm = BandTelemetry(systolicMmHg: 118, diastolicMmHg: 74);

void main() async {
  // ---- What reaches the batcher, and how ----
  {
    final sent = <(Map<String, dynamic>, bool)>[];
    final raised = <TriageResult>[];
    var clock = DateTime.utc(2026, 7, 20, 8, 0);
    final m = HealthMonitor(
      deviceId: 'band-1',
      enqueue: (t, {required urgent}) => sent.add((t, urgent)),
      onEmergency: (tr, _) => raised.add(tr),
      now: () => clock,
    );

    m.handle(_calm, assessTelemetry(_calm));
    _chk('a calm reading is enqueued', sent.length == 1);
    _chk('a calm reading is not urgent', sent.single.$2 == false);
    _chk('a calm reading raises nothing', raised.isEmpty);
    _chk('the wire carries the device id', sent.single.$1['deviceId'] == 'band-1');
    _chk('the wire carries a UTC timestamp',
        (sent.single.$1['recordedAt'] as String).endsWith('Z'));
    _chk('the wire carries the reading', sent.single.$1['systolicMmHg'] == 118);

    m.handle(_critical, assessTelemetry(_critical));
    _chk('a critical reading bypasses the batch', sent.last.$2 == true);
    _chk('a critical reading opens the rescue screen', raised.length == 1);
  }

  // ---- record() remembers without re-sending ----
  {
    final sent = <Map<String, dynamic>>[];
    var clock = DateTime.utc(2026, 7, 20, 8, 0);
    final m = HealthMonitor(
      deviceId: 'manual',
      enqueue: (t, {required urgent}) => sent.add(t),
      onEmergency: (_, __) {},
      now: () => clock,
    );

    // A hand-entered cuff reading: the controller has already queued and
    // triaged it. handle() would send it a second time.
    m.record(_calm, assessTelemetry(_calm));
    _chk('record() sends nothing', sent.isEmpty);
    _chk('record() is what the assistant reads', m.latest?.systolicMmHg == 118);
    _chk('record() stamps when it happened', m.latestAt == clock);
  }

  // ---- The reading the assistant sees must expire ----
  //
  // latest is attached to every chat message, and the server treats a critical
  // one as grounds to skip the model entirely and open the Emergency Rescue
  // screen. Nothing expired it: a reading entered on Monday — acted on,
  // treated, resolved — was still attached on Friday, so an unrelated question
  // about a mild headache was answered by throwing the emergency screen at her
  // again. That is how an emergency screen stops being read.
  {
    var clock = DateTime.utc(2026, 7, 20, 8, 0);
    final m = HealthMonitor(
      deviceId: 'manual',
      enqueue: (t, {required urgent}) {},
      onEmergency: (_, __) {},
      now: () => clock,
    );

    _chk('nothing recorded yet reads as no reading', m.latest == null);

    m.record(_critical, assessTelemetry(_critical));
    _chk('a fresh reading is attached', m.latest?.systolicMmHg == 175);
    _chk('and so is its triage', m.latestTriage?.forceEmergencyScreen == true);

    clock = clock.add(const Duration(hours: 5, minutes: 59));
    _chk('still current at 5h59', m.latest?.systolicMmHg == 175);

    clock = clock.add(const Duration(minutes: 2)); // 6h01
    _chk('expired just past six hours', m.latest == null);
    _chk('its triage expires with it', m.latestTriage == null);

    clock = clock.add(const Duration(days: 4)); // the Monday-to-Friday case
    _chk('four days later it is certainly gone',
        m.latest == null && m.latestTriage == null);

    // The value itself is not forgotten — the vitals card still shows it with
    // its timestamp, which stays honest as it ages. Only the assistant's
    // "this is how she is right now" claim expires.
    _chk('the timestamp survives expiry', m.latestAt == DateTime.utc(2026, 7, 20, 8, 0));

    // A new reading revives it.
    m.record(_calm, assessTelemetry(_calm));
    _chk('a new reading is current again', m.latest?.systolicMmHg == 118);
  }

  // ---- Binding twice must not double-handle ----
  {
    final sent = <Map<String, dynamic>>[];
    final ctrl = StreamController<(BandTelemetry, TriageResult)>.broadcast();
    final m = HealthMonitor(
      deviceId: 'band-1',
      enqueue: (t, {required urgent}) => sent.add(t),
      onEmergency: (_, __) {},
      now: () => DateTime.utc(2026, 7, 20, 8, 0),
    );

    m.bind(ctrl.stream);
    m.bind(ctrl.stream); // a re-pair
    ctrl.add((_calm, assessTelemetry(_calm)));
    await Future<void>.delayed(Duration.zero);
    _chk('re-binding does not enqueue the same reading twice', sent.length == 1);

    await m.dispose();
    ctrl.add((_calm, assessTelemetry(_calm)));
    await Future<void>.delayed(Duration.zero);
    _chk('nothing arrives after dispose', sent.length == 1);
    await ctrl.close();
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
