/// Screen 05 — «Здоровье · браслета нет».
///
/// docs/CLAUDE-app-design.md §6: «Без устройства приложение полноценно. Экран
/// «Здоровье без браслета» — ручной дневник со сканом тонометра, а не заглушка
/// с апселлом.» And in ЧАСТЬ 3, in bold: «**Апселла браслета здесь нет.**»
///
/// What was there: a watch icon and «Наденьте браслет — и данные появятся
/// здесь». Shown to a woman who has not bought one — and for most users that is
/// the permanent state of this app, not a step on the way to buying. The screen
/// told her the app was broken until she spent 29 800 ₸.
///
/// The upsell rule is checked as a rule, in every language, because it is the
/// kind of copy that comes back one string at a time.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/dashboard/no_band_card.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  Future<void> pumpDashboard(WidgetTester tester, AppLocale locale) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(locale),
      home: L10nScope(
        l10n: L10n(locale),
        // No samples: the state a user without a band is in permanently.
        child: const HealthDashboardView(samples: []),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a user with no band gets the manual diary, not a stub',
      (tester) async {
    await pumpDashboard(tester, AppLocale.ru);
    expect(find.byType(NoBandCard), findsOneWidget);
    const l = L10n(AppLocale.ru);
    expect(find.text(l.t('noband_title')), findsOneWidget);
  });

  testWidgets('all four entries the spec lists are offered', (tester) async {
    await pumpDashboard(tester, AppLocale.ru);
    const l = L10n(AppLocale.ru);
    for (final key in ['noband_bp', 'noband_pulse', 'noband_weight', 'noband_sleep']) {
      expect(find.text(l.t(key)), findsOneWidget, reason: '$key is not offered');
    }
  });

  testWidgets('and every one of them does something', (tester) async {
    // A diary whose buttons open nothing is the same dead end with more chrome.
    final tapped = <String>[];
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: L10nScope(
        l10n: const L10n(AppLocale.ru),
        child: Scaffold(
          body: ListView(children: [
            NoBandCard(
              onLogVitals: () => tapped.add('vitals'),
              onLogWeight: () => tapped.add('weight'),
              onLogSleep: () => tapped.add('sleep'),
              onScanMonitor: () => tapped.add('scan'),
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    const l = L10n(AppLocale.ru);
    for (final key in ['noband_bp', 'noband_weight', 'noband_sleep', 'noband_scan_title']) {
      await tester.tap(find.text(l.t(key)));
      await tester.pumpAndSettle();
    }
    expect(tapped, ['vitals', 'weight', 'sleep', 'scan']);
  });

  testWidgets('the camera card is hidden when nothing can read the photo',
      (tester) async {
    // Offering a scan with no server behind it is worse than not offering one.
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: L10nScope(
        l10n: const L10n(AppLocale.ru),
        child: const Scaffold(body: NoBandCard()),
      ),
    ));
    await tester.pumpAndSettle();
    const l = L10n(AppLocale.ru);
    expect(find.text(l.t('noband_scan_title')), findsNothing);
  });

  group('«Апселла браслета здесь нет»', () {
    testWidgets('the screen never tells her to put a band on', (tester) async {
      // The exact copy that was here, and its siblings. This is the kind of
      // line that comes back one string at a time, in one language first.
      const banned = {
        AppLocale.ru: ['Наденьте браслет', 'купите', 'браслет —'],
        AppLocale.kk: ['Білезікті тағыңыз', 'сатып'],
        AppLocale.en: ['Put on your band', 'buy'],
      };
      for (final locale in AppLocale.values) {
        await pumpDashboard(tester, locale);
        for (final phrase in banned[locale]!) {
          expect(find.textContaining(phrase), findsNothing,
              reason: '${locale.name} upsells the band on the no-band screen');
        }
      }
    });

    testWidgets('and says the app is whole without one', (tester) async {
      // «Без устройства приложение полноценно» — stated, not merely implied by
      // the absence of a nag.
      await pumpDashboard(tester, AppLocale.ru);
      const l = L10n(AppLocale.ru);
      expect(find.text(l.t('noband_body')), findsOneWidget);
    });
  });
}
