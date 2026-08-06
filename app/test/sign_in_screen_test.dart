/// The phone-OTP sign-in screen, end to end against the stub provider.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/phone_auth.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/auth/sign_in_screen.dart';

const ru = L10n(AppLocale.ru);

Future<AuthSession?> pump(WidgetTester tester) async {
  AuthSession? signedIn;
  final provider = StubPhoneAuthProvider(now: () => DateTime.utc(2026, 7, 22, 12));
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(
      l10n: ru,
      child: SignInScreen(provider: provider, onSignedIn: (s) => signedIn = s),
    ),
  ));
  // The closure captures signedIn; return a getter-ish via a wrapper.
  _lastSignedIn = () => signedIn;
  return signedIn;
}

late AuthSession? Function() _lastSignedIn;

void main() {
  testWidgets('phone → code → signed in with the test code', (tester) async {
    await pump(tester);
    expect(find.text(ru.t('auth_phone_intro')), findsOneWidget);

    await tester.enterText(find.byType(TextField), '+77001234567');
    await tester.tap(find.widgetWithText(FilledButton, ru.t('auth_send_code')));
    await tester.pumpAndSettle();

    // Now on the code step.
    expect(find.widgetWithText(FilledButton, ru.t('auth_verify')), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, ru.t('auth_verify')));
    await tester.pumpAndSettle();

    final s = _lastSignedIn();
    expect(s, isNotNull);
    expect(s!.phoneE164, '+77001234567');
    expect(s.userId, isNotEmpty);
  });

  testWidgets('offers to resend the code, on a cooldown', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '+77001234567');
    await tester.tap(find.widgetWithText(FilledButton, ru.t('auth_send_code')));
    // pump (not pumpAndSettle) so the 1s cooldown timer does not run to zero.
    await tester.pump();
    await tester.pump();
    // On the code step the resend affordance is present but on cooldown.
    expect(find.text(ru.t('auth_no_code')), findsOneWidget);
    final resend = tester.widget<TextButton>(find.byType(TextButton).first);
    expect(resend.onPressed, isNull); // disabled during cooldown
    // Let the cooldown expire so no timer outlives the test.
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('a wrong code shows an error and does not sign in', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '+77001234567');
    await tester.tap(find.widgetWithText(FilledButton, ru.t('auth_send_code')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.widgetWithText(FilledButton, ru.t('auth_verify')));
    await tester.pumpAndSettle();

    expect(find.text(ru.t('auth_err_invalid-code')), findsOneWidget);
    expect(_lastSignedIn(), isNull);
  });

  testWidgets('an invalid phone is rejected before any code is sent', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '+7');
    await tester.tap(find.widgetWithText(FilledButton, ru.t('auth_send_code')));
    await tester.pumpAndSettle();
    expect(find.text(ru.t('auth_err_invalid-phone')), findsOneWidget);
    // Still on the phone step.
    expect(find.text(ru.t('auth_phone_intro')), findsOneWidget);
  });

  /// What the screen says when there is no SMS to send.
  ///
  /// The production build has no gateway: `POST /auth/phone` finds or creates
  /// the account and the code step is skipped entirely. The screen still read
  /// «мы отправим код подтверждения» over a button saying «Отправить код», so
  /// she was signed in instantly and then sat waiting for a message nobody
  /// sent — and the natural next move is to retype the number, thinking she
  /// got it wrong.
  group('when the build has no SMS gateway', () {
    testWidgets('promises no code, and offers to continue instead', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: L10nScope(
          l10n: ru,
          child: SignInScreen(
            provider: _NoCodeProvider(),
            onSignedIn: (_) {},
          ),
        ),
      ));

      expect(find.text(ru.t('auth_phone_intro_nocode')), findsOneWidget);
      expect(find.text(ru.t('auth_phone_intro')), findsNothing);
      expect(find.widgetWithText(FilledButton, ru.t('auth_continue')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, ru.t('auth_send_code')), findsNothing);
    });

    testWidgets('a number is enough to be signed in', (tester) async {
      AuthSession? signedIn;
      await tester.pumpWidget(MaterialApp(
        home: L10nScope(
          l10n: ru,
          child: SignInScreen(
            provider: _NoCodeProvider(),
            onSignedIn: (s) => signedIn = s,
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField), '+77001234567');
      await tester.tap(find.widgetWithText(FilledButton, ru.t('auth_continue')));
      await tester.pumpAndSettle();

      expect(signedIn, isNotNull);
      expect(signedIn!.phoneE164, '+77001234567');
    });
  });
}

/// Mirrors ServerPhoneAuthProvider's contract — no SMS, so no code step —
/// without reaching the network.
class _NoCodeProvider implements PhoneAuthProvider {
  @override
  bool get requiresCode => false;

  @override
  Future<OtpChallenge> requestCode(String phoneE164) async {
    if (!isValidE164(phoneE164)) throw const AuthException('invalid-phone');
    return OtpChallenge(verificationId: 'server:$phoneE164', phoneE164: phoneE164);
  }

  @override
  Future<AuthSession> verifyCode(OtpChallenge challenge, String code) async =>
      AuthSession(
        userId: 'u-1',
        phoneE164: challenge.phoneE164,
        token: 't-1',
        signedInAt: DateTime.utc(2026, 8, 6),
      );
}
