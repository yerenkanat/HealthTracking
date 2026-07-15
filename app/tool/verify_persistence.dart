/// Pure-Dart verification of persistence: config round-trip + AppController
/// restore/save (profile + children + devices). `dart run tool/verify_persistence.dart`
library;

import 'dart:io';

import '../lib/app/app_controller.dart';
import '../lib/core/geofence.dart';
import '../lib/data/app_store.dart';
import '../lib/data/persisted_config.dart';
import '../lib/domain/family.dart';
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
      ChildProfile(id: 'child-1', name: 'Sultan', geofences: [
        Geofence.circle('home', 'Home', const Coordinates(43.238949, 76.889709), 100),
      ]),
      const ChildProfile(id: 'child-2', name: 'Aida'),
    ],
    devices: const [PairedDevice(id: 'AA:BB', name: 'Band', kind: DeviceKind.band)],
  );
  final decoded = PersistedConfig.decode(cfg.encode());
  _chk('round-trip onboarded + locale', decoded.onboarded && decoded.locale == AppLocale.kk);
  _chk('round-trip profile phone', decoded.profile.displayName == 'Aigerim' && decoded.profile.e164 == '+77001234567');
  _chk('round-trip 2 children', decoded.children.length == 2 && decoded.children[1].name == 'Aida');
  _chk('round-trip child geofence', decoded.children[0].geofences.first.center?.lat == 43.238949);
  _chk('round-trip device', decoded.devices.length == 1 && decoded.devices.first.kind == DeviceKind.band);

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

  // ---- reset wipes + returns to onboarding ----
  await ctl4.resetApp();
  _chk('reset clears onboarded', !ctl4.onboarded && ctl4.children.isEmpty);
  _chk('reset clears persisted', (await store3.load()) == null);
  await ctl4.dispose();

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
