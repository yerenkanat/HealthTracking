/// Pure-Dart verification of persistence: config round-trip + AppController
/// restore/save (profile + children + devices). `dart run tool/verify_persistence.dart`
library;

import 'dart:io';

import '../lib/app/app_controller.dart';
import '../lib/core/geofence.dart';
import '../lib/data/app_store.dart';
import '../lib/data/persisted_config.dart';
import '../lib/domain/cycle_log.dart';
import '../lib/domain/family.dart';
import '../lib/domain/appointment.dart';
import '../lib/domain/contraction.dart';
import '../lib/domain/geofence_alerts.dart';
import '../lib/domain/kick_session.dart';
import '../lib/domain/weight.dart';
import '../lib/domain/onboarding_controller.dart';
import '../lib/l10n/l10n.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

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
    childBattery: const {'child-1': 62, 'child-2': 8},
    waterReminderMinutes: 20 * 60 + 30, // 20:30
  );
  final decoded = PersistedConfig.decode(cfg.encode());
  _chk('round-trip onboarded + locale', decoded.onboarded && decoded.locale == AppLocale.kk);
  _chk('round-trip profile phone', decoded.profile.displayName == 'Aigerim' && decoded.profile.e164 == '+77001234567');
  _chk('round-trip 2 children', decoded.children.length == 2 && decoded.children[1].name == 'Aida');
  _chk('round-trip child DOB', decoded.children[0].dateOfBirth == DateTime(2019, 3, 8) && !decoded.children[1].hasDateOfBirth);
  _chk('round-trip child photo', decoded.children[0].photoPath == '/docs/photos/c1.jpg' && !decoded.children[1].hasPhoto);
  _chk('round-trip child gender', decoded.children[0].gender == Gender.boy && decoded.children[1].gender == null);
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
  _chk('round-trip child battery', decoded.childBattery['child-1'] == 62 && decoded.childBattery['child-2'] == 8);
  _chk('round-trip water reminder', decoded.waterReminderMinutes == 20 * 60 + 30);
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
  await Future<void>.delayed(Duration.zero);
  final saved = await store3.load();
  _chk('onboarding persisted', saved?.onboarded == true && saved?.children.first.name == 'Kid');
  _chk('onboarding persisted band device', saved?.devices.any((d) => d.id == 'BAND-9') == true);
  _chk('onboarding persisted profile', saved?.profile.displayName == 'Mom');

  // ---- add a second child persists + select ----
  ctl3.addChild(const ChildProfile(id: 'child-2', name: 'Aida'));
  await Future<void>.delayed(Duration.zero);
  _chk('added child persisted', (await store3.load())?.children.length == 2);
  ctl3.selectChild('child-2');
  _chk('select second child', ctl3.childName == 'Aida');

  // ---- setLocale persists ----
  ctl3.setLocale(AppLocale.kk);
  await Future<void>.delayed(Duration.zero);
  _chk('setLocale persisted', (await store3.load())?.locale == AppLocale.kk);

  await ctl3.dispose();

  // ---- new controller restores everything ----
  final ctl4 = AppController(persistStore: store3);
  await ctl4.restore();
  _chk('new controller restores session', ctl4.onboarded && ctl4.children.length == 2 && ctl4.locale == AppLocale.kk);

  // ---- add device, then remove ----
  ctl4.addDevice(const PairedDevice(id: 'TAG-1', name: 'Tag', kind: DeviceKind.tag, childId: 'child-1'));
  await Future<void>.delayed(Duration.zero);
  _chk('device added', ctl4.devices.any((d) => d.id == 'TAG-1'));
  ctl4.removeDevice('TAG-1');
  await Future<void>.delayed(Duration.zero);
  _chk('device removed + persisted', !ctl4.devices.any((d) => d.id == 'TAG-1') &&
      (await store3.load())?.devices.any((d) => d.id == 'TAG-1') == false);

  // ---- geofence zones CRUD on a child ----
  ctl4.upsertGeofence('child-2', Geofence.circle('z1', 'Grandma', const Coordinates(43.3, 76.9), 150));
  await Future<void>.delayed(Duration.zero);
  _chk('zone added', ctl4.children.firstWhere((c) => c.id == 'child-2').geofences.any((f) => f.id == 'z1'));
  _chk('zone persisted', (await store3.load())!.children.firstWhere((c) => c.id == 'child-2').geofences.any((f) => f.id == 'z1'));
  // upsert same id updates in place (no duplicate)
  ctl4.upsertGeofence('child-2', Geofence.circle('z1', 'Grandma', const Coordinates(43.3, 76.9), 250));
  await Future<void>.delayed(Duration.zero);
  final z = ctl4.children.firstWhere((c) => c.id == 'child-2').geofences.where((f) => f.id == 'z1').toList();
  _chk('zone updated in place', z.length == 1 && z.first.radiusM == 250);
  ctl4.removeGeofence('child-2', 'z1');
  await Future<void>.delayed(Duration.zero);
  _chk('zone removed + persisted', !ctl4.children.firstWhere((c) => c.id == 'child-2').geofences.any((f) => f.id == 'z1') &&
      !(await store3.load())!.children.firstWhere((c) => c.id == 'child-2').geofences.any((f) => f.id == 'z1'));

  // ---- remove a child reselects remaining ----
  ctl4.removeChild('child-1'); // currently selected; child-2 remains
  await Future<void>.delayed(Duration.zero);
  _chk('child removed', ctl4.children.length == 1 && ctl4.children.first.id == 'child-2');
  _chk('reselected remaining child', ctl4.childName == 'Aida');

  // ---- BP calibration stored + persisted + restored ----
  ctl4.calibrateBp(cuffSystolic: 128, cuffDiastolic: 82, ppgSystolic: 120, ppgDiastolic: 78,
      at: DateTime.parse('2026-07-15T00:00:00Z'));
  await Future<void>.delayed(Duration.zero);
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
  await Future<void>.delayed(Duration.zero);
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

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
