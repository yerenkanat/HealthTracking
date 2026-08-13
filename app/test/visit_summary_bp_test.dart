/// The blood-pressure row of the page a woman hands to her doctor.
///
/// docs/CLINICAL-REVIEW-WATCH.md REFUSED the wrist blood-pressure day average
/// outright, for the admin panel, whose reader is the owner. This summary is put
/// into a clinician's hand, so every reason applies with more force: the peak is
/// the clinical object and a mean hides it; `emergency_confirmation.dart` puts
/// wrist PPG blood pressure at ±10–15 mmHg against the 140 threshold; and
/// calibration state cannot be on a row that is read off a clipboard days later,
/// which is what `bpCalibrationMaxAgeDays` exists for.
///
/// The aggravating one is specific to this page: blood pressure is what the
/// antenatal protocol acts on. `packages/contract/antenatal_protocol.json` pairs
/// it with urine protein at every visit from the second, and a reassuring wrist
/// estimate can defer the very check the protocol schedules.
///
/// A cuff reading she typed in is a different evidential object and IS
/// distinguishable in the store: `AppController.logManualVitals` builds its
/// sample with the default `ReadingSource.manual`, every device path states
/// `ReadingSource.sensor`. Those are presentable, and the row names the
/// instrument.
///
/// Each test fails if its fix is reverted.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/ui/appointments/visit_summary.dart';

void main() {
  const en = L10n(AppLocale.en);
  final now = DateTime(2026, 8, 14, 12);

  List<HealthSample> bp(ReadingSource source, List<List<int>> pairs) => [
        for (var i = 0; i < pairs.length; i++)
          HealthSample(
              at: now.subtract(Duration(days: i + 1)),
              systolic: pairs[i][0].toDouble(),
              diastolic: pairs[i][1].toDouble(),
              source: source),
      ];

  String visit(List<HealthSample> samples, [L10n l = en]) => buildVisitSummary(
        l,
        samples: samples,
        dayLogs: const {},
        medications: const [],
        weights: const [],
        now: now,
      );

  group('the blood-pressure row', () {
    test('wrist estimates never reach it', () {
      // The exact construct the review refused, in the document whose reader is
      // deciding care: a day touching 158/104 and resting at 105/68 prints a
      // reassuring mean, and nothing in «118/76» says it came off a strap.
      final s = visit(bp(ReadingSource.sensor, [
        [158, 104],
        [105, 68],
        [132, 85],
      ]));
      expect(s, isNot(contains('mmHg')));
      expect(s, isNot(contains('132/85')));
      expect(s, isNot(contains('105/68')));
      expect(s, isNot(contains('158/104')));
      expect(s, isNot(contains(en.t('metric_bp'))));
    });

    test('it is silent about them rather than caveated', () {
      // A caveat is not what stops a figure in a patient-presented summary from
      // being read as data — the figure has to not be there. In particular the
      // instrument label must not be repurposed into a hedge on an estimate.
      final s = visit(bp(ReadingSource.sensor, [
        [132, 85],
        [105, 68],
      ]));
      expect(s, isNot(contains(en.t('visit_bp_cuff'))));
      expect(s, isNot(contains(en.t('visit_avg'))));
      expect(s, isNot(contains(en.t('visit_vitals_head'))));
    });

    test('cuff readings do, and the row names the instrument', () {
      final s = visit(bp(ReadingSource.manual, [
        [132, 85],
        [105, 68],
      ]));
      expect(s, contains('mmHg'));
      expect(s, contains(en.t('visit_bp_cuff')));
      // The extremes stay beside the mean: the review's first objection to the
      // panel's row was that no maximum column existed there.
      expect(s, contains('105/68–132/85'));
      expect(s, contains('119/77'));
    });

    test('a mixed window keeps only what a cuff measured', () {
      final s = visit([
        ...bp(ReadingSource.sensor, [
          [158, 104],
          [105, 68],
        ]),
        HealthSample(
            at: now.subtract(const Duration(hours: 3)),
            systolic: 122,
            diastolic: 78,
            source: ReadingSource.manual),
      ]);
      expect(s, contains('122/78'));
      expect(s, isNot(contains('158')));
      expect(s, isNot(contains('105')));
      // One reading is not a series: no mean, no span.
      expect(s, isNot(contains(en.t('visit_avg'))));
    });

    test('an unlabelled stored row is treated as a device one here too', () {
      // A row written before `source` existed cannot be shown to have come off
      // a cuff, and fromJson reads it as a device estimate on purpose.
      final legacy = HealthSample.fromJson(const {
        'recordedAt': '2026-08-13T09:00:00.000',
        'systolicMmHg': 148,
        'diastolicMmHg': 96,
      });
      final s = visit([legacy]);
      expect(s, isNot(contains('148')));
      expect(s, isNot(contains('mmHg')));
    });

    test('the instrument label ships in all three languages, without a threshold', () {
      for (final locale in AppLocale.values) {
        final text = L10n(locale).t('visit_bp_cuff');
        expect(text, isNot('visit_bp_cuff'), reason: 'missing in ${locale.name}');
        // 140/90 is ACOG's and belongs to triage, not to a label on a printout.
        expect(text, isNot(contains('140')));
        expect(text, isNot(contains('90')));
        // And it must not be reachable when only the strap contributed.
        expect(
            visit(
                bp(ReadingSource.sensor, [
                  [132, 85],
                  [105, 68],
                ]),
                L10n(locale)),
            isNot(contains(text)));
      }
    });
  });

  group('the reading count', () {
    // 40 wrist heart-rate samples and two cuff readings: the old header counted
    // every sample in the window, so it claimed «40 измерений» over a row that
    // rested on two.
    final mixed = [
      for (var i = 0; i < 40; i++)
        HealthSample(
            at: now.subtract(Duration(hours: i + 1)),
            heartRate: 70 + (i % 5).toDouble(),
            source: ReadingSource.sensor),
      ...bp(ReadingSource.manual, [
        [132, 85],
        [105, 68],
      ]),
    ];

    test('the header no longer states one count for differently-sourced rows', () {
      final s = visit(mixed);
      expect(s, contains('\n${en.t('visit_vitals_head')}\n'));
      expect(s, isNot(contains('42')));
      expect(s, isNot(contains(en.t('visit_vitals', {'n': 42}))));
    });

    test('each row states the denominator it actually rests on', () {
      final s = visit(mixed);
      final bpRow = s
          .split('\n')
          .firstWhere((r) => r.contains(en.t('metric_bp')), orElse: () => '');
      final hrRow = s
          .split('\n')
          .firstWhere((r) => r.contains(en.metricLabel('hr')), orElse: () => '');
      expect(bpRow, contains(en.t('visit_row_readings', {'n': 2})));
      expect(hrRow, contains(en.t('visit_row_readings', {'n': 40})));
    });

    test('a single reading carries no count and no invented series', () {
      final s = visit([
        HealthSample(
            at: now.subtract(const Duration(hours: 2)),
            systolic: 122,
            diastolic: 78,
            heartRate: 74,
            spo2: 98),
      ]);
      expect(s, contains('122/78 mmHg'));
      expect(s, contains('74 bpm'));
      expect(s, contains('98%'));
      expect(s, isNot(contains(en.t('visit_avg'))));
      expect(s, isNot(contains(en.t('visit_row_readings', {'n': 1}))));
    });

    test('the count string ships in all three languages', () {
      for (final locale in AppLocale.values) {
        final text = L10n(locale).t('visit_row_readings', {'n': 4});
        expect(text, isNot(contains('visit_row_readings')),
            reason: 'missing in ${locale.name}');
        expect(text, contains('4'));
        expect(L10n(locale).t('visit_vitals_head'),
            isNot('visit_vitals_head'), reason: 'missing in ${locale.name}');
      }
    });
  });
}
