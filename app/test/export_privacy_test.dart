/// «Выгрузить копию всех данных» must hand out a COPY, not a KEY.
///
/// The export is written to a file and the only thing the screen can do with it
/// is the system share sheet — which in this country means WhatsApp, to a
/// husband, a sister, or whoever is helping her move to a new phone. It carried
/// the whole PersistedConfig, and the config holds her signed-in session: a
/// bearer token the server honours for ninety days (db/schema.sql). Anyone who
/// received the file could read her health record and her children's live
/// locations for three months, and nothing in the app would ever tell her.
///
/// So the export is her data with every credential removed — and it still has
/// to restore, because it is the only backup this app offers. Who is signed in
/// is a property of the phone, not of the file.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/phone_auth.dart';

/// Distinctive enough that finding it anywhere in the exported text is proof,
/// and long enough that it cannot appear by accident.
const _liveToken = 'sess_live_9f3c1d7b_DO_NOT_SHARE';
const _revokedToken = 'sess_signed_out_2a11ee_DO_NOT_SHARE';

AuthSession _session(String token) => AuthSession(
      userId: 'u_abc123',
      phoneE164: '+77001234567',
      token: token,
      signedInAt: DateTime(2026, 7, 1),
    );

AppController _signedInController() {
  final c = AppController(now: () => DateTime(2026, 7, 15));
  c.debugMarkOnboarded();
  c.signIn(_session(_liveToken));
  c.addAppointment('Приём у гинеколога', DateTime(2026, 8, 1, 9, 0));
  c.logWeight(DateTime(2026, 7, 15), 65.0);
  return c;
}

void main() {
  test('the file she shares contains her data and no session token', () {
    final c = _signedInController();
    final json = c.exportJson();

    // Her data is all there — this is a backup, not a redaction.
    expect(json, contains('Приём у гинеколога'));
    expect(json, contains('65'));

    // The token itself, searched for as a VALUE in the serialised text. Not a
    // key name: renaming 'authSession' to 'session' would defeat that check
    // while shipping exactly the same credential.
    expect(json.contains(_liveToken), isFalse,
        reason: 'the exported backup carries a live 90-day session token');

    c.dispose();
  });

  test('a token she signed out of does not travel either', () {
    // Signing out is local and instant; the revoke is retried later, so the
    // token sits in pendingLogouts — still valid on the server until that retry
    // lands. A queue of unrevoked keys is no safer to share than a live one.
    final c = AppController(now: () => DateTime(2026, 7, 15));
    c.debugMarkOnboarded();
    c.signIn(_session(_revokedToken));
    c.signOut();
    c.signIn(_session(_liveToken));

    final json = c.exportJson();
    expect(json.contains(_revokedToken), isFalse,
        reason: 'the backup carries a session token still awaiting revocation');
    expect(json.contains(_liveToken), isFalse);

    c.dispose();
  });

  test('nothing in the export authenticates: no key holds a token-shaped value', () {
    // A sweep rather than a list, so a credential added to PersistedConfig
    // later has to walk past this test on its way into the share sheet.
    final c = _signedInController();
    final decoded = jsonDecode(c.exportJson()) as Map<String, dynamic>;
    for (final key in ['authSession', 'pendingLogouts']) {
      expect(decoded.containsKey(key), isFalse, reason: '$key is a credential, not data');
    }
    expect(jsonEncode(decoded).toLowerCase().contains('sess_'), isFalse);
    c.dispose();
  });

  test('the stripped backup still restores everything', () {
    // The point of removing the session is that nothing needed it. If this
    // breaks, the fix has cost her the only backup the app offers.
    final a = _signedInController();
    final backup = a.exportJson();

    final b = AppController(now: () => DateTime(2026, 7, 20));
    expect(b.importJson(backup), isTrue);
    expect(b.appointments.single.title, 'Приём у гинеколога');
    expect(b.weights.single.kg, 65.0);
    expect(b.onboarded, isTrue);

    a.dispose();
    b.dispose();
  });

  test('restoring a backup leaves her signed in on this phone', () {
    // The new-handset flow: sign in with her number, then restore. Applying a
    // session-less config verbatim would blank the session she just created and
    // drop her back at the sign-in screen holding a restored, unusable app.
    final source = _signedInController();
    final backup = source.exportJson();

    final phone = AppController(now: () => DateTime(2026, 7, 20));
    phone.signIn(_session('sess_this_phone_owns_it'));
    expect(phone.importJson(backup), isTrue);
    expect(phone.isSignedIn, isTrue, reason: 'restoring a backup signed her out');
    expect(phone.authSession?.token, 'sess_this_phone_owns_it');

    source.dispose();
    phone.dispose();
  });

  test('an OLD backup that still holds a token cannot sign anyone in', () {
    // Files exported before this fix are already out there, in chats. Opening
    // one must restore its data and nothing else — a backup that moves the
    // account to whoever imports it is the same defect from the other side.
    final c = _signedInController();
    final legacy = jsonDecode(c.exportJson()) as Map<String, dynamic>;
    legacy['authSession'] = _session(_liveToken).toJson();
    legacy['pendingLogouts'] = [_revokedToken];

    final fresh = AppController(now: () => DateTime(2026, 7, 20));
    expect(fresh.importJson(jsonEncode(legacy)), isTrue);
    expect(fresh.appointments.single.title, 'Приём у гинеколога'); // data restored
    expect(fresh.isSignedIn, isFalse,
        reason: 'importing a shared file signed the phone in as its author');

    c.dispose();
    fresh.dispose();
  });
}
