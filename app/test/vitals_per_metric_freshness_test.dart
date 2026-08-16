/// Backlog 1.1 — freshness belongs to a READING, not to a frame.
///
/// The watch sends a sample every couple of minutes and puts `tempRaw = 0` in
/// it for anything it did not measure. Freshness was computed per SAMPLE, so
/// the newest thing on screen dated the stalest number on it: «2 мин назад»
/// over last night's 36.9. The age shown belonged to a different reading than
/// the number shown.
///
/// And the ladder is per metric, because the two ends are different kinds of
/// fact (docs/CLINICAL-REVIEW-WATCH.md, "Freshness must differ per metric"):
///
/// | Blood pressure | ≤ 4 h AND calibration ≤ 8 days | 4–12 h | > 12 h, always when calibration is stale |
/// | Heart rate     | ≤ 6 h                          | 6–24 h | > 24 h |
/// | SpO2           | ≤ 6 h                          | 6–24 h | > 24 h |
///
/// The second half of the item is the absorber: «Всё стабильно» — now
/// `ADV_NOTHING_UNUSUAL` — rendered over readings the app knew were old. A
/// reassurance may claim no more than the readings behind it, so the sentence
/// is computed from current readings only. The corollary is asserted just as
/// hard: **the warnings are not gated**, and neither is the ring's ability to
/// go down.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/current_advisories.dart';
import 'package:fcs_app/domain/health_monitor.dart' show latestTelemetryMaxAge;
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/advisor/advisor_screen.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/dashboard/health_summary.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/widgets/glass.dart';

const _en = L10n(AppLocale.en);

void main() {
  final now = DateTime(2026, 8, 14, 18);

  // ---------------------------------------------------------------------------
  // The reading the age belongs to
  // ---------------------------------------------------------------------------
  group('latestAtFor answers per metric, not per sample', () {
    /// A wrist that measured a temperature nine hours ago and has been sending
    /// frames without one every two minutes since. This is the exact shape the
    /// backlog item describes, and it is what the watch actually does.
    final watchDay = <HealthSample>[
      HealthSample(
          at: now.subtract(const Duration(hours: 9)),
          heartRate: 70,
          spo2: 98,
          coreTemp: 36.9,
          source: ReadingSource.sensor),
      for (var i = 4; i >= 0; i--)
        HealthSample(
            at: now.subtract(Duration(minutes: i * 2)),
            heartRate: 74,
            spo2: 98,
            source: ReadingSource.sensor),
    ];

    test('the newest temperature is nine hours old; the newest sample is not', () {
      expect(latestAtFor(watchDay, 'temp'), now.subtract(const Duration(hours: 9)));
      expect(latestAtFor(watchDay, 'hr'), now);
      // The old rule, kept here as the thing that was wrong: the newest SAMPLE
      // is two minutes old and carries no temperature at all.
      final newestSample =
          watchDay.map((s) => s.at).reduce((a, b) => a.isAfter(b) ? a : b);
      expect(newestSample, now);
    });

    test('order in the list does not decide it', () {
      // Nothing guarantees the order of what the band flushed.
      final shuffled = [watchDay[2], watchDay.first, watchDay[1]];
      expect(latestAtFor(shuffled, 'temp'),
          now.subtract(const Duration(hours: 9)));
    });

    test('a metric nothing carries has no age', () {
      expect(latestAtFor(watchDay, 'systolic'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // The ladder
  // ---------------------------------------------------------------------------
  group('the ladder differs per metric', () {
    MetricFreshness bp(Duration age, {bool calStale = false}) => metricFreshness(
        'systolic', age,
        source: ReadingSource.sensor, bpCalibrationStale: calStale);

    test('blood pressure: four hours, then twelve', () {
      expect(bp(const Duration(hours: 4)), MetricFreshness.current);
      expect(bp(const Duration(hours: 4, minutes: 1)), MetricFreshness.aging);
      expect(bp(const Duration(hours: 12)), MetricFreshness.aging);
      expect(bp(const Duration(hours: 12, minutes: 1)), MetricFreshness.stale);
    });

    test('heart rate and SpO2: six hours, then a day', () {
      for (final k in ['hr', 'spo2']) {
        expect(metricFreshness(k, const Duration(hours: 6)),
            MetricFreshness.current, reason: k);
        expect(metricFreshness(k, const Duration(hours: 6, minutes: 1)),
            MetricFreshness.aging, reason: k);
        expect(metricFreshness(k, const Duration(hours: 24)),
            MetricFreshness.aging, reason: k);
        expect(metricFreshness(k, const Duration(hours: 24, minutes: 1)),
            MetricFreshness.stale, reason: k);
      }
    });

    test('a heart rate at nine hours outlives a blood pressure at nine hours', () {
      // The ruling in one line. Same age, same watch, different kind of fact.
      const age = Duration(hours: 9);
      expect(metricFreshness('hr', age), MetricFreshness.aging);
      expect(bp(age), MetricFreshness.aging);
      expect(metricFreshness('hr', const Duration(hours: 13)),
          MetricFreshness.aging);
      expect(bp(const Duration(hours: 13)), MetricFreshness.stale);
    });

    test('a stale calibration takes a WRIST blood pressure out at any age', () {
      expect(bp(const Duration(minutes: 1), calStale: true),
          MetricFreshness.stale);
    });

    test('a stale calibration says nothing about a cuff reading she typed in', () {
      // There is no offset behind a tonometer to expire. Gating it would delete
      // the one blood pressure this product is entitled to act on.
      expect(
        metricFreshness('systolic', const Duration(minutes: 1),
            source: ReadingSource.manual, bpCalibrationStale: true),
        MetricFreshness.current,
      );
    });

    test('the numbers are the constants that already exist, not fresh copies', () {
      // «A fourth copy of 8 is a fourth thing to drift.» The six-hour window is
      // latestTelemetryMaxAge itself, not a 6 written out again — so moving it
      // moves this ladder too.
      expect(metricFreshness('hr', latestTelemetryMaxAge),
          MetricFreshness.current);
      expect(metricFreshness('hr', latestTelemetryMaxAge + const Duration(seconds: 1)),
          MetricFreshness.aging);
      // Four hours is ACOG's repeat-reading interval, cited in
      // emergency_confirmation.dart.
      expect(bpRepeatInterval, const Duration(hours: 4));
    });

    test('a timestamp from the future is not treated as ancient', () {
      expect(metricFreshness('hr', const Duration(hours: -3)),
          MetricFreshness.current);
    });
  });

  // ---------------------------------------------------------------------------
  // The pool a reassurance may be computed from
  // ---------------------------------------------------------------------------
  group('currentReadingsOnly', () {
    test('drops a stale metric whole and keeps a fresh one', () {
      final samples = [
        HealthSample(
            at: now.subtract(const Duration(hours: 9)),
            coreTemp: 36.9,
            heartRate: 70),
        HealthSample(at: now.subtract(const Duration(minutes: 2)), heartRate: 74),
      ];
      final pool = currentReadingsOnly(samples, now: now);
      expect(buildSeries(pool, 'temp'), isEmpty);
      // The heart rate in the SAME nine-hour-old sample survives, because it is
      // the metric's own newest reading that decides — and hr's newest is two
      // minutes old.
      expect(buildSeries(pool, 'hr').length, 2);
    });

    test('a sample left carrying nothing is dropped, not kept as an empty shell',
        () {
      // The worst outcome available here: three empty shells clear
      // generateAdvisories' minSamples gate, no series is found in any of them,
      // and the fall-through reassures from no readings at all.
      final samples = [
        for (var i = 0; i < 4; i++)
          HealthSample(
              at: now.subtract(Duration(hours: 30 + i)),
              heartRate: 72,
              spo2: 98),
      ];
      expect(currentReadingsOnly(samples, now: now), isEmpty);
    });

    test('everything current is returned untouched', () {
      final samples = [
        for (var i = 0; i < 3; i++)
          HealthSample(at: now.subtract(Duration(minutes: i)), heartRate: 72),
      ];
      expect(currentReadingsOnly(samples, now: now), same(samples));
    });
  });

  // ---------------------------------------------------------------------------
  // The absorbers
  // ---------------------------------------------------------------------------
  group('a reassurance claims no more than the readings behind it', () {
    List<HealthSample> quietDay(Duration ago) => [
          for (var i = 0; i < 4; i++)
            HealthSample(
                at: now.subtract(ago + Duration(minutes: i)),
                heartRate: 72,
                spo2: 98,
                source: ReadingSource.sensor),
        ];

    test('current readings still earn the sentence', () {
      final codes = currentAdvisories(quietDay(const Duration(minutes: 5)),
              now: now)
          .map((a) => a.code);
      expect(codes, contains('ADV_NOTHING_UNUSUAL'));
    });

    test('old readings do not — and what is said instead is true', () {
      final codes =
          currentAdvisories(quietDay(const Duration(hours: 30)), now: now)
              .map((a) => a.code)
              .toList();
      expect(codes, isNot(contains('ADV_NOTHING_UNUSUAL')));
      // This used to fall through to ADV_GATHERING — «Собираем данные» —
      // accepted at the time as approved copy that claims nothing. It claims
      // something, and the something is false: nothing is being gathered, the
      // readings exist and are out of date. A woman whose band is in a drawer
      // reads it as "the app is on it", which is the same false reassurance as
      // a promise to warn her.
      expect(codes, ['ADV_NO_CURRENT_READINGS']);
    });

    test('no readings at all is still ADV_GATHERING', () {
      // The distinction the new code exists to make. Nothing to be stale, so
      // «Свежих измерений нет» would be its own kind of untrue.
      expect(currentAdvisories(const [], now: now).map((a) => a.code),
          ['ADV_GATHERING']);
      expect(
          currentAdvisories([HealthSample(at: now, heartRate: 72)], now: now)
              .map((a) => a.code),
          ['ADV_GATHERING'],
          reason: 'one fresh reading is too few to say anything, and it is not '
              'stale');
    });

    test('a WARNING is never gated on age', () {
      // The corollary, and the costs are not symmetric: a missed warning is a
      // woman at home with preeclampsia.
      final rising = [
        for (var i = 0; i < 6; i++)
          HealthSample(
              at: now.subtract(
                  const Duration(hours: 40) - Duration(minutes: i * 5)),
              heartRate: i < 3 ? 70 : 92,
              source: ReadingSource.sensor),
      ];
      final codes = currentAdvisories(rising, now: now).map((a) => a.code);
      expect(codes, contains('ADV_HR_RISING'));
      // …and the reassurance does not ride along under it.
      expect(codes, isNot(contains('ADV_NOTHING_UNUSUAL')));
      expect(codes, isNot(contains('ADV_GATHERING')));
    });
  });

  // ---------------------------------------------------------------------------
  // On the screen
  // ---------------------------------------------------------------------------
  group('the tile states the age of the reading it is showing', () {
    /// The backlog item's own scenario: a nine-hour-old temperature under a
    /// stream of frames that carry everything except one.
    final watchDay = <HealthSample>[
      HealthSample(
          at: now.subtract(const Duration(hours: 9)),
          heartRate: 70,
          spo2: 98,
          coreTemp: 36.9,
          source: ReadingSource.sensor),
      for (var i = 4; i >= 0; i--)
        HealthSample(
            at: now.subtract(Duration(minutes: i * 2)),
            heartRate: 74,
            spo2: 98,
            source: ReadingSource.sensor),
    ];

    testWidgets('nine hours over the temperature, just now over the pulse',
        (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_dashboard(watchDay, now));
      await tester.pumpAndSettle();

      // Said in the announcement as well as painted: `db_outside_range` is this
      // file's own precedent for a claim that outlived the paint.
      expect(_labels(tester), contains('Temperature: 36.9 °C, 9 h ago'));
      expect(_labels(tester), contains('Heart rate: 74 bpm, just now'));
      // And drawn, where she reads it.
      expect(find.text('9 h ago'), findsOneWidget);
    });

    testWidgets('the group line under-states rather than over-states',
        (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_dashboard(watchDay, now));
      await tester.pumpAndSettle();
      // «Readings: 9 h ago», not «just now». An aggregate may claim no more
      // than the readings behind it, and this line stands over four of them.
      expect(find.text(_en.t('db_vitals_as_of', {'when': '9 h ago'})),
          findsOneWidget);
      expect(find.text(_en.t('db_vitals_as_of', {'when': 'just now'})),
          findsNothing);
    });

    testWidgets('the age travels with the tap into the detail screen',
        (tester) async {
      // Pushed route, in Russian: the scope sits above MaterialApp, so this
      // also catches the L10nScope-at-`home:` trap, where a pushed screen falls
      // back to English silently. «Показания» never travelled with the tap —
      // the detail screen showed a 44px number with no time on it at all.
      tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_dashboard(watchDay, now, locale: AppLocale.ru));
      await tester.pumpAndSettle();
      const ru = L10n(AppLocale.ru);
      await tester.tap(find.text('36.9'));
      await tester.pumpAndSettle();
      expect(find.text(ru.metricLabel('temp')), findsWidgets);
      expect(find.text(ru.t('ago_hour', {'n': 9})), findsOneWidget);
    });

    testWidgets('every language gets the age, not only Russian', (tester) async {
      for (final locale in AppLocale.values) {
        tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final l = L10n(locale);
        await tester.pumpWidget(_dashboard(watchDay, now, locale: locale));
        await tester.pumpAndSettle();
        expect(find.text(l.t('ago_hour', {'n': 9})), findsWidgets,
            reason: 'no per-metric age in ${locale.name}');
      }
    });
  });

  group('an old reading is not drawn as a current one', () {
    List<HealthSample> bpDay(Duration ago, ReadingSource source) => [
          for (var i = 0; i < 3; i++)
            HealthSample(
                at: now.subtract(ago + Duration(minutes: i)),
                systolic: 150,
                diastolic: 96,
                source: source),
        ];

    Future<void> pump(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(w);
      await tester.pumpAndSettle();
    }

    testWidgets('a thirteen-hour-old 150/96 is greyed, with its age',
        (tester) async {
      // «The panel dims only past 48 h, so a stale preeclampsia-range reading
      // is drawn at full strength for forty-two hours.»
      await pump(
          tester,
          _dashboard(bpDay(const Duration(hours: 13), ReadingSource.manual), now,
              bpCalibrationStale: false));
      expect(
          _labels(tester),
          isNot(contains(
              'Blood pressure: 150 / 96 mmHg, outside the safe range, 13 h ago')));
      expect(_labels(tester),
          contains('Blood pressure: 150 / 96 mmHg, 13 h ago'));
      final sys = tester.widget<Text>(find.text('150'));
      expect(sys.style?.color, Palette.textDim);
    });

    testWidgets('the same reading four hours old keeps its red', (tester) async {
      await pump(
          tester,
          _dashboard(bpDay(const Duration(hours: 4), ReadingSource.manual), now,
              bpCalibrationStale: false));
      expect(
          _labels(tester),
          contains(
              'Blood pressure: 150 / 96 mmHg, outside the safe range, 4 h ago'));
      final sys = tester.widget<Text>(find.text('150'));
      expect(sys.style?.color, Palette.danger);
    });

    testWidgets('a wrist reading with an expired calibration is never current',
        (tester) async {
      // Taken one minute ago. The second condition on the blood-pressure row:
      // the offset behind the estimate expired at bpCalibrationMaxAgeDays, so
      // the number it produced is not a current claim at any age.
      await pump(
          tester,
          _dashboard(
              bpDay(const Duration(minutes: 1), ReadingSource.sensor), now,
              bpCalibrationStale: true));
      final sys = tester.widget<Text>(find.text('150'));
      expect(sys.style?.color, Palette.textDim);
    });

    testWidgets('a cuff reading is not punished for a calibration it never had',
        (tester) async {
      await pump(
          tester,
          _dashboard(
              bpDay(const Duration(minutes: 1), ReadingSource.manual), now,
              bpCalibrationStale: true));
      final sys = tester.widget<Text>(find.text('150'));
      expect(sys.style?.color, Palette.danger);
    });
  });

  group('the ring', () {
    double? ringFraction(WidgetTester tester) =>
        tester.widget<MetricRing>(find.byType(MetricRing).first).fraction;

    Future<void> pump(WidgetTester tester, List<HealthSample> samples) async {
      tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_dashboard(samples, now));
      await tester.pumpAndSettle();
    }

    testWidgets('a healthy reading that is old is not counted as healthy',
        (tester) async {
      await pump(tester, [
        for (var i = 0; i < 4; i++)
          HealthSample(
              at: now.subtract(Duration(hours: 30, minutes: i)),
              heartRate: 72,
              spo2: 98,
              source: ReadingSource.sensor),
      ]);
      // Null, not 1.0 — a shape cannot be qualified, and a complete ring is the
      // most confident register this screen has.
      expect(ringFraction(tester), isNull);
      expect(find.text(_en.t('db_ring_ungraded')), findsOneWidget);
    });

    testWidgets('an old reading in the danger band still pulls it down',
        (tester) async {
      // THE ARITHMETIC TRAP. Dropping the stale 150/96 from the numerator AND
      // the denominator would turn 1-of-2 into a complete green ring: a
      // reassurance arriving by arithmetic, off the very reading that is not
      // fine.
      await pump(tester, [
        for (var i = 0; i < 3; i++)
          HealthSample(
              at: now.subtract(Duration(hours: 30, minutes: i)),
              systolic: 150,
              diastolic: 96,
              source: ReadingSource.manual),
        for (var i = 0; i < 3; i++)
          HealthSample(
              at: now.subtract(Duration(minutes: i)),
              heartRate: 72,
              source: ReadingSource.manual),
      ]);
      final f = ringFraction(tester);
      expect(f, isNotNull);
      expect(f, lessThan(1.0));
    });
  });

  group('the banner and the clipboard', () {
    List<HealthSample> quietDay(Duration ago) => [
          for (var i = 0; i < 4; i++)
            HealthSample(
                at: now.subtract(ago + Duration(minutes: i)),
                heartRate: 72,
                spo2: 98,
                source: ReadingSource.sensor),
          ];

    testWidgets('«nothing unusual» does not render over old readings',
        (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_dashboard(quietDay(const Duration(hours: 30)), now));
      await tester.pumpAndSettle();
      expect(find.text(_en.t('ADV_NOTHING_UNUSUAL')), findsNothing);
      expect(find.text(_en.t('ADV_NO_CURRENT_READINGS')), findsOneWidget);
      // «Not many readings yet» would be false: she has four of them.
      expect(find.text(_en.t('ADV_GATHERING')), findsNothing);
    });

    testWidgets('and does render over current ones', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_dashboard(quietDay(const Duration(minutes: 5)), now));
      await tester.pumpAndSettle();
      expect(find.text(_en.t('ADV_NOTHING_UNUSUAL')), findsOneWidget);
    });

    testWidgets('nor on the advisor screen, which is the third absorber',
        (tester) async {
      // «What else on this product can say she is fine?» Gating the banner and
      // the clipboard and leaving this one would put the removed reassurance
      // one tap away, on the screen someone opens to ask exactly that.
      tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      for (final (ago, present) in [
        (const Duration(hours: 30), false),
        (const Duration(minutes: 5), true),
      ]) {
        await tester.pumpWidget(L10nScope(
          l10n: _en,
          child: MaterialApp(
              key: UniqueKey(),
              home: AdvisorScreen(samples: quietDay(ago), now: now)),
        ));
        await tester.pumpAndSettle();
        expect(find.text(_en.t('ADV_NOTHING_UNUSUAL')),
            present ? findsOneWidget : findsNothing,
            reason: 'readings $ago old');
      }
    });

    test('the copied summary carries a per-metric age on every row', () {
      final samples = [
        HealthSample(
            at: now.subtract(const Duration(hours: 9)),
            coreTemp: 36.9,
            source: ReadingSource.sensor),
        for (var i = 0; i < 3; i++)
          HealthSample(
              at: now.subtract(Duration(minutes: i)),
              heartRate: 74,
              source: ReadingSource.sensor),
      ];
      final text = buildHealthSummary(_en, samples, now: now);
      expect(text, contains('74 bpm (just now)'));
      expect(text, contains('36.9 °C (9 h ago)'));
    });

    test('and no reassurance travels out of the app from old readings', () {
      // The export sends advisory TITLES only, so this sentence arrives with no
      // body text, no numbers and none of the ages above it.
      final old = buildHealthSummary(_en, quietDay(const Duration(hours: 30)),
          now: now);
      expect(old, isNot(contains(_en.t('ADV_NOTHING_UNUSUAL'))));
      final fresh = buildHealthSummary(_en, quietDay(const Duration(minutes: 5)),
          now: now);
      expect(fresh, contains(_en.t('ADV_NOTHING_UNUSUAL')));
    });
  });
}

/// Every non-empty semantics label in the rendered tree — what a screen reader
/// would have to announce. Read off the widgets rather than through
/// `find.bySemanticsLabel`, which compares whole merged nodes.
Iterable<String> _labels(WidgetTester tester) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .map((w) => w.properties.label ?? '')
    .where((s) => s.isNotEmpty);

/// The rendered dashboard, with the scope ABOVE MaterialApp so a pushed route
/// keeps its language.
Widget _dashboard(List<HealthSample> samples, DateTime now,
        {bool bpCalibrationStale = true, AppLocale locale = AppLocale.en}) =>
    L10nScope(
      l10n: L10n(locale),
      child: MaterialApp(
        theme: FcsTheme.light(locale),
        home: HealthDashboardView(
          samples: samples,
          nowForAppointment: now,
          bpCalibrationStale: bpCalibrationStale,
        ),
      ),
    );
