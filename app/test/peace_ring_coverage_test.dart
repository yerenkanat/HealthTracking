/// TODO §2.2 — the peace ring on a day it cannot grade, and on a day it can
/// only grade SOME of.
///
/// The reported half was `withData == 0 ? 1.0`: a complete, reassuring circle
/// produced by the absence of data. That was fixed before this file existed —
/// the fraction is nullable, null draws no arc, and a sentence explains it.
///
/// The half that was still live is the same defect one step milder and shipped
/// far more often. `healthy / withData` counted only the cards that survived
/// the provenance and freshness gates, and the ones that did not survive left
/// the numerator and the denominator TOGETHER. A band-only day can grade two
/// cards of four — a wrist temperature and a wrist blood pressure may not be
/// graded at all — so the everyday state of this product drew the closed green
/// circle of a day on which everything was checked and everything was fine.
/// `goldens/home_dashboard.png` was a photograph of exactly that.
///
/// What the ring draws now, ruled here and in domain/peace_ring.dart:
///
///  · the arc spans the ASSESSED share of the circle, never the whole of it;
///  · the rest is dashed body ink — «not assessed», the tiles' own
///    `MetricStatus.ungraded` treatment, which is deliberately neither the
///    healthy accent nor the dim ink that means stale;
///  · a closed circle therefore means all four cards assessed and all four
///    healthy, which is what a closed circle looks like it means;
///  · and it is said in words, in the paint AND in the semantics tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/peace_ring.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/widgets/glass.dart';

const _en = L10n(AppLocale.en);

void main() {
  final now = DateTime(2026, 8, 14, 18);

  /// The ordinary day of a woman wearing the band: heart rate, SpO2 and a
  /// wrist temperature, all minutes old, nothing wrong with any of them.
  List<HealthSample> bandDay() => [
        for (var i = 0; i < 4; i++)
          HealthSample(
              at: now.subtract(Duration(minutes: i * 2)),
              heartRate: 72,
              spo2: 98,
              coreTemp: 36.6,
              source: ReadingSource.sensor),
      ];

  group('the pool the fraction is over is stated, not thinned', () {
    test('a band day grades two cards of four and says so', () {
      final r = gradePeaceRing(bandDay(), now: now, bpCalibrationStale: false);
      expect(r.cards[RingCard.hr], RingGrade.healthy);
      expect(r.cards[RingCard.spo2], RingGrade.healthy);
      // The reading is there and carries no verdict — not «fine», not «old».
      expect(r.cards[RingCard.temp], RingGrade.ungraded);
      // No reading at all, which is a different absence and a different grade.
      expect(r.cards[RingCard.bp], RingGrade.missing);

      expect(r.assessed, 2);
      expect(r.total, 4);
      // The verdict over what was assessed is still «all of it is healthy» —
      // that is true and she has earned it.
      expect(r.fraction, 1.0);
      // What is new is that the ring may not draw it as a whole circle.
      expect(r.complete, isFalse);
      expect(r.partial, isTrue);
      expect(r.assessedShare, 0.5);
    });

    test('a cuff, a thermometer and a band close the circle', () {
      // The over-correction guard. None of this may be achieved by making the
      // ring impossible to fill: a woman who typed in a cuff reading and a
      // thermometer reading has FOUR assessed cards, and the closed circle is
      // hers.
      final r = gradePeaceRing([
        for (var i = 0; i < 4; i++)
          HealthSample(
              at: now.subtract(Duration(minutes: i * 2)),
              heartRate: 72,
              spo2: 98,
              coreTemp: 36.6,
              systolic: 118,
              diastolic: 76,
              source: ReadingSource.manual),
      ], now: now, bpCalibrationStale: false);
      expect(r.assessed, 4);
      expect(r.fraction, 1.0);
      expect(r.complete, isTrue);
      expect(r.assessedShare, 1.0);
    });

    test('blood pressure is ONE card, not two fifths of the ring', () {
      // `metricKeys` carries systolic and diastolic separately, so a cuff day
      // used to be 3 entries of which 2 were one instrument. The grid draws one
      // card, the copy says «of 4», and a denominator the reader cannot check
      // by counting her own screen is a number she has no way to catch.
      expect(RingCard.values.length, 4);
      expect(RingCard.bp.metrics, ['systolic', 'diastolic']);
    });

    test('nothing assessed is null, and it is not zero', () {
      // 0.0 is «every card was assessed and every card is concerning». Null is
      // «nothing was assessed». They are different days and they may not share
      // a number.
      final stale = gradePeaceRing([
        for (var i = 0; i < 4; i++)
          HealthSample(
              at: now.subtract(Duration(hours: 30, minutes: i)),
              heartRate: 72,
              spo2: 98,
              source: ReadingSource.sensor),
      ], now: now, bpCalibrationStale: false);
      expect(stale.assessed, 0);
      expect(stale.fraction, isNull);
      expect(stale.assessedShare, 0.0);
      expect(stale.anyReading, isTrue, reason: 'she has readings; they are old');
      expect(stale.partial, isFalse, reason: 'nothing was assessed at all');
    });

    test('a danger still pulls the ring down from any source and any age', () {
      // The asymmetry, restated where it can regress: the gates above may only
      // ever refuse a POSITIVE claim.
      final r = gradePeaceRing([
        for (var i = 0; i < 4; i++)
          HealthSample(
              at: now.subtract(Duration(hours: 30, minutes: i)),
              systolic: 165,
              diastolic: 112,
              source: ReadingSource.sensor),
        for (var i = 0; i < 4; i++)
          HealthSample(
              at: now.subtract(Duration(minutes: i)),
              heartRate: 72,
              source: ReadingSource.sensor),
      ], now: now, bpCalibrationStale: true);
      expect(r.cards[RingCard.bp], RingGrade.concerning);
      expect(r.cards[RingCard.hr], RingGrade.healthy);
      expect(r.fraction, 0.5);
      expect(r.complete, isFalse);
    });
  });

  group('the shape carries the coverage, because a shape cannot be qualified',
      () {
    testWidgets('a partial pool cannot close the circle', (tester) async {
      // The paint, not the argument: the accent is drawn over the assessed
      // share and the rest is a run of dashes, so the display list holds many
      // arcs where a complete day holds one.
      await tester.pumpWidget(const MaterialApp(
        home: Center(
          child: MetricRing(
              fraction: 1.0, assessed: 0.5, color: Palette.good, size: 74, stroke: 8),
        ),
      ));
      expect(
          find.byType(MetricRing),
          paints
            ..arc()
            ..arc()
            ..arc(),
          reason: 'the not-assessed half is drawn, not left out of the sum');
    });

    testWidgets('a complete pool still draws one clean arc', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(
          child: MetricRing(
              fraction: 1.0, assessed: 1.0, color: Palette.good, size: 74, stroke: 8),
        ),
      ));
      expect(
          find.byType(MetricRing),
          isNot(paints
            ..arc()
            ..arc()),
          reason: 'a day with everything assessed has nothing to dash');
    });

    testWidgets('nothing assessed does not look like everything concerning',
        (tester) async {
      // Before this, both drew the bare track and differed only by the colour
      // of the badge in the middle — so «I could check nothing» and «I checked
      // everything and it is bad» were the same picture.
      await tester.pumpWidget(const MaterialApp(
        home: Column(children: [
          MetricRing(
              key: Key('nothing'),
              fraction: null,
              assessed: 0.0,
              color: Palette.textDim,
              size: 74,
              stroke: 8),
          MetricRing(
              key: Key('allbad'),
              fraction: 0.0,
              assessed: 1.0,
              color: Palette.amber,
              size: 74,
              stroke: 8),
        ]),
      ));
      // The dashes are a run of arcs; the concerning day is the single accent
      // arc it always was (of zero length, at zero healthy).
      expect(find.byKey(const Key('nothing')), paints..arc()..arc()..arc());
      expect(find.byKey(const Key('allbad')), isNot(paints..arc()..arc()));
    });

    testWidgets('the rings that are not health verdicts are untouched',
        (tester) async {
      // The water goal and the kick count have one denominator and it is never
      // in doubt. `assessed` is null for them and the paint is what it was.
      await tester.pumpWidget(const MaterialApp(
        home: Center(
          child: MetricRing(fraction: 0.5, color: Palette.blue, size: 74, stroke: 8),
        ),
      ));
      final ring = tester.widget<MetricRing>(find.byType(MetricRing));
      expect(ring.assessed, isNull);
      expect(find.byType(MetricRing), isNot(paints..arc()..arc()));
    });
  });

  group('and it is said in words', () {
    Widget dashboard(List<HealthSample> samples, {AppLocale locale = AppLocale.en}) =>
        L10nScope(
          l10n: L10n(locale),
          child: MaterialApp(
            theme: FcsTheme.light(locale),
            home: HealthDashboardView(
              samples: samples,
              nowForAppointment: now,
              bpCalibrationStale: false,
            ),
          ),
        );

    Future<void> pump(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(w);
      await tester.pumpAndSettle();
    }

    testWidgets('the everyday band day is partial, and says so', (tester) async {
      await pump(tester, dashboard(bandDay()));
      final ring = tester.widget<MetricRing>(find.byType(MetricRing).first);
      expect(ring.fraction, 1.0);
      expect(ring.assessed, 0.5,
          reason: 'two cards of four — the arc may not reach the top again');
      final partial = _en.t('db_ring_partial', {'n': 2, 'total': 4});
      expect(find.text(partial), findsOneWidget);
      // In the announcement as well as in the paint: `db_outside_range` is this
      // screen's own precedent for a claim that outlived the picture.
      expect(
          tester
              .widgetList<Semantics>(find.byType(Semantics))
              .map((s) => s.properties.label)
              .whereType<String>(),
          contains(partial));
    });

    testWidgets('a complete day says nothing extra', (tester) async {
      await pump(
          tester,
          dashboard([
            for (var i = 0; i < 4; i++)
              HealthSample(
                  at: now.subtract(Duration(minutes: i * 2)),
                  heartRate: 72,
                  spo2: 98,
                  coreTemp: 36.6,
                  systolic: 118,
                  diastolic: 76,
                  source: ReadingSource.manual),
          ]));
      final ring = tester.widget<MetricRing>(find.byType(MetricRing).first);
      expect(ring.assessed, 1.0);
      expect(find.textContaining('of 4'), findsNothing);
      expect(find.text(_en.t('db_ring_ungraded')), findsNothing);
    });

    testWidgets('the two absences never explain each other twice',
        (tester) async {
      // Nothing assessed keeps the sentence it already had, and does NOT also
      // get the partial one: «not everything was counted» is false when nothing
      // was.
      await pump(
          tester,
          dashboard([
            for (var i = 0; i < 4; i++)
              HealthSample(
                  at: now.subtract(Duration(hours: 30, minutes: i)),
                  heartRate: 72,
                  spo2: 98,
                  source: ReadingSource.sensor),
          ]));
      expect(find.text(_en.t('db_ring_ungraded')), findsOneWidget);
      expect(find.textContaining('of 4'), findsNothing);
    });

    test('the sentence exists in all three languages and invents nothing', () {
      for (final loc in AppLocale.values) {
        final s = L10n(loc).t('db_ring_partial', {'n': 2, 'total': 4});
        expect(s, contains('2'));
        expect(s, contains('4'));
        expect(s, isNot(contains('{')), reason: '$loc left a placeholder');
      }
      // kk is a translation, never a copy of the ru — the guard verify_l10n
      // applies to the whole table, restated here because this string was
      // written by a designer and goes to the language gate.
      expect(const L10n(AppLocale.kk).t('db_ring_partial'),
          isNot(const L10n(AppLocale.ru).t('db_ring_partial')));
      // Neither an alarm nor a reassurance: it may not tell her she is fine,
      // and it may not tell her something is wrong.
      for (final loc in AppLocale.values) {
        final s = L10n(loc).t('db_ring_partial').toLowerCase();
        for (final refused in const [
          'норм', 'в порядке', 'стабильн', 'fine', 'normal', 'stable',
          'опасн', 'срочно', 'тревог', 'danger', 'urgent',
        ]) {
          expect(s, isNot(contains(refused)), reason: '$loc says «$refused»');
        }
      }
    });
  });
}
