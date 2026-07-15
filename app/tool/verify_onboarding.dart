/// Pure-Dart verification of the onboarding state machine.
/// `dart run tool/verify_onboarding.dart`
library;

import 'dart:io';
import '../lib/domain/onboarding_controller.dart';
import '../lib/l10n/l10n.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  final c = OnboardingController();

  // ---- initial state ----
  _chk('starts at welcome', c.step == OnboardingStep.welcome);
  _chk('default locale ru', c.locale == AppLocale.ru);
  _chk('welcome can proceed', c.canProceed);

  // ---- welcome -> language -> profile ----
  c.next();
  _chk('advanced to language', c.step == OnboardingStep.language);
  c.setLocale(AppLocale.kk);
  _chk('locale set to kk', c.locale == AppLocale.kk);
  c.next();
  _chk('advanced to profile', c.step == OnboardingStep.profile);

  // ---- profile gating ----
  _chk('profile blocked without name', !c.canProceed);
  c.next(); // should be a no-op (blocked)
  _chk('next is no-op while blocked', c.step == OnboardingStep.profile);
  c.setDisplayName('Aigerim');
  _chk('profile proceeds with name', c.canProceed);
  c.next();
  _chk('advanced to pairBand', c.step == OnboardingStep.pairBand);

  // ---- pairBand is optional ----
  _chk('pairBand can proceed (optional)', c.canProceed);
  c.setBandId('AA:BB:CC:DD:EE:FF');
  c.next();
  _chk('advanced to child', c.step == OnboardingStep.child);

  // ---- child gating: needs name + home ----
  _chk('child blocked without name/home', !c.canProceed);
  c.setChildName('Sultan');
  _chk('still blocked without home', !c.canProceed);
  c.setHome(const ZoneInput('Home', 43.238949, 76.889709, radiusM: 100));
  _chk('child proceeds with name + home', c.canProceed);
  c.setSchool(const ZoneInput('School', 43.25, 76.95, radiusM: 120));
  c.next();
  _chk('reached done', c.step == OnboardingStep.done && c.isComplete);

  // ---- build result ----
  final r = c.build();
  _chk('result locale kk', r.locale == AppLocale.kk);
  _chk('result displayName', r.displayName == 'Aigerim');
  _chk('result bandId', r.bandId == 'AA:BB:CC:DD:EE:FF');
  _chk('result childName', r.childName == 'Sultan');
  _chk('result has Home + School fences', r.geofences.length == 2 &&
      r.geofences.any((f) => f.name == 'Home') && r.geofences.any((f) => f.name == 'School'));
  _chk('Home fence is a circle at the given point',
      r.geofences.firstWhere((f) => f.name == 'Home').center?.lat == 43.238949);

  // ---- back navigation ----
  c.back();
  _chk('back returns to child', c.step == OnboardingStep.child);

  // ---- step counters ----
  _chk('totalSteps excludes done', c.totalSteps == 5);

  // ---- skipping band still builds (null bandId) ----
  final c2 = OnboardingController();
  c2.next(); c2.next(); // language, profile
  c2.setDisplayName('X'); c2.next(); // pairBand
  c2.next(); // child (band skipped)
  c2.setChildName('Y');
  c2.setHome(const ZoneInput('Home', 1, 2));
  c2.next();
  _chk('band optional -> null bandId in result', c2.build().bandId == null);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
