/// Widget tests for the Settings and Profile screens (run with `flutter test`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/onboarding_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/profile/profile_screen.dart';
import 'package:fcs_app/ui/settings/settings_screen.dart';

AppController _onboarded() {
  final c = AppController();
  c.completeOnboarding(OnboardingResult(
    locale: AppLocale.en,
    profile: const UserProfile(displayName: 'Aigerim', dialCode: '+7', phoneNumber: '7001234567'),
    bandId: null,
    child: ChildProfile(id: 'child-1', name: 'Sultan', geofences: [
      Geofence.circle('home', 'Home', const Coordinates(43.2, 76.8), 100),
    ]),
  ));
  return c;
}

Widget _wrap(Widget child) =>
    MaterialApp(home: L10nScope(l10n: const L10n(AppLocale.en), child: child));

void main() {
  testWidgets('Settings shows profile, language, child, calibration, about', (tester) async {
    final c = _onboarded();
    await tester.pumpWidget(_wrap(SettingsScreen(controller: c)));

    expect(find.text('Aigerim'), findsOneWidget); // profile row
    expect(find.text('English'), findsOneWidget); // language option
    expect(find.text('Sultan'), findsOneWidget); // child row
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Not calibrated'), 250, scrollable: scrollable);
    expect(find.text('Not calibrated'), findsOneWidget); // BP calibration status
    await tester.scrollUntilVisible(find.text('Umay'), 250, scrollable: scrollable);
    expect(find.text('Umay'), findsOneWidget); // about
    addTearDown(c.dispose);
  });

  testWidgets('Settings language selection updates the controller', (tester) async {
    final c = _onboarded();
    await tester.pumpWidget(_wrap(SettingsScreen(controller: c)));
    expect(c.locale, AppLocale.en);
    await tester.tap(find.text('Қазақша'));
    await tester.pump();
    expect(c.locale, AppLocale.kk);
    addTearDown(c.dispose);
  });

  testWidgets('Profile shows avatar, name, phone, stats', (tester) async {
    final c = _onboarded();
    await tester.pumpWidget(_wrap(ProfileScreen(controller: c)));

    expect(find.text('A'), findsOneWidget); // avatar initial
    expect(find.text('Aigerim'), findsOneWidget);
    expect(find.textContaining('+7'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Children'), findsOneWidget); // stat tile label
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // one child
    addTearDown(c.dispose);
  });
}
