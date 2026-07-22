/// The week-detail screen: the destination for "Подробнее".
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/pregnancy_weeks_repository.dart';
import 'package:fcs_app/domain/baby_size.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/domain/fetal_development.dart';
import 'package:fcs_app/domain/pregnancy_week_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/week_detail_screen.dart';

final today = DateTime(2026, 7, 22);
GestationInfo at(int week) => gestationFor(today.add(Duration(days: (40 - week) * 7)), today)!;

Future<void> pump(WidgetTester tester, int week, [AppLocale loc = AppLocale.ru]) async {
  // Tall: the screen now carries the mother-focused notes and the full warning
  // list, and a short viewport would let the lazy ListView skip the warnings
  // these tests are about.
  tester.view.physicalSize = const Size(880, 4400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(l10n: L10n(loc), child: WeekDetailScreen(gestation: at(week))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('shows the size comparison for the week', (tester) async {
    await pump(tester, 12);
    final size = babySizeFor(12)!;
    expect(find.text(ru.t(size.code)), findsOneWidget);
    expect(find.textContaining(size.lengthCm.toStringAsFixed(1)), findsOneWidget);
  });

  testWidgets('leads with what baby is developing this week', (tester) async {
    await pump(tester, 20);
    expect(find.text(ru.t('fet_title').toUpperCase()), findsOneWidget);
    // Week 20 resolves to the "can hear your voice" highlight.
    expect(fetalHighlightFor(20)!.id, 'voice');
    expect(find.text(ru.t('fet_voice')), findsOneWidget);
  });

  testWidgets('shows the MoH week calendar (recommend / you / baby)', (tester) async {
    debugSetPregnancyWeeks(const [
      PregnancyWeekContent(
        week: 22,
        lengthCm: '19',
        hcg: '—',
        ru: PregnancyWeekText(baby: 'Малыш активно шевелится.', you: 'Вы чувствуете толчки.', recommend: 'Считайте шевеления.'),
        kk: PregnancyWeekText(baby: 'Нәресте қозғалады.', you: 'Тепкенін сезесіз.', recommend: 'Қимылды санаңыз.'),
      ),
    ]);
    addTearDown(() => debugSetPregnancyWeeks(const []));
    await pump(tester, 22);
    expect(find.text(ru.t('pw_recommend').toUpperCase()), findsOneWidget);
    expect(find.text('Считайте шевеления.'), findsOneWidget);
    expect(find.text('Вы чувствуете толчки.'), findsOneWidget);
  });

  testWidgets('tells her how she may feel this week', (tester) async {
    await pump(tester, 22);
    expect(find.text(ru.t('preg_expect_title').toUpperCase()), findsOneWidget);
    // Week 22 is in the first-movements window.
    expect(find.text(ru.t('preg_note_first_movements')), findsOneWidget);
  });

  testWidgets('always shows the when-to-call warnings, at every week', (tester) async {
    for (final week in [8, 22, 36]) {
      await pump(tester, week);
      expect(find.text(ru.t('preg_warn_title')), findsOneWidget, reason: 'week $week');
      // Reduced movement is the one most often missed — assert it explicitly.
      expect(find.text(ru.t('preg_warn_movement')), findsOneWidget, reason: 'week $week');
      expect(find.text(ru.t('preg_warn_bleeding')), findsOneWidget, reason: 'week $week');
    }
  });

  testWidgets('shows the current trimester milestone and the next one', (tester) async {
    await pump(tester, 14);
    expect(find.text(ru.t('MS_SECOND_TRIMESTER')), findsOneWidget);
    // _Card uppercases its title, so assert what is actually drawn.
    expect(find.text(ru.t('ms_next').toUpperCase()), findsOneWidget);
    expect(find.text(ru.t('MS_HALFWAY')), findsOneWidget); // week 20 is next
  });

  testWidgets('at term there is no next milestone to promise', (tester) async {
    await pump(tester, 40);
    expect(find.text(ru.t('ms_next').toUpperCase()), findsNothing);
  });

  testWidgets('very early weeks have no size comparison, and do not invent one', (tester) async {
    // The table starts at week 4; before that a fruit comparison would be made
    // up rather than merely approximate.
    await pump(tester, 2);
    expect(babySizeFor(2), isNull);
    // Uppercased by the card. The first version of this line asserted the
    // mixed-case form and so passed no matter what the screen did.
    expect(find.text(ru.t('bsize_title').toUpperCase()), findsNothing);
  });

  testWidgets('says plainly that every date here is an estimate', (tester) async {
    await pump(tester, 20);
    expect(find.text(ru.t('gest_estimate_note')), findsOneWidget);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, 22, loc);
      expect(find.textContaining('bsize_'), findsNothing, reason: loc.name);
      expect(find.textContaining('MS_'), findsNothing, reason: loc.name);
      expect(find.textContaining('gest_'), findsNothing, reason: loc.name);
      expect(find.textContaining('preg_'), findsNothing, reason: loc.name);
      expect(find.textContaining('fet_'), findsNothing, reason: loc.name);
    }
  });

  testWidgets('golden: week 22', (tester) async {
    // Seed a fixed calendar entry so the golden does not depend on the bundled
    // asset (or on test order, since the loader caches globally).
    debugSetPregnancyWeeks(const [
      PregnancyWeekContent(
        week: 22,
        lengthCm: '19',
        hcg: '—',
        ru: PregnancyWeekText(
            baby: 'Малыш активно шевелится и реагирует на звуки.',
            you: 'Вы отчётливо чувствуете толчки.',
            recommend: 'Считайте шевеления и следите за их регулярностью.'),
        kk: PregnancyWeekText(baby: '—', you: '—', recommend: '—'),
      ),
    ]);
    addTearDown(() => debugSetPregnancyWeeks(const []));
    await pump(tester, 22);
    await expectLater(
      find.byType(WeekDetailScreen),
      matchesGoldenFile('goldens/week_detail_22.png'),
    );
  });
}
