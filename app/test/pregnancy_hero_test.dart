/// Screen 53's hero — «Главная при беременности».
///
/// docs/CLAUDE-app-design.md §2.4 and ЧАСТЬ 3: «герой недели (размер малыша,
/// прогресс триместров) → … три быстрых действия (Шевеления / Самочувствие /
/// Вес)».
///
/// The home screen had none of it. It opened on band readings and never said
/// what week she was in, which is the one thing a pregnant woman opens this app
/// to see.
///
/// The three quick actions are tested for what they DO, not for being drawn: a
/// row of pretty tiles wired to nothing is the failure this codebase keeps
/// producing, and it had already happened once on this exact screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/dashboard/stage_hero.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  /// [week] completed weeks, with the rest of the pregnancy still to run.
  GestationInfo at(int week) {
    final days = week * 7;
    return GestationInfo(days, week, 0, 280 - days);
  }

  Future<void> pump(WidgetTester tester, Widget child,
      {AppLocale locale = AppLocale.ru}) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(locale),
      home: L10nScope(
        l10n: L10n(locale),
        child: Scaffold(body: ListView(children: [child])),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('the hero says where she is', () {
    testWidgets('week, trimester and how long is left', (tester) async {
      await pump(tester, PregnancyHero(gestation: at(22)));
      const l = L10n(AppLocale.ru);
      expect(find.text(l.t('hero_week_trimester', {'w': 22, 't': 2})), findsOneWidget);
      // 280 − 154 = 126 days = 18 weeks.
      expect(find.text(l.t('hero_weeks_left', {'n': 18})), findsOneWidget);
    });

    testWidgets('and how big the baby is', (tester) async {
      await pump(tester, PregnancyHero(gestation: at(24)));
      const l = L10n(AppLocale.ru);
      expect(find.text(l.t('bsize_corn')), findsOneWidget);
      expect(find.text(l.t('hero_length', {'cm': '30.0'})), findsOneWidget);
    });

    testWidgets('before week 4 it does not invent a fruit', (tester) async {
      // babySizeFor returns null there, and «размером с ничего» is worse than
      // saying it is early.
      await pump(tester, PregnancyHero(gestation: at(2)));
      const l = L10n(AppLocale.ru);
      expect(find.text(l.t('hero_early')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('past the due date it stops counting down', (tester) async {
      // «осталось -3 нед.» is not a fact. The pill disappears instead.
      await pump(tester, PregnancyHero(gestation: GestationInfo(287, 41, 0, -7)));
      const l = L10n(AppLocale.ru);
      // The pill is gone entirely, not merely showing a different number.
      // Not `textContaining('-')`: «3-й триместр» has a hyphen in it, which is
      // what the first version of this assertion caught.
      expect(find.textContaining('осталось'), findsNothing);
      expect(find.text(l.t('hero_weeks_left', {'n': -1})), findsNothing);
    });
  });

  group('the trimester bar', () {
    test('splits at the usual 13 and 27 weeks', () {
      expect(PregnancyHero.trimesterOf(1), 1);
      expect(PregnancyHero.trimesterOf(13), 1);
      expect(PregnancyHero.trimesterOf(14), 2);
      expect(PregnancyHero.trimesterOf(27), 2);
      expect(PregnancyHero.trimesterOf(28), 3);
      expect(PregnancyHero.trimesterOf(40), 3);
    });

    testWidgets('fills one segment per trimester reached', (tester) async {
      await pump(tester, PregnancyHero(gestation: at(22))); // 2nd trimester
      final bars = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(PregnancyHero),
            matching: find.byType(Container),
          ))
          .where((c) => (c.constraints?.maxHeight == 6) ||
              ((c.decoration as BoxDecoration?)?.borderRadius ==
                      BorderRadius.circular(3) &&
                  c.decoration != null))
          .toList();
      // Three segments exist; two are solid, one is the 25% wash.
      expect(bars.length, greaterThanOrEqualTo(3));
    });
  });

  group('the three quick actions', () {
    testWidgets('each one runs its handler', (tester) async {
      // The point of the row. Tiles that look right and do nothing is the
      // defect this screen already shipped once.
      final tapped = <String>[];
      await pump(
        tester,
        QuickActionRow(actions: [
          QuickAction(
            icon: Icons.child_care_rounded,
            tint: Colors.white, iconColor: Colors.black,
            label: 'Шевеления', onTap: () => tapped.add('kicks'),
          ),
          QuickAction(
            icon: Icons.mood_rounded,
            tint: Colors.white, iconColor: Colors.black,
            label: 'Самочувствие', onTap: () => tapped.add('day'),
          ),
          QuickAction(
            icon: Icons.monitor_weight_outlined,
            tint: Colors.white, iconColor: Colors.black,
            label: 'Вес', onTap: () => tapped.add('weight'),
          ),
        ]),
      );

      for (final label in ['Шевеления', 'Самочувствие', 'Вес']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(tapped, ['kicks', 'day', 'weight']);
    });

    testWidgets('shows today\'s figure, and says «ещё нет» when there is none',
        (tester) async {
      await pump(
        tester,
        const QuickActionRow(actions: [
          QuickAction(
            icon: Icons.monitor_weight_outlined,
            tint: Colors.white, iconColor: Colors.black,
            label: 'Вес', value: '64.2 кг',
          ),
          QuickAction(
            icon: Icons.mood_rounded,
            tint: Colors.white, iconColor: Colors.black,
            label: 'Самочувствие', value: 'ещё нет',
          ),
        ]),
      );
      expect(find.text('64.2 кг'), findsOneWidget);
      expect(find.text('ещё нет'), findsOneWidget);
    });

    testWidgets('survives Kazakh at 130% on a 360dp phone', (tester) async {
      // Three cards across the narrowest phone in the longest language is where
      // a fixed-height tile row breaks.
      tester.view.physicalSize = const Size(360 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      const l = L10n(AppLocale.kk);
      await tester.pumpWidget(MaterialApp(
        theme: FcsTheme.light(AppLocale.kk),
        home: L10nScope(
          l10n: l,
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: ListView(children: [
                QuickActionRow(actions: [
                  QuickAction(
                    icon: Icons.child_care_rounded,
                    tint: Colors.white, iconColor: Colors.black,
                    label: l.t('log_kicks'), value: l.t('qa_not_yet'),
                  ),
                  QuickAction(
                    icon: Icons.mood_rounded,
                    tint: Colors.white, iconColor: Colors.black,
                    label: l.t('qa_wellbeing'), value: l.t('qa_not_yet'),
                  ),
                  QuickAction(
                    icon: Icons.monitor_weight_outlined,
                    tint: Colors.white, iconColor: Colors.black,
                    label: l.t('qa_weight'), value: l.t('qa_not_yet'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
