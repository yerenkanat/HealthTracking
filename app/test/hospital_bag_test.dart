/// The hospital-bag checklist screen and its persistence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/persisted_config.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/hospital_bag.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/hospital_bag_screen.dart';

Future<void> pump(WidgetTester tester, Set<String> checked,
    {ValueChanged<String>? onToggle, AppLocale loc = AppLocale.ru}) async {
  tester.view.physicalSize = const Size(880, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(
      l10n: L10n(loc),
      child: HospitalBagScreen(checked: checked, onToggle: onToggle ?? (_) {}),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('shows the three bags and their items', (tester) async {
    await pump(tester, const {});
    for (final c in BagCategory.values) {
      expect(find.text(ru.t('bag_cat_${c.name}').toUpperCase()), findsOneWidget, reason: c.name);
    }
    expect(find.text(ru.t('bag_car_seat')), findsOneWidget);
    expect(find.text(ru.t('bag_exchange_card')), findsOneWidget);
  });

  testWidgets('shows how many are packed', (tester) async {
    await pump(tester, {hospitalBagItems.first.id, hospitalBagItems[1].id});
    expect(find.text(ru.t('bag_packed', {'n': 2, 'total': hospitalBagTotal})), findsOneWidget);
  });

  testWidgets('tapping an item toggles it', (tester) async {
    String? toggled;
    await pump(tester, const {}, onToggle: (id) => toggled = id);
    await tester.tap(find.text(ru.t('bag_car_seat')));
    expect(toggled, 'car_seat');
  });

  testWidgets('everything packed shows the done state', (tester) async {
    await pump(tester, {for (final i in hospitalBagItems) i.id});
    expect(find.text(ru.t('bag_done')), findsOneWidget);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, {hospitalBagItems.first.id}, loc: loc);
      expect(find.textContaining('bag_'), findsNothing, reason: loc.name);
    }
  });

  test('the ticks survive a persistence round-trip', () {
    const cfg = PersistedConfig(
      onboarded: true,
      locale: AppLocale.ru,
      profile: UserProfile(),
      children: [],
      devices: [],
      hospitalBagChecked: ['car_seat', 'nappies'],
    );
    final back = PersistedConfig.decode(cfg.encode());
    expect(back.hospitalBagChecked, containsAll(<String>['car_seat', 'nappies']));
  });

  test('a corrupt tick entry is dropped, not the whole config', () {
    // A non-string in the list must not throw out the parse.
    final json = {
      'onboarded': true,
      'locale': 'ru',
      'profile': const UserProfile().toJson(),
      'children': [],
      'devices': [],
      'hospitalBagChecked': ['car_seat', 42, null, 'nappies'],
    };
    final cfg = PersistedConfig.fromJson(json);
    expect(cfg.hospitalBagChecked, <String>['car_seat', 'nappies']);
  });

  testWidgets('golden: the checklist part-packed', (tester) async {
    await pump(tester, {'id_documents', 'car_seat', 'nightgown'});
    await expectLater(find.byType(HospitalBagScreen), matchesGoldenFile('goldens/hospital_bag.png'));
  });
}
