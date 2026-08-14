/// «Давление ровное» is a verdict on a body, and a wrist cannot deliver it.
///
/// The temperature half of this defect was refused as sentence #15 in
/// docs/CLINICAL-REVIEW-WATCH.md and fixed in `generateAdvisories`. Blood
/// pressure sat four lines above it in the SAME function, doing the same thing,
/// and shipped in all three languages for another week.
///
/// It is the worse of the two:
///
///   * the review puts wrist PPG blood pressure at ±10–15 mmHg against a 140
///     threshold, so the uncertainty is the size of the decision;
///   * `bpCalibrationMaxAgeDays` exists because the calibration behind that
///     estimate expires, and nothing on this path checks whether it has;
///   * the antenatal protocol pairs blood pressure with urine protein at every
///     visit from the second — so unlike a temperature, a reassurance here can
///     defer a check that is actually scheduled.
///
/// What is NOT being claimed: that the app should go quiet about a high
/// reading. Refusing to reassure and refusing to warn are different decisions,
/// and only the first is made here. The last test pins that distinction,
/// because the obvious over-correction is to silence the whole branch.
///
/// ---------------------------------------------------------------------------
/// UPDATED 2026-08-14 — "Device blood pressure — closed" and "The absorber
/// rule" in docs/CLINICAL-REVIEW-WATCH.md.
///
/// One expectation below CHANGED, and it is intent-preserving rather than a
/// loosening. «a HIGH reading still warns, whoever measured it» used to assert
/// that a sensor 138/88 yields `ADV_BP_ELEVATED`. Its INTENT — a high reading
/// still warns, whoever measured it — is unchanged and still pinned; only the
/// code is now `ADV_BP_DEVICE_HIGH`, because what the card may SAY depends on
/// who measured it. Both branches are asserted below, in the same test, so the
/// warning cannot be silenced by taking either one away.
///
/// Three things this file additionally guards, each of which shipped:
///
///   1. the OR-guard. `sysElevated || diaElevated` was bounded per half, so
///      150/86 produced a calm «отдохните и измерьте снова» card while
///      `assessTelemetry` raised PREECLAMPSIA_BP at emergency severity on the
///      same sample;
///   2. the absorbers. Silencing ADV_BP_STEADY did not produce silence — the
///      day fell through to «Всё стабильно», so a blood-pressure reassurance
///      was promoted into a whole-body one, on the banner and in the clipboard;
///   3. the numbers, which are asymmetric ON PURPOSE. 140/90 may appear on the
///      cuff card (ACOG, cited in this repo) and may not appear on the device
///      card; 135/85 may appear nowhere.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/core/triage.dart';
import 'package:fcs_app/domain/health_advisor.dart';
// Also brings ReadingSource, which health_series re-exports so a decoder needs
// one import rather than two.
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/advisor/advisor_screen.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/dashboard/health_summary.dart';
import 'package:fcs_app/ui/widgets/glass.dart';

List<String> _codes(List<Advisory> a) => [for (final x in a) x.code];

/// Three readings, because `generateAdvisories` says nothing below `minSamples`.
List<HealthSample> _bp(double sys, double dia, ReadingSource source) => [
      for (var i = 0; i < 3; i++)
        HealthSample(
          at: DateTime(2026, 8, 14, 9 + i),
          systolic: sys,
          diastolic: dia,
          source: source,
        ),
    ];

/// The locales these assertions read the approved copy in. All three are
/// checked: approval was given for three languages, and a string that is right
/// in Russian and missing in Kazakh has not shipped.
const _en = L10n(AppLocale.en);
const _ru = L10n(AppLocale.ru);
const _kk = L10n(AppLocale.kk);

/// The scope sits ABOVE MaterialApp. Below the Navigator it covers only the
/// first route and `L10nScope.of` falls back to English silently.
Widget _advisor(List<HealthSample> samples) => L10nScope(
      l10n: _en,
      child: MaterialApp(home: AdvisorScreen(samples: samples)),
    );

void main() {
  group('the advisor does not call a wrist estimate normal', () {
    test('a device reading in range earns NO reassurance', () {
      final codes = _codes(generateAdvisories(_bp(118, 76, ReadingSource.sensor)));
      expect(codes, isNot(contains('ADV_BP_STEADY')));
    });

    test('a cuff reading she typed in still does', () {
      // The whole point of branching on provenance rather than deleting the
      // card: a real instrument keeps its voice. If this ever goes silent the
      // fix has become "say nothing about blood pressure", which is a different
      // and unreviewed decision.
      final codes = _codes(generateAdvisories(_bp(118, 76, ReadingSource.manual)));
      expect(codes, contains('ADV_BP_STEADY'));
    });

    test('a stored row with no provenance is treated as a wrist, not a cuff', () {
      // The safe reading of an ambiguous row. Assuming manual would restore the
      // defect across every legacy row at once.
      //
      // This WAS the live case: `GET /vitals/manual` emitted no `source`, so
      // every typed thermometer reading came back from the server labelled a
      // wrist estimate after a handset change — silently demoting the one
      // source entitled to raise an emergency. The route now states the
      // provenance its own `device_id IS NULL` filter already guaranteed.
      // The assertion stays, because rows stored BEFORE that fix still carry
      // no label, and the safe reading of them has not changed.
      final legacy = HealthSample.fromJson(const {
        'recordedAt': '2026-08-01T09:00:00.000',
        'systolicMmHg': 118.0,
        'diastolicMmHg': 76.0,
      });
      expect(legacy.isDeviceEstimate, isTrue);
      expect(_codes(generateAdvisories([legacy, legacy, legacy])),
          isNot(contains('ADV_BP_STEADY')));
    });

    test('provenance follows the newest reading, not the last one in the list', () {
      // The number comes from `statsFor(buildSeries(...)).latest`, which is
      // CHRONOLOGICAL. If the provenance check used list order instead, the two
      // could describe different readings — and the card would be about one
      // while claiming the authority of the other.
      final samples = [
        HealthSample(
          at: DateTime(2026, 8, 14, 18),
          systolic: 118,
          diastolic: 76,
          source: ReadingSource.sensor,
        ),
        HealthSample(
          at: DateTime(2026, 8, 14, 9),
          systolic: 117,
          diastolic: 75,
          source: ReadingSource.manual,
        ),
        HealthSample(
          at: DateTime(2026, 8, 14, 10),
          systolic: 119,
          diastolic: 77,
          source: ReadingSource.manual,
        ),
      ];
      // Newest is the 18:00 wrist estimate, though a manual reading is last in
      // the list. No reassurance.
      expect(_codes(generateAdvisories(samples)), isNot(contains('ADV_BP_STEADY')));
    });

    test('a HIGH reading still warns, whoever measured it', () {
      // The blast-radius guard, and the reason this fix is scoped to the
      // positive card only. Silencing a warning because the sensor is imprecise
      // would be the same error in the opposite direction — and worse, because
      // the cost of a missed warning is not symmetrical with the cost of a
      // missed reassurance.
      //
      // INTENT-PRESERVING UPDATE, 2026-08-14: this used to assert
      // ADV_BP_ELEVATED for the sensor case. The warning is unchanged — it
      // still fires, from both sources, at watch tone — but the wording it
      // fires with now depends on who measured it, so the sensor branch has its
      // own code. Both branches are asserted here on purpose: taking either
      // away would silence a warning.
      final device = _codes(generateAdvisories(_bp(138, 88, ReadingSource.sensor)));
      expect(device, contains('ADV_BP_DEVICE_HIGH'));
      // Refused sentence #17: «давление повышено» states as fact the one thing
      // a wrist estimate cannot establish — its firing window sits entirely
      // inside the estimate's own ±10–15 mmHg.
      expect(device, isNot(contains('ADV_BP_ELEVATED')));

      final cuff = _codes(generateAdvisories(_bp(138, 88, ReadingSource.manual)));
      expect(cuff, contains('ADV_BP_ELEVATED'));
      expect(cuff, isNot(contains('ADV_BP_DEVICE_HIGH')));

      // Whoever measured it, it is a WATCH — it outranks every positive card.
      for (final samples in [
        _bp(138, 88, ReadingSource.sensor),
        _bp(138, 88, ReadingSource.manual),
      ]) {
        expect(generateAdvisories(samples).first.tone, AdviceTone.watch);
      }
    });

    test('a diastolic-only rise warns from either source', () {
      // 128/86 clears the systolic band and not the diastolic one. The OR
      // between the two halves is correct INSIDE the sub-emergency band; what
      // was wrong was that neither half was bounded by the other's cutoff.
      expect(_codes(generateAdvisories(_bp(128, 86, ReadingSource.sensor))),
          contains('ADV_BP_DEVICE_HIGH'));
      expect(_codes(generateAdvisories(_bp(128, 86, ReadingSource.manual))),
          contains('ADV_BP_ELEVATED'));
    });
  });

  group('the advisor and triage cannot disagree about danger', () {
    // The live contradiction: two screens in one app, on the same sample.
    test('150/86 is not an "elevated, rest and re-measure" card', () {
      for (final source in ReadingSource.values) {
        final codes = _codes(generateAdvisories(_bp(150, 86, source)));
        expect(codes, isNot(contains('ADV_BP_ELEVATED')),
            reason: 'systolic 150 is what assessTelemetry calls an emergency');
        expect(codes, isNot(contains('ADV_BP_DEVICE_HIGH')));
        expect(codes, isNot(contains('ADV_BP_STEADY')));
      }
      // …and this is what the other screen says about the very same reading.
      final r = assessTelemetry(const BandTelemetry(
          systolicMmHg: 150, diastolicMmHg: 86, source: ReadingSource.sensor));
      expect(r.severity, TriageSeverity.emergency);
      expect(r.findings.single.code, 'PREECLAMPSIA_BP');
    });

    test('a high diastolic with a calm systolic is the same case, mirrored', () {
      // 128/95: the old guard fired the calm card off `diaElevated` alone,
      // bounded by 90 — except that 95 is above 90, so the band it was bounded
      // to did not exclude it. Triage escalates.
      for (final source in ReadingSource.values) {
        final codes = _codes(generateAdvisories(_bp(128, 95, source)));
        expect(codes, isNot(contains('ADV_BP_ELEVATED')));
        expect(codes, isNot(contains('ADV_BP_DEVICE_HIGH')));
      }
      expect(
          assessTelemetry(const BandTelemetry(
                  systolicMmHg: 128,
                  diastolicMmHg: 95,
                  source: ReadingSource.sensor))
              .severity,
          TriageSeverity.emergency);
    });

    test('the top of the advisory band is still the advisory band', () {
      // 139/89 is the last reading below both cutoffs, and it must still warn —
      // the AND narrows the card to the band under triage, it does not shrink
      // that band.
      expect(_codes(generateAdvisories(_bp(139, 89, ReadingSource.manual))),
          contains('ADV_BP_ELEVATED'));
      expect(
          assessTelemetry(const BandTelemetry(
                  systolicMmHg: 139,
                  diastolicMmHg: 89,
                  source: ReadingSource.sensor))
              .severity,
          isNot(TriageSeverity.emergency));
    });
  });

  group('the copy is the approved copy', () {
    test('the new strings exist in all three languages', () {
      for (final locale in AppLocale.values) {
        final l = L10n(locale);
        for (final key in const [
          'ADV_BP_DEVICE_HIGH',
          'ADV_BP_DEVICE_HIGH_b',
          'ADV_BP_ELEVATED',
          'ADV_BP_ELEVATED_b',
          'ADV_NOTHING_UNUSUAL',
          'ADV_NOTHING_UNUSUAL_b',
          'share_bp_cuff_only',
        ]) {
          expect(l.t(key), isNot(key), reason: '$key is missing in ${locale.name}');
        }
      }
    });

    test('135 and 85 appear in no user-facing blood-pressure string', () {
      // They fire the card and they appear in NO source this product cites.
      for (final locale in AppLocale.values) {
        final l = L10n(locale);
        for (final key in const [
          'ADV_BP_DEVICE_HIGH',
          'ADV_BP_DEVICE_HIGH_b',
          'ADV_BP_ELEVATED',
          'ADV_BP_ELEVATED_b',
          'ADV_BP_STEADY',
          'ADV_BP_STEADY_b',
        ]) {
          expect(l.t(key), isNot(contains('135')), reason: '$key (${locale.name})');
          expect(l.t(key), isNot(contains('85')), reason: '$key (${locale.name})');
        }
      }
    });

    test('140/90 is on the cuff card and NOWHERE on the device card', () {
      // The asymmetry is the ruling and must not be "harmonised". 140/90 is
      // attributed to ACOG in packages/shared/src/triage.ts and is the level
      // the product acts on, so on a cuff card it gives her a checkable rule
      // instead of an adjective. Beside a wrist estimate it invites a
      // comparison the estimate cannot support — refused sentence #20.
      for (final locale in AppLocale.values) {
        expect(L10n(locale).t('ADV_BP_ELEVATED_b'), contains('140/90'),
            reason: 'the cuff card gives her the rule (${locale.name})');
        for (final n in const ['140', '90']) {
          expect(L10n(locale).t('ADV_BP_DEVICE_HIGH_b'), isNot(contains(n)),
              reason: 'no cuff threshold beside a wrist estimate (${locale.name})');
          expect(L10n(locale).t('ADV_BP_DEVICE_HIGH'), isNot(contains(n)));
        }
      }
    });

    test('«выпейте воды» is gone from both cards', () {
      // Refused sentence #18. Hydration is not a treatment for hypertension, no
      // cited source offers it, and beside «при стойком повышении» it produced
      // wait-and-see on the one condition this product exists to catch.
      const banned = [
        'выпейте воды', 'пейте воду', 'су ішіп', 'hydrate', 'drink water',
      ];
      for (final locale in AppLocale.values) {
        for (final key in const ['ADV_BP_ELEVATED_b', 'ADV_BP_DEVICE_HIGH_b']) {
          final text = L10n(locale).t(key).toLowerCase();
          for (final phrase in banned) {
            expect(text, isNot(contains(phrase)), reason: '$key (${locale.name})');
          }
        }
      }
    });

    test('both cards name an instrument, and the red flags with 103', () {
      // «Измерьте снова» named no instrument (refused #16), and off a wrist a
      // re-read is not a second measurement. The red-flag branch is the only
      // part that helps the woman whose wrist reads 137 while her true pressure
      // is 160, so it is unconditional on both cards.
      final ruDevice = _ru.t('ADV_BP_DEVICE_HIGH_b');
      expect(ruDevice, contains('тонометр'));
      expect(ruDevice, contains('женской консультации'),
          reason: 'the route that needs no equipment');
      expect(ruDevice, contains('103'));
      final ruCuff = _ru.t('ADV_BP_ELEVATED_b');
      expect(ruCuff, contains('тонометр'));
      expect(ruCuff, contains('103'));

      final kkDevice = _kk.t('ADV_BP_DEVICE_HIGH_b');
      expect(kkDevice, contains('тонометр'));
      expect(kkDevice, contains('103'));
      expect(_kk.t('ADV_BP_ELEVATED_b'), contains('103'));

      final enDevice = _en.t('ADV_BP_DEVICE_HIGH_b').toLowerCase();
      expect(enDevice, contains('cuff'));
      expect(enDevice, contains('antenatal visit'));
      expect(enDevice, contains('103'));
      expect(_en.t('ADV_BP_ELEVATED_b'), contains('103'));
    });

    test('the device title names the sensor, because titles ship alone', () {
      // The clipboard export maps advisories to their TITLES and never touches
      // the body, so every title leaves the app without its qualifier. Refused
      // sentence #24: a title must be true with no body, no number and no
      // surrounding screen.
      expect(_ru.t('ADV_BP_DEVICE_HIGH'), contains('Датчик'));
      expect(_kk.t('ADV_BP_DEVICE_HIGH'), contains('Датчик'));
      expect(_en.t('ADV_BP_DEVICE_HIGH').toLowerCase(), contains('sensor'));
    });

    test('nothing promises that the app will warn her', () {
      // Refused sentence #12, in every phrasing: it turns every gap in coverage
      // into an implied all-clear.
      const banned = [
        'предупредит', 'сообщим', 'уведомим', 'следим',
        'ескертеді', 'хабарлаймыз', 'қадағалап',
        'will warn', 'will alert', 'we monitor', 'we will let you know',
      ];
      for (final locale in AppLocale.values) {
        for (final key in const [
          'ADV_BP_DEVICE_HIGH',
          'ADV_BP_DEVICE_HIGH_b',
          'ADV_BP_ELEVATED_b',
          'ADV_NOTHING_UNUSUAL',
          'ADV_NOTHING_UNUSUAL_b',
        ]) {
          final text = L10n(locale).t(key).toLowerCase();
          for (final phrase in banned) {
            expect(text, isNot(contains(phrase)), reason: '$key (${locale.name})');
          }
        }
      }
    });

    test('the fallback card keeps its third sentence', () {
      // The clinically load-bearing one: it stops the reassurance outranking
      // her own symptoms, which is the specific harm a green banner does to a
      // woman who feels wrong and decides not to call.
      expect(_ru.t('ADV_NOTHING_UNUSUAL_b'),
          contains('Если вы плохо себя чувствуете'));
      expect(_kk.t('ADV_NOTHING_UNUSUAL_b'),
          contains('Өзіңізді нашар сезінсеңіз'));
      expect(_en.t('ADV_NOTHING_UNUSUAL_b').toLowerCase(),
          contains('if you feel unwell'));
      // And it does not claim to have checked her.
      expect(_en.t('ADV_NOTHING_UNUSUAL_b').toLowerCase(),
          contains('not a health check'));
    });

    test('the refused normality verdicts are gone from the table entirely', () {
      // Deleted rather than reworded, so a missed call site fails visibly
      // instead of quietly rendering an approved-looking old sentence.
      for (final locale in AppLocale.values) {
        for (final key in const [
          'ADV_ALL_STEADY',
          'ADV_ALL_STEADY_b',
          'db_peace_stable',
          'db_peace_stable_noname',
          'db_peace_stable_b',
        ]) {
          expect(L10n(locale).t(key), key,
              reason: '$key still resolves in ${locale.name}');
        }
      }
    });
  });

  group('a card badge shows a blood pressure or shows nothing', () {
    testWidgets('the cuff card badges both halves, never a bare systolic',
        (tester) async {
      // Refused sentence #19: a bare unitless «137» in bold, beside copy
      // explaining the reading is not a measurement. Half a reading, no unit.
      await tester.pumpWidget(_advisor(_bp(137, 88, ReadingSource.manual)));
      expect(find.text(_en.t('ADV_BP_ELEVATED')), findsOneWidget);
      expect(find.text('137/88'), findsOneWidget);
      expect(find.text('137'), findsNothing);
    });

    testWidgets('the device card carries no number at all', (tester) async {
      await tester.pumpWidget(_advisor(_bp(137, 88, ReadingSource.sensor)));
      expect(find.text(_en.t('ADV_BP_DEVICE_HIGH')), findsOneWidget);
      expect(find.text(_en.t('ADV_BP_DEVICE_HIGH_b')), findsOneWidget);
      expect(find.text('137'), findsNothing);
      expect(find.text('137/88'), findsNothing);
    });

    testWidgets('a metric that is not a pair still shows its value', (tester) async {
      // The formatter now returns null for a systolic with no diastolic beside
      // it; that must not have swallowed every other badge on the screen.
      final samples = [
        for (var i = 0; i < 4; i++)
          HealthSample(
              at: DateTime(2026, 8, 14, 9, i * 10),
              spo2: 90,
              duringSleep: true,
              source: ReadingSource.sensor),
      ];
      await tester.pumpWidget(_advisor(samples));
      expect(find.text('90%'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // THE CHECKLIST. When a positive claim is silenced for provenance, every
  // aggregate that can include that metric must be given the same filter in the
  // SAME commit — otherwise the reassurance survives as a broader one, and a
  // broader reassurance is worse than the specific one that was removed. The
  // absorber table in docs/CLINICAL-REVIEW-WATCH.md is the list; this is it,
  // executed. If you are here because you have just silenced a metric, this
  // group is what you copy.
  // ---------------------------------------------------------------------------
  group('a day of normal wrist readings produces no reassurance anywhere', () {
    /// A wrist-only day that looks fine, plus one metric this product IS
    /// entitled to grade and which is not fine — so the ring has something real
    /// to say and the wrist BP's contribution to it is visible.
    List<HealthSample> wristDay({double hr = 72}) => [
          for (var i = 0; i < 4; i++)
            HealthSample(
              at: DateTime(2026, 8, 14, 9, i * 10),
              heartRate: hr,
              systolic: 118,
              diastolic: 76,
              source: ReadingSource.sensor,
            ),
        ];

    /// The clock these readings are CURRENT on.
    ///
    /// Pinned rather than left to `DateTime.now()`, because a second filter now
    /// stands between these readings and every absorber below: a reassurance
    /// may claim no more than the readings behind it, and a reading past its
    /// metric's window no longer feeds one. Without this the whole group would
    /// pass on the day it was written and assert nothing ever again — the
    /// wrist BP would be filtered for AGE before the provenance rule it exists
    /// to pin ever ran.
    final now = DateTime(2026, 8, 14, 9, 35);

    testWidgets('the advisor, the banner, the ring and the clipboard, together',
        (tester) async {
      // 1. THE CARD. The narrow claim, silenced at 21a0a01.
      final codes = _codes(generateAdvisories(wristDay()));
      expect(codes, isNot(contains('ADV_BP_STEADY')));

      // 2. THE FALLBACK. Silence is not what the old code produced: the day
      // fell through to «Всё стабильно», promoting a blood-pressure
      // reassurance into a whole-body one.
      expect(codes, isNot(contains('ADV_ALL_STEADY')));
      expect(codes, contains('ADV_NOTHING_UNUSUAL'));

      // 3. THE BANNER. It composed its own copy for the positive tone instead
      // of rendering the advisory, so the first screen she opens went on
      // saying refused sentence #2 after the advisor had been fixed. Asserted
      // as literal text, not by key, because the keys are deleted.
      await tester.pumpWidget(L10nScope(
        l10n: _en,
        child: MaterialApp(
            home: HealthDashboardView(
                samples: wristDay(), nowForAppointment: now)),
      ));
      expect(find.text('Your readings are within a healthy range.'), findsNothing);
      expect(find.text('Everything looks stable'), findsNothing);
      expect(find.textContaining('Everything is stable'), findsNothing);
      expect(find.text(_en.t('ADV_NOTHING_UNUSUAL')), findsOneWidget);

      // 4. THE RING. A wrist 118/76 counted as "healthy" is the same
      // reassurance re-entering as a number — and it diluted the one metric
      // that could be graded: 2 of 3 healthy instead of 0 of 1.
      await tester.pumpWidget(L10nScope(
        l10n: _en,
        child: MaterialApp(
            home: HealthDashboardView(
                samples: wristDay(hr: 145), nowForAppointment: now)),
      ));
      final ring = tester.widget<MetricRing>(find.byType(MetricRing).first);
      expect(ring.fraction, 0.0);

      // 5. THE CLIPBOARD. It leaves the app and is read by whoever she sends it
      // to, and it prints the advisory TITLES, so both the row and the fallback
      // card travel.
      final shared = buildHealthSummary(_en, wristDay(), now: now);
      expect(shared, isNot(contains('118/76')));
      expect(shared, isNot(contains('mmHg')));
      expect(shared, contains(_en.t('share_bp_cuff_only')));
      expect(shared, isNot(contains('All steady')));
      expect(shared, contains(_en.t('ADV_NOTHING_UNUSUAL')));
    });

    testWidgets('a wrist BP in the danger band may still turn the ring red',
        (tester) async {
      // The asymmetry, and it is the ruling rather than a preference: the
      // product DOES escalate a device BP at 140/90 — triage.dart has no source
      // check — so the estimate may pull the fraction down. It may only never
      // push it up. Gating it symmetrically would remove a warning.
      final samples = [
        for (var i = 0; i < 4; i++)
          HealthSample(
            at: DateTime(2026, 8, 14, 9, i * 10),
            heartRate: 72,
            systolic: 165,
            diastolic: 112,
            source: ReadingSource.sensor,
          ),
      ];
      await tester.pumpWidget(L10nScope(
        l10n: _en,
        child: MaterialApp(home: HealthDashboardView(samples: samples)),
      ));
      final ring = tester.widget<MetricRing>(find.byType(MetricRing).first);
      expect(ring.fraction, lessThan(1.0),
          reason: 'a wrist estimate in the danger band still counts against her');
    });

    test('a cuff day keeps every reassurance it earned', () {
      // The over-correction guard. None of the above may be achieved by going
      // quiet about blood pressure: a reading she took with an instrument and
      // typed in is a different evidential object, and it keeps its card, its
      // clipboard row and its place in the ring.
      final cuffDay = [
        for (var i = 0; i < 4; i++)
          HealthSample(
            at: DateTime(2026, 8, 14, 9, i * 10),
            heartRate: 72,
            systolic: 118,
            diastolic: 76,
            source: ReadingSource.manual,
          ),
      ];
      expect(_codes(generateAdvisories(cuffDay)), contains('ADV_BP_STEADY'));
      final shared = buildHealthSummary(_en, cuffDay, now: now);
      expect(shared, contains('118/76'));
      expect(shared, isNot(contains(_en.t('share_bp_cuff_only'))));
    });

    test('the clipboard prefers a cuff reading over a newer wrist one', () {
      // The row is built from the cuff-measured pool, not from "the latest
      // reading if it happens to be manual" — a wrist estimate arriving later
      // must not delete a real measurement from the summary.
      final mixed = [
        HealthSample(
          at: DateTime(2026, 8, 14, 9),
          systolic: 118,
          diastolic: 76,
          source: ReadingSource.manual,
        ),
        for (var i = 0; i < 3; i++)
          HealthSample(
            at: DateTime(2026, 8, 14, 12 + i),
            systolic: 129,
            diastolic: 84,
            source: ReadingSource.sensor,
          ),
      ];
      final shared = buildHealthSummary(_en, mixed, now: DateTime(2026, 8, 14, 14));
      expect(shared, contains('118/76'));
      expect(shared, isNot(contains('129/84')));
    });
  });
}
