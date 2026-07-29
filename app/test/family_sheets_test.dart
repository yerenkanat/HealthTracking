/// Widget tests for the family bottom sheets (edit profile, add child, add
/// device). These were reachable from Settings but had no coverage — the
/// emergency doctor-phone field in particular round-trips through here and was
/// only unit-tested on the model, never at the widget level.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/family_sheets.dart';

void main() {
  final now = DateTime.utc(2026, 7, 16);

  /// A host whose one button opens [open] against a live BuildContext.
  Widget host(void Function(BuildContext) open) => MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => open(context),
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

  // The profile sheet is tall (name, phone, doctor, birthdate, city); give it a
  // viewport that fits so the Save button is on-screen and tappable.
  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('edit-profile sheet saves the name and the emergency doctor phone', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    tallView(tester);
    await tester.pumpWidget(host((ctx) => showEditProfileSheet(ctx, c)));
    await openSheet(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Aigerim');
    await tester.enterText(find.widgetWithText(TextField, "Doctor's phone (emergency)"), '+77007654321');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(c.profile.displayName, 'Aigerim');
    expect(c.profile.doctorPhone, '+77007654321');
    expect(c.profile.hasDoctor, isTrue);
  });

  testWidgets('edit-profile sheet refuses to save an empty name (stays open)', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    tallView(tester);
    await tester.pumpWidget(host((ctx) => showEditProfileSheet(ctx, c)));
    await openSheet(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Your name'), '');
    await tester.enterText(find.widgetWithText(TextField, "Doctor's phone (emergency)"), '+77007654321');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // onSave returned false → the sheet is still up and nothing was persisted.
    expect(find.widgetWithText(TextField, "Doctor's phone (emergency)"), findsOneWidget);
    expect(c.profile.doctorPhone, isEmpty);
  });

  testWidgets('add-child sheet adds a child by name', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await tester.pumpWidget(host((ctx) => showAddChildSheet(ctx, c)));
    await openSheet(tester);

    await tester.enterText(find.widgetWithText(TextField, "Child's name"), 'Sultan');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(c.children.any((ch) => ch.name == 'Sultan'), isTrue);
  });

  testWidgets('add-device sheet adds a band with the entered id', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await tester.pumpWidget(host((ctx) => showAddDeviceSheet(ctx, c)));
    await openSheet(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Device ID'), 'AA:BB:CC:DD');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(c.devices, isNotEmpty);
  });
}
