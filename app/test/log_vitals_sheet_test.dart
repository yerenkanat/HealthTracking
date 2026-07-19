/// Widget tests for the hand-entered vitals sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/manual_vitals.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/dashboard/log_vitals_sheet.dart';

void main() {
  /// A host with a button that opens the sheet and keeps whatever it returns.
  Widget host(void Function(ManualVitals?) onResult) => MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => onResult(await showLogVitalsSheet(context)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('save is disabled until something is entered', (tester) async {
    await tester.pumpWidget(host((_) {}));
    await openSheet(tester);

    final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    expect(save.onPressed, isNull);
  });

  testWidgets('a temperature alone is enough to save', (tester) async {
    ManualVitals? result;
    await tester.pumpWidget(host((r) => result = r));
    await openSheet(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Temperature (°C)'), '36.8');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(result?.temperature, 36.8);
    expect(result?.heartRate, isNull);
  });

  testWidgets('a half-entered blood pressure explains itself and blocks save', (tester) async {
    await tester.pumpWidget(host((_) {}));
    await openSheet(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Systolic (mmHg)'), '120');
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter both blood-pressure values'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
  });

  testWidgets('a transposed blood pressure is caught', (tester) async {
    await tester.pumpWidget(host((_) {}));
    await openSheet(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Systolic (mmHg)'), '80');
    await tester.enterText(find.widgetWithText(TextField, 'Diastolic (mmHg)'), '120');
    await tester.pumpAndSettle();
    expect(find.textContaining('they may be swapped'), findsOneWidget);
  });

  testWidgets('an implausible value is rejected', (tester) async {
    await tester.pumpWidget(host((_) {}));
    await openSheet(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Heart rate (bpm)'), '900');
    await tester.pumpAndSettle();
    expect(find.textContaining('outside the plausible range'), findsOneWidget);
  });

  testWidgets('the empty dashboard offers a way in when there is no band', (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: HealthDashboardView(samples: const [], onLogVitals: () => opened = true),
      ),
    ));
    expect(find.text('No readings yet'), findsOneWidget);
    // The empty state is otherwise a dead end without hardware.
    await tester.tap(find.widgetWithText(FilledButton, 'Log a reading'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('no entry point when hand-logging is not wired', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: L10nScope(
        l10n: L10n(AppLocale.en),
        child: HealthDashboardView(samples: <HealthSample>[]),
      ),
    ));
    expect(find.widgetWithText(FilledButton, 'Log a reading'), findsNothing);
  });
}
