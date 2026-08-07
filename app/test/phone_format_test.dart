/// Grouping a phone number as it is typed.
///
/// The field took a bare run of digits — `7071112233` — on the one form every
/// user fills. Eleven unbroken digits cannot be checked at a glance, which is
/// exactly what somebody does before tapping the button that decides where her
/// account lives: a transposed pair reads the same as a correct one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/ui/widgets/phone_format.dart';

void main() {
  test('a Kazakh mobile is written the way it is said', () {
    expect(groupPhone('7071112233'), '707 111 22 33');
  });

  test('groups as she types, not only when it is complete', () {
    expect(groupPhone('7'), '7');
    expect(groupPhone('707'), '707');
    expect(groupPhone('7071'), '707 1');
    expect(groupPhone('707111'), '707 111');
    expect(groupPhone('70711122'), '707 111 22');
  });

  test('re-typing an already grouped number does not double the spaces', () {
    // The formatter runs on its own previous output on every keystroke.
    expect(groupPhone('707 111 22 33'), '707 111 22 33');
  });

  test('keeps digits past the shape rather than swallowing them', () {
    // A number that is too long is hers to see, not ours to hide.
    expect(groupPhone('707111223344'), contains('44'));
  });

  test('an unknown country falls back to threes', () {
    expect(groupPhone('4155551234', dial: '+1'), '415 555 123 4');
  });

  test('empty stays empty rather than becoming a stray space', () {
    expect(groupPhone(''), '');
    expect(groupPhone('   '), '');
  });

  test('the grouped text still reaches the server as E.164', () {
    // The whole point: the spaces are for her eyes only. If the profile could
    // not strip them, this change would break every sign-in.
    const p = UserProfile(
        displayName: 'Айгерім', dialCode: '+7', phoneNumber: '707 111 22 33');
    expect(p.e164, '+77071112233');
  });
}
