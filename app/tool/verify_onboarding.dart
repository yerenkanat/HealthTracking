/// Pure-Dart verification of the onboarding state machine (now with phone + child).
/// `dart run tool/verify_onboarding.dart`
library;

import 'dart:io';
import '../lib/domain/family.dart';
import '../lib/domain/onboarding_controller.dart';
import '../lib/l10n/l10n.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  final c = OnboardingController();

  _chk('starts at welcome', c.step == OnboardingStep.welcome);
  _chk('default locale ru', c.locale == AppLocale.ru);
  _chk('default dial code +7', c.dialCode == '+7');

  c.next();
  _chk('advanced to language', c.step == OnboardingStep.language);
  c.setLocale(AppLocale.kk);
  c.next();
  _chk('advanced to profile', c.step == OnboardingStep.profile);

  // ---- profile now needs name AND a valid phone ----
  _chk('profile blocked without name/phone', !c.canProceed);
  c.setDisplayName('Aigerim');
  _chk('still blocked without phone', !c.canProceed);
  c.setPhoneNumber('700 123 45 67');
  _chk('profile proceeds with name + phone', c.canProceed);
  c.next();
  _chk('advanced to pairBand', c.step == OnboardingStep.pairBand);

  _chk('pairBand can proceed (optional)', c.canProceed);
  c.setBandId('AA:BB:CC:DD:EE:FF');
  c.next();
  _chk('advanced to child', c.step == OnboardingStep.child);

  // The child step is OPTIONAL and used to be a hard block: it required a name
  // AND a home zone, behind a single button that stayed greyed out until both
  // were given, with no skip. A first-time expectant mother — the most likely
  // person to install a pregnancy app — could not finish setup at all without
  // inventing a child.
  _chk('an empty child step can be skipped', c.canProceed);
  _chk('and reports that there is no child', !c.hasChild);

  // Half a child is still refused: a name with no home zone would create a
  // child the tracking half cannot do anything with.
  c.setChildName('Sultan');
  _chk('naming a child then requires a home zone', !c.canProceed);
  c.setChildName('');
  _chk('clearing the name makes it skippable again', c.canProceed);
  c.setChildName('Sultan');
  c.setHome(const ZoneInput('Home', 43.238949, 76.889709, radiusM: 100));
  _chk('child proceeds with name + home', c.canProceed);
  c.setSchool(const ZoneInput('School', 43.25, 76.95, radiusM: 120));
  c.next();
  _chk('reached done', c.isComplete);

  final r = c.build();
  _chk('result locale kk', r.locale == AppLocale.kk);
  _chk('result profile name', r.profile.displayName == 'Aigerim');
  _chk('result profile e164', r.profile.e164 == '+77001234567');
  _chk('result bandId', r.bandId == 'AA:BB:CC:DD:EE:FF');
  _chk('result child name', r.child!.name == 'Sultan');
  _chk('result child has Home + School', r.child!.geofences.length == 2 &&
      r.child!.geofences.any((f) => f.name == 'Home') && r.child!.geofences.any((f) => f.name == 'School'));
  _chk('Home fence circle at point', r.child!.geofences.firstWhere((f) => f.name == 'Home').center?.lat == 43.238949);

  c.back();
  _chk('back returns to child', c.step == OnboardingStep.child);
  _chk('totalSteps excludes done', c.totalSteps == 5);

  // ---- band optional → null bandId ----
  final c2 = OnboardingController();
  c2.next(); c2.next(); // language, profile
  c2.setDisplayName('X');
  c2.setPhoneNumber('9012345678');
  c2.next(); // pairBand
  c2.next(); // child (band skipped)
  c2.setChildName('Y');
  c2.setHome(const ZoneInput('Home', 1, 2));
  c2.next();
  _chk('band optional → null bandId', c2.build().bandId == null);

  // ---- Child gender flows into the result ----
  final cg = OnboardingController();
  cg.setChildName('Sultan');
  cg.setChildGender(Gender.boy);
  _chk('child gender in result', cg.build().child!.gender == Gender.boy);
  // A fresh controller now builds NO child rather than a nameless one. That is
  // the whole point: an empty child would appear in her family list and on the
  // tracking screen as a blank entry she never created.
  _chk('a skipped child step produces no child at all',
      OnboardingController().build().child == null);
  _chk('a named child still defaults gender to null', () {
    final c = OnboardingController()..setChildName('Sultan');
    return c.build().child!.gender == null;
  }());

  // ---- Expecting → due date drives pregnancy mode ----
  final c3 = OnboardingController();
  _chk('not expecting by default', !c3.expecting && c3.build().profile.dueDate == null);
  c3.setExpecting(true);
  c3.setDueDate(DateTime(2026, 12, 1));
  _chk('expecting + due date → profile.dueDate', c3.build().profile.dueDate == DateTime(2026, 12, 1));
  c3.setExpecting(false);
  _chk('unchecking expecting drops due date', c3.build().profile.dueDate == null);

  // ---- A pregnant woman with no children can finish setup ----
  //
  // Walked end to end, because that is the only way the block was visible:
  // every step passed on its own, and the last one simply could not be left.
  {
    final s = OnboardingController();
    s.setDisplayName('Aigerim');
    s.setPhoneNumber('7001112233');
    s.setExpecting(true);
    s.setDueDate(DateTime(2026, 11, 1));
    s.next(); // welcome → language
    s.next(); // language → profile
    s.next(); // profile → pairBand
    s.next(); // pairBand → child
    _chk('she reaches the child step', s.step == OnboardingStep.child);
    _chk('and can leave it without inventing a child', s.canProceed);
    s.next();
    _chk('setup completes', s.isComplete);
    final r = s.build();
    _chk('with no child', r.child == null);
    _chk('her due date intact', r.profile.dueDate == DateTime(2026, 11, 1));
    _chk('her name intact', r.profile.displayName == 'Aigerim');
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
