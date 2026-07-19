/// Widget tests for the Settings → Data (export / import) UI. Widget tests throw
/// on layout errors, so these guard against the render-overflow regression the
/// export dialog + import sheet previously had.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/settings/settings_screen.dart';

void main() {
  Widget wrap(AppController c) => MaterialApp(
        home: L10nScope(l10n: const L10n(AppLocale.en), child: SettingsScreen(controller: c)),
      );

  testWidgets('backup line reads "never" until an export happens', (tester) async {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    await tester.pumpWidget(wrap(c));
    await tester.scrollUntilVisible(find.text('Never backed up yet'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Never backed up yet'), findsOneWidget);

    // Exporting records the backup time → the line changes.
    c.exportJson();
    await tester.pumpAndSettle();
    expect(find.text('Never backed up yet'), findsNothing);
    expect(c.lastExportAt, isNotNull);
    addTearDown(c.dispose);
  });

  testWidgets('export dialog opens and lays out without overflow', (tester) async {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    c.addAppointment('OB visit', DateTime(2026, 8, 1, 9, 0));
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('Export data'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Export data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export data'));
    await tester.pumpAndSettle(); // throws if the dialog overflows / fails layout

    expect(find.text('Copy'), findsOneWidget);
    expect(find.textContaining('OB visit'), findsOneWidget); // JSON preview
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    addTearDown(c.dispose);
  });

  testWidgets('import sheet opens, accepts text, and restores on Import', (tester) async {
    // Build a backup from one controller...
    final src = AppController(now: () => DateTime(2026, 7, 15));
    src.addAppointment('Scan', DateTime(2026, 8, 2, 10, 0));
    final backup = src.exportJson();
    src.dispose();

    final c = AppController(now: () => DateTime(2026, 7, 15));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('Import data'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Import data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import data'));
    await tester.pumpAndSettle(); // throws if the sheet fails layout

    await tester.enterText(find.byType(TextField).last, backup);
    await tester.pump();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(c.appointments.single.title, 'Scan');
    addTearDown(c.dispose);
  });
}
