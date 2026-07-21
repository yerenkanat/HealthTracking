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
import '../lib/domain/geofence_alerts.dart';
import '../lib/domain/manual_vitals.dart';
import '../lib/l10n/l10n.dart';

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

  // ---- Reset erases EVERYTHING ----
  // It used to clear nine fields by hand and leave the rest behind: weights,
  // medications, appointments, hand-entered vitals, the water log, kick and
  // contraction sessions, battery history, cycle settings. A reset done before
  // selling a phone, or to exercise a right to erasure, kept most of the
  // record. Defining reset as "apply an empty config" makes coverage automatic;
  // these assertions are what would have caught the old version.
  {
    final t = DateTime(2026, 7, 20, 9);
    final r = AppController(now: () => t);
    r.updateProfile(const UserProfile(
        displayName: 'Aigerim', dialCode: '+7', phoneNumber: '7001112233', city: 'Almaty'));
    r.configureChild(name: 'Sultan', fences: const []);
    r.logWeight(t, 64.0);
    r.setWeightGoal(70);
    r.addMedication('Folic acid');
    r.addAppointment('OB visit', t.add(const Duration(days: 3)));
    r.addWater(t, 4);
    r.logManualVitals(const ManualVitals(systolic: 118, diastolic: 76));
    r.logChildEvent(AlertKind.checkIn);
    r.debugMarkOnboarded();

    await r.resetApp();

    _chk('reset clears the profile', r.profile.displayName.isEmpty && r.profile.city.isEmpty);
    _chk('reset clears children', r.children.isEmpty);
    _chk('reset clears weights', r.weights.isEmpty);
    _chk('reset clears the weight goal', r.weightGoalKg == null);
    _chk('reset clears medications', r.medications.isEmpty);
    _chk('reset clears appointments', r.appointments.isEmpty);
    _chk('reset clears the water log', r.waterLog.isEmpty);
    _chk('reset clears hand-entered vitals', r.manualSamples.isEmpty);
    _chk('reset clears the alert feed', r.alerts.isEmpty);
    _chk('reset returns to onboarding', !r.onboarded);
    // ...but not her language: that is how she reads the screen, not her data.
    _chk('reset keeps the chosen language', r.locale == AppLocale.ru);
    r.dispose();
  }

  // ---- Replacing the data must revoke its reminders ----
  // Scheduling with the OS is one-way: a notification survives until it fires
  // or is cancelled, and it does not care that the appointment behind it is
  // gone. Import replaced the data and armed the new reminders WITHOUT
  // revoking the old ones, and erase did neither — so a wiped phone went on
  // announcing her gynaecologist appointment from her lock screen.
  {
    final t = DateTime(2026, 7, 20, 9);
    final r = AppController(now: () => t);
    final cancelled = <int>[];
    final scheduled = <int>[];
    final sub2 = r.reminderCommands.listen((cmd) {
      (cmd.at == null ? cancelled : scheduled).add(cmd.id);
    });

    r.addAppointment('OB visit', t.add(const Duration(days: 3)));
    final apptId = r.appointments.single.id;
    await Future<void>.delayed(Duration.zero);
    _chk('adding an appointment schedules its reminder',
        scheduled.contains(AppController.reminderIdFor(apptId)));

    cancelled.clear();
    scheduled.clear();
    await r.resetApp();
    await Future<void>.delayed(Duration.zero);
    _chk('erasing revokes the appointment reminder',
        cancelled.contains(AppController.reminderIdFor(apptId)));
    _chk('erasing revokes the cycle reminders too', cancelled.length >= 3);
    _chk('erasing schedules nothing new', scheduled.isEmpty);

    await sub2.cancel();
    await r.dispose();
  }

  {
    // Import: the reminders of the data being REPLACED have to go, or the
    // phone fires for appointments the import just deleted.
    final t = DateTime(2026, 7, 20, 9);
    final src = AppController(now: () => t);
    src.debugMarkOnboarded();
    src.addAppointment('Scan', t.add(const Duration(days: 5)));
    final backup = src.exportJson();
    await src.dispose();

    final dst = AppController(now: () => t);
    dst.addAppointment('Old visit', t.add(const Duration(days: 2)));
    final staleId = AppController.reminderIdFor(dst.appointments.single.id);

    final cancelled = <int>[];
    final sub3 = dst.reminderCommands.listen((cmd) {
      if (cmd.at == null) cancelled.add(cmd.id);
    });
    dst.importJson(backup);
    await Future<void>.delayed(Duration.zero);
    _chk('importing revokes the reminder of the appointment it replaced',
        cancelled.contains(staleId));
    _chk('and the imported appointment is the one that remains',
        dst.appointments.single.title == 'Scan');

    await sub3.cancel();
    await dst.dispose();
  }

  // ---- A server-supplied position carries the time it was OBSERVED ----
  // The tracking screen decides "live" or "8 minutes ago" from this timestamp,
  // and a fix fetched now may have been recorded minutes back. Stamping it with
  // now() would call a stale position live, which is the one thing a child
  // tracker must not do.
  {
    final t = DateTime(2026, 7, 21, 12, 0);
    final c = AppController(now: () => t);
    c.configureChild(name: 'Sultan', fences: const []);

    final observed = t.subtract(const Duration(minutes: 8));
    c.onChildLocation(const Coordinates(43.24, 76.89), at: observed);
    _chk('a server fix keeps the time it was observed',
        c.childLocation?.at == observed);

    // Polling can answer out of order. A late reply carrying an EARLIER
    // position would walk the child backwards on the map, and could re-fire a
    // zone alert for somewhere they had already left.
    c.onChildLocation(const Coordinates(43.30, 77.00),
        at: t.subtract(const Duration(minutes: 20)));
    _chk('an older fix arriving late is ignored',
        c.childLocation?.at == observed && c.childLocation?.coords.lat == 43.24);

    // A newer one is taken.
    final newer = t.subtract(const Duration(minutes: 1));
    c.onChildLocation(const Coordinates(43.25, 76.95), at: newer);
    _chk('a newer fix replaces it', c.childLocation?.at == newer);

    // With no timestamp — a local BLE fix — it is happening now.
    c.onChildLocation(const Coordinates(43.26, 76.96));
    _chk('a fix with no timestamp is treated as now', c.childLocation?.at == t);

    c.dispose();
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
