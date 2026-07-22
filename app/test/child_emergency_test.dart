/// The child emergency medical-ID screen, its form, and its persistence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/persisted_config.dart';
import 'package:fcs_app/domain/child_emergency.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/child_emergency_screen.dart';

Future<void> pump(WidgetTester tester, ChildEmergencyInfo info,
    {ValueChanged<ChildEmergencyInfo>? onSave, AppLocale loc = AppLocale.ru}) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    // Scope above the Navigator so the pushed edit form has one.
    builder: (context, child) => L10nScope(l10n: L10n(loc), child: child!),
    home: ChildEmergencyScreen(childName: 'Сұлтан', info: info, onSave: onSave ?? (_) {}),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('an empty record invites the parent to fill it in', (tester) async {
    await pump(tester, const ChildEmergencyInfo());
    expect(find.text(ru.t('ei_empty')), findsOneWidget);
    expect(find.text(ru.t('ei_add')), findsOneWidget);
  });

  testWidgets('a filled record shows the details, allergies leading', (tester) async {
    await pump(tester, const ChildEmergencyInfo(
      allergies: 'арахис', bloodType: 'A+', doctorName: 'Др. Алиева', contactPhone: '+7 700 111 1111',
    ));
    expect(find.text('арахис'), findsOneWidget);
    expect(find.text('A+'), findsOneWidget);
    expect(find.text('Др. Алиева'), findsOneWidget);
    expect(find.text('+7 700 111 1111'), findsOneWidget);
    // A phone number gets a call button.
    expect(find.text(ru.t('ei_call')), findsOneWidget);
  });

  testWidgets('editing an empty record and saving hands back the new info', (tester) async {
    ChildEmergencyInfo? saved;
    await pump(tester, const ChildEmergencyInfo(), onSave: (i) => saved = i);
    await tester.tap(find.text(ru.t('ei_add')));
    await tester.pumpAndSettle();

    // Type an allergy into its field (labelled by ei_allergies).
    await tester.enterText(find.widgetWithText(TextField, ru.t('ei_allergies')), 'пенициллин');
    await tester.tap(find.text(ru.t('ei_save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.allergies, 'пенициллин');
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, const ChildEmergencyInfo(allergies: 'x', doctorPhone: '112'), loc: loc);
      expect(find.textContaining('ei_'), findsNothing, reason: loc.name);
    }
  });

  test('the info survives a persistence round-trip, per child', () {
    const info = ChildEmergencyInfo(bloodType: 'O+', allergies: 'peanuts', doctorPhone: '112');
    const cfg = PersistedConfig(
      onboarded: true,
      locale: AppLocale.ru,
      profile: UserProfile(),
      children: [],
      devices: [],
      childEmergency: {'c1': info},
    );
    final back = PersistedConfig.decode(cfg.encode());
    expect(back.childEmergency['c1']?.bloodType, 'O+');
    expect(back.childEmergency['c1']?.allergies, 'peanuts');
    expect(back.childEmergency['c1']?.doctorPhone, '112');
  });

  testWidgets('golden: a filled emergency record', (tester) async {
    await pump(tester, const ChildEmergencyInfo(
      allergies: 'Арахис, пенициллин',
      conditions: 'Астма',
      bloodType: 'A+',
      medications: 'Ингалятор',
      doctorName: 'Др. Алиева',
      doctorPhone: '+7 700 000 0000',
      contactName: 'Бабушка',
      contactPhone: '+7 700 111 1111',
    ));
    await expectLater(find.byType(ChildEmergencyScreen), matchesGoldenFile('goldens/child_emergency.png'));
  });
}
