/// Pure-Dart verification of the phone-OTP sign-in core (domain/phone_auth.dart).
/// `dart run tool/verify_phone_auth.dart`
///
/// This is the app's root blocker being unblocked: a real sign-in flow that runs
/// today against a deterministic stub and swaps to Firebase later. The things
/// that matter are the ones a wrong implementation would get subtly wrong — a
/// wrong code accepted, a session that does not survive a restart, a userId that
/// changes between runs for the same phone.
library;

import 'dart:io';
import '../lib/domain/phone_auth.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

DateTime _clock() => DateTime.utc(2026, 7, 22, 12);

Future<void> main() async {
  // ---- Validation ----
  _chk('a 6-digit code is valid', isValidOtp('123456'));
  _chk('a 5-digit code is not', !isValidOtp('12345'));
  _chk('a non-numeric code is not', !isValidOtp('12a456'));
  _chk('a well-formed E.164 is valid', isValidE164('+77001234567'));
  _chk('a number without + is not', !isValidE164('77001234567'));
  _chk('too-short is not', !isValidE164('+7700'));

  // ---- Stub provider ----
  final p = StubPhoneAuthProvider(now: _clock);
  {
    final ch = await p.requestCode('+77001234567');
    _chk('requestCode returns a challenge for the phone', ch.phoneE164 == '+77001234567');

    var threw = false;
    try {
      await p.requestCode('bogus');
    } on AuthException catch (e) {
      threw = e.code == 'invalid-phone';
    }
    _chk('requestCode rejects a malformed phone', threw);

    final session = await p.verifyCode(ch, '123456');
    _chk('the test code signs in', session.phoneE164 == '+77001234567');
    _chk('the session carries a token', session.token.isNotEmpty);
    _chk('the session is stamped with the injected clock', session.signedInAt == _clock());

    var rejected = false;
    try {
      await p.verifyCode(ch, '000000');
    } on AuthException catch (e) {
      rejected = e.code == 'invalid-code';
    }
    _chk('a wrong code is refused', rejected);
  }

  // ---- Stable userId ----
  _chk('the same phone maps to the same userId',
      stubUserIdFor('+77001234567') == stubUserIdFor('+77001234567'));
  _chk('different phones map to different userIds',
      stubUserIdFor('+77001234567') != stubUserIdFor('+77007654321'));

  // ---- Session persistence ----
  {
    final s = AuthSession(userId: 'u_1', phoneE164: '+77001234567', token: 't', signedInAt: _clock());
    final round = AuthSession.fromJson(s.toJson());
    _chk('a session round-trips through json',
        round != null && round.userId == 'u_1' && round.phoneE164 == s.phoneE164);
    _chk('a session missing a field decodes to null (not a crash)',
        AuthSession.fromJson({'userId': 'u_1'}) == null);
  }

  // ---- Controller state machine ----
  {
    var changes = 0;
    final c = PhoneAuthController(provider: p, onChange: () => changes++);
    _chk('starts at the phone step', c.step == AuthStep.phone && !c.isSignedIn);

    await c.submitPhone('bogus');
    _chk('a bad phone sets an error and does not advance',
        c.errorCode == 'invalid-phone' && c.step == AuthStep.phone);

    await c.submitPhone('+77001234567');
    _chk('a good phone advances to the code step', c.step == AuthStep.code && c.errorCode == null);

    await c.submitCode('000000');
    _chk('a wrong code stays on the code step with an error',
        c.step == AuthStep.code && c.errorCode == 'invalid-code' && !c.isSignedIn);

    await c.submitCode('123456');
    _chk('the right code signs in and finishes',
        c.step == AuthStep.done && c.isSignedIn && c.session!.phoneE164 == '+77001234567');

    _chk('the controller notified the UI along the way', changes > 0);

    c.editPhone();
    _chk('editPhone returns to the phone step', c.step == AuthStep.phone);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
