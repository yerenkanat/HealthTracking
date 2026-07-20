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
import '../lib/domain/family.dart';
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
  // Movable, because escalation now depends on a condition PERSISTING across
  // readings — a frozen clock cannot express that.
  var clock = now;
  final ctl = AppController(store: SampleStore(), now: () => clock);
  final sub = ctl.changes.listen((_) => notifications++);

  ctl.onTelemetry(const BandTelemetry(heartRateBpm: 80),
      assessTelemetry(const BandTelemetry(heartRateBpm: 80)));
  await Future<void>.delayed(Duration.zero);
  _chk('normal telemetry: route stays home', ctl.route == AppRoute.home);
  _chk('normal telemetry: sample recorded', ctl.samples.length == 1);
  _chk('normal telemetry: emitted a change', notifications == 1);

  // ---- Emergency latching from telemetry ----
  // One sensor estimate no longer takes over her screen. A wrist PPG carries
  // ±10-15 mmHg of error and blood pressure spikes transiently with movement,
  // so the first crossing asks for another reading; a condition that persists
  // escalates. See lib/domain/emergency_confirmation.dart.
  final emT = const BandTelemetry(systolicMmHg: 150, diastolicMmHg: 95);
  ctl.onTelemetry(emT, assessTelemetry(emT));
  await Future<void>.delayed(Duration.zero);
  _chk('one high estimate does NOT take over the screen', ctl.route == AppRoute.home);
  _chk('one high estimate does not latch the emergency flag', !ctl.emergencyActive);
  _chk('but it does ask for a repeat reading', ctl.awaitingRepeat == 'bp');

  // Still high two minutes on — that is a condition, not an artifact.
  clock = clock.add(const Duration(minutes: 2));
  ctl.onTelemetry(emT, assessTelemetry(emT));
  await Future<void>.delayed(Duration.zero);
  _chk('a crossing that persists escalates', ctl.route == AppRoute.emergency);
  _chk('emergency: active flag set', ctl.emergencyActive);
  _chk('emergency: has message + ambulance button',
      (ctl.emergency?.message.isNotEmpty ?? false) && ctl.emergency!.callButtons.first.tel == '103');
  _chk('escalating clears the repeat prompt', ctl.awaitingRepeat == null);

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

  // ---- Emergency call buttons ----
  // app.dart picks a localized label by MATCHING these strings. If the two
  // sides ever drift the switch falls through and ships English to the
  // emergency screen, so the labels the controller emits must all be known.
  {
    var t = DateTime(2026, 7, 16, 9);
    final em = AppController(now: () => t);
    em.updateProfile(const UserProfile(
      displayName: 'Aigerim', dialCode: '+7', phoneNumber: '7001112233', doctorPhone: '+77011234567'));
    const severe = BandTelemetry(systolicMmHg: 170, diastolicMmHg: 115);
    // Severe range is confirmed too. A single PPG estimate of 170 is at least
    // as likely to be an artifact as a reading, and two minutes is a small
    // price against telling a healthy woman to seek emergency care.
    em.onTelemetry(severe, assessTelemetry(severe));
    _chk('even severe-range needs a second reading', em.emergency == null);
    t = t.add(const Duration(minutes: 2));
    em.onTelemetry(severe, assessTelemetry(severe));
    final buttons = em.emergency!.callButtons;
    _chk('an emergency offers a way to call someone', buttons.isNotEmpty);
    _chk('every default label is one app.dart can localize',
        buttons.every((b) => EmergencyLabels.all.contains(b.label)));
    _chk('the doctor is offered first when one is known',
        buttons.first.label == EmergencyLabels.doctor);
    // She will be asked "what was the reading?" on the phone. It has to be on
    // the screen she is already looking at.
    _chk('the emergency carries the reading that caused it',
        em.emergency?.readingKind == 'bp' && em.emergency?.readingValue == '170/115');
    _chk('blood pressure shows both numbers, not just the one that crossed',
        (em.emergency?.readingValue ?? '').contains('/'));
    _chk('the ambulance is always offered',
        buttons.any((b) => b.tel == EmergencyLabels.ambulanceTel));

    // With no doctor recorded there is still a way to get help.
    var nd = DateTime(2026, 7, 16, 9);
    final noDoc = AppController(now: () => nd);
    noDoc.onTelemetry(severe, assessTelemetry(severe));
    nd = nd.add(const Duration(minutes: 2));
    noDoc.onTelemetry(severe, assessTelemetry(severe));
    _chk('without a doctor the ambulance is still offered',
        noDoc.emergency!.callButtons.single.tel == EmergencyLabels.ambulanceTel);

    // A later ordinary reading must NOT silently clear the emergency: it has
    // to be dismissed deliberately, or a transient dip would hide a real one.
    em.onTelemetry(
      const BandTelemetry(systolicMmHg: 118, diastolicMmHg: 76),
      assessTelemetry(const BandTelemetry(systolicMmHg: 118, diastolicMmHg: 76)),
    );
    _chk('a normal reading does not clear a latched emergency',
        em.route == AppRoute.emergency && em.emergencyActive);
    em.dismissEmergency();
    _chk('dismissing returns to the app', em.route == AppRoute.home && !em.emergencyActive);
    await em.dispose();
    await noDoc.dispose();
  }

  // ---- Reminder notification ids ----
  // Appointment reminders derive their id from a hash, so nothing stopped one
  // from landing on a fixed reminder id (period/fertile/water/medication) and
  // silently cancelling or overwriting it. They now map into a reserved block,
  // which makes that impossible rather than merely improbable.
  const fixedReminderIds = {800001, 800002, 900001, 900002};
  const base = AppController.appointmentIdBase;
  const span = AppController.appointmentIdSpan;
  var outOfBlock = 0, hitFixed = 0;
  const micros = 1750000000000000;
  for (var i = 0; i < 50000; i++) {
    final n = AppController.reminderIdFor('apt-${micros + i * 997}-${i % 7}');
    if (n < base || n >= base + span) outOfBlock++;
    if (fixedReminderIds.contains(n)) hitFixed++;
  }
  _chk('appointment reminder ids stay inside the reserved block', outOfBlock == 0);
  _chk('appointment reminder ids never hit a fixed reminder id', hitFixed == 0);
  _chk('no fixed reminder id falls in the appointment block',
      !fixedReminderIds.any((f) => f >= base && f < base + span));
  // Cancelling after a restart looks the id up again, so it must be reproducible
  // for the same appointment — otherwise the notification could never be cleared.
  _chk('a reminder id is reproducible for the same appointment',
      AppController.reminderIdFor('apt-42-0') == AppController.reminderIdFor('apt-42-0'));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
