/// Widget tests for the Settings → Data (export / import) UI. Widget tests throw
/// on layout errors, so these guard against the render-overflow regression the
/// export dialog + import sheet previously had.
library;
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

  testWidgets('importing a non-backup file is refused and keeps your data', (tester) async {
    // Regression: any valid JSON decoded into an empty config, which was then
    // applied — so picking the wrong file in the restore dialog silently wiped
    // everything AND reported success.
    final c = AppController(now: () => DateTime(2026, 7, 15));
    c.debugMarkOnboarded();
    c.addAppointment('OB visit', DateTime(2026, 8, 1, 9, 0));
    c.addMedication('Folic acid');
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('Import data'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Import data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import data'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '{"foo":1,"bar":"baz"}');
    await tester.pump(); // let the Import button enable
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    // Import replaces everything, so it confirms first — see the guard in
    // tool/verify_destructive.dart. Confirming here is what reaches the parser.
    expect(find.text('Replace all your data?'), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await tester.pump(); // close the dialog
    await tester.pump(const Duration(milliseconds: 400)); // let the snackbar in

    expect(c.appointments, hasLength(1), reason: 'a wrong file must not cost data');
    expect(c.medications, hasLength(1));
    expect(find.text("Couldn't read that backup"), findsOneWidget);
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

    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();

    expect(c.appointments.single.title, 'Scan');
    addTearDown(c.dispose);
  });

  testWidgets('backing out of the confirmation leaves your data alone', (tester) async {
    // The whole point of the confirmation: a hesitated import must cost nothing.
    final src = AppController(now: () => DateTime(2026, 7, 15));
    src.addAppointment('Scan', DateTime(2026, 8, 2, 10, 0));
    final backup = src.exportJson();
    src.dispose();

    final c = AppController(now: () => DateTime(2026, 7, 15));
    c.addAppointment('Mine', DateTime(2026, 8, 5, 9, 0));
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('Import data'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Import data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import data'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, backup);
    await tester.pump();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Replace all your data?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(c.appointments.single.title, 'Mine', reason: 'cancelling must change nothing');
    addTearDown(c.dispose);
  });

  testWidgets('the export dialog says what is actually in the file', (tester) async {
    // It carries the child's name and date of birth and the coordinates of home
    // and school, and it is headed for the clipboard. The old hint said only
    // what was ABSENT ("band readings are not included"), which is not enough
    // for someone to judge where it is safe to paste.
    final c = AppController(now: () => DateTime(2026, 7, 15));
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('Export data'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Export data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export data'));
    await tester.pumpAndSettle();

    // Anchor on the phrase unique to the hint — "child safety" appears in the
    // app tagline too, which is what an over-loose finder latches onto.
    final hint = tester.widgetList<Text>(find.byType(Text))
        .map((t) => (t.data ?? '').toLowerCase())
        .firstWhere((s) => s.contains('date of birth'), orElse: () => '');
    expect(hint, isNotEmpty, reason: 'the hint must say the file holds the child’s date of birth');
    for (final mustName in ['name', 'coordinates', 'zones', 'health history']) {
      expect(hint, contains(mustName), reason: 'the hint must name what is inside: $mustName');
    }
    addTearDown(c.dispose);
  });
}
