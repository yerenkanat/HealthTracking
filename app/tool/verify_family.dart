/// Pure-Dart verification of country codes, phone E.164, and family models.
/// `dart run tool/verify_family.dart`
library;

import 'dart:io';
import '../lib/domain/country_codes.dart';
import '../lib/domain/family.dart';
import '../lib/core/geofence.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- Country codes ----
  _chk('default country is Kazakhstan', defaultCountry.iso == 'KZ' && defaultCountry.dial == '+7');
  _chk('has CIS countries', countryByIso('UZ')?.dial == '+998' && countryByIso('KG')?.dial == '+996');
  _chk('lookup unknown → null', countryByIso('ZZ') == null);

  // ---- E.164 ----
  _chk('toE164 strips formatting', toE164('+7', '700 123 45 67') == '+77001234567');
  _chk('toE164 handles dashes/parens', toE164('+998', '(90) 123-45-67') == '+998901234567');
  _chk('valid national number', isValidNationalNumber('7001234567'));
  _chk('too short rejected', !isValidNationalNumber('12345'));
  _chk('too long rejected', !isValidNationalNumber('1234567890123'));
  _chk('format groups digits', formatNational('7001234567') == '700 123 45 67');

  // ---- UserProfile ----
  const p = UserProfile(displayName: 'Aigerim', dialCode: '+7', phoneNumber: '700 123 45 67');
  _chk('profile e164', p.e164 == '+77001234567');
  _chk('profile hasPhone', p.hasPhone);
  _chk('profile copyWith', p.copyWith(phoneNumber: '111').phoneNumber == '111' && p.copyWith(phoneNumber: '111').displayName == 'Aigerim');
  final pj = UserProfile.fromJson(p.toJson());
  _chk('profile round-trip', pj.displayName == 'Aigerim' && pj.e164 == '+77001234567');

  const pd = UserProfile(displayName: 'A', dialCode: '+7', phoneNumber: '7001234567', doctorPhone: '+77771234567');
  _chk('profile hasDoctor', pd.hasDoctor);
  _chk('profile doctor round-trip', UserProfile.fromJson(pd.toJson()).doctorPhone == '+77771234567');
  _chk('profile no doctor by default', !p.hasDoctor);

  // ---- Due date (gestation) ----
  _chk('profile no dueDate by default', !p.hasDueDate);
  final withDue = p.copyWith(dueDate: DateTime(2026, 12, 1));
  _chk('profile set dueDate', withDue.hasDueDate && withDue.dueDate == DateTime(2026, 12, 1));
  _chk('profile clear dueDate', !withDue.copyWith(clearDueDate: true).hasDueDate);
  _chk('profile dueDate round-trip',
      UserProfile.fromJson(withDue.toJson()).dueDate == DateTime(2026, 12, 1));
  _chk('profile keeps name when setting dueDate', withDue.displayName == 'Aigerim');

  // ---- ChildProfile ----
  final child = ChildProfile(
    id: 'c1', name: 'Sultan',
    geofences: [Geofence.circle('home', 'Home', const Coordinates(43.23, 76.88), 100)],
    tagId: 'TAG-1',
  );
  _chk('child fields', child.name == 'Sultan' && child.geofences.length == 1 && child.tagId == 'TAG-1');
  _chk('child copyWith name', child.copyWith(name: 'Aida').name == 'Aida' && child.copyWith(name: 'Aida').id == 'c1');

  // ---- PairedDevice ----
  const band = PairedDevice(id: 'AA:BB', name: 'Band 1', kind: DeviceKind.band);
  const tag = PairedDevice(id: 'TAG-1', name: 'Sultan tag', kind: DeviceKind.tag, childId: 'c1');
  _chk('device kinds', band.kind == DeviceKind.band && tag.kind == DeviceKind.tag && tag.childId == 'c1');
  final dj = PairedDevice.fromJson(tag.toJson());
  _chk('device round-trip', dj.kind == DeviceKind.tag && dj.childId == 'c1' && dj.id == 'TAG-1');

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
