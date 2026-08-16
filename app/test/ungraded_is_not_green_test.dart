/// Green is a claim, and an ungraded reading was being painted in it.
///
/// Three rulings, closed together on 2026-08-17 because the absorber rule makes
/// them one commit (docs/CLINICAL-REVIEW-WATCH.md).
///
/// 1. THE COLOUR OUTLIVED THE GRADE. The device-temperature verdict removed the
///    grade from a wrist estimate by answering `MetricStatus.normal` — on the
///    reasoning, written into `metricStatus` itself, that normal renders as
///    "plain ink, no raised step, no suffix". Two of those three held.
///    `_statusColor(MetricStatus.normal)` returned the palette's teal, so a
///    device temperature went on being drawn in the same green as a healthy
///    heart rate. An ungraded reading now renders in `Palette.text` — ordinary
///    body ink, and deliberately NOT `Palette.textDim`, which is the STALE
///    appearance and would say "old" about a reading two minutes fresh.
///
/// 2. THE DEVICE-BP TILE WAS REFUSED SENTENCE #23, SHIPPING. It called
///    `metricStatus('systolic', …)` with no source at all, and `metricStatus`
///    had no provenance branch for either half — so a fresh, CALIBRATED wrist
///    118/76 was drawn in mint. The ring beside it has had the rule since
///    2026-08-14 and is the model: a device BP may pull the grade DOWN and
///    never up.
///
/// 3. `ADV_GATHERING_b` WAS A BAND UPSELL shown to a woman who types her
///    readings by hand — «Наденьте браслет — советы появятся…». The dashboard's
///    empty state had this exact sentence family removed for exactly this
///    reason; the advisory was the surviving instance. And a new code for the
///    case «Собираем данные» could not describe honestly: readings exist, and
///    not one of them is current.
///
/// The two traps the gate named in advance are pinned here rather than
/// rediscovered: `worstStatus` cannot express "an ungraded half makes the pair
/// ungraded" by enum index, and the source-passing scan test only enforced its
/// rule where the metric could be temperature — which is why it never saw the
/// blood-pressure card. That second one lives in `device_temperature_test.dart`,
/// beside the scan it fixes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/domain/current_advisories.dart';
import 'package:fcs_app/domain/health_advisor.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/advisor/advisor_screen.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/dashboard/health_summary.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/design_system.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/widgets/glass.dart';

const _en = L10n(AppLocale.en);
const _ru = L10n(AppLocale.ru);
const _kk = L10n(AppLocale.kk);

final _now = DateTime(2026, 8, 17, 12);

/// Four readings a couple of minutes apart — current on every metric's ladder,
/// so nothing below can be explained away as staleness.
List<HealthSample> _fresh({
  required ReadingSource source,
  double? hr,
  double? spo2,
  double? sys,
  double? dia,
  double? temp,
}) =>
    [
      for (var i = 3; i >= 0; i--)
        HealthSample(
          at: _now.subtract(Duration(minutes: i * 2)),
          heartRate: hr,
          spo2: spo2,
          systolic: sys,
          diastolic: dia,
          coreTemp: temp,
          source: source,
        ),
    ];

/// The dashboard, with the scope ABOVE MaterialApp so a pushed route keeps its
/// language, and with the calibration stated: a device blood pressure whose
/// calibration is stale is not current at any age, and the whole point of the
/// tile below is a reading that IS current and still may not be graded.
Widget _dashboard(List<HealthSample> samples, {bool bpCalibrationStale = false}) =>
    L10nScope(
      l10n: _en,
      child: MaterialApp(
        theme: FcsTheme.light(AppLocale.en),
        home: HealthDashboardView(
          samples: samples,
          nowForAppointment: _now,
          bpCalibrationStale: bpCalibrationStale,
        ),
      ),
    );

/// The colour the big value on a tile is painted in.
Color _inkOf(WidgetTester tester, String value) {
  final texts = tester.widgetList<Text>(find.text(value)).toList();
  expect(texts, isNotEmpty, reason: '«$value» is not on the screen at all');
  // The reading is the one drawn in the monospace face; the same digits can
  // appear in a label or a stat row.
  final reading = texts.firstWhere(
      (t) => t.style?.fontFamily == 'JetBrainsMono',
      orElse: () => throw StateError('«$value» is not drawn as a reading'));
  return reading.style!.color!;
}

Iterable<String> _labels(WidgetTester tester) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .map((w) => w.properties.label ?? '')
    .where((s) => s.isNotEmpty);

/// The card a given reading sits on, so its raised step can be read.
bool _raisedAround(WidgetTester tester, String value) => tester
    .widget<DsCard>(
        find.ancestor(of: find.text(value), matching: find.byType(DsCard)).first)
    .raised;

void main() {
  // A wide, tall surface: the grid must lay out without the tiles being
  // clipped out of the tree.
  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  group('an ungraded reading is drawn in ordinary ink', () {
    testWidgets('a device temperature is not green', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(_dashboard(
          _fresh(source: ReadingSource.sensor, temp: 36.6, hr: 72)));
      await tester.pumpAndSettle();
      final ink = _inkOf(tester, '36.6');
      expect(ink, Palette.text);
      expect(ink, isNot(Palette.teal),
          reason: 'the grade was removed in 2026-08-13 and the colour survived it');
      expect(ink, isNot(Palette.textDim),
          reason: 'dim ink means STALE, and this reading is two minutes old');
    });

    testWidgets('a thermometer reading of the same value still is', (tester) async {
      // The over-correction guard. A reading she took with an instrument and
      // typed in is a different evidential object and keeps its grade.
      bigScreen(tester);
      await tester.pumpWidget(_dashboard(
          _fresh(source: ReadingSource.manual, temp: 36.6, hr: 72)));
      await tester.pumpAndSettle();
      expect(_inkOf(tester, '36.6'), Palette.teal);
    });

    testWidgets('a wrist heart rate is still green — it is graded', (tester) async {
      // Green survives where the grade is real: a current reading, on a cited
      // band, from a source the product may reassure from.
      bigScreen(tester);
      await tester.pumpWidget(
          _dashboard(_fresh(source: ReadingSource.sensor, hr: 72, spo2: 98)));
      await tester.pumpAndSettle();
      expect(_inkOf(tester, '72'), Palette.teal);
      expect(_inkOf(tester, '98'), Palette.teal);
    });
  });

  group('the device blood-pressure tile — refused sentence #23', () {
    testWidgets('a fresh, calibrated wrist 118/76 is not mint', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(_dashboard(
          _fresh(source: ReadingSource.sensor, sys: 118, dia: 76, hr: 72)));
      await tester.pumpAndSettle();
      for (final v in const ['118', '76']) {
        expect(_inkOf(tester, v), Palette.text, reason: v);
        expect(_inkOf(tester, v), isNot(Palette.teal), reason: v);
        expect(_inkOf(tester, v), isNot(Palette.textDim),
            reason: '$v is four minutes old and the calibration is good');
      }
    });

    testWidgets('no raised step and no out-of-range announcement with it',
        (tester) async {
      // The rest of the ungraded rendering: a step means "this one wants your
      // attention", and `db_outside_range` is the same claim said out loud to
      // someone who cannot see the colour.
      bigScreen(tester);
      await tester.pumpWidget(_dashboard(
          _fresh(source: ReadingSource.sensor, sys: 118, dia: 76, hr: 72)));
      await tester.pumpAndSettle();
      expect(_raisedAround(tester, '118'), isFalse);
      expect(_labels(tester).where((s) => s.contains('118')), isNotEmpty,
          reason: 'the reading is still announced — it is the claim about it '
              'that goes');
      expect(
          _labels(tester)
              .where((s) => s.contains('118') && s.contains('outside the safe range')),
          isEmpty);
    });

    testWidgets('a cuff 118/76 keeps its green', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(_dashboard(
          _fresh(source: ReadingSource.manual, sys: 118, dia: 76, hr: 72)));
      await tester.pumpAndSettle();
      expect(_inkOf(tester, '118'), Palette.teal);
      expect(_inkOf(tester, '76'), Palette.teal);
    });

    testWidgets('a wrist 165/112 is still red, and still raised', (tester) async {
      // The asymmetry is the ruling: the product escalates a device BP at
      // 140/90, so the estimate may pull the tile DOWN. Gating it symmetrically
      // would remove a warning, which the absorber corollary forbids.
      bigScreen(tester);
      await tester.pumpWidget(_dashboard(
          _fresh(source: ReadingSource.sensor, sys: 165, dia: 112, hr: 72)));
      await tester.pumpAndSettle();
      expect(_inkOf(tester, '165'), Palette.danger);
      expect(_raisedAround(tester, '165'), isTrue);
      expect(
          _labels(tester)
              .where((s) => s.contains('165') && s.contains('outside the safe range')),
          isNotEmpty);
    });

    test('a mixed pair goes ungraded whole, and a warning still carries it', () {
      // The trap the gate named: `worstStatus` picks the max enum index, and no
      // declaration order can express "an ungraded half makes the pair
      // ungraded" on its own.
      final sys = metricStatus('systolic', 118, source: ReadingSource.manual);
      final dia = metricStatus('diastolic', 76, source: ReadingSource.sensor);
      expect(sys, MetricStatus.normal);
      expect(dia, MetricStatus.ungraded);
      expect(worstStatus([sys, dia]), isNot(MetricStatus.normal),
          reason: 'half a blood pressure is not a blood pressure');
      expect(
          worstStatus([
            metricStatus('systolic', 165, source: ReadingSource.sensor),
            metricStatus('diastolic', 76, source: ReadingSource.sensor),
          ]),
          MetricStatus.danger);
    });
  });

  group('the band upsell is gone from the advisory', () {
    test('ADV_GATHERING no longer sells a bracelet, in any language', () {
      // «Апселла браслета здесь нет» — the spec quoted at no_band_card.dart.
      // For most users the app without a band is the permanent state, not a
      // step towards buying one.
      const band = ['браслет', 'білезік', 'band', 'браслета', 'браслетті'];
      for (final locale in AppLocale.values) {
        final text = L10n(locale).t('ADV_GATHERING_b').toLowerCase();
        for (final w in band) {
          expect(text, isNot(contains(w)),
              reason: 'ADV_GATHERING_b (${locale.name}) still sells a band');
        }
      }
    });

    test('and it does not promise that advice will arrive', () {
      // Refused sentence #12's family: a promise of future advice turns every
      // gap in coverage into an implied all-clear once she has the hardware.
      const promises = [
        'появятся', 'пайда болады', 'will appear', 'appears after',
        'предупредит', 'ескертеді', 'will warn', 'will alert',
      ];
      for (final locale in AppLocale.values) {
        for (final key in const ['ADV_GATHERING', 'ADV_GATHERING_b',
          'ADV_NO_CURRENT_READINGS', 'ADV_NO_CURRENT_READINGS_b']) {
          final text = L10n(locale).t(key).toLowerCase();
          for (final p in promises) {
            expect(text, isNot(contains(p)), reason: '$key (${locale.name})');
          }
        }
      }
    });

    test('the new card exists in all three languages and invents no number', () {
      for (final locale in AppLocale.values) {
        for (final key in const [
          'ADV_NO_CURRENT_READINGS',
          'ADV_NO_CURRENT_READINGS_b'
        ]) {
          final text = L10n(locale).t(key);
          expect(text, isNot(key), reason: '$key missing in ${locale.name}');
          for (final n in const ['37.8', '38.5', '135', '85', '140', '90']) {
            expect(text, isNot(contains(n)), reason: '$key (${locale.name})');
          }
        }
      }
    });

    test('the closing sentence is the counterweight, word for word', () {
      // Deliberately identical to ADV_NOTHING_UNUSUAL_b's, in all three
      // languages: it is what stops an absence-of-data card from reading as an
      // all-clear, and it is already through the gate. Do not paraphrase it.
      String tail(String s) => s.substring(s.lastIndexOf('. ') + 2);
      for (final l in const [_ru, _kk, _en]) {
        final counterweight = tail(l.t('ADV_NOTHING_UNUSUAL_b'));
        expect(counterweight.length, greaterThan(20));
        expect(l.t('ADV_NO_CURRENT_READINGS_b'), endsWith(counterweight));
        expect(l.t('ADV_GATHERING_b'), endsWith(counterweight));
      }
    });
  });

  group('«Собираем данные» is not said about readings that exist', () {
    List<HealthSample> quiet(Duration ago) => [
          for (var i = 0; i < 4; i++)
            HealthSample(
                at: _now.subtract(ago + Duration(minutes: i)),
                heartRate: 72,
                spo2: 98,
                source: ReadingSource.sensor),
        ];

    test('all-stale readings get the new code, not the gathering one', () {
      expect(
          currentAdvisories(quiet(const Duration(hours: 30)), now: _now)
              .map((a) => a.code),
          ['ADV_NO_CURRENT_READINGS']);
    });

    test('and it never prints underneath a warning', () {
      // THE ABSORBER DISCIPLINE, and the reason this had to land in the same
      // commit as the code itself: the fall-through set is what stops «Свежих
      // измерений нет» from travelling beside a finding computed from those
      // very readings. Warnings are computed from every reading whatever its
      // age, so this pairing is reachable.
      final rising = [
        for (var i = 0; i < 6; i++)
          HealthSample(
              at: _now.subtract(
                  const Duration(hours: 40) - Duration(minutes: i * 5)),
              heartRate: i < 3 ? 70 : 92,
              source: ReadingSource.sensor),
      ];
      final codes = currentAdvisories(rising, now: _now).map((a) => a.code);
      expect(codes, contains('ADV_HR_RISING'));
      expect(codes, isNot(contains('ADV_NO_CURRENT_READINGS')));
      expect(codes, isNot(contains('ADV_GATHERING')));
      expect(codes, isNot(contains('ADV_NOTHING_UNUSUAL')));
    });

    test('and it does not travel out of the app on the clipboard', () {
      // The export sends advisory TITLES only. «No recent readings» arriving in
      // somebody's chat, under a summary that does carry rows, explains
      // nothing and contradicts the rows above it.
      final text = buildHealthSummary(_en, quiet(const Duration(hours: 30)),
          now: _now);
      expect(text, isNot(contains(_en.t('ADV_NO_CURRENT_READINGS'))));
      expect(text, isNot(contains(_en.t('ADV_GATHERING'))));
      // …and the filter is the shared constant, so neither code can be added
      // to one surface and forgotten on the other.
      expect(noDataAdvisories,
          containsAll(<String>['ADV_GATHERING', 'ADV_NO_CURRENT_READINGS']));
    });
  });

  group('the info tone is neutral, and promises no arrival', () {
    List<HealthSample> stale() => [
          for (var i = 0; i < 4; i++)
            HealthSample(
                at: _now.subtract(Duration(hours: 30, minutes: i)),
                heartRate: 72,
                source: ReadingSource.sensor),
        ];

    testWidgets('the banner does not paint "nothing to report" in crimson',
        (tester) async {
      // `Palette.violet` is `Ds.coralCta` = #D6004A — a near-crimson, louder
      // than the app's actual warning amber — under an hourglass meaning
      // "coming". The calmest state the banner has was drawn in the loudest
      // colour it owns.
      bigScreen(tester);
      await tester.pumpWidget(_dashboard(stale()));
      await tester.pumpAndSettle();
      expect(find.text(_en.t('ADV_NO_CURRENT_READINGS')), findsOneWidget);
      // The disc behind the icon in the middle of the ring is where the tone
      // colour is actually painted — the glyph itself is white on top of it.
      final ring = tester.widget<MetricRing>(find.byType(MetricRing).first);
      final disc = (ring.center! as Container).decoration! as BoxDecoration;
      expect(disc.color, isNot(Ds.coralCta));
      expect(disc.color, Palette.textDim);
    });

    testWidgets('and does not draw it under an hourglass', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(_dashboard(stale()));
      await tester.pumpAndSettle();
      for (final icon in const [
        Icons.hourglass_bottom_rounded,
        Icons.hourglass_empty,
        Icons.hourglass_top_rounded,
        Icons.check_rounded,
        Icons.check_circle_outline,
        Icons.warning_amber_rounded,
      ]) {
        expect(find.byIcon(icon), findsNothing,
            reason: 'nothing is on its way, nothing is confirmed fine, and '
                'nothing is wrong that the app can see');
      }
    });

    testWidgets('the advisor screen agrees with the banner', (tester) async {
      // The third absorber. An icon fixed on the dashboard and left on the
      // screen someone opens to ask exactly this question is the partial fix
      // the absorber rule calls worse than none.
      bigScreen(tester);
      await tester.pumpWidget(L10nScope(
        l10n: _en,
        child: MaterialApp(
            theme: FcsTheme.light(AppLocale.en),
            home: AdvisorScreen(samples: stale(), now: _now)),
      ));
      await tester.pumpAndSettle();
      expect(find.text(_en.t('ADV_NO_CURRENT_READINGS')), findsOneWidget);
      expect(find.text(_en.t('ADV_NO_CURRENT_READINGS_b')), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_empty), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    });

    testWidgets('the gathering card keeps its hourglass — data really is coming',
        (tester) async {
      // The distinction is the point: with one fresh reading the app IS
      // waiting for more, so the icon that means "coming" is true there.
      bigScreen(tester);
      await tester.pumpWidget(L10nScope(
        l10n: _en,
        child: MaterialApp(
            theme: FcsTheme.light(AppLocale.en),
            home: AdvisorScreen(
                samples: [HealthSample(at: _now, heartRate: 72)], now: _now)),
      ));
      await tester.pumpAndSettle();
      expect(find.text(_en.t('ADV_GATHERING')), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
    });

    test('the tone itself is still info, so nothing here raises an alarm', () {
      expect(
          currentAdvisories([
            for (var i = 0; i < 4; i++)
              HealthSample(
                  at: _now.subtract(Duration(hours: 30, minutes: i)),
                  heartRate: 72,
                  source: ReadingSource.sensor),
          ], now: _now).first.tone,
          AdviceTone.info);
    });
  });
}
