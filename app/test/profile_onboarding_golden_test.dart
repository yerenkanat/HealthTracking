/// Pictures of Profile, Settings and the onboarding steps, in both languages.
///
/// Profile and onboarding are the two screens a new user meets first and last,
/// and neither had a golden. The Kazakh pass is not decoration: Unbounded has no
/// ә ғ қ ң ө ұ ү һ, so a heading that failed to switch to Rubik drops letters
/// mid-word — visible in an image, invisible to every assertion in the suite.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/onboarding/onboarding_flow.dart';
import 'package:fcs_app/ui/profile/profile_screen.dart';
import 'package:fcs_app/ui/settings/settings_screen.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  final now = DateTime(2026, 7, 16);

  Future<void> shoot(
    WidgetTester tester,
    Widget Function() build,
    String name, {
    AppLocale locale = AppLocale.ru,
    double h = 1100,
  }) async {
    tester.view.physicalSize = Size(402 * 3, h * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: FcsTheme.light(locale),
      home: L10nScope(l10n: L10n(locale), child: build()),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('golden: profile (ru)', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await shoot(tester, () => ProfileScreen(controller: c), 'profile_ru');
  });

  testWidgets('golden: profile (kk)', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await shoot(tester, () => ProfileScreen(controller: c), 'profile_kk', locale: AppLocale.kk);
  });

  testWidgets('golden: settings', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await shoot(tester, () => SettingsScreen(controller: c), 'settings', h: 1300);
  });

  testWidgets('golden: onboarding — first launch', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await shoot(
      tester,
      () => OnboardingFlow(
        controller: c.onboarding,
        onLocaleChange: c.setLocale,
        onComplete: (_) {},
      ),
      'onboarding_language',
      h: 900,
    );
  });
}
