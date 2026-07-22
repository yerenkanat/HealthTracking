/// The home-safety checklist screen and its persistence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/persisted_config.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/home_safety.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/home_safety_screen.dart';

Future<void> pump(WidgetTester tester, int ageMonths, Set<String> done,
    {ValueChanged<String>? onToggle, AppLocale loc = AppLocale.ru}) async {
  tester.view.physicalSize = const Size(880, 2800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(
      l10n: L10n(loc),
      child: HomeSafetyScreen(ageMonths: ageMonths, done: done, onToggle: onToggle ?? (_) {}),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('a newborn sees the from-birth tasks, not the later ones', (tester) async {
    await pump(tester, 0, const {});
    expect(find.text(ru.t('hs_stage_birth').toUpperCase()), findsOneWidget);
    expect(find.text(ru.t('hs_safe_sleep_space')), findsOneWidget);
    // A stair gate is a crawling-stage task — not shown for a newborn.
    expect(find.text(ru.t('hs_stair_gates')), findsNothing);
    expect(find.text(ru.t('hs_stage_crawling').toUpperCase()), findsNothing);
  });

  testWidgets('a crawler sees the crawling tasks too', (tester) async {
    await pump(tester, 8, const {});
    expect(find.text(ru.t('hs_stair_gates')), findsOneWidget);
    expect(find.text(ru.t('hs_outlet_covers')), findsOneWidget);
    // But not the standing-stage tasks yet.
    expect(find.text(ru.t('hs_furniture_anchored')), findsNothing);
  });

  testWidgets('shows progress over the relevant tasks', (tester) async {
    final total = homeSafetyRelevantTotal(0);
    await pump(tester, 0, {'safe_sleep_space'});
    expect(find.text(ru.t('hs_progress', {'n': 1, 'total': total})), findsOneWidget);
  });

  testWidgets('tapping a task toggles it', (tester) async {
    String? toggled;
    await pump(tester, 0, const {}, onToggle: (id) => toggled = id);
    await tester.tap(find.text(ru.t('hs_safe_sleep_space')));
    expect(toggled, 'safe_sleep_space');
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, 12, {'safe_sleep_space'}, loc: loc);
      expect(find.textContaining('hs_'), findsNothing, reason: loc.name);
    }
  });

  test('done tasks survive a persistence round-trip', () {
    const cfg = PersistedConfig(
      onboarded: true,
      locale: AppLocale.ru,
      profile: UserProfile(),
      children: [],
      devices: [],
      homeSafetyDone: ['stair_gates', 'outlet_covers'],
    );
    final back = PersistedConfig.decode(cfg.encode());
    expect(back.homeSafetyDone, containsAll(<String>['stair_gates', 'outlet_covers']));
  });

  testWidgets('golden: the checklist for a crawler', (tester) async {
    await pump(tester, 8, {'safe_sleep_space', 'outlet_covers'});
    await expectLater(find.byType(HomeSafetyScreen), matchesGoldenFile('goldens/home_safety.png'));
  });
}
