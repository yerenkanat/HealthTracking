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

  // ---- How people actually write their own number ----
  //
  // Nobody in Almaty writes "700 123 45 67". They write "8 700 123 45 67",
  // because 8 is what you dial domestically, or paste "+7 700 123 45 67" out
  // of a contact card. Both used to be glued onto the dial code as-is, giving
  // +787001234567 and +777001234567 — numbers that reach nobody. This is the
  // phone number of an emergency contact.
  _chk('the domestic trunk 8 is dropped',
      toE164('+7', '8 700 123 45 67') == '+77001234567');
  _chk('a pasted international number is not doubled',
      toE164('+7', '+7 700 123 45 67') == '+77001234567');
  _chk('a country code typed without + is still dropped at 11 digits',
      toE164('+7', '77001234567') == '+77001234567');
  _chk('the plain national form is unchanged',
      toE164('+7', '700 123 45 67') == '+77001234567');
  _chk('a Russian mobile behaves the same',
      toE164('+7', '8 921 123 45 67') == '+79211234567');

  // Outside the +7 zone: one leading trunk zero.
  _chk('a UK trunk zero is dropped', toE164('+44', '07700 900000') == '+447700900000');
  _chk('a German trunk zero is dropped', toE164('+49', '0151 12345678') == '+4915112345678');
  _chk('a pasted UK international number is not doubled',
      toE164('+44', '+44 7700 900000') == '+447700900000');
  // NOT guessed at without a '+': German national numbers beginning 49 exist
  // (4941 is Otterndorf), so stripping a bare leading 49 would corrupt a real
  // number. Left alone on purpose.
  _chk('a bare leading country code is left alone where it is ambiguous',
      toE164('+49', '4941123456') == '+494941123456');

  // Validation has to see the same number that will be dialled.
  _chk('the trunk form validates once normalised',
      isValidNationalNumber('8 700 123 45 67', dial: '+7'));
  _chk('a +7 number of the wrong length is rejected',
      !isValidNationalNumber('700 123 45', dial: '+7'));
  _chk('eleven arbitrary digits are not a +7 number',
      !isValidNationalNumber('12345678901', dial: '+7'));
  _chk('without a dial code the old lenient range still applies',
      isValidNationalNumber('7001234567'));

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

  // ---- Photo ----
  _chk('profile no photo by default', !p.hasPhoto);
  final withPhoto = p.copyWith(photoPath: '/docs/photos/profile_1.jpg');
  _chk('profile set photo', withPhoto.hasPhoto && withPhoto.photoPath == '/docs/photos/profile_1.jpg');
  _chk('profile clear photo', !withPhoto.copyWith(clearPhoto: true).hasPhoto);
  _chk('profile photo round-trip', UserProfile.fromJson(withPhoto.toJson()).photoPath == '/docs/photos/profile_1.jpg');
  const childPhoto = ChildProfile(id: 'cp', name: 'K', photoPath: '/docs/photos/c1.jpg');
  _chk('child set/clear photo', childPhoto.hasPhoto && !childPhoto.copyWith(clearPhoto: true).hasPhoto);

  // ---- Gender ----
  const boy = ChildProfile(id: 'cg', name: 'S', gender: Gender.boy);
  _chk('child gender set', boy.gender == Gender.boy);
  _chk('child gender switch', boy.copyWith(gender: Gender.girl).gender == Gender.girl);
  _chk('child gender clear', boy.copyWith(clearGender: true).gender == null);
  _chk('genderFromName round-trip', genderFromName('girl') == Gender.girl && genderFromName(null) == null);

  // ---- ChildProfile ----
  final child = ChildProfile(
    id: 'c1', name: 'Sultan',
    geofences: [Geofence.circle('home', 'Home', const Coordinates(43.23, 76.88), 100)],
    tagId: 'TAG-1',
  );
  _chk('child fields', child.name == 'Sultan' && child.geofences.length == 1 && child.tagId == 'TAG-1');
  _chk('child copyWith name', child.copyWith(name: 'Aida').name == 'Aida' && child.copyWith(name: 'Aida').id == 'c1');

  // ---- Child date of birth + age ----
  _chk('child no DOB by default', !child.hasDateOfBirth && child.ageInMonths(DateTime(2026, 7, 15)) == 0);
  final dobChild = ChildProfile(id: 'c2', name: 'Baby', dateOfBirth: DateTime(2024, 1, 15));
  _chk('child hasDateOfBirth', dobChild.hasDateOfBirth);
  _chk('child ageInMonths (past birthday)', dobChild.ageInMonths(DateTime(2026, 7, 15)) == 30);
  final preBday = ChildProfile(id: 'c3', name: 'B', dateOfBirth: DateTime(2024, 7, 20));
  _chk('child ageInMonths (before birthday this month)', preBday.ageInMonths(DateTime(2026, 7, 15)) == 23);
  _chk('child ageInMonths clamps future to 0', preBday.ageInMonths(DateTime(2024, 1, 1)) == 0);
  _chk('child DOB copyWith clear', !dobChild.copyWith(clearDateOfBirth: true).hasDateOfBirth);

  // ---- PairedDevice ----
  const band = PairedDevice(id: 'AA:BB', name: 'Band 1', kind: DeviceKind.band);
  const tag = PairedDevice(id: 'TAG-1', name: 'Sultan tag', kind: DeviceKind.tag, childId: 'c1');
  _chk('device kinds', band.kind == DeviceKind.band && tag.kind == DeviceKind.tag && tag.childId == 'c1');
  final dj = PairedDevice.fromJson(tag.toJson());
  _chk('device round-trip', dj.kind == DeviceKind.tag && dj.childId == 'c1' && dj.id == 'TAG-1');

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
