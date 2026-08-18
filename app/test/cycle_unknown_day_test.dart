/// TODO §8.5 — the cycle ring must not paint a fallback as a measurement.
///
/// `CycleInfo.cycleDay` is null while `hasData` is TRUE for exactly one reason:
/// the most recent period start she has logged is still in the future, so no
/// days have elapsed to count (`cycle_predictions.dart:158`). The ring drew
/// `(info.cycleDay ?? 1) / info.avgCycleLength` and printed «1» in its middle,
/// so in that state the screen told her she was on DAY 1 OF HER CYCLE — the
/// first day of bleeding, a specific clinical claim, produced by a `??` and not
/// by anything she recorded.
///
/// The same null reached one screen further: `cyclePhaseFor` returns null for
/// it, and `cycleBandFor` mapped a null phase to `CycleBand.follicular`, so the
/// dashboard hero's 21pt headline read «Спокойные дни» over a lit second
/// segment — including for a brand-new account with nothing logged at all,
/// which is the opening state of screen 55.
///
/// These tests fail if either fallback returns.
library;

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/cycle_insights.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/domain/cycle_predictions.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/logging_drawer.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';
import 'package:fcs_app/ui/dashboard/cycle_hero.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/widgets/glass.dart';

void main() {
  final today = DateTime(2026, 7, 16);
  final marked = today.add(const Duration(days: 3)); // 19.07.2026
  const ru = L10n(AppLocale.ru);

  // ---------------------------------------------------------------------------
  // The state is reachable, and not only through a user tapping a future day.
  // ---------------------------------------------------------------------------

  group('a period marked on a date that has not arrived', () {
    test('leaves the cycle day null while hasData stays true', () {
      final info = computeCycle({marked}, today);
      expect(info.hasData, isTrue,
          reason: 'hasData is what the empty branch of the header keys off, so '
              'a true hasData with a null day is what slips past it');
      expect(info.cycleDay, isNull);
      expect(info.lastPeriodStart, marked);
    });

    test('arrives from a server restore, with no wrong tap and no wrong clock',
        () {
      // `mergeRemoteDayLogs` adopts any date the server hands it — there is no
      // future-date filter (app_controller.dart:1732). The month grid refuses
      // to open a future day, so the grid is NOT the only way in: another
      // install, a phone whose clock ran ahead, a restored hand-editable
      // backup, or a flight west across the date line all produce this.
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      c.mergeRemoteDayLogs([DayLog(date: dateKey(marked), flow: Flow.medium)]);
      expect(c.cycle.hasData, isTrue);
      expect(c.cycle.cycleDay, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // The calendar screen's cycle ring.
  // ---------------------------------------------------------------------------

  group('the cycle ring on the calendar screen', () {
    AppController markedController() {
      final c = AppController(now: () => today);
      c.setDayLog(DayLog(date: dateKey(marked), flow: Flow.medium));
      return c;
    }

    Widget wrap(AppController c, {AppLocale locale = AppLocale.ru}) =>
        L10nScope(
          l10n: L10n(locale),
          child: MaterialApp(
            theme: FcsTheme.light(locale),
            home: WomensHealthScreen(controller: c, now: () => today),
          ),
        );

    Future<void> pump(WidgetTester tester, AppController c,
        {AppLocale locale = AppLocale.ru}) async {
      tester.view.physicalSize = const Size(402 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(c, locale: locale));
      await tester.pumpAndSettle();
    }

    MetricRing ringOf(WidgetTester tester) =>
        tester.widget<MetricRing>(find.byType(MetricRing).first);

    testWidgets('draws no arc at all, and dashes the whole circle',
        (tester) async {
      final c = markedController();
      addTearDown(c.dispose);
      await pump(tester, c);

      final ring = ringOf(tester);
      expect(ring.fraction, isNull,
          reason: 'ANY rose arc is a position in the cycle. `?? 1` drew '
              '1/28 of one — a tick at twelve o\'clock that reads as «you have '
              'just started».');
      expect(ring.assessed, 0.0,
          reason: 'the not-assessed dashes, the vocabulary the peace ring '
              'already established — not a second visual language for the '
              'same idea');
    });

    testWidgets('prints a dash where the day would be, never «1»',
        (tester) async {
      final c = markedController();
      addTearDown(c.dispose);
      await pump(tester, c);

      final inRing = find.descendant(
          of: find.byType(MetricRing).first, matching: find.byType(Text));
      final texts =
          tester.widgetList<Text>(inRing).map((t) => t.data).toList();
      expect(texts, contains('—'),
          reason: 'the dash is this product\'s glyph for «no reading» — the '
              'vitals tiles print it where a number would go');
      expect(texts, isNot(contains('1')),
          reason: 'day 1 is the first day of bleeding. The app does not know '
              'that, and must not say it.');
      // Body ink, not dim: dim is how STALE renders, and «not known» is a
      // different claim from «old» (c316c29).
      final dash = tester.widget<Text>(find.descendant(
          of: find.byType(MetricRing).first, matching: find.text('—')));
      expect(dash.style?.color, isNot(Palette.textDim));
    });

    testWidgets('says the cycle day is unknown to a screen reader',
        (tester) async {
      final c = markedController();
      addTearDown(c.dispose);
      final handle = tester.ensureSemantics();
      await pump(tester, c);
      expect(find.bySemanticsLabel(ru.t('cyc_day_unknown')), findsOneWidget,
          reason: 'a dashed circle and an em dash announce nothing on their '
              'own; the reader who cannot see the ring is the one most exposed '
              'to it meaning one thing and announcing another');
      handle.dispose();
    });

    testWidgets('names the marked date and offers to change it', (tester) async {
      final c = markedController();
      addTearDown(c.dispose);
      await pump(tester, c);

      expect(
          find.text(ru.t('cyc_future_mark_title', {'d': '19.07'})), findsOneWidget,
          reason: 'the cause is knowable and singular, so the screen names it '
              'rather than blanking — and it is a restatement of HER entry, '
              'not a verdict on it');
      expect(find.text(ru.t('cyc_future_mark_body')), findsOneWidget);
      expect(find.text(ru.t('cyc_future_mark_fix')), findsOneWidget);
    });

    testWidgets('«Изменить отметку» opens that day, which nothing else reaches',
        (tester) async {
      // The month grid will not open a future day (`onTap: isFuture ? null`),
      // so without this link the entry causing the state cannot be undone from
      // this screen at all.
      final c = markedController();
      addTearDown(c.dispose);
      await pump(tester, c);

      await tester.tap(find.text(ru.t('cyc_future_mark_fix')));
      await tester.pumpAndSettle();

      final sheet = tester.widget<FloStyleCalendarDrawer>(
          find.byType(FloStyleCalendarDrawer));
      expect(dateKey(sheet.day), dateKey(marked),
          reason: 'the sheet must open on the marked date, not on today');
    });

    testWidgets('claims nothing else about where she is in the cycle',
        (tester) async {
      final c = markedController();
      addTearDown(c.dispose);
      await pump(tester, c);

      // Scoped to the header card. Further down the SCREEN, «Месячные через 31
      // дн.» and «Фертильное окно через 12 дн.» are still drawn: `computeCycle`
      // rolls its prediction forward from a start that has not happened, so the
      // countdown contradicts her own entry. That is a WRONG ANCHOR in the
      // prediction, not an invented number, and changing it moves every
      // prediction and every cycle reminder in the app — recorded as a separate
      // item rather than smuggled into this fix.
      final card = find
          .ancestor(
              of: find.text(ru.t('cyc_future_mark_body')),
              matching: find.byType(Container))
          .first;
      expect(
          find.descendant(
              of: card,
              matching: find.textContaining(ru.t('cyc_period_in', {'n': 31}))),
          findsNothing);
      for (final key in [
        'cyc_phase_period',
        'cyc_phase_fertile',
        'cyc_phase_ovulation'
      ]) {
        expect(find.descendant(of: card, matching: find.text(ru.t(key))),
            findsNothing,
            reason: '$key is a phase claim, and the phase is exactly what is '
                'not known here');
      }
      // And the day number itself is nowhere on the card in any form.
      expect(find.descendant(of: card, matching: find.text('1')), findsNothing);
    });

    testWidgets('the known state is untouched — a real day still fills the arc',
        (tester) async {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      // A period that started 10 days ago → cycle day 11.
      c.setDayLog(DayLog(
          date: dateKey(today.subtract(const Duration(days: 10))),
          flow: Flow.medium));
      await pump(tester, c);

      expect(c.cycle.cycleDay, 11);
      final ring = ringOf(tester);
      expect(ring.fraction, closeTo(11 / 28, 0.0001));
      expect(ring.assessed, isNull,
          reason: 'a known day is fully known — no dashes');
      expect(
          find.descendant(
              of: find.byType(MetricRing).first, matching: find.text('11')),
          findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // The dashboard hero, which inherited the same null one screen along.
  // ---------------------------------------------------------------------------

  group('the cycle hero', () {
    Future<void> pumpHero(WidgetTester tester, CycleInfo info) async {
      tester.view.physicalSize = const Size(390 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: FcsTheme.light(AppLocale.ru),
        home: L10nScope(
          l10n: ru,
          child: Scaffold(
            body: ListView(children: [
              CycleHero(
                info: info,
                phase: cyclePhaseFor(info),
                confidence: PredictionConfidence.low,
              ),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    test('no phase means NO band, not the follicular one', () {
      // A brand-new account, and the future-mark state, both land here. The
      // fallback made the second of five segments light up at full white and
      // the headline read «Спокойные дни» — a position in her cycle, from
      // nothing she recorded.
      expect(cycleBandFor(computeCycle(const {}, today), null), isNull);
      final marked_ = computeCycle({marked}, today);
      expect(cycleBandFor(marked_, cyclePhaseFor(marked_)), isNull);
    });

    testWidgets('headlines the absence, not a phase name', (tester) async {
      for (final info in [
        computeCycle(const {}, today),
        computeCycle({marked}, today),
      ]) {
        await pumpHero(tester, info);
        expect(find.text(ru.t('cyc_no_phase')), findsOneWidget);
        for (final key in [
          'cyc_band_follicular',
          'cyc_band_luteal',
          'cyc_phase_period',
          'cyc_phase_fertile',
          'cyc_ovulation_today',
        ]) {
          expect(find.text(ru.t(key)), findsNothing,
              reason: '$key is a phase claim the data cannot support');
        }
      }
    });

    testWidgets('lights no segment of the five', (tester) async {
      await pumpHero(tester, computeCycle(const {}, today));
      final segments = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(3))
          .toList();
      expect(segments.length, 5, reason: 'the five phase segments');
      for (final s in segments) {
        expect((s.decoration as BoxDecoration).color!.a, lessThan(0.9),
            reason: 'a segment at full white says «you are here», and nothing '
                'here knows where here is');
      }
    });

    testWidgets('names the marked date in the day slot', (tester) async {
      await pumpHero(tester, computeCycle({marked}, today));
      expect(find.text(ru.t('cyc_future_mark_title', {'d': '19.07'})),
          findsOneWidget);
    });

    testWidgets('a known day still gets its band and its number', (tester) async {
      final info =
          computeCycle({today.subtract(const Duration(days: 10))}, today);
      await pumpHero(tester, info);
      expect(info.cycleDay, 11);
      expect(find.text(ru.t('cyc_day_n', {'n': 11})), findsOneWidget);
      expect(find.text(ru.t('cyc_no_phase')), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Copy.
  // ---------------------------------------------------------------------------

  group('the wording', () {
    test('exists in all three languages', () {
      for (final key in [
        'cyc_day_unknown',
        'cyc_future_mark_title',
        'cyc_future_mark_body',
        'cyc_future_mark_fix',
        'cyc_no_phase',
      ]) {
        for (final locale in AppLocale.values) {
          final s = L10n(locale).t(key);
          expect(s, isNotEmpty, reason: '$key is missing in $locale');
          expect(s, isNot(contains(key)),
              reason: '$key fell through to its own name in $locale');
        }
        expect(const L10n(AppLocale.kk).t(key),
            isNot(const L10n(AppLocale.ru).t(key)),
            reason: '$key ships Russian text to Kazakh readers');
      }
    });

    test('carries no number the system cannot compute', () {
      // The only digits any of these may contain are the ones substituted from
      // her own entry, which arrive through {d}.
      for (final key in [
        'cyc_day_unknown',
        'cyc_future_mark_body',
        'cyc_future_mark_fix',
        'cyc_no_phase',
      ]) {
        for (final locale in AppLocale.values) {
          expect(RegExp(r'\d').hasMatch(L10n(locale).t(key)), isFalse,
              reason: '$key ($locale) prints a number, and this is the state '
                  'in which the app has no number to print');
        }
      }
    });
  });
}
