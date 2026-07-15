/// Pure-Dart verification of persistence: config round-trip + AppController
/// restore/save. `dart run tool/verify_persistence.dart`
library;

import 'dart:io';

import '../lib/app/app_controller.dart';
import '../lib/core/geofence.dart';
import '../lib/data/app_store.dart';
import '../lib/data/persisted_config.dart';
import '../lib/domain/onboarding_controller.dart';
import '../lib/l10n/l10n.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

Future<void> main() async {
  // ---- PersistedConfig round-trip (circle + polygon) ----
  final cfg = PersistedConfig(
    onboarded: true,
    locale: AppLocale.kk,
    displayName: 'Aigerim',
    childName: 'Sultan',
    bandId: 'AA:BB',
    geofences: [
      Geofence.circle('home', 'Home', const Coordinates(43.238949, 76.889709), 100),
      Geofence.polygon('yard', 'Yard', const [
        Coordinates(43.24, 76.88), Coordinates(43.24, 76.89), Coordinates(43.25, 76.89),
      ]),
    ],
  );
  final decoded = PersistedConfig.decode(cfg.encode());
  _chk('round-trip onboarded', decoded.onboarded);
  _chk('round-trip locale kk', decoded.locale == AppLocale.kk);
  _chk('round-trip names', decoded.displayName == 'Aigerim' && decoded.childName == 'Sultan');
  _chk('round-trip bandId', decoded.bandId == 'AA:BB');
  _chk('round-trip 2 geofences', decoded.geofences.length == 2);
  _chk('round-trip circle preserved', () {
    final h = decoded.geofences.firstWhere((f) => f.id == 'home');
    return h.shape == GeofenceShape.circle && h.center!.lat == 43.238949 && h.radiusM == 100;
  }());
  _chk('round-trip polygon preserved', () {
    final y = decoded.geofences.firstWhere((f) => f.id == 'yard');
    return y.shape == GeofenceShape.polygon && y.vertices!.length == 3;
  }());

  // ---- AppController.restore() from a seeded store ----
  final seeded = InMemoryAppStore(cfg);
  final ctl = AppController(persistStore: seeded);
  _chk('fresh controller not onboarded', !ctl.onboarded);
  await ctl.restore();
  _chk('restore -> onboarded', ctl.onboarded);
  _chk('restore -> locale kk', ctl.locale == AppLocale.kk);
  _chk('restore -> childName', ctl.childName == 'Sultan');
  _chk('restore -> displayName', ctl.displayName == 'Aigerim');
  _chk('restore -> geofences', ctl.geofences.length == 2);
  await ctl.dispose();

  // ---- Empty store -> stays first-run ----
  final empty = InMemoryAppStore();
  final ctl2 = AppController(persistStore: empty);
  await ctl2.restore();
  _chk('empty store -> not onboarded', !ctl2.onboarded);

  // ---- completeOnboarding persists ----
  final store3 = InMemoryAppStore();
  final ctl3 = AppController(persistStore: store3);
  ctl3.completeOnboarding(OnboardingResult(
    locale: AppLocale.en,
    displayName: 'Mom',
    bandId: null,
    childName: 'Kid',
    geofences: [Geofence.circle('home', 'Home', const Coordinates(1, 2), 50)],
  ));
  await Future<void>.delayed(Duration.zero); // let unawaited save run
  final saved = await store3.load();
  _chk('completeOnboarding persisted onboarded', saved?.onboarded == true);
  _chk('completeOnboarding persisted childName', saved?.childName == 'Kid');
  _chk('completeOnboarding persisted locale en', saved?.locale == AppLocale.en);

  // ---- setLocale persists after onboarding ----
  ctl3.setLocale(AppLocale.kk);
  await Future<void>.delayed(Duration.zero);
  final saved2 = await store3.load();
  _chk('setLocale persisted', saved2?.locale == AppLocale.kk);
  await ctl3.dispose();

  // ---- A new controller pointed at the same store restores the session ----
  final ctl4 = AppController(persistStore: store3);
  await ctl4.restore();
  _chk('new controller restores prior session', ctl4.onboarded && ctl4.childName == 'Kid' && ctl4.locale == AppLocale.kk);
  await ctl4.dispose();

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
