/// Pure-Dart verification of SampleStore + AppController (state, emergency
/// latching, navigation route, change notifications).
/// `dart run tool/verify_app.dart`
library;

import 'dart:async';
import 'dart:io';

import '../lib/data/sample_store.dart';
import '../lib/app/app_controller.dart';
import '../lib/core/triage.dart';
import '../lib/core/geofence.dart';
import '../lib/domain/health_series.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

Future<void> main() async {
  final now = DateTime.utc(2026, 7, 15, 9, 0);

  // ---- SampleStore ----
  final store = SampleStore(capacity: 3);
  for (var i = 0; i < 5; i++) {
    store.addSample(HealthSample(at: now.add(Duration(minutes: i)), heartRate: 70.0 + i));
  }
  _chk('store capped at 3', store.length == 3);
  _chk('store dropped oldest (latest hr=74)', store.latest?.heartRate == 74);
  _chk('store keeps order', store.all.first.heartRate == 72 && store.all.last.heartRate == 74);
  _chk('store recent window filters', store.recent(const Duration(minutes: 1), now.add(const Duration(minutes: 4))).length == 1);

  // ---- AppController: normal telemetry, no emergency ----
  var notifications = 0;
  final ctl = AppController(store: SampleStore(), now: () => now);
  final sub = ctl.changes.listen((_) => notifications++);

  ctl.onTelemetry(const BandTelemetry(heartRateBpm: 80),
      assessTelemetry(const BandTelemetry(heartRateBpm: 80)));
  await Future<void>.delayed(Duration.zero);
  _chk('normal telemetry: route stays home', ctl.route == AppRoute.home);
  _chk('normal telemetry: sample recorded', ctl.samples.length == 1);
  _chk('normal telemetry: emitted a change', notifications == 1);

  // ---- Emergency latching from telemetry ----
  final emT = const BandTelemetry(systolicMmHg: 150, diastolicMmHg: 95);
  ctl.onTelemetry(emT, assessTelemetry(emT));
  await Future<void>.delayed(Duration.zero);
  _chk('emergency telemetry: route -> emergency', ctl.route == AppRoute.emergency);
  _chk('emergency: active flag set', ctl.emergencyActive);
  _chk('emergency: has message + ambulance button',
      (ctl.emergency?.message.isNotEmpty ?? false) && ctl.emergency!.callButtons.first.tel == '103');

  // ---- Dismissal returns to home ----
  ctl.dismissEmergency();
  await Future<void>.delayed(Duration.zero);
  _chk('dismiss: route back to home', ctl.route == AppRoute.home);
  _chk('dismiss: emergency cleared', ctl.emergency == null);

  // ---- Chat-driven emergency ----
  ctl.onChatEmergency('Server says BP is dangerous.', const [(label: 'Doctor', tel: '+7700')]);
  await Future<void>.delayed(Duration.zero);
  _chk('chat emergency: route -> emergency', ctl.route == AppRoute.emergency);
  _chk('chat emergency: custom button preserved', ctl.emergency?.callButtons.first.tel == '+7700');

  // ---- Child location ----
  ctl.onChildLocation(const Coordinates(43.238949, 76.889709));
  await Future<void>.delayed(Duration.zero);
  _chk('child location stored', ctl.childLocation?.coords.lat == 43.238949);

  await sub.cancel();
  await ctl.dispose();

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
