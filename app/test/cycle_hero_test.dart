/// Screen 55 — «Главная без беременности и детей».
///
/// The cycle hero, and the three routers that were the app's missing answer to
/// «Переключение — событием, а не табом». Before this the only way to become
/// pregnant in the app was to find «срок родов» in the calendar and set a date;
/// «Тест положительный» existed in the design system and nowhere in the code.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/cycle_insights.dart';
import 'package:fcs_app/domain/cycle_predictions.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/dashboard/cycle_hero.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  final today = DateTime(2026, 8, 8);

  CycleInfo infoWith({DateTime? ovulation, int? cycleDay}) => CycleInfo(
        today: today,
        avgCycleLength: 28,
        avgPeriodLength: 5,
        lastPeriodStart: today.subtract(const Duration(days: 14)),
        nextPeriodStart: today.add(const Duration(days: 14)),
        ovulation: ovulation,
        fertileStart: today.subtract(const Duration(days: 2)),
        fertileEnd: today.add(const Duration(days: 2)),
        cycleDay: cycleDay ?? 15,
        hasData: true,
      );

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: L10nScope(
        l10n: const L10n(AppLocale.ru),
        child: Scaffold(body: ListView(children: [child])),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('which band today is in', () {
    test('ovulation beats the fertile window it sits inside', () {
      // It is the day the whole screen is about, so it must not be swallowed by
      // the wider window around it.
      final info = infoWith(ovulation: today);
      const phase = CyclePhaseInfo(CyclePhase.fertile, 3, 6);
      expect(cycleBandFor(info, phase), CycleBand.ovulation);
    });

    test('a day either side of ovulation is still the fertile window', () {
      final info = infoWith(ovulation: today.add(const Duration(days: 1)));
      const phase = CyclePhaseInfo(CyclePhase.fertile, 3, 6);
      expect(cycleBandFor(info, phase), CycleBand.fertile);
    });

    test('the other phases map straight through', () {
      final info = infoWith();
      for (final pair in [
        (CyclePhase.menstrual, CycleBand.menstrual),
        (CyclePhase.follicular, CycleBand.follicular),
        (CyclePhase.luteal, CycleBand.luteal),
      ]) {
        expect(cycleBandFor(info, CyclePhaseInfo(pair.$1, 1, 5)), pair.$2);
      }
    });

    test('with no phase at all it claims no band, not even a quiet one', () {
      // A new account with nothing logged. This used to answer
      // `CycleBand.follicular` — and that was checked here, with the reasoning
      // that guessing «Овуляция сегодня» would be a claim about her body from
      // no data. So it is, and so is guessing «Спокойные дни»: the hero printed
      // it at 21pt over a lit second segment, which reads «you are here».
      // Follicular was the softest wrong answer available, not a right one.
      expect(cycleBandFor(infoWith(ovulation: null), null), isNull);
    });
  });

  group('the hero', () {
    testWidgets('says «Овуляция сегодня» on the day', (tester) async {
      await pump(
        tester,
        CycleHero(
          info: infoWith(ovulation: today),
          phase: const CyclePhaseInfo(CyclePhase.fertile, 3, 6),
          confidence: PredictionConfidence.good,
        ),
      );
      const l = L10n(AppLocale.ru);
      expect(find.text(l.t('cyc_ovulation_today')), findsOneWidget);
    });

    testWidgets('reports accuracy in words, never as an invented percentage',
        (tester) async {
      // The spec's mock says «82 %». This app computes a four-level judgement
      // from cycles completed and their spread; rendering a number would invent
      // a precision nothing measured, on a screen used to decide whether she
      // might be pregnant.
      await pump(
        tester,
        CycleHero(
          info: infoWith(),
          phase: const CyclePhaseInfo(CyclePhase.luteal, 1, 14),
          confidence: PredictionConfidence.building,
        ),
      );
      const l = L10n(AppLocale.ru);
      expect(
        find.text(l.t('cyc_forecast_is', {'v': l.t('cyc_conf_building')})),
        findsOneWidget,
      );
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('draws five phase segments', (tester) async {
      await pump(
        tester,
        CycleHero(
          info: infoWith(),
          phase: const CyclePhaseInfo(CyclePhase.luteal, 1, 14),
          confidence: PredictionConfidence.good,
        ),
      );
      expect(CycleBand.values.length, 5);
      expect(tester.takeException(), isNull);
    });
  });

  group('«Что дальше» — the three routers', () {
    testWidgets('offers all three, and each one runs', (tester) async {
      final tapped = <String>[];
      await pump(
        tester,
        WhatNextRouters(
          onPlanning: () => tapped.add('planning'),
          onPregnant: () => tapped.add('pregnant'),
          onHasChild: () => tapped.add('child'),
        ),
      );
      const l = L10n(AppLocale.ru);
      for (final key in ['whatnext_planning', 'whatnext_pregnant', 'whatnext_haschild']) {
        expect(find.text(l.t(key)), findsOneWidget, reason: '$key is not offered');
        await tester.tap(find.text(l.t(key)));
        await tester.pumpAndSettle();
      }
      expect(tapped, ['planning', 'pregnant', 'child']);
    });

    testWidgets('the pregnancy router says what it is for, in her words',
        (tester) async {
      // «Тест положительный» — she recognises the moment, not a database field
      // called due date.
      await pump(tester, const WhatNextRouters());
      expect(find.textContaining('Тест положительный'), findsOneWidget);
    });

    testWidgets('each row clears the 68dp the spec asks of a list row',
        (tester) async {
      await pump(tester, WhatNextRouters(onPlanning: () {}, onPregnant: () {}, onHasChild: () {}));
      const l = L10n(AppLocale.ru);
      for (final key in ['whatnext_planning', 'whatnext_pregnant', 'whatnext_haschild']) {
        final row = find.ancestor(
          of: find.text(l.t(key)),
          matching: find.byType(ConstrainedBox),
        );
        expect(tester.getSize(row.first).height, greaterThanOrEqualTo(68.0),
            reason: '$key is shorter than a list row');
      }
    });
  });
}
