/// Screen 15a — the nine care screens, from the tab they belong to.
///
/// Медкарта, Прививки, Рост и вес, Развитие, Дневник малыша, Детектор плача,
/// Прикорм, Безопасность дома и Болезни all hung off one unlabelled folder
/// glyph floating over a full-bleed map: three taps, and nothing on the tab
/// said they existed.
///
/// So this counts taps from the tab bar, the way a parent does — and the count
/// is the assertion, not a screenshot.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/phone_auth.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/home_shell.dart';
import 'package:fcs_app/ui/theme.dart';

const ru = L10n(AppLocale.ru);
final today = DateTime(2026, 8, 12, 9);

AppController withChild({DateTime? dob}) {
  final c = AppController(now: () => today, locale: AppLocale.ru);
  c.addChild(ChildProfile(id: 'c1', name: 'Сұлтан', dateOfBirth: dob));
  return c;
}

// L10nScope wraps MaterialApp, never `home:`: the tools sheet pushes routes,
// and below the Navigator they would all silently fall back to English.
Widget wrap(AppController c) => StreamBuilder<void>(
      stream: c.changes,
      builder: (_, __) => L10nScope(
        l10n: ru,
        child: MaterialApp(
          theme: FcsTheme.light(AppLocale.ru),
          home: HomeShell(controller: c, catalog: const ContentCatalog({})),
        ),
      ),
    );

Future<void> pump(WidgetTester tester, AppController c) async {
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(c));
  await tester.pumpAndSettle();
}

/// Tap 1: the «Ребёнок» tab. Tap 2: the labelled tools control.
Future<void> openTools(WidgetTester tester) async {
  await tester.tap(find.text(ru.t('nav_child')));
  await tester.pumpAndSettle();
  expect(find.text(ru.t('tr_tools')), findsOneWidget,
      reason: 'the Ребёнок tab still names none of its care screens');
  await tester.tap(find.text(ru.t('tr_tools')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all nine care screens are named on the Ребёнок tab',
      (tester) async {
    final c = withChild(dob: DateTime(2026, 2, 12)); // 6 months
    addTearDown(c.dispose);
    // Signed out, the cry classifier cannot answer — it is reached through the
    // authenticated proxy — so that row is offered only with a session.
    c.signIn(AuthSession(
        userId: 'u-1',
        phoneE164: '+77001112233',
        token: 't',
        signedInAt: today));
    await pump(tester, c);
    await openTools(tester);

    for (final key in [
      'ei_title', // Медкарта
      'vac_title', // Прививки
      'grw_title', // Рост и вес
      'dev_title', // Развитие
      'nb_title', // Дневник малыша
      'cry_title', // Детектор плача
      'sol_card_title', // Прикорм
      'hs_card_title', // Безопасность дома
      'ill_title', // Болезни
    ]) {
      expect(find.text(ru.t(key)), findsOneWidget,
          reason: '«${ru.t(key)}» is not on the tools list');
    }
  });

  /// The target: standing on «Ребёнок», every care screen is two taps — the
  /// tools control, then the row. It was three, the first of them an unlabelled
  /// folder glyph.
  testWidgets('a second tap on the tab lands on the screen itself',
      (tester) async {
    final c = withChild(dob: DateTime(2026, 2, 12));
    addTearDown(c.dispose);
    await pump(tester, c);
    await openTools(tester);

    await tester.tap(find.text(ru.t('vac_title')));
    await tester.pumpAndSettle();
    // The vaccination screen's disclaimer sits at the top — the same landing
    // marker child_care_hub_test uses.
    expect(find.text(ru.t('vac_disclaimer')), findsOneWidget);
  });

  testWidgets('the screen that opens is about THIS child', (tester) async {
    final c = withChild(dob: DateTime(2026, 2, 12)); // 6 months old
    addTearDown(c.dispose);
    await pump(tester, c);
    await openTools(tester);

    await tester.tap(find.text(ru.t('dev_title')));
    await tester.pumpAndSettle();
    // Not merely "a screen opened": the development calendar prints the child's
    // name and their age, so a row wired to the wrong child shows up here.
    expect(find.text('Сұлтан'), findsWidgets);
    expect(find.text(ru.childAge(6)), findsWidgets);
  });

  testWidgets('without a birth date the age-keyed rows say what is missing',
      (tester) async {
    // Five of the nine are keyed on age. Hiding them silently is how a parent
    // who skipped the birthday never learns прививки are in the app.
    final c = withChild(dob: null);
    addTearDown(c.dispose);
    await pump(tester, c);
    await openTools(tester);

    expect(find.text(ru.t('vac_title')), findsNothing);
    expect(find.text(ru.t('dev_title')), findsNothing);
    expect(find.text(ru.t('child_no_dob')), findsOneWidget);
    expect(find.text(ru.t('tools_needs_dob')), findsOneWidget);
    // The ones that need no age still work.
    expect(find.text(ru.t('ei_title')), findsOneWidget);
    expect(find.text(ru.t('grw_title')), findsOneWidget);
  });

  testWidgets('the missing-birth-date row opens the editor that fixes it',
      (tester) async {
    final c = withChild(dob: null);
    addTearDown(c.dispose);
    await pump(tester, c);
    await openTools(tester);

    await tester.tap(find.text(ru.t('child_no_dob')));
    await tester.pumpAndSettle();
    // The child editor, on the birth-date field.
    expect(find.text(ru.t('child_dob_hint')), findsWidgets);
  });
}
