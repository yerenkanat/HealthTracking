/// TODO §10.9 — «Средний цикл: 28 дн.» after ONE logged period.
///
/// The same shape as the `cycleDay ?? 1` fallback closed in `359fb8d` and
/// covered by `cycle_unknown_day_test.dart`, one card lower on the same screen:
/// a number presented as something the app measured, produced by a default.
///
/// It takes TWO period starts to measure one cycle length. With exactly one,
/// `computeCycle` finds no gaps, the median branch never runs, and `avgCycle`
/// is still `_clamp(defaultCycle, 21, 35)` — 28 unless she moved the settings
/// slider (`cycle_predictions.dart:111`). `hasData` is true throughout, so the
/// whole predictions block renders and prints `cyc_avg_cycle`: a stated average
/// cycle length she never provided, with a next-period date, a fertile window
/// and an ovulation date rolled forward from it.
///
/// The app already knew better in two places and neither reached that line:
/// `predictionConfidence` returns `low` at zero completed cycles, and
/// `AppController.cycleBaselineDays` is nullable so «she chose 28» can be told
/// from «nobody chose anything».
///
/// WHAT CHANGED, AND WHAT DELIBERATELY DID NOT. The dates stay. They are what
/// the screen is for, they are hedged by the `_ConfidenceChip` beside them
/// («мало данных»), and `cyc_share_disclaimer` already refuses the contraceptive
/// reading. That chip is the right hedge on a DATE; it is not a licence for a
/// measurement claim to sit next to it. So only the sentence changed: it now
/// names the number as the assumption the dates rest on, and says whose
/// assumption it is.
///
/// These tests fail if the assertion returns.
library;

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/domain/cycle_predictions.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  final today = DateTime(2026, 7, 16);
  const ru = L10n(AppLocale.ru);

  // ---------------------------------------------------------------------------
  // The domain: where the 28 comes from, and whether anything measured it.
  // ---------------------------------------------------------------------------

  group('one logged period measures nothing', () {
    test('but hasData is true, which is what let it through', () {
      final info =
          computeCycle({today.subtract(const Duration(days: 4))}, today);
      expect(info.hasData, isTrue,
          reason: 'hasData gates the entire predictions block');
      expect(info.avgCycleMeasured, isFalse,
          reason: 'no two starts, therefore no gap, therefore nothing to take '
              'a median of — the 28 is the baseline standing in');
      expect(info.avgCycleLength, 28);
    });

    test('a second period start is what turns it into a measurement', () {
      final first = today.subtract(const Duration(days: 34));
      final second = today.subtract(const Duration(days: 4)); // 30 days later
      final info = computeCycle({first, second}, today);
      expect(info.avgCycleMeasured, isTrue);
      expect(info.avgCycleLength, 30,
          reason: 'her own gap, not the 28 baseline');
    });

    test('an empty log claims no measurement either', () {
      expect(computeCycle(const {}, today).avgCycleMeasured, isFalse);
    });

    test('a baseline she never set is distinguishable from one she did', () {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      expect(c.cycleBaselineDays, isNull,
          reason: 'nobody chose anything — the 28 is ours');
      expect(c.avgCycleLength, 28,
          reason: 'and it still reaches computeCycle as defaultCycle, which is '
              'why the card cannot read the number alone');
      c.setCycleBaseline(cycle: 28);
      expect(c.cycleBaselineDays, 28,
          reason: 'she chose 28, and the identical number now means something '
              'the card is allowed to attribute to her');
    });
  });

  // ---------------------------------------------------------------------------
  // The card itself.
  // ---------------------------------------------------------------------------

  group('the predictions card on the calendar screen', () {
    AppController loggedController({List<int> daysAgo = const [4]}) {
      final c = AppController(now: () => today);
      for (final d in daysAgo) {
        c.setDayLog(DayLog(
            date: dateKey(today.subtract(Duration(days: d))),
            flow: Flow.medium));
      }
      return c;
    }

    // L10nScope ABOVE MaterialApp, not at `home:` — below the Navigator every
    // pushed route silently falls back to English.
    Widget wrap(AppController c) => L10nScope(
          l10n: const L10n(AppLocale.ru),
          child: MaterialApp(
            theme: FcsTheme.light(AppLocale.ru),
            home: WomensHealthScreen(controller: c, now: () => today),
          ),
        );

    /// Tall enough that the screen's `ListView(children:)` mounts the whole
    /// column. It builds only what is near the viewport, and an absence
    /// assertion over a widget that was never built passes for the wrong
    /// reason — which is why every `findsNothing` below is preceded by
    /// [expectCardIsBuilt].
    Future<void> pump(WidgetTester tester, AppController c) async {
      tester.view.physicalSize = const Size(402 * 3, 4400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();
    }

    void expectCardIsBuilt(WidgetTester tester) {
      expect(find.text(ru.t('cyc_predictions').toUpperCase()), findsOneWidget,
          reason: 'the card must actually be on screen for an absence '
              'assertion about its contents to mean anything');
      expect(find.text(ru.t('cyc_conf_low')), findsOneWidget,
          reason: 'zero completed cycles → PredictionConfidence.low. The chip '
              'hedging the DATES is what made the asserted average beside it '
              'so strange');
    }

    testWidgets('after one period it states no average she never gave',
        (tester) async {
      final c = loggedController();
      addTearDown(c.dispose);
      await pump(tester, c);
      expectCardIsBuilt(tester);

      expect(find.text(ru.t('cyc_avg_cycle', {'n': 28})), findsNothing,
          reason: '«Средний цикл: 28 дн.» over zero completed cycles is a '
              'measurement produced by a default');
      expect(find.text(ru.t('cyc_avg_cycle_assumed', {'n': 28})), findsOneWidget,
          reason: 'the number the dates rest on, named as an assumption');
    });

    testWidgets('it does not attribute the app\'s own 28 to her',
        (tester) async {
      final c = loggedController();
      addTearDown(c.dispose);
      await pump(tester, c);
      expectCardIsBuilt(tester);

      expect(find.text(ru.t('cyc_avg_cycle_setting', {'n': 28})), findsNothing,
          reason: 'cycleBaselineDays is null — she never moved the slider, and '
              'calling our default «ваша настройка» is the same invention '
              'wearing a politer hat');
    });

    testWidgets('a baseline she DID choose is named as hers', (tester) async {
      final c = loggedController()..setCycleBaseline(cycle: 31);
      addTearDown(c.dispose);
      await pump(tester, c);
      expectCardIsBuilt(tester);

      expect(
          find.text(ru.t('cyc_avg_cycle_setting', {'n': 31})), findsOneWidget);
      expect(find.text(ru.t('cyc_avg_cycle', {'n': 31})), findsNothing,
          reason: 'a slider position is not a measured average either');
      expect(find.text(ru.t('cyc_avg_cycle_assumed', {'n': 31})), findsNothing);
    });

    testWidgets('the dates stay, hedged, rather than being withheld',
        (tester) async {
      // Deliberate, and the reason is written down: the defect is the SENTENCE,
      // not the card. A next-period date derived from a stated assumption and
      // flagged «мало данных» is a forecast; removing it would leave the screen
      // a period tracker exists for blank right after her first log, which
      // teaches her that logging achieves nothing.
      final c = loggedController();
      addTearDown(c.dispose);
      await pump(tester, c);
      expectCardIsBuilt(tester);

      expect(find.text(ru.t('cyc_next_period')), findsOneWidget);
      expect(find.text(ru.t('cyc_phase_fertile')), findsWidgets);
      // findsWidgets, not findsOneWidget: the calendar legend above the card
      // labels its ovulation swatch with the same word.
      expect(find.text(ru.t('cyc_ovulation')), findsWidgets);
    });

    testWidgets('once a cycle IS measured the average comes back',
        (tester) async {
      final c = loggedController(daysAgo: [34, 4]); // a 30-day gap
      addTearDown(c.dispose);
      await pump(tester, c);

      expect(find.text(ru.t('cyc_avg_cycle', {'n': 30})), findsOneWidget,
          reason: 'measured from her own two starts. This line was always '
              'correct and must not have been hedged away with the broken one');
      expect(find.text(ru.t('cyc_avg_cycle_assumed', {'n': 30})), findsNothing);
      expect(find.text(ru.t('cyc_avg_cycle_setting', {'n': 30})), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Width. The new sentence is four times longer than «Средний цикл: 28 дн.»
  // and shares a Row with the confidence chip.
  // ---------------------------------------------------------------------------

  testWidgets('the hedged line fits at 320dp in Kazakh at 130%',
      (tester) async {
    // `narrow_phone_test.dart` renders this screen at 320×640 with a period
    // logged, which is exactly this state — but the predictions card is far
    // below a 640dp fold and the screen's `ListView(children:)` never builds
    // it there. So the width of this line has no history at all, and it is the
    // longest string on the card in the app's longer language.
    //
    // Tall viewport, narrow one: the risk here is HORIZONTAL. The card is a
    // Column inside a ListView, so it cannot overflow vertically, and a 640dp
    // fold would only hide the row being measured.
    const kk = L10n(AppLocale.kk);
    tester.view.physicalSize = const Size(320 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    c.setDayLog(DayLog(
        date: dateKey(today.subtract(const Duration(days: 4))),
        flow: Flow.medium));

    await tester.pumpWidget(L10nScope(
      l10n: kk,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: FcsTheme.light(AppLocale.kk),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: WomensHealthScreen(controller: c, now: () => today),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'the striped overflow bar covers the card on a 320dp phone '
            'with the font slider up — the phone this app is sold to');
    expect(find.text(kk.t('cyc_avg_cycle_assumed', {'n': 28})), findsOneWidget,
        reason: 'and the Kazakh must be the string actually drawn, not a '
            'screen that quietly rendered nothing to fit');
  });

  // ---------------------------------------------------------------------------
  // The wording.
  // ---------------------------------------------------------------------------

  group('the two hedged lines', () {
    const keys = ['cyc_avg_cycle_assumed', 'cyc_avg_cycle_setting'];

    test('exist in all three languages, and the Kazakh is not the Russian', () {
      for (final key in keys) {
        for (final locale in AppLocale.values) {
          final s = L10n(locale).t(key, {'n': 28});
          expect(s, isNotEmpty, reason: '$key is missing in $locale');
          expect(s, isNot(contains(key)),
              reason: '$key fell through to its own name in $locale');
          expect(s, contains('28'),
              reason: '$key ($locale) drops {n} — the number the dates rest on '
                  'is the one thing this line exists to expose');
        }
        expect(const L10n(AppLocale.kk).t(key),
            isNot(const L10n(AppLocale.ru).t(key)),
            reason: '$key ships Russian text to Kazakh readers');
      }
    });

    test('neither carries a number of its own', () {
      // {n} is hers or ours and is substituted in. A second hard-coded figure
      // on the line that exists to stop inventing figures would be absurd.
      for (final key in keys) {
        for (final locale in AppLocale.values) {
          expect(RegExp(r'\d').hasMatch(L10n(locale).t(key)), isFalse,
              reason: '$key ($locale) prints a hard-coded number');
        }
      }
    });
  });
}
