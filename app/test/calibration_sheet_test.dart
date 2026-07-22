/// The blood-pressure calibration sheet — the weekly cuff-vs-band entry that
/// produces the correction offsets. Its logic is verified in verify_calibration;
/// these tests pin the sheet: it refuses without a band reading, stores accepted
/// offsets and closes, and keeps a mismatched pair on screen with an explanation
/// rather than silently discarding it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calibration/bp_calibration_sheet.dart';

final today = DateTime(2026, 7, 22);
const ru = L10n(AppLocale.ru);

/// Pump a host with a button that opens the sheet, and tap it open.
Future<void> openSheet(WidgetTester tester, AppController c) async {
  // L10nScope must sit ABOVE the Navigator (via builder) so the modal bottom
  // sheet — pushed on the root Navigator — inherits it; wrapping only `home`
  // leaves the sheet on the default (English) locale.
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => L10nScope(l10n: ru, child: child!),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showCalibrateBpSheet(context, c),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// A controller whose band has a latest BP reading of [sys]/[dia].
AppController withBand(int sys, int dia) {
  final c = AppController(now: () => today);
  c.debugSeed([
    HealthSample(at: today, heartRate: 72, spo2: 98, systolic: sys.toDouble(), diastolic: dia.toDouble(), coreTemp: 36.6),
  ]);
  return c;
}

void main() {
  testWidgets('with no band reading it explains it cannot calibrate yet', (tester) async {
    final c = AppController(now: () => today); // no samples → latestBp null
    addTearDown(c.dispose);
    await openSheet(tester, c);
    expect(find.text(ru.t('cal_no_band')), findsOneWidget);
    // No cuff inputs to fill when there is nothing to calibrate against.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('an accepted cuff reading stores the offsets and closes', (tester) async {
    final c = withBand(120, 80);
    addTearDown(c.dispose);
    await openSheet(tester, c);
    expect(find.text(ru.t('cal_band_reading', {'sys': 120, 'dia': 80})), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '126'); // +6 systolic
    await tester.enterText(find.byType(TextField).last, '82'); // +2 diastolic
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, ru.t('cal_title')));
    await tester.pumpAndSettle();

    // Stored and dismissed.
    expect(c.bpCalibration, isNotNull);
    expect(c.bpCalibration!.systolicOffset, 6);
    expect(c.bpCalibration!.diastolicOffset, 2);
    expect(find.text(ru.t('cal_band_reading', {'sys': 120, 'dia': 80})), findsNothing);
  });

  testWidgets('a wildly mismatched cuff is refused, with the numbers kept', (tester) async {
    final c = withBand(120, 80);
    addTearDown(c.dispose);
    await openSheet(tester, c);
    // 160 systolic vs a band 120 → a 40 mmHg gap, past the calibration limit.
    await tester.enterText(find.byType(TextField).first, '160');
    await tester.enterText(find.byType(TextField).last, '82');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, ru.t('cal_title')));
    await tester.pumpAndSettle();

    expect(c.bpCalibration, isNull); // nothing stored
    expect(find.text(ru.t('cal_too_far')), findsOneWidget); // explained
    expect(find.byType(TextField), findsWidgets); // still open, numbers kept
  });
}
