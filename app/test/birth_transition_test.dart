/// The end-of-pregnancy fork, driven through the UI.
///
/// One dialog used to handle two entirely different events. These tests exist
/// to keep them apart: a birth must carry the date forward into a child record,
/// and the other path must create nothing and say nothing celebratory.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';

final today = DateTime(2026, 7, 22);

AppController pregnant() {
  final c = AppController(now: () => today, locale: AppLocale.ru);
  c.updateProfile(const UserProfile(displayName: 'Айгерим', dialCode: '+7', phoneNumber: '7001112233'));
  c.setDueDate(today.subtract(const Duration(days: 2))); // due date just passed
  return c;
}

Widget wrap(AppController c) => MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.ru),
        child: WomensHealthScreen(controller: c, now: () => today),
      ),
    );

Future<void> openFork(WidgetTester tester, AppController c) async {
  await tester.pumpWidget(wrap(c));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(const L10n(AppLocale.ru).t('cyc_end_pregnancy')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(const L10n(AppLocale.ru).t('cyc_end_pregnancy')));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('the exit offers two paths, not one yes/no', (tester) async {
    final c = pregnant();
    addTearDown(c.dispose);
    await openFork(tester, c);

    expect(find.text(ru.t('birth_which')), findsOneWidget);
    expect(find.text(ru.t('birth_born')), findsOneWidget);
    expect(find.text(ru.t('birth_other')), findsOneWidget);
  });

  testWidgets('"just turn tracking off" creates no child and says nothing cheerful',
      (tester) async {
    // The path a woman takes after a loss. It must not congratulate her, and
    // must not leave a child record behind.
    final c = pregnant();
    addTearDown(c.dispose);
    await openFork(tester, c);

    await tester.tap(find.text(ru.t('birth_other')));
    await tester.pumpAndSettle();

    expect(c.children, isEmpty);
    expect(c.dueDate, isNull);
    expect(find.text(ru.t('birth_title')), findsNothing);
    expect(find.text(ru.t('birth_done')), findsNothing);
  });

  testWidgets('"the baby is here" carries the date into a child record', (tester) async {
    final c = pregnant();
    addTearDown(c.dispose);
    await openFork(tester, c);

    await tester.tap(find.text(ru.t('birth_born')));
    await tester.pumpAndSettle();

    // The date picker opens on the due date, which has just passed.
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Then the name, which may be left blank.
    expect(find.text(ru.t('birth_title')), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Сұлтан');
    await tester.tap(find.text(ru.t('birth_save')));
    await tester.pumpAndSettle();

    expect(c.children, hasLength(1));
    expect(c.children.single.name, 'Сұлтан');
    expect(c.children.single.hasDateOfBirth, isTrue,
        reason: 'the calendars are keyed on this date');
    expect(c.dueDate, isNull, reason: 'pregnancy tracking is over');
  });

  testWidgets('a baby with no name yet still gets a record', (tester) async {
    // Blocking on a name would mean the app stops working during the week it
    // is most wanted.
    final c = pregnant();
    addTearDown(c.dispose);
    await openFork(tester, c);

    await tester.tap(find.text(ru.t('birth_born')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ru.t('birth_save'))); // no name typed
    await tester.pumpAndSettle();

    expect(c.children, hasLength(1));
    expect(c.children.single.name, isEmpty);
    expect(c.children.single.hasDateOfBirth, isTrue);
  });

  testWidgets('backing out of the fork changes nothing', (tester) async {
    final c = pregnant();
    addTearDown(c.dispose);
    await openFork(tester, c);

    Navigator.of(tester.element(find.text(ru.t('birth_which')))).pop();
    await tester.pumpAndSettle();

    expect(c.children, isEmpty);
    expect(c.dueDate, isNotNull, reason: 'she is still pregnant');
  });
}
