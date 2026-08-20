/// Frame 15a — the «Ребёнок» hub: two segments, a grouped care list, and four
/// counts that have to be readings rather than literals.
///
/// This file replaces `child_tools_sheet_test.dart`. Every assertion that file
/// made is still made here — the nine care screens are named, a second tap
/// lands on the screen itself, the screen that opens is about THIS child, a
/// missing birth date is said rather than hidden, and the row that says so
/// opens the editor — retargeted at the segment that replaced the sheet.
///
/// What is new is the part the sheet could not have: the four sublines. Each is
/// asserted against the value the DOMAIN computes for the controller's data,
/// never against a string typed into the test, and each is asserted to MOVE
/// when the controller's data moves. A literal in the widget would pass the
/// first kind of check and fail the second.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/vaccination_schedule_repository.dart';
import 'package:fcs_app/domain/child_growth.dart';
import 'package:fcs_app/domain/cry_analysis.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/newborn_log.dart';
import 'package:fcs_app/domain/phone_auth.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/domain/vaccination.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/home_shell.dart';
import 'package:fcs_app/ui/theme.dart';

const ru = L10n(AppLocale.ru);
final today = DateTime(2026, 8, 12, 9);

AppController withChild({DateTime? dob, String? tagId}) {
  final c = AppController(now: () => today, locale: AppLocale.ru);
  c.addChild(ChildProfile(
      id: 'c1', name: 'Сұлтан', dateOfBirth: dob, tagId: tagId));
  return c;
}

void signIn(AppController c) => c.signIn(AuthSession(
    userId: 'u-1', phoneE164: '+77001112233', token: 't', signedInAt: today));

// L10nScope wraps MaterialApp, never `home:`: the hub pushes routes, and below
// the Navigator they would all silently fall back to English.
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
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(c));
  await tester.pumpAndSettle();
}

/// Tap 1: the «Ребёнок» tab. With no paired tracker the hub already opens on
/// «Сегодня», so there is no tap 2 to get to the care list.
Future<void> openChildTab(WidgetTester tester) async {
  await tester.tap(find.text(ru.t('nav_child')));
  await tester.pumpAndSettle();
}

/// The segment labelled [key], and only it.
///
/// Scoped to [DsSegmented] on purpose: `child_seg_today` and `nav_today` are
/// the same word in all three languages («Сегодня» / «Бүгін» / «Today»), so a
/// bare text finder here also matches the bottom tab bar.
Finder segment(String key) => find.descendant(
      of: find.byType(DsSegmented),
      matching: find.text(ru.t(key)),
    );

Future<void> openToday(WidgetTester tester) async {
  await openChildTab(tester);
  expect(segment('child_seg_today'), findsOneWidget,
      reason: 'the «Сегодня» segment is not on the Ребёнок tab');
  await tester.tap(segment('child_seg_today'));
  await tester.pumpAndSettle();
}

/// The care list scrolls; a finder that never scrolls proves only the first
/// fold, which is how three overflows got through this week.
Future<void> scrollTo(WidgetTester tester, Finder f) => tester.scrollUntilVisible(
      f,
      120,
      scrollable: find.byType(Scrollable).last,
    );

void main() {
  // ------------------------------------------------------------------
  // Carried over from child_tools_sheet_test.dart, unchanged in strength
  // ------------------------------------------------------------------

  testWidgets('all nine care screens are named on the Ребёнок tab',
      (tester) async {
    final c = withChild(dob: DateTime(2026, 2, 12)); // 6 months
    addTearDown(c.dispose);
    // Signed in, so the cry tile is the tool rather than the invitation to
    // sign in. It is present either way — that is asserted separately below.
    signIn(c);
    await pump(tester, c);
    await openToday(tester);

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
      await scrollTo(tester, find.text(ru.t(key)));
      expect(find.text(ru.t(key)), findsOneWidget,
          reason: '«${ru.t(key)}» is not on the care list');
    }
    // Screen 27, which the sheet never offered at all — §15a puts it in
    // «На всякий случай» beside the medical card.
    await scrollTo(tester, find.text(ru.t('gd_title')));
    expect(find.text(ru.t('gd_title')), findsOneWidget);
  });

  testWidgets('a tile lands on the screen itself', (tester) async {
    final c = withChild(dob: DateTime(2026, 2, 12));
    addTearDown(c.dispose);
    await pump(tester, c);
    await openToday(tester);

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
    await openToday(tester);

    await scrollTo(tester, find.text(ru.t('dev_title')));
    await tester.tap(find.text(ru.t('dev_title')));
    await tester.pumpAndSettle();
    // Not merely "a screen opened": the development calendar prints the child's
    // name and their age, so a row wired to the wrong child shows up here.
    expect(find.text('Сұлтан'), findsWidgets);
    expect(find.text(ru.childAge(6)), findsWidgets);
  });

  testWidgets('without a birth date the age-keyed rows say what is missing',
      (tester) async {
    // Hiding them silently is how a parent who skipped the birthday never
    // learns прививки are in the app.
    final c = withChild(dob: null);
    addTearDown(c.dispose);
    await pump(tester, c);
    await openToday(tester);

    expect(find.text(ru.t('dev_title')), findsNothing);
    expect(find.text(ru.t('ill_title')), findsNothing);
    await scrollTo(tester, find.text(ru.t('child_no_dob')));
    expect(find.text(ru.t('child_no_dob')), findsOneWidget);
    expect(find.text(ru.t('tools_needs_dob')), findsOneWidget);
    // Прививки keeps its tile — it self-explains rather than vanishing — and
    // the ones that need no age still work.
    expect(find.text(ru.t('vac_title')), findsOneWidget);
    expect(find.text(ru.t('child_tile_set_dob')), findsOneWidget);
    expect(find.text(ru.t('ei_title')), findsOneWidget);
    expect(find.text(ru.t('grw_title')), findsOneWidget);
  });

  testWidgets('the missing-birth-date row opens the editor that fixes it',
      (tester) async {
    final c = withChild(dob: null);
    addTearDown(c.dispose);
    await pump(tester, c);
    await openToday(tester);

    await scrollTo(tester, find.text(ru.t('child_no_dob')));
    await tester.tap(find.text(ru.t('child_no_dob')));
    await tester.pumpAndSettle();
    // The child editor, on the birth-date field.
    expect(find.text(ru.t('child_dob_hint')), findsWidgets);
  });

  // ------------------------------------------------------------------
  // The segments
  // ------------------------------------------------------------------

  testWidgets('with no paired tracker the tab opens on «Сегодня»',
      (tester) async {
    // «карта без брелока — это пустой экран, поставленный заголовком».
    final c = withChild(dob: DateTime(2026, 2, 12));
    addTearDown(c.dispose);
    await pump(tester, c);
    await openChildTab(tester);

    expect(find.text(ru.t('child_sec_daily').toUpperCase()), findsOneWidget,
        reason: 'the tab opened on the map for a child with no tracker');
  });

  testWidgets('with a paired tracker the tab opens on the map', (tester) async {
    final c = withChild(dob: DateTime(2026, 2, 12), tagId: 'tag-1');
    addTearDown(c.dispose);
    await pump(tester, c);
    await openChildTab(tester);

    expect(find.text(ru.t('child_sec_daily').toUpperCase()), findsNothing,
        reason: 'the tab opened on the care list despite a paired tracker');
    expect(segment('child_seg_where'), findsOneWidget);
  });

  testWidgets('a second tap on the chosen segment does not empty it',
      (tester) async {
    // DsSegmented.onClear is opt-in, and a tab-like use must not pass it: an
    // empty index here leaves the whole tab blank with no way back.
    final c = withChild(dob: DateTime(2026, 2, 12));
    addTearDown(c.dispose);
    await pump(tester, c);
    await openToday(tester);

    await tester.tap(segment('child_seg_today'));
    await tester.pumpAndSettle();
    expect(find.text(ru.t('child_sec_daily').toUpperCase()), findsOneWidget,
        reason: 'tapping the selected segment cleared it and blanked the tab');
  });

  testWidgets('the cry tile is the only entry to the cry screen on this screen',
      (tester) async {
    // The reference puts a banner above a grid whose first tile goes to the
    // same place. Two entries to one screen on one screen is the defect
    // docs/UI_REVIEW_CHECKLIST.md exists for.
    final c = withChild(dob: DateTime(2026, 2, 12));
    addTearDown(c.dispose);
    signIn(c);
    await pump(tester, c);
    await openToday(tester);

    expect(find.text(ru.t('cry_title')), findsOneWidget);
  });

  // ------------------------------------------------------------------
  // The counts — read off the controller, or absent
  // ------------------------------------------------------------------

  testWidgets('«Сегодня отмечено» counts what the controller holds',
      (tester) async {
    final c = withChild(dob: DateTime(2026, 2, 12));
    addTearDown(c.dispose);
    await pump(tester, c);
    await openToday(tester);

    // Nothing logged is a real answer, and it is zero rather than absent.
    expect(find.text(ru.t('child_tile_logged', {'n': 0})), findsOneWidget);

    for (final kind in [
      NewbornEventKind.feed,
      NewbornEventKind.diaper,
      NewbornEventKind.sleep,
    ]) {
      c.logNewbornEvent(
          'c1', NewbornEvent(kind: kind, at: today.subtract(const Duration(hours: 1))));
    }
    await tester.pumpAndSettle();

    // The number the DOMAIN computes, not a number typed here.
    final s = summaryFor(c.newbornLogFor('c1'), today);
    final n = s.feeds + s.diapers + s.sleepStretches;
    expect(n, 3, reason: 'the fixture did not log what this test assumes');
    expect(find.text(ru.t('child_tile_logged', {'n': n})), findsOneWidget,
        reason: 'the tile did not follow the controller');
    expect(find.text(ru.t('child_tile_logged', {'n': 0})), findsNothing,
        reason: 'the tile is printing a literal, not the log');
  });

  testWidgets('«Рост и вес» prints the last measurement and its date, never a percentile',
      (tester) async {
    final c = withChild(dob: DateTime(2026, 2, 12));
    addTearDown(c.dispose);
    await pump(tester, c);
    await openToday(tester);

    expect(find.text(ru.t('child_tile_no_growth')), findsOneWidget);

    c.recordGrowth(
        'c1',
        GrowthPoint(
            at: DateTime(2026, 8, 10), weightKg: 7.4, heightCm: 68));
    await tester.pumpAndSettle();

    expect(find.text('7.4 ${ru.t('grw_kg')} · 68 ${ru.t('grw_cm')} · 10.08.2026'),
        findsOneWidget);
    expect(find.text(ru.t('child_tile_no_growth')), findsNothing);
    // domain/child_growth.dart:12-21 refuses WHO bands. Nothing on this screen
    // may imply one.
    expect(find.textContaining('перцентил'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('«Прививки» says «Стоит уточнить», with the domain\'s own count',
      (tester) async {
    // 18 months: several doses are past their age and none is recorded done.
    final c = withChild(dob: DateTime(2025, 2, 12));
    addTearDown(c.dispose);
    await pump(tester, c);
    await openToday(tester);

    final expected = vaccinesToCatchUp(
      c.children.first.ageInMonths(today),
      c.vaccinesDoneFor('c1'),
      servedVaccines(),
      servedDueWindowMonths(),
    ).length;
    expect(expected, greaterThan(0),
        reason: 'the fixture has nothing to catch up on, so this proves nothing');
    expect(find.text(ru.t('child_tile_vac_check', {'n': expected})),
        findsOneWidget);

    // The word the domain forbids. vaccination.dart:126 calls this `passed`
    // and says the app has no idea what the child has received.
    expect(find.textContaining('просроч'), findsNothing);
    expect(find.textContaining('пропущ'), findsNothing);
  });

  testWidgets('marking every passed dose done turns the tile to «Всё отмечено»',
      (tester) async {
    final c = withChild(dob: DateTime(2025, 2, 12));
    addTearDown(c.dispose);
    await pump(tester, c);
    await openToday(tester);

    for (final v in vaccinesToCatchUp(
      c.children.first.ageInMonths(today),
      c.vaccinesDoneFor('c1'),
      servedVaccines(),
      servedDueWindowMonths(),
    )) {
      c.toggleVaccineDone('c1', vaccineKey(v));
    }
    await tester.pumpAndSettle();

    expect(find.text(ru.t('child_tile_vac_ok')), findsOneWidget);
  });

  testWidgets('the cry tile says «Ещё не проверяли», then the last check',
      (tester) async {
    final c = withChild(dob: DateTime(2026, 2, 12));
    addTearDown(c.dispose);
    signIn(c);
    await pump(tester, c);
    await openToday(tester);

    expect(find.text(ru.t('child_tile_never')), findsOneWidget);

    // Stamped by the controller's own clock, which this fixture pins to
    // [today] — so the date on the tile is the one the history carries.
    c.recordCry(const CryAnalysis(
      primaryReason: 'hungry',
      confidence: 0.81,
      probabilities: {'hungry': 81, 'tired': 19},
      recommendationRu: '',
    ));
    await tester.pumpAndSettle();

    expect(find.text('${ru.t('cry_reason_hungry')} · 12.08.2026'),
        findsOneWidget);
    expect(find.text(ru.t('child_tile_never')), findsNothing);
  });

  testWidgets('below the threshold the tile refuses to name the reason',
      (tester) async {
    // The screen behind it withholds the reason; a tile printing «Голод» for
    // the same recording would be the app disagreeing with itself, with the
    // confident claim made by the line read in passing.
    final c = withChild(dob: DateTime(2026, 2, 12));
    addTearDown(c.dispose);
    signIn(c);
    await pump(tester, c);
    await openToday(tester);

    c.recordCry(const CryAnalysis(
      primaryReason: 'hungry',
      confidence: 0.21,
      probabilities: {'hungry': 21, 'tired': 20},
      recommendationRu: '',
    ));
    await tester.pumpAndSettle();

    expect(find.text('${ru.t('cry_unsure_headline')} · 12.08.2026'),
        findsOneWidget);
    expect(find.textContaining(ru.t('cry_reason_hungry')), findsNothing);
  });

  testWidgets('signed out the cry tile stays and leads to sign-in',
      (tester) async {
    // «Плитка в 15a не прячется — она объясняет и ведёт на вход.» The sheet
    // this replaced dropped the row entirely, so the feature did not exist
    // for anyone who had not signed in.
    final c = withChild(dob: DateTime(2026, 2, 12));
    addTearDown(c.dispose);
    await pump(tester, c);
    await openToday(tester);

    expect(find.text(ru.t('cry_title')), findsOneWidget);
    expect(find.text(ru.t('cry_signed_out')), findsOneWidget);

    await tester.tap(find.text(ru.t('cry_title')));
    await tester.pumpAndSettle();
    expect(find.text(ru.t('auth_title')), findsWidgets,
        reason: 'the signed-out cry tile did not lead to sign-in');
  });
}
