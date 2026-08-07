/// Finishing onboarding signs her in with the number she just typed.
///
/// Onboarding collected a phone and then did nothing with it, so the first
/// thing the app said to a woman who had just entered her number was "sign in
/// with your phone number" — step 1 of 7 of the setup checklist. She has no way
/// to know those are the same number and two different acts; it reads as the
/// app not having listened.
///
/// It is not cosmetic. Until she signs in, nothing she records leaves the
/// handset, so the step she is most likely to dismiss as a repeat is the one
/// that decides whether her pregnancy survives a lost phone.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/onboarding_controller.dart';
import 'package:fcs_app/domain/phone_auth.dart';
import 'package:fcs_app/l10n/l10n.dart';

OnboardingResult _result() => OnboardingResult(
      locale: AppLocale.ru,
      profile: const UserProfile(
          displayName: 'Айгерім', dialCode: '+7', phoneNumber: '707 111 22 33'),
      child: null,
      bandId: null,
    );

void main() {
  test('claims the onboarded number and signs her in', () async {
    final c = AppController(now: () => DateTime.utc(2026, 8, 7));
    addTearDown(c.dispose);

    String? asked;
    c.onPhoneSignIn = (phone, name) async {
      asked = phone;
      return AuthSession(
        userId: 'u1', phoneE164: phone, token: 'tok',
        signedInAt: DateTime.utc(2026, 8, 7),
      );
    };

    c.completeOnboarding(_result());
    await Future<void>.delayed(Duration.zero);

    expect(asked, '+77071112233', reason: 'the number she typed was not used');
    expect(c.isSignedIn, isTrue);
  });

  test('a failed claim leaves setup finished and the nudge standing', () async {
    // Offline during setup is ordinary. An error over a freshly finished
    // onboarding would be the first thing she ever saw from us, and the
    // checklist already asks.
    final c = AppController(now: () => DateTime.utc(2026, 8, 7));
    addTearDown(c.dispose);
    c.onPhoneSignIn = (_, __) async => throw Exception('offline');

    c.completeOnboarding(_result());
    await Future<void>.delayed(Duration.zero);

    expect(c.onboarded, isTrue, reason: 'setup must still be complete');
    expect(c.isSignedIn, isFalse);
  });

  test('does nothing without an API configured', () async {
    final c = AppController(now: () => DateTime.utc(2026, 8, 7));
    addTearDown(c.dispose);
    c.completeOnboarding(_result());
    await Future<void>.delayed(Duration.zero);
    expect(c.isSignedIn, isFalse);
  });
}
