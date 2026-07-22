/// The pregnancy weight-gain guide screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/pregnancy_weight_guide.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/pregnancy_weight_screen.dart';

Future<void> pump(WidgetTester tester, double? rate, [AppLocale loc = AppLocale.ru]) async {
  tester.view.physicalSize = const Size(880, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(l10n: L10n(loc), child: PregnancyWeightScreen(weeklyRateKg: rate)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('shows the reference ranges for every BMI band', (tester) async {
    await pump(tester, null);
    for (final b in BmiBand.values) {
      expect(find.text(ru.t('pwg_band_${b.name}')), findsOneWidget, reason: b.name);
    }
    // The normal-band range value, formatted with a ru decimal comma.
    expect(find.text('11,5–16 кг'), findsOneWidget);
  });

  testWidgets('without enough entries it says so instead of a pace', (tester) async {
    await pump(tester, null);
    expect(find.text(ru.t('pwg_no_data')), findsOneWidget);
  });

  testWidgets('an on-track pace is read from the logged rate', (tester) async {
    await pump(tester, 0.42);
    expect(find.text(ru.t('pwg_pace_onTrack')), findsOneWidget);
    expect(find.text(ru.t('pwg_your_avg', {'n': '0,42'})), findsOneWidget);
  });

  testWidgets('a fast pace is flagged gently, with the caveat', (tester) async {
    await pump(tester, 0.9);
    expect(find.text(ru.t('pwg_pace_fast')), findsOneWidget);
  });

  testWidgets('a slow pace is flagged gently', (tester) async {
    await pump(tester, 0.1);
    expect(find.text(ru.t('pwg_pace_slow')), findsOneWidget);
  });

  testWidgets('carries a not-medical-advice note', (tester) async {
    await pump(tester, 0.4);
    expect(find.text(ru.t('pwg_disclaimer')), findsOneWidget);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, 0.42, loc);
      expect(find.textContaining('pwg_'), findsNothing, reason: loc.name);
    }
  });

  testWidgets('golden: the weight-gain guide with an on-track pace', (tester) async {
    await pump(tester, 0.42);
    await expectLater(find.byType(PregnancyWeightScreen), matchesGoldenFile('goldens/pregnancy_weight.png'));
  });
}
