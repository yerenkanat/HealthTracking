/// Pure-Dart verification of persistence: config round-trip + AppController
/// restore/save (profile + children + devices). `dart run tool/verify_persistence.dart`
library;

import 'dart:convert';
import 'dart:io';
import '../lib/domain/child_growth.dart';
import '../lib/domain/newborn_log.dart';

import '../lib/app/app_controller.dart';
import '../lib/core/geofence.dart';
import '../lib/data/app_store.dart';
import '../lib/data/persisted_config.dart';
import '../lib/domain/phone_auth.dart';
import '../lib/domain/cycle_log.dart';
import '../lib/domain/manual_sleep.dart';
import '../lib/domain/sleep.dart';
import '../lib/domain/family.dart';
import '../lib/domain/appointment.dart';
import '../lib/domain/battery.dart';
import '../lib/domain/contraction.dart';
import '../lib/domain/geofence_alerts.dart';
import '../lib/domain/health_series.dart';
import '../lib/domain/kick_session.dart';
import '../lib/domain/manual_vitals.dart';
import '../lib/domain/medication.dart';
import '../lib/domain/weight.dart';
import '../lib/domain/onboarding_controller.dart';
import '../lib/l10n/l10n.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

/// Wait past the persistence debounce. Writes are coalesced so a burst of taps
/// does not re-encode the whole config each time; these tests are about WHAT
/// ends up saved, so they wait for it to settle rather than assuming it is
/// instant.
Future<void> settled() => Future<void>.delayed(const Duration(milliseconds: 400));

void main() async {
  // ---- PersistedConfig round-trip (profile + 2 children + device) ----
  final cfg = PersistedConfig(
    onboarded: true,
    locale: AppLocale.kk,
    profile: const UserProfile(displayName: 'Aigerim', dialCode: '+7', phoneNumber: '700 123 45 67'),
    children: [
      ChildProfile(id: 'child-1', name: 'Sultan', dateOfBirth: DateTime(2019, 3, 8), photoPath: '/docs/photos/c1.jpg', gender: Gender.boy, geofences: [
        Geofence.circle('home', 'Home', const Coordinates(43.238949, 76.889709), 100),
      ]),
      const ChildProfile(id: 'child-2', name: 'Aida'),
    ],
    devices: const [PairedDevice(id: 'AA:BB', name: 'Band', kind: DeviceKind.band)],
    authSession: AuthSession(userId: 'u_abc', phoneE164: '+77001234567', token: 'stub-token:u_abc', signedInAt: DateTime.utc(2026, 7, 22, 12)),
    acceptedLegalVersion: 1,
    notificationsEnabled: false,
    avgCycleLength: 30,
    avgPeriodLength: 6,
    lastChildZone: 'School',
    alerts: [
      SafetyAlert(kind: AlertKind.entered, childName: 'Sultan', zoneName: 'School', at: DateTime.utc(2026, 7, 16, 9)),
      SafetyAlert(kind: AlertKind.left, childName: 'Sultan', zoneName: 'Home', at: DateTime.utc(2026, 7, 16, 8)),
    ],
    dayLogs: {
      '2026-07-14': const DayLog(date: '2026-07-14', mood: Mood.happy, symptoms: {Symptom.cramps}, kicks: 4, note: 'felt great today'),
      '2026-07-15': const DayLog(date: '2026-07-15', kicks: 0), // empty → dropped on encode
    },
    kickSessions: [
      KickSessionRecord(endedAt: DateTime.utc(2026, 7, 15, 21, 30), count: 10, durationSec: 620),
      KickSessionRecord(endedAt: DateTime.utc(2026, 7, 16, 8, 5), count: 6, durationSec: 240),
    ],
    contractionSessions: [
      ContractionSessionRecord(endedAt: DateTime.utc(2026, 12, 1, 3), count: 6, avgDurationSec: 55, avgIntervalSec: 300),
    ],
    waterLog: const {'2026-07-16': 5, '2026-07-15': 8},
    waterGoal: 9,
    appointments: [
      Appointment(id: 'apt-1', title: 'OB visit', at: DateTime.utc(2026, 7, 20, 9, 30), note: 'Bring results'),
      Appointment(id: 'apt-2', title: 'Ultrasound', at: DateTime.utc(2026, 8, 3, 14)),
    ],
    weights: const [
      WeightEntry(date: '2026-07-01', kg: 62.0),
      WeightEntry(date: '2026-07-15', kg: 63.4),
    ],
    weightGoalKg: 70.0,
    childBattery: const {'child-1': 62, 'child-2': 8},
    childBatteryHistory: {
      'child-1': [BatteryReading(DateTime(2026, 7, 15, 8), 80), BatteryReading(DateTime(2026, 7, 15, 12), 62)],
    },
    childGrowth: {
      'child-1': [
        GrowthPoint(at: DateTime(2026, 1, 10), weightKg: 3.6, heightCm: 51),
        GrowthPoint(at: DateTime(2026, 2, 10), weightKg: 4.6),
      ],
    },
    newbornLog: {
      'child-1': [
        NewbornEvent(at: DateTime(2026, 7, 22, 8), kind: NewbornEventKind.feed, detail: 'left'),
        NewbornEvent(at: DateTime(2026, 7, 22, 9), kind: NewbornEventKind.diaper, detail: 'both'),
        NewbornEvent(at: DateTime(2026, 7, 22, 10), kind: NewbornEventKind.sleep, durationMin: 75),
      ],
    },
    lastExportAt: DateTime(2026, 7, 14, 10, 30),
    medications: const [
      Medication(id: 'med-1', name: 'Folic acid', dose: '400 mcg'),
      Medication(id: 'med-2', name: 'Iron', dose: '27 mg', perDay: 2),
    ],
    medLog: const {
      '2026-07-15': {'med-1': 1, 'med-2': 2},
    },
    manualSamples: [
      HealthSample(at: DateTime.utc(2026, 7, 15, 9), systolic: 118, diastolic: 76, heartRate: 70),
    ],
    waterReminderMinutes: 20 * 60 + 30, // 20:30
    medReminderMinutes: 9 * 60, // 09:00
    periodReminderEnabled: true,
    fertileReminderEnabled: true,
  );
  final decoded = PersistedConfig.decode(cfg.encode());
  _chk('round-trip onboarded + locale', decoded.onboarded && decoded.locale == AppLocale.kk);
  _chk('round-trip auth session', decoded.authSession?.userId == 'u_abc' &&
      decoded.authSession?.phoneE164 == '+77001234567' && decoded.authSession?.token == 'stub-token:u_abc');
  _chk('round-trip accepted legal version', decoded.acceptedLegalVersion == 1);
  _chk('accepted legal version defaults to 0',
      PersistedConfig.decode('{"onboarded":true,"locale":"en"}').acceptedLegalVersion == 0);
  _chk('round-trip profile phone', decoded.profile.displayName == 'Aigerim' && decoded.profile.e164 == '+77001234567');
  _chk('round-trip 2 children', decoded.children.length == 2 && decoded.children[1].name == 'Aida');
  _chk('round-trip child DOB', decoded.children[0].dateOfBirth == DateTime(2019, 3, 8) && !decoded.children[1].hasDateOfBirth);
  _chk('round-trip child photo', decoded.children[0].photoPath == '/docs/photos/c1.jpg' && !decoded.children[1].hasPhoto);
  _chk('round-trip child gender', decoded.children[0].gender == Gender.boy && decoded.children[1].gender == null);
  {
    final g = decoded.childGrowth['child-1'] ?? const [];
    _chk('round-trip growth measurements', g.length == 2);
    _chk('round-trip growth kept both values', g[0].weightKg == 3.6 && g[0].heightCm == 51);
    _chk('round-trip growth kept a weight-only visit', g[1].weightKg == 4.6 && g[1].heightCm == null);
  }
  {
    final n = decoded.newbornLog['child-1'] ?? const [];
    _chk('round-trip newborn log', n.length == 3);
    _chk('round-trip newborn kinds and details',
        n.any((e) => e.kind == NewbornEventKind.feed && e.detail == 'left') &&
            n.any((e) => e.kind == NewbornEventKind.diaper && e.detail == 'both'));
    _chk('round-trip newborn sleep duration',
        n.any((e) => e.kind == NewbornEventKind.sleep && e.durationMin == 75));
  }
  _chk('round-trip child geofence', decoded.children[0].geofences.first.center?.lat == 43.238949);
  _chk('round-trip device', decoded.devices.length == 1 && decoded.devices.first.kind == DeviceKind.band);
  _chk('round-trip notificationsEnabled', decoded.notificationsEnabled == false);
  _chk('notificationsEnabled defaults true', PersistedConfig.decode('{"onboarded":true,"locale":"en"}').notificationsEnabled);
  _chk('round-trip alerts feed', decoded.alerts.length == 2 &&
      decoded.alerts.first.kind == AlertKind.entered && decoded.alerts.first.zoneName == 'School');
  _chk('round-trip lastChildZone', decoded.lastChildZone == 'School');
  _chk('round-trip cycle baseline', decoded.avgCycleLength == 30 && decoded.avgPeriodLength == 6);
  _chk('round-trip kick sessions', decoded.kickSessions.length == 2 &&
      decoded.kickSessions[0].count == 10 && decoded.kickSessions[0].durationSec == 620 &&
      decoded.kickSessions[1].endedAt == DateTime.utc(2026, 7, 16, 8, 5));
  _chk('round-trip contraction sessions', decoded.contractionSessions.length == 1 &&
      decoded.contractionSessions[0].count == 6 && decoded.contractionSessions[0].avgDurationSec == 55 &&
      decoded.contractionSessions[0].avgIntervalSec == 300);
  _chk('round-trip water log + goal',
      decoded.waterLog['2026-07-16'] == 5 && decoded.waterLog['2026-07-15'] == 8 && decoded.waterGoal == 9);
  _chk('round-trip appointments', decoded.appointments.length == 2 &&
      decoded.appointments[0].title == 'OB visit' && decoded.appointments[0].note == 'Bring results' &&
      decoded.appointments[0].at == DateTime.utc(2026, 7, 20, 9, 30) && decoded.appointments[1].note == '');
  _chk('round-trip weights', decoded.weights.length == 2 &&
      decoded.weights[0].date == '2026-07-01' && decoded.weights[1].kg == 63.4);
  _chk('round-trip weight goal', decoded.weightGoalKg == 70.0);
  _chk('round-trip child battery', decoded.childBattery['child-1'] == 62 && decoded.childBattery['child-2'] == 8);
  _chk('round-trip last export', decoded.lastExportAt == DateTime(2026, 7, 14, 10, 30));
  _chk('round-trip medications',
      decoded.medications.length == 2 &&
          decoded.medications.last.name == 'Iron' &&
          decoded.medications.last.perDay == 2);
  _chk('round-trip medication log', decoded.medLog['2026-07-15']?['med-2'] == 2);
  _chk('round-trip hand-entered readings',
      decoded.manualSamples.length == 1 &&
          decoded.manualSamples.single.systolic == 118 &&
          decoded.manualSamples.single.at == DateTime.utc(2026, 7, 15, 9));
  _chk('round-trip battery history',
      decoded.childBatteryHistory['child-1']?.length == 2 &&
          decoded.childBatteryHistory['child-1']?.last.pct == 62 &&
          decoded.childBatteryHistory['child-1']?.first.at == DateTime(2026, 7, 15, 8));
  _chk('round-trip water reminder', decoded.waterReminderMinutes == 20 * 60 + 30);
  _chk('round-trip medication reminder', decoded.medReminderMinutes == 9 * 60);
  _chk('round-trip period reminder', decoded.periodReminderEnabled == true);
  _chk('round-trip fertile reminder', decoded.fertileReminderEnabled == true);
  _chk('round-trip dayLogs drops empties', decoded.dayLogs.length == 1 && decoded.dayLogs.containsKey('2026-07-14'));
  _chk('round-trip dayLog fields',
      decoded.dayLogs['2026-07-14']?.mood == Mood.happy &&
          decoded.dayLogs['2026-07-14']?.symptoms.contains(Symptom.cramps) == true &&
          decoded.dayLogs['2026-07-14']?.kicks == 4 &&
          decoded.dayLogs['2026-07-14']?.note == 'felt great today');

  // ---- AppController.restore() ----
  final ctl = AppController(persistStore: InMemoryAppStore(cfg));
  _chk('fresh controller not onboarded', !ctl.onboarded);
  await ctl.restore();
  _chk('restore onboarded', ctl.onboarded);
  _chk('restore profile name', ctl.displayName == 'Aigerim');
  _chk('restore children', ctl.children.length == 2);
  _chk('restore selected child = first', ctl.childName == 'Sultan' && ctl.geofences.length == 1);
  _chk('restore band device', ctl.bandId == 'AA:BB');
  await ctl.dispose();

  // ---- Empty store → first run ----
  final ctl2 = AppController(persistStore: InMemoryAppStore());
  await ctl2.restore();
  _chk('empty store not onboarded', !ctl2.onboarded);

  // ---- completeOnboarding persists ----
  final store3 = InMemoryAppStore();
  final ctl3 = AppController(persistStore: store3);
  ctl3.completeOnboarding(OnboardingResult(
    locale: AppLocale.en,
    profile: const UserProfile(displayName: 'Mom', dialCode: '+7', phoneNumber: '7001112233'),
    bandId: 'BAND-9',
    child: ChildProfile(id: 'child-1', name: 'Kid', geofences: [
      Geofence.circle('home', 'Home', const Coordinates(1, 2), 50),
    ]),
  ));
  await settled();
  final saved = await store3.load();
  _chk('onboarding persisted', saved?.onboarded == true && saved?.children.first.name == 'Kid');
  _chk('onboarding persisted band device', saved?.devices.any((d) => d.id == 'BAND-9') == true);
  _chk('onboarding persisted profile', saved?.profile.displayName == 'Mom');

  // ---- add a second child persists + select ----
  ctl3.addChild(const ChildProfile(id: 'child-2', name: 'Aida'));

  await settled();
  _chk('added child persisted', (await store3.load())?.children.length == 2);
  ctl3.selectChild('child-2');
  _chk('select second child', ctl3.childName == 'Aida');

  // ---- setLocale persists ----
  ctl3.setLocale(AppLocale.kk);

  await settled();
  _chk('setLocale persisted', (await store3.load())?.locale == AppLocale.kk);

  await ctl3.dispose();

  // ---- new controller restores everything ----
  final ctl4 = AppController(persistStore: store3);
  await ctl4.restore();
  _chk('new controller restores session', ctl4.onboarded && ctl4.children.length == 2 && ctl4.locale == AppLocale.kk);

  // ---- add device, then remove ----
  ctl4.addDevice(const PairedDevice(id: 'TAG-1', name: 'Tag', kind: DeviceKind.tag, childId: 'child-1'));
  await settled();
  _chk('device added', ctl4.devices.any((d) => d.id == 'TAG-1'));
  ctl4.removeDevice('TAG-1');
  await settled();
  _chk('device removed + persisted', !ctl4.devices.any((d) => d.id == 'TAG-1') &&
      (await store3.load())?.devices.any((d) => d.id == 'TAG-1') == false);

  // ---- geofence zones CRUD on a child ----
  ctl4.upsertGeofence('child-2', Geofence.circle('z1', 'Grandma', const Coordinates(43.3, 76.9), 150));
  await settled();
  _chk('zone added', ctl4.children.firstWhere((c) => c.id == 'child-2').geofences.any((f) => f.id == 'z1'));
  _chk('zone persisted', (await store3.load())!.children.firstWhere((c) => c.id == 'child-2').geofences.any((f) => f.id == 'z1'));
  // upsert same id updates in place (no duplicate)
  ctl4.upsertGeofence('child-2', Geofence.circle('z1', 'Grandma', const Coordinates(43.3, 76.9), 250));
  await settled();
  final z = ctl4.children.firstWhere((c) => c.id == 'child-2').geofences.where((f) => f.id == 'z1').toList();
  _chk('zone updated in place', z.length == 1 && z.first.radiusM == 250);
  ctl4.removeGeofence('child-2', 'z1');
  await settled();
  _chk('zone removed + persisted', !ctl4.children.firstWhere((c) => c.id == 'child-2').geofences.any((f) => f.id == 'z1') &&
      !(await store3.load())!.children.firstWhere((c) => c.id == 'child-2').geofences.any((f) => f.id == 'z1'));

  // ---- remove a child reselects remaining ----
  ctl4.removeChild('child-1'); // currently selected; child-2 remains
  await settled();
  _chk('child removed', ctl4.children.length == 1 && ctl4.children.first.id == 'child-2');
  _chk('reselected remaining child', ctl4.childName == 'Aida');

  // ---- BP calibration stored + persisted + restored ----
  ctl4.calibrateBp(cuffSystolic: 128, cuffDiastolic: 82, ppgSystolic: 120, ppgDiastolic: 78,
      at: DateTime.parse('2026-07-15T00:00:00Z'));
  await settled();
  _chk('calibration offsets stored', ctl4.bpCalibration?.systolicOffset == 8 && ctl4.bpCalibration?.diastolicOffset == 4);
  _chk('calibration persisted', (await store3.load())?.bpCalibration?.systolicOffset == 8);
  // restore into a fresh controller
  final ctl5 = AppController(persistStore: store3);
  await ctl5.restore();
  _chk('calibration restored', ctl5.bpCalibration?.diastolicOffset == 4);
  await ctl5.dispose();

  // ---- day logs: toggle + kicks persist + restore ----
  final day = DateTime(2026, 7, 15);
  ctl4.toggleMoodFor(day, Mood.calm);
  ctl4.toggleSymptomFor(day, Symptom.nausea);
  ctl4.addKickFor(day);
  ctl4.addKickFor(day);
  await settled();
  _chk('day log recorded', ctl4.logFor(day).mood == Mood.calm && ctl4.logFor(day).kicks == 2);
  _chk('day log persisted', (await store3.load())?.dayLogs['2026-07-15']?.kicks == 2);
  final ctl6 = AppController(persistStore: store3, now: () => day);
  await ctl6.restore();
  _chk('day log restored', ctl6.logFor(day).symptoms.contains(Symptom.nausea) && ctl6.logFor(day).mood == Mood.calm);
  // due date drives gestation (now pinned to `day` for determinism)
  ctl6.setDueDate(day.add(const Duration(days: 112)));
  _chk('gestation from due date', ctl6.gestation?.week == 24 && ctl6.gestation?.dayOfWeek == 0);
  await ctl6.dispose();

  // ---- reset wipes + returns to onboarding ----
  await ctl4.resetApp();
  _chk('reset clears onboarded', !ctl4.onboarded && ctl4.children.isEmpty);
  _chk('reset clears day logs', ctl4.dayLogs.isEmpty);
  _chk('reset clears persisted', (await store3.load()) == null);
  await ctl4.dispose();

  // ---- A backup must actually restore everything ----
  // Guards the whole export→import path end to end: a field wired into the
  // controller but not into PersistedConfig would silently vanish from backups.
  final src = AppController(now: () => DateTime(2026, 7, 20, 9));
  src.debugMarkOnboarded();
  src.updateProfile(const UserProfile(displayName: 'Aigerim', dialCode: '+7', phoneNumber: '700 123 45 67'));
  src.configureChild(name: 'Sultan', fences: [Geofence.circle('h', 'Home', const Coordinates(43.2, 76.8), 100)]);
  src.setDayLog(const DayLog(date: '2026-07-10', mood: Mood.happy, note: 'scan'));
  src.addWater(DateTime(2026, 7, 20), 5);
  src.setWaterGoal(9);
  src.logWeight(DateTime(2026, 7, 20), 63.4);
  src.setWeightGoal(70);
  src.addAppointment('OB visit', DateTime(2026, 8, 1, 9));
  src.addMedication('Folic acid', dose: '400 mcg');
  src.takeMedicationDose(src.medications.single.id, DateTime(2026, 7, 20));
  src.logKickSession(DateTime(2026, 7, 20), 10, const Duration(seconds: 600));
  src.logContractionSession(6, const Duration(seconds: 55), const Duration(seconds: 300));
  src.setChildBattery('child-1', 62);
  src.logChildEvent(AlertKind.checkIn);
  src.setWaterReminder(20 * 60);
  src.setMedReminder(9 * 60);
  src.setPeriodReminder(true);
  src.setFertileReminder(true);
  src.logManualVitals(const ManualVitals(systolic: 118, diastolic: 76));
  src.setCycleBaseline(cycle: 30, period: 6);

  final restored = AppController(now: () => DateTime(2026, 7, 20, 9));
  _chk('a backup imports cleanly', restored.importJson(src.exportJson()));
  String fingerprint(AppController c) => [
        c.displayName, c.profile.e164, '${c.children.length}',
        '${c.children.isEmpty ? 0 : c.children.first.geofences.length}',
        '${c.dayLogs.length}', '${c.waterFor(DateTime(2026, 7, 20))}', '${c.waterGoal}',
        '${c.weights.length}', '${c.weightGoalKg}', '${c.appointments.length}',
        '${c.medications.length}', '${c.medLog.length}', '${c.kickSessions.length}',
        '${c.contractionSessions.length}', '${c.alerts.length}',
        '${c.waterReminderMinutes}', '${c.medReminderMinutes}',
        '${c.periodReminderEnabled}', '${c.fertileReminderEnabled}',
        '${c.manualSamples.length}', '${c.avgCycleLength}', c.locale.name,
        '${c.batteryFor('child-1')}', '${c.batteryHistoryFor('child-1').length}',
      ].join('|');
  _chk('a backup restores every tracked field', fingerprint(src) == fingerprint(restored));
  await src.dispose();
  await restored.dispose();

  // ---- Import must not destroy data on a wrong file ----
  // Every config field is optional, so ANY JSON object decodes into a valid but
  // EMPTY config. Applying one would wipe everything the user has — so picking
  // the wrong file in the restore dialog must cost nothing.
  _chk('random json is not a backup', !looksLikeBackup(jsonDecode('{"foo":1,"bar":"baz"}')));
  _chk('empty object is not a backup', !looksLikeBackup(jsonDecode('{}')));
  _chk('a json array is not a backup', !looksLikeBackup(jsonDecode('[1,2,3]')));
  _chk('a bare number is not a backup', !looksLikeBackup(jsonDecode('42')));
  _chk('the export marker is accepted', looksLikeBackup(jsonDecode('{"app":"Umay"}')));
  _chk('a pre-marker backup is still accepted',
      looksLikeBackup(jsonDecode('{"locale":"ru","profile":{}}')));
  _chk('a real encoded config is recognised', looksLikeBackup(jsonDecode(cfg.encode())));

  final guarded = AppController(persistStore: InMemoryAppStore(cfg));
  await guarded.restore();
  final childrenBefore = guarded.children.length;
  final rejected = guarded.importJson('{"foo":1}');
  _chk('importing a non-backup is refused', !rejected);
  _chk('importing a non-backup leaves data untouched', guarded.children.length == childrenBefore);
  _chk('importing garbage is refused', !guarded.importJson('not json at all'));
  _chk('a genuine backup still imports', guarded.importJson(guarded.exportJson()));
  await guarded.dispose();

  // ---- Upgrade safety ----
  // Saved configs outlive the build that wrote them. A user upgrading must not
  // lose data or crash because a field they never had is now read non-
  // defensively, so decoding old/new/minimal payloads is asserted explicitly.
  const legacy = '{"version":1,"onboarded":true,"locale":"ru",'
      '"profile":{"displayName":"Aigerim"},"children":[],"devices":[]}';
  PersistedConfig? oldCfg;
  try {
    oldCfg = PersistedConfig.decode(legacy);
  } catch (_) {
    oldCfg = null;
  }
  _chk('a legacy config still decodes', oldCfg != null);
  _chk('legacy keeps the data it did have', oldCfg?.profile.displayName == 'Aigerim' && oldCfg?.onboarded == true);
  _chk('fields added later default safely',
      oldCfg != null &&
          oldCfg.medications.isEmpty &&
          oldCfg.medLog.isEmpty &&
          oldCfg.weights.isEmpty &&
          oldCfg.childBatteryHistory.isEmpty &&
          oldCfg.lastExportAt == null &&
          oldCfg.medReminderMinutes == null &&
          oldCfg.waterReminderMinutes == null &&
          !oldCfg.periodReminderEnabled);

  // A payload from a NEWER build: unknown keys must be ignored, not fatal.
  PersistedConfig? futureCfg;
  try {
    futureCfg = PersistedConfig.decode('{"version":99,"onboarded":true,"locale":"en",'
        '"profile":{"displayName":"X"},"children":[],"devices":[],'
        '"someUnknownFeature":{"a":1},"anotherNew":[1,2,3]}');
  } catch (_) {
    futureCfg = null;
  }
  _chk('a newer config decodes, ignoring unknown fields', futureCfg?.profile.displayName == 'X');

  // The bare minimum a file could contain.
  PersistedConfig? minimal;
  try {
    minimal = PersistedConfig.decode('{"onboarded":true}');
  } catch (_) {
    minimal = null;
  }
  _chk('a minimal config decodes', minimal != null && minimal.onboarded);

  // Encoding what we decoded must not drift.
  final reencoded = PersistedConfig.decode(cfg.encode()).encode();
  _chk('encode → decode → encode is stable', reencoded == cfg.encode());
  // The write side skips empty logs, matching the read side that discards them
  // — otherwise every save persisted stubs the next load threw away. (Checked
  // against the dayLogs map specifically: that date also appears legitimately in
  // the water, weight and medication logs.)
  final encodedLogs = (jsonDecode(cfg.encode()) as Map<String, dynamic>)['dayLogs'] as Map<String, dynamic>;
  _chk('empty day logs are never written',
      encodedLogs.containsKey('2026-07-14') && !encodedLogs.containsKey('2026-07-15'));

  // ---- A hand-logged night survives a restart ----
  // The band re-sends its own summaries on the next sync, so those stay
  // transient. Nothing re-supplies a night the user typed, so losing it on
  // restart would mean the band-less user can never build a sleep history.
  final sleepStore = InMemoryAppStore();
  final sleepCtl = AppController(persistStore: sleepStore);
  await sleepCtl.restore();
  sleepCtl.completeOnboarding(OnboardingResult(
    locale: AppLocale.en,
    profile: const UserProfile(displayName: 'Aigerim'),
    bandId: null, // no band — the case this feature exists for
    child: const ChildProfile(id: 'child-1', name: 'Kid'),
  ));
  final logged = sleepCtl.logManualSleep(SleepEntry(
    bedAt: DateTime(2026, 7, 14, 23, 0),
    wokeAt: DateTime(2026, 7, 15, 7, 0),
    awakeMin: 30,
  ));
  _chk('a valid night is accepted', logged);
  _chk('an impossible night is refused',
      !sleepCtl.logManualSleep(SleepEntry(bedAt: DateTime(2026, 7, 14, 7), wokeAt: DateTime(2026, 7, 14, 1))));
  await settled(); // let the async save land

  final sleepBack = AppController(persistStore: sleepStore);
  await sleepBack.restore();
  final restoredNight = latestNight(sleepBack.sleepNights);
  _chk('a hand-logged night survives a restart', restoredNight != null);
  _chk('the restored night keeps its total', restoredNight?.asleepMin == 7 * 60 + 30);
  _chk('the restored night is still marked manual',
      restoredNight?.source == SleepSource.manual);
  _chk('the restored night keeps its quality', restoredNight?.quality == SleepQuality.good);
  await sleepCtl.dispose();
  await sleepBack.dispose();

  // ---- A decade of daily logging still round-trips ----
  // The day-keyed logs (water, medication, cycle) are deliberately uncapped:
  // trimming them would throw away exactly the history the user is keeping.
  // Measured, a decade of daily entries is ~550KB and ~4ms to encode, so the
  // growth is fine — what matters is that nothing breaks or silently drops at
  // that size, which is where an accidental O(n^2) or a lossy encode shows up.
  final bigWater = <String, int>{};
  final bigMed = <String, Map<String, int>>{};
  final bigLogs = <String, DayLog>{};
  final decadeStart = DateTime(2026, 1, 1);
  const decadeDays = 3650;
  for (var i = 0; i < decadeDays; i++) {
    final d = decadeStart.add(Duration(days: i));
    final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    bigWater[k] = 8;
    bigMed[k] = {'m1': 1, 'm2': 2};
    bigLogs[k] = DayLog(date: k, flow: Flow.medium, symptoms: const {Symptom.cramps}, note: 'ok');
  }
  final bigCfg = PersistedConfig(
    onboarded: true,
    locale: AppLocale.ru,
    profile: const UserProfile(displayName: 'Aigerim'),
    children: const [],
    devices: const [],
    waterLog: bigWater,
    medLog: bigMed,
    dayLogs: bigLogs,
  );
  final bigBack = PersistedConfig.fromJson(
      (jsonDecode(jsonEncode(bigCfg.toJson())) as Map).cast<String, dynamic>());
  _chk('a decade of water entries survives a round-trip',
      bigBack.waterLog.length == decadeDays && bigBack.waterLog['2030-06-15'] == 8);
  _chk('a decade of medication entries survives a round-trip',
      bigBack.medLog.length == decadeDays && bigBack.medLog['2030-06-15']?['m2'] == 2);
  _chk('a decade of day logs survives a round-trip',
      bigBack.dayLogs.length == decadeDays &&
          bigBack.dayLogs['2030-06-15']?.flow == Flow.medium);

  // ---- Every field must be persisted, without anyone remembering ----
  //
  // The ninety-odd round-trip assertions above are one per field, written by
  // hand. They prove what they cover and say nothing about what they do not: a
  // field added to PersistedConfig and forgotten in toJson simply vanishes on
  // the next launch, silently, and no existing assertion notices.
  //
  // This reads the class instead. It is the same shape as the destructive-action
  // guard and the pg schema check — the list is DERIVED, so forgetting is a
  // build failure rather than a hole.
  {
    final src = File.fromUri(Platform.script.resolve('../lib/data/persisted_config.dart'))
        .readAsStringSync();

    // Field declarations on the class: `  final Type name;`
    final fields = <String>[
      for (final m in RegExp(r'^  final [\w<>?, ]+ (\w+);', multiLine: true).allMatches(src))
        m.group(1)!,
    ];
    _chk('the field sweep found the config class (${fields.length} fields)', fields.length > 20);

    final toJson = RegExp(r'Map<String, dynamic> toJson\(\)[\s\S]*?\n      \};').stringMatch(src) ?? '';
    final fromJson = RegExp(r'factory PersistedConfig\.fromJson[\s\S]*?\n      \);').stringMatch(src) ?? '';
    _chk('the sweep located toJson', toJson.length > 100);
    _chk('the sweep located fromJson', fromJson.length > 100);

    final notWritten = fields.where((f) => !toJson.contains(f)).toList();
    final notRead = fields.where((f) => !fromJson.contains(f)).toList();
    _chk('every field is written by toJson${notWritten.isEmpty ? '' : ' — missing: ${notWritten.join(", ")}'}',
        notWritten.isEmpty);
    _chk('every field is read by fromJson${notRead.isEmpty ? '' : ' — missing: ${notRead.join(", ")}'}',
        notRead.isEmpty);
  }

  // ---- A damaged file must not take the app down with it ----
  // The backup is a text file the user is told to keep and can edit. Restoring
  // one that has been truncated, hand-mangled or written by a newer build has
  // to degrade, not throw: losing the session is bad, crashing on launch is
  // worse because there is then no way back in to fix it.
  {
    // The contract is NOT that fromJson is total — it is not, deliberately, and
    // every caller guards. What must hold is that the two entry points a user
    // can actually reach survive anything: restoring a saved config on launch
    // (PrefsAppStore.load catches and falls back to first run) and restoring a
    // backup by hand.
    //
    // importJson is the one testable in pure Dart, and it is the one where the
    // input is genuinely untrusted: the file is text we tell her to keep, and
    // she can pick the wrong one.
    final broken = <String, String>{
      'truncated object': '{"onboarded":true,"locale":"ru"',
      'not an object': '[1,2,3]',
      'empty string': '',
      'null literal': 'null',
      'plain prose': 'this is not my backup, it is a shopping list',
      'wrong types throughout': '{"onboarded":"yes","locale":42,"children":"none","devices":{}}',
      'nested junk': '{"onboarded":true,"locale":"ru","children":[{"id":null}],"devices":[7]}',
      'a different app entirely': '{"version":3,"records":[{"a":1}]}',
    };
    for (final e in broken.entries) {
      final c = AppController(now: () => DateTime(2026, 7, 21));
      c.addAppointment('Keep me', DateTime(2026, 8, 1, 9, 0));
      var threw = false;
      var accepted = true;
      try {
        accepted = c.importJson(e.value);
      } catch (_) {
        threw = true;
      }
      _chk('importing ${e.key} does not throw', !threw);
      _chk('importing ${e.key} is refused', !accepted);
      _chk('importing ${e.key} keeps the existing data',
          c.appointments.length == 1 && c.appointments.single.title == 'Keep me');
      c.dispose();
    }

    // Forward compatibility: a backup written by a LATER build carries keys
    // this one has never heard of. Dropping them is right; refusing the whole
    // file because of them would strand a user who upgraded, restored, and
    // downgraded.
    {
      final c = AppController(now: () => DateTime(2026, 7, 21));
      final withFuture = jsonDecode(c.exportJson()) as Map<String, dynamic>;
      withFuture['quantumField'] = {'x': 1};
      withFuture['children'] = [
        {'id': 'c1', 'name': 'Sultan', 'telepathyLevel': 9},
      ];
      _chk('a backup from a newer build is still accepted',
          c.importJson(jsonEncode(withFuture)));
      _chk('and the parts this build understands survive',
          c.children.length == 1 && c.children.single.name == 'Sultan');
      c.dispose();
    }
  }

  // ---- Saving must not stutter the screen it is saving from ----
  //
  // Every mutation snapshotted and re-encoded the WHOLE config synchronously.
  // For a user with three years of history that is ~158 KB of JSON, measured at
  // roughly 7ms per tap on a desktop — and the kick counter is a rapid-tap
  // control on a phone several times slower. The cost grows with her history,
  // so the users who have relied on the app longest feel it worst.
  //
  // Writes are coalesced now. What has to stay true is that they still HAPPEN:
  // a debounce that quietly drops the last write would be far worse than the
  // stutter it replaced.
  {
    final store = _CountingStore();
    final c = AppController(now: () => DateTime(2026, 7, 21), persistStore: store);

    for (var i = 0; i < 20; i++) {
      c.addKickFor(DateTime(2026, 7, 21));
    }
    _chk('a burst of taps does not write once per tap', store.saves < 20);

    await Future<void>.delayed(const Duration(milliseconds: 500));
    _chk('but the burst IS written once it settles', store.saves >= 1);

    // Nothing pending must be lost on shutdown.
    final before = store.saves;
    c.addKickFor(DateTime(2026, 7, 21));
    await c.dispose();
    _chk('a pending write is flushed on dispose', store.saves > before);
  }

  {
    // Irreversible operations do not wait: losing 300ms of a deletion would
    // resurrect something the user removed on purpose.
    final store = _CountingStore();
    final c = AppController(now: () => DateTime(2026, 7, 21), persistStore: store);
    c.configureChild(name: 'Sultan', fences: const []);
    final before = store.saves;
    c.removeChild(c.children.single.id);
    _chk('a deletion is written immediately', store.saves > before);
    await c.dispose();
  }

  // ---- One unreadable entry must not cost her everything ----
  //
  // Every list here used to be all-or-nothing. One appointment with an
  // unparseable date threw out of the whole constructor; PrefsAppStore.load
  // catches that and returns null; restore() then returns early — and the app
  // shows FIRST-RUN ONBOARDING. Her pregnancy, her children, their zones and
  // her entire history still on the disk, unreachable, while the app behaves as
  // though she had never opened it. This is her only copy.
  {
    final base = PersistedConfig(
      onboarded: true,
      locale: AppLocale.ru,
      profile: const UserProfile(displayName: 'Aigerim', phoneNumber: '7001112233'),
      children: const [],
      devices: const [],
    ).toJson();

    PersistedConfig parse(Map<String, dynamic> j) => PersistedConfig.fromJson(j);

    // A good appointment and a broken one.
    final mixed = parse({
      ...base,
      'appointments': [
        {'id': 'a', 'title': 'Приём у врача', 'at': '2026-08-01T10:00:00.000'},
        {'id': 'b', 'title': 'broken', 'at': 'not-a-date'},
      ],
    });
    _chk('a broken appointment does not take the config with it', mixed.onboarded);
    _chk('the profile survives', mixed.profile.displayName == 'Aigerim');
    _chk('the readable appointment is kept', mixed.appointments.length == 1);
    _chk('and it is the right one', mixed.appointments.single.title == 'Приём у врача');
    _chk('the loss is counted, not silent', PersistedConfig.lastDroppedEntries == 1);

    // Every other shape that used to throw.
    for (final (label, bad) in [
      ('a weight that is not a number', {'weights': [{'date': '2026-07-21', 'kg': 'sixty'}]}),
      ('a child that is not a map', {'children': ['oops']}),
      ('a device that is not a map', {'devices': [42]}),
      ('an alert that is not a map', {'alerts': [null]}),
      ('a water count that is not a number', {'waterLog': {'2026-07-21': 'eight'}}),
      ('a battery level that is not a number', {'childBattery': {'c1': 'full'}}),
      ('a kick session with a bad date', {'kickSessions': [{'endedAt': 'nope', 'count': 3, 'durationSec': 60}]}),
    ]) {
      final c = parse({...base, ...bad});
      _chk('$label: the rest is still restored',
          c.onboarded && c.profile.displayName == 'Aigerim');
      _chk('$label: and the loss is counted', PersistedConfig.lastDroppedEntries >= 1);
    }

    // ---- One bad zone must not cost her the child ----
    //
    // Zones were parsed inline inside childFromJson rather than through the
    // tolerant list, so a single unreadable zone threw and the outer parser
    // dropped the WHOLE child — her name, her date of birth, her photo, and
    // every other zone she had drawn — to save one corrupted circle.
    {
      final c = parse({
        ...base,
        'children': [
          {
            'id': 'c1',
            'name': 'Sultan',
            'geofences': [
              {'id': 'home', 'name': 'Дом', 'shape': 'circle', 'lat': 43.2, 'lng': 76.9, 'radiusM': 120},
              {'id': 'bad', 'name': 'Broken', 'shape': 'circle', 'lat': 'nope', 'lng': 76.9, 'radiusM': 100},
            ],
          },
        ],
      });
      _chk('the child survives a broken zone', c.children.length == 1);
      _chk('and keeps her name', c.children.single.name == 'Sultan');
      _chk('the readable zone is kept', c.children.single.geofences.length == 1);
      _chk('and it is the right one', c.children.single.geofences.single.id == 'home');
      _chk('the lost zone is counted', PersistedConfig.lastDroppedEntries == 1);
    }

    // ---- A zone that could never fire is not a zone ----
    //
    // These parse cleanly and are geometrically dead: a polygon needs three
    // points to enclose anything, and a circle of radius zero has no inside.
    // Kept, they sit in her zone list looking like protection that works.
    for (final (label, fence) in [
      ('a two-point polygon', {'id': 'p', 'name': 'P', 'shape': 'polygon', 'vertices': [[43.2, 76.9], [43.3, 76.9]]}),
      ('an empty polygon', {'id': 'p', 'name': 'P', 'shape': 'polygon', 'vertices': []}),
      ('a circle with no radius', {'id': 'c', 'name': 'C', 'shape': 'circle', 'lat': 43.2, 'lng': 76.9, 'radiusM': 0}),
      ('a circle with a negative radius', {'id': 'c', 'name': 'C', 'shape': 'circle', 'lat': 43.2, 'lng': 76.9, 'radiusM': -5}),
    ]) {
      final c = parse({
        ...base,
        'children': [
          {'id': 'c1', 'name': 'Sultan', 'geofences': [fence]},
        ],
      });
      _chk('$label is not kept as a working zone',
          c.children.single.geofences.isEmpty);
      _chk('$label is counted as lost', PersistedConfig.lastDroppedEntries == 1);
    }

    // A clean config drops nothing — otherwise the counter would be noise.
    parse(base);
    _chk('a clean config drops nothing', PersistedConfig.lastDroppedEntries == 0);

    // A payload from a newer build, carrying fields this one has never seen.
    final future = parse({...base, 'version': 99, 'somethingNew': {'a': 1}});
    _chk('a newer config still restores what this build understands',
        future.onboarded && future.profile.displayName == 'Aigerim');
  }

  // ---- Import: what a wrong, hostile or partly-unreadable file does ----
  {
    final t = DateTime(2026, 7, 21, 10);
    AppController seeded() {
      final c = AppController(now: () => t);
      c.debugMarkOnboarded();
      c.updateProfile(const UserProfile(displayName: 'Aigerim'));
      c.addAppointment('Приём у врача', t.add(const Duration(days: 3)));
      return c;
    }

    // Picking the wrong file must not cost her anything. Every field has a
    // default, so ANY json object would otherwise decode into a valid-but-empty
    // config and wipe her.
    for (final (label, payload) in [
      ('a shopping list', '{"eggs":2,"milk":1}'),
      ('an empty object', '{}'),
      ('a bare array', '[1,2,3]'),
      ('a number', '42'),
      ('truncated json', '{"app":"Umay","profile":'),
      ('not json at all', 'hello'),
      ('an empty string', ''),
    ]) {
      final c = seeded();
      final before = c.appointments.length;
      _chk('$label is refused', !c.importJson(payload));
      _chk('$label leaves her data alone',
          c.appointments.length == before && c.profile.displayName == 'Aigerim');
      c.dispose();
    }

    // A real backup restores, and reports nothing dropped.
    {
      final src = seeded();
      final backup = src.exportJson();
      final dst = AppController(now: () => t);
      _chk('a real backup is accepted', dst.importJson(backup));
      _chk('it restores the appointment', dst.appointments.length == 1);
      _chk('a clean import reports nothing dropped', dst.lastImportDropped == 0);
      await src.dispose();
      await dst.dispose();
    }

    // A backup with unreadable entries restores the rest AND says how much it
    // could not read. Silence here would tell her the backup came back whole.
    {
      final src = seeded();
      final decoded = jsonDecode(src.exportJson()) as Map<String, dynamic>;
      decoded['appointments'] = [
        ...(decoded['appointments'] as List),
        {'id': 'x', 'title': 'broken', 'at': 'not-a-date'},
        {'id': 'y', 'title': 'also broken', 'at': 'nope'},
      ];
      final dst = AppController(now: () => t);
      _chk('a partly unreadable backup still restores', dst.importJson(jsonEncode(decoded)));
      _chk('the readable appointment survives', dst.appointments.length == 1);
      _chk('and she is told how much did not', dst.lastImportDropped == 2);
      await src.dispose();
      await dst.dispose();
    }
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}

/// Counts writes without touching a disk.
class _CountingStore implements AppStore {
  int saves = 0;
  @override
  Future<PersistedConfig?> load() async => null;
  @override
  Future<void> save(PersistedConfig c) async => saves++;
  @override
  Future<void> clear() async {}
}
