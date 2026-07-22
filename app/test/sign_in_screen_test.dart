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
}
