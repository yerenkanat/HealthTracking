/// A temperature is only as good as whoever measured it.
///
/// The defect this file exists for shipped: ANY temperature below 37.8, from any
/// source, produced «Температура по браслету держится ровно» — a normality
/// verdict on a body, off one wrist estimate whose dominant error term is the
/// room. The woman whose wrist reads 35.9 while her core is 39 was not met with
/// silence, she was reassured by name.
///
/// The verdict that closed it (docs/CLINICAL-REVIEW-WATCH.md, "Device
/// temperature — closed 2026-08-13") has four parts, and every one of them is
/// pinned below:
///
///   1. no device path may raise `emergency` — the error the conversion would
///      have to correct for (room, bedding, strap) is not one of its inputs;
///   2. the confirmation gate does not rescue it — that error is systematic, so
///      a repeat reading confirms it rather than filtering it;
///   3. warning only, under a code that must NOT end in 'FEVER', because
///      `emergencyFamily` sweeps those into the escalation path;
///   4. a thermometer reading typed in is UNCHANGED, at full emergency weight.
///
/// Each test fails if its fix is reverted.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/ble/starmax/starmax_frames.dart';
import 'package:fcs_app/ble/starmax/starmax_health_bridge.dart';
import 'package:fcs_app/core/triage.dart';
import 'package:fcs_app/domain/emergency_confirmation.dart';
import 'package:fcs_app/domain/health_advisor.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/manual_vitals.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/appointments/visit_summary.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/dashboard/health_summary.dart';
import 'package:fcs_app/ui/dashboard/metric_detail_screen.dart';
import 'package:fcs_app/ui/widgets/glass.dart';

StarmaxHealthSnapshot _snap({int hr = 0, int tempTenths = 0}) =>
    StarmaxHealthSnapshot(
      totalSteps: 0, totalKcal: 0, totalMeters: 0, totalSleepMin: 0,
      deepSleepMin: 0, lightSleepMin: 0, heartRate: hr, bloodOxygen: 0,
      bpSystolic: 0, bpDiastolic: 0, tempRaw: tempTenths, bloodSugar: 0,
      isWorn: true, breathRate: 0, stress: 0, met: 0,
    );

/// Enough samples to clear the advisor's `minSamples` gate, all carrying the
/// same provenance and the same temperature.
List<HealthSample> _tempSamples(double c, ReadingSource source) => [
      for (var i = 0; i < 4; i++)
        HealthSample(
          at: DateTime(2026, 8, 13, 9, i * 10),
          coreTemp: c,
          source: source,
        ),
    ];

List<String> _codes(List<Advisory> a) => [for (final x in a) x.code];

/// The locale these assertions read the approved copy in.
const _en = L10n(AppLocale.en);

void main() {
  group('triage branches on who measured it', () {
    test('a thermometer reading of 38.6 typed in still raises an emergency', () {
      // Ruling 4. This is the ONLY temperature path this product is entitled to
      // escalate on, and "simplifying" the three sources into one rule disarms
      // exactly it.
      const t = BandTelemetry(coreTempC: 38.6, source: ReadingSource.manual);
      final r = assessTelemetry(t);
      expect(r.severity, TriageSeverity.emergency);
      expect(r.forceEmergencyScreen, isTrue);
      expect(r.findings.first.code, 'HIGH_FEVER');
    });

    test('a typed 37.9 is still the two-tier warning it always was', () {
      const t = BandTelemetry(coreTempC: 37.9, source: ReadingSource.manual);
      final r = assessTelemetry(t);
      expect(r.severity, TriageSeverity.warning);
      expect(r.findings.first.code, 'LOW_FEVER');
    });

    test('a device reading of 38.6 warns and never takes over the screen', () {
      const t = BandTelemetry(coreTempC: 38.6, source: ReadingSource.sensor);
      final r = assessTelemetry(t);
      expect(r.severity, TriageSeverity.warning);
      expect(r.forceEmergencyScreen, isFalse);
      expect(r.findings.single.code, 'DEVICE_TEMP_HIGH');
    });

    test('the device code does not end in FEVER, because that name escalates', () {
      // Ruling 3, and it is not cosmetic: emergencyFamily sweeps anything
      // matching endsWith('FEVER') into the confirmation gate's fever family,
      // which is the path to the Emergency screen.
      final r = assessTelemetry(
          const BandTelemetry(coreTempC: 39.5, source: ReadingSource.sensor));
      final code = r.findings.single.code;
      expect(code.endsWith('FEVER'), isFalse, reason: 'the name is load-bearing');
      expect(emergencyFamily(code), isNot('fever'));
    });

    test('a device reading below the threshold produces no finding at all', () {
      final r = assessTelemetry(
          const BandTelemetry(coreTempC: 36.9, source: ReadingSource.sensor));
      expect(r.severity, TriageSeverity.ok);
      expect(r.findings, isEmpty);
    });

    test('an UNLABELLED reading is treated as a device one', () {
      // Provenance arrives over a wire and off disk, and a row that predates the
      // field cannot be shown to have come off a thermometer.
      final r = assessTelemetry(
          BandTelemetry.fromJson(const {'coreTempC': 38.6}));
      expect(r.forceEmergencyScreen, isFalse);
      expect(r.findings.single.code, 'DEVICE_TEMP_HIGH');
    });

    test('no other vital changed: a device 160/110 still escalates', () {
      // The branch is inside the fever block only. Blood pressure, hypoxia and
      // heart rate escalate from a device exactly as before.
      final r = assessTelemetry(const BandTelemetry(
          systolicMmHg: 165, diastolicMmHg: 112, source: ReadingSource.sensor));
      expect(r.forceEmergencyScreen, isTrue);
      expect(assessTelemetry(const BandTelemetry(spo2Pct: 88, source: ReadingSource.sensor))
          .forceEmergencyScreen, isTrue);
      expect(assessTelemetry(const BandTelemetry(heartRateBpm: 145, source: ReadingSource.sensor))
          .forceEmergencyScreen, isTrue);
    });
  });

  group('provenance survives the store and the disk', () {
    test('a sample round-trips its source', () {
      final manual = HealthSample(
          at: DateTime(2026, 8, 13, 9), coreTemp: 38.6, source: ReadingSource.manual);
      expect(HealthSample.fromJson(manual.toJson()).source, ReadingSource.manual);
      final sensor = HealthSample(
          at: DateTime(2026, 8, 13, 9), coreTemp: 38.6, source: ReadingSource.sensor);
      expect(HealthSample.fromJson(sensor.toJson()).source, ReadingSource.sensor);
    });

    test('a row written before the field existed reads as a device estimate', () {
      // The safe interpretation, not the convenient one: assuming manual would
      // restore the reassurance defect on every stored row at once.
      final legacy = HealthSample.fromJson(const {
        'recordedAt': '2026-08-01T09:00:00.000',
        'coreTempC': 36.7,
      });
      expect(legacy.source, ReadingSource.sensor);
      expect(legacy.isDeviceEstimate, isTrue);
      expect(_codes(generateAdvisories([
        legacy,
        legacy,
        legacy,
      ])), isNot(contains('ADV_TEMP_STEADY')));
    });

    test('telemetry carries its provenance to the server', () {
      expect(const BandTelemetry(coreTempC: 36.7, source: ReadingSource.sensor)
          .toJson()['source'], 'band');
      expect(const BandTelemetry(coreTempC: 36.7, source: ReadingSource.manual)
          .toJson()['source'], 'manual');
    });
  });

  group('the advisor says nothing it cannot support', () {
    test('a device sample below the threshold earns NO positive advisory', () {
      // Refused sentence #15. Silence is the correct output — and honest: the
      // same fever in a cool room reads low on the wrist and raises nothing
      // either way.
      final codes = _codes(generateAdvisories(_tempSamples(36.6, ReadingSource.sensor)));
      expect(codes, isNot(contains('ADV_TEMP_STEADY')));
      expect(codes, isNot(contains('ADV_TEMP_ELEVATED')));
      expect(codes, isNot(contains('ADV_TEMP_DEVICE_HIGH')));
    });

    test('a low wrist reading is not reassuring even when the core is high', () {
      // The case named in the review: 35.9 on the wrist, 39 inside.
      final codes = _codes(generateAdvisories(_tempSamples(35.9, ReadingSource.sensor)));
      expect(codes, isNot(contains('ADV_TEMP_STEADY')));
    });

    test('a thermometer reading below the threshold still says so', () {
      // It may remain where it is true, and it must: removing it would strip a
      // real reassurance from a real measurement.
      expect(_codes(generateAdvisories(_tempSamples(36.6, ReadingSource.manual))),
          contains('ADV_TEMP_STEADY'));
    });

    test('a high device reading gets the device card, not the assertion', () {
      final codes = _codes(generateAdvisories(_tempSamples(38.6, ReadingSource.sensor)));
      expect(codes, contains('ADV_TEMP_DEVICE_HIGH'));
      // Refused sentence #16: ADV_TEMP_ELEVATED asserts «Температура повышена»
      // and says «измерьте снова» without naming an instrument.
      expect(codes, isNot(contains('ADV_TEMP_ELEVATED')));
    });

    test('a high thermometer reading still gets ADV_TEMP_ELEVATED', () {
      final codes = _codes(generateAdvisories(_tempSamples(38.6, ReadingSource.manual)));
      expect(codes, contains('ADV_TEMP_ELEVATED'));
      expect(codes, isNot(contains('ADV_TEMP_DEVICE_HIGH')));
    });

    test('provenance is read off the same sample the number came from', () {
      // A typed thermometer reading taken AFTER a run of wrist estimates is the
      // latest temperature, and the card is about that one.
      final samples = <HealthSample>[
        ..._tempSamples(36.4, ReadingSource.sensor),
        HealthSample(
            at: DateTime(2026, 8, 13, 12), coreTemp: 36.6, source: ReadingSource.manual),
      ];
      expect(_codes(generateAdvisories(samples)), contains('ADV_TEMP_STEADY'));
    });
  });

  group('the Starmax raw value knows what it is', () {
    test('an implausible frame raises nothing', () {
      // tempRaw is a u16 off an external device: 4000 tenths is 400 °C, and it
      // went straight into triage and took over the screen.
      final s = _snap(hr: 72, tempTenths: 4000);
      expect(s.tempCelsius, isNull);
      final t = bandTelemetryFromSnapshot(s);
      expect(t.deviceTempC, isNull);
      expect(t.coreTempC, isNull);
      final r = assessTelemetry(t);
      expect(r.severity, TriageSeverity.ok);
      expect(r.findings, isEmpty);
    });

    test('a frame with nothing but an impossible temperature is not emitted', () {
      expect(snapshotHasVitals(_snap(tempTenths: 4000)), isFalse);
      expect(snapshotHasVitals(_snap(tempTenths: 368)), isTrue);
    });

    test('the plausible window keeps the alarming readings', () {
      // A credibility bound, not a clinical one.
      expect(_snap(tempTenths: 405).tempCelsius, 40.5);
      expect(_snap(tempTenths: 199).tempCelsius, isNull);
      expect(_snap(tempTenths: 451).tempCelsius, isNull);
    });

    test('the watch temperature still reaches the server, in its own field', () {
      final t = bandTelemetryFromSnapshot(_snap(hr: 72, tempTenths: 368));
      expect(t.deviceTempC, closeTo(36.8, 1e-9));
      expect(t.toJson()['deviceTempC'], closeTo(36.8, 1e-9),
          reason: 'toJson is what /ingest receives');
      expect(t.toJson().containsKey('coreTempC'), isFalse,
          reason: 'a value with no stated site may not occupy the core field');
    });
  });

  group('the whole path, through the controller', () {
    test('a watch fever warns, charts and never opens the Emergency screen', () async {
      final c = AppController(now: () => DateTime(2026, 8, 13, 9));
      final t = bandTelemetryFromSnapshot(_snap(hr: 72, tempTenths: 386));
      c.onTelemetry(t, assessTelemetry(t), source: ReadingSource.sensor);

      expect(c.emergencyActive, isFalse);
      expect(c.route, isNot(AppRoute.emergency));
      expect(c.awaitingRepeat, isNull, reason: 'nothing to confirm — it never escalated');
      // It still reaches the chart, and it still knows what it is.
      expect(c.samples.single.coreTemp, closeTo(38.6, 1e-9));
      expect(c.samples.single.source, ReadingSource.sensor);
      await c.dispose();
    });

    test('a thermometer reading of 38.6 typed in opens the Emergency screen', () async {
      final c = AppController(now: () => DateTime(2026, 8, 13, 9));
      expect(c.logManualVitals(const ManualVitals(temperature: 38.6)), isTrue);
      expect(c.emergencyActive, isTrue);
      expect(c.route, AppRoute.emergency);
      expect(c.samples.single.source, ReadingSource.manual);
      await c.dispose();
    });

    test('a run of watch temperatures leaves the dashboard banner silent on temperature', () async {
      final c = AppController(now: () => DateTime(2026, 8, 13, 9));
      for (var i = 0; i < 4; i++) {
        final t = bandTelemetryFromSnapshot(_snap(hr: 72, tempTenths: 366));
        c.onTelemetry(t, assessTelemetry(t), source: ReadingSource.sensor);
      }
      expect(_codes(generateAdvisories(c.samples)), isNot(contains('ADV_TEMP_STEADY')));
      await c.dispose();
    });
  });

  group('the copy is the approved copy', () {
    test('the new strings exist in all three languages', () {
      for (final locale in AppLocale.values) {
        final l = L10n(locale);
        for (final key in const [
          'ADV_TEMP_DEVICE_HIGH',
          'ADV_TEMP_DEVICE_HIGH_b',
          'temp_device_estimate_note',
        ]) {
          expect(l.t(key), isNot(key), reason: '$key is missing in ${locale.name}');
        }
      }
    });

    test('no user-facing temperature string states an uncited threshold', () {
      // 37.8 and 38.5 have no source for pregnancy anywhere this product cites:
      // the antenatal protocol has no fever item, and emergency_help.json's two
      // fever entries are newborn and postpartum, both at 38 °C.
      for (final locale in AppLocale.values) {
        final l = L10n(locale);
        for (final key in const [
          'ADV_TEMP_DEVICE_HIGH',
          'ADV_TEMP_DEVICE_HIGH_b',
          'temp_device_estimate_note',
        ]) {
          expect(l.t(key), isNot(contains('37.8')));
          expect(l.t(key), isNot(contains('38.5')));
        }
      }
    });

    test('the device card names the instrument and who to call, and not 103', () {
      final ru = L10n(AppLocale.ru).t('ADV_TEMP_DEVICE_HIGH_b');
      expect(ru, contains('термометр'));
      expect(ru, contains('врачу сегодня'));
      // emergency_help.json reserves 103 for lethargy / unresponsiveness. A
      // device estimate is not a reason to call an ambulance.
      expect(ru, isNot(contains('103')));
      final kk = L10n(AppLocale.kk).t('ADV_TEMP_DEVICE_HIGH_b');
      expect(kk, contains('термометр'));
      expect(kk, contains('дәрігерге'));
      expect(kk, isNot(contains('103')));
      final en = _en.t('ADV_TEMP_DEVICE_HIGH_b');
      expect(en.toLowerCase(), contains('thermometer'));
      expect(en.toLowerCase(), contains('doctor'));
    });

    test('nothing promises that the app will warn her', () {
      // Refused sentence #12, in every phrasing: it turns every gap in coverage
      // — the watch off her wrist, the app closed — into an implied all-clear.
      const banned = [
        'предупредит', 'сообщим', 'уведомим', 'следим',
        'ескертеді', 'хабарлаймыз', 'қадағалап',
        'will warn', 'will alert', 'we monitor', 'we will let you know',
      ];
      for (final locale in AppLocale.values) {
        for (final key in const [
          'ADV_TEMP_DEVICE_HIGH',
          'ADV_TEMP_DEVICE_HIGH_b',
          'temp_device_estimate_note',
        ]) {
          final text = L10n(locale).t(key).toLowerCase();
          for (final phrase in banned) {
            expect(text, isNot(contains(phrase)), reason: '$key (${locale.name})');
          }
        }
      }
    });

    test('«Ваша температура» stays on the manual path it is true on', () {
      // em_reading_temp is the Emergency screen's reading line. Once device
      // temperatures stop escalating it is reachable only from a thermometer
      // reading she typed in, where "your temperature" is a true sentence.
      final source = File('lib/core/triage.dart').readAsStringSync();
      expect(source.contains("code: 'DEVICE_TEMP_HIGH'"), isTrue);
      expect(L10n(AppLocale.ru).t('em_reading_temp'), contains('Ваша температура'));
    });
  });

  group('every device path states its provenance', () {
    // The default is ReadingSource.manual, chosen so that a missing label can
    // never disarm the one escalation this product may make. The cost of that
    // choice is that a NEW device path which forgets the label would escalate a
    // wrist estimate — so no device path may rely on the default, and this is
    // what stops one from starting to.
    //
    // Exempt, and only these: the typed-reading path, which IS the manual case
    // (app_controller.dart:logManualVitals, approved as it stands), and the two
    // class declarations.
    const exempt = {
      'lib/core/triage.dart',
      'lib/domain/health_series.dart',
    };

    /// The argument list of every `TypeName(` call in [source].
    List<String> callsTo(String source, String type) {
      final out = <String>[];
      final re = RegExp('(?<![A-Za-z0-9_.])$type\\(');
      for (final m in re.allMatches(source)) {
        var depth = 0;
        var i = m.end - 1;
        for (; i < source.length; i++) {
          if (source[i] == '(') depth++;
          if (source[i] == ')') {
            depth--;
            if (depth == 0) break;
          }
        }
        out.add(source.substring(m.end, i));
      }
      return out;
    }

    test('nothing but the hand-entry path leaves the source unstated', () {
      final unlabelled = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final path = f.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart')) continue;
        if (exempt.contains(path)) continue;
        final source = f.readAsStringSync();
        for (final type in const ['BandTelemetry', 'HealthSample']) {
          for (final args in callsTo(source, type)) {
            if (args.contains('source:')) continue;
            // The manual path, approved as it stands: it relies on the default
            // precisely because the default IS manual.
            if (path.endsWith('app_controller.dart') &&
                args.contains('v.temperature')) {
              continue;
            }
            if (path.endsWith('app_controller.dart') && args.contains('coreTemp: v.')) {
              continue;
            }
            unlabelled.add('$path → $type(${args.trim().split('\n').first}…)');
          }
        }
      }
      expect(unlabelled, isEmpty,
          reason: 'a reading with no stated provenance is read as hand-measured, '
              'which is what let a wrist estimate reassure her:\n'
              '${unlabelled.join('\n')}');
    });

    test('the scan can see the constructions at all', () {
      // A scan that matches nothing passes the check above trivially.
      final source = File('lib/ble/starmax/starmax_health_bridge.dart').readAsStringSync();
      expect(callsTo(source, 'BandTelemetry'), hasLength(1));
      expect(callsTo(source, 'BandTelemetry').single, contains('ReadingSource.sensor'));
    });
  });

  group('the qualifier is on the number', () {
    testWidgets('a device temperature carries the estimate note on the vitals grid',
        (tester) async {
      final samples = _tempSamples(36.6, ReadingSource.sensor);
      await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples)));
      final note = _en.t('temp_device_estimate_note');
      await tester.scrollUntilVisible(find.text(note), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(note), findsOneWidget);
    });

    testWidgets('a thermometer reading does not', (tester) async {
      // A qualifier attached to a real measurement is false, and teaches her to
      // ignore the qualifier where it matters.
      final samples = _tempSamples(36.6, ReadingSource.manual);
      await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples)));
      expect(find.text(_en.t('temp_device_estimate_note')), findsNothing);
    });

    // The detail screen is where someone goes to look HARDER at exactly this
    // number — it draws it at 44px — so the qualifier is more necessary here,
    // not less. It is the same approved string and the same widget; a second
    // wording would be a second vocabulary.
    testWidgets('the note follows the number into the metric detail screen',
        (tester) async {
      await tester.pumpWidget(_detail('temp', _tempSamples(38.6, ReadingSource.sensor)));
      expect(find.text(_en.t('temp_device_estimate_note')),
          findsOneWidget);
    });

    testWidgets('the detail screen leaves a thermometer reading unqualified',
        (tester) async {
      await tester.pumpWidget(_detail('temp', _tempSamples(38.6, ReadingSource.manual)));
      expect(find.text(_en.t('temp_device_estimate_note')), findsNothing);
    });

    testWidgets('another metric does not borrow the temperature note', (tester) async {
      // The samples carry a device temperature, but this screen is about the
      // heart rate — a qualifier on the wrong number is noise.
      final samples = [
        for (var i = 0; i < 4; i++)
          HealthSample(
              at: DateTime(2026, 8, 13, 9, i * 10),
              heartRate: 70 + i.toDouble(),
              coreTemp: 38.6,
              source: ReadingSource.sensor),
      ];
      await tester.pumpWidget(_detail('hr', samples));
      expect(find.text(_en.t('temp_device_estimate_note')), findsNothing);
    });
  });

  group('a device temperature is never coloured', () {
    // docs/CLINICAL-REVIEW-WATCH.md, the freshness table: "never coloured —
    // recommended removal, and barred from emergency severity at any freshness".
    test('the grade is normal at any value', () {
      expect(metricStatus('temp', 38.6, source: ReadingSource.sensor),
          MetricStatus.normal);
      expect(metricStatus('temp', 40.5, source: ReadingSource.sensor),
          MetricStatus.normal);
      expect(metricStatus('temp', 35.2, source: ReadingSource.sensor),
          MetricStatus.normal);
    });

    test('a thermometer reading is graded exactly as it always was', () {
      expect(metricStatus('temp', 38.6, source: ReadingSource.manual),
          MetricStatus.danger);
      expect(metricStatus('temp', 37.9, source: ReadingSource.manual),
          MetricStatus.watch);
      expect(metricStatus('temp', 36.6, source: ReadingSource.manual),
          MetricStatus.normal);
    });

    test('no other metric reads the source', () {
      // The branch is inside the temperature case only, exactly as the triage
      // one is inside the fever block.
      expect(metricStatus('systolic', 145, source: ReadingSource.sensor),
          MetricStatus.danger);
      expect(metricStatus('spo2', 88, source: ReadingSource.sensor),
          MetricStatus.danger);
      expect(metricStatus('hr', 145, source: ReadingSource.sensor),
          MetricStatus.danger);
    });

    test('the chart paints no danger zone behind a device temperature', () {
      // The red band under the line makes the same claim the red number makes.
      expect(bandFor('temp', source: ReadingSource.sensor).warnAbove, isNull);
      expect(bandFor('temp', source: ReadingSource.manual).warnAbove, isNotNull);
      final stats = statsFor(
          buildSeries(_tempSamples(38.6, ReadingSource.sensor), 'temp'));
      expect(latestInDanger('temp', stats, source: ReadingSource.sensor), isFalse);
      expect(latestInDanger('temp', stats, source: ReadingSource.manual), isTrue);
    });

    test('provenance is read off the newest sample carrying the metric', () {
      final samples = [
        ..._tempSamples(38.6, ReadingSource.sensor),
        HealthSample(
            at: DateTime(2026, 8, 13, 12), coreTemp: 38.6, source: ReadingSource.manual),
      ];
      expect(latestSourceFor(samples, 'temp'), ReadingSource.manual);
      // A metric nothing carries has no number to grade.
      expect(latestSourceFor(samples, 'spo2'), ReadingSource.manual);
    });

    testWidgets('the screen reader is not told a wrist estimate is out of range',
        (tester) async {
      // The label matters as much as the colour: «вне безопасного диапазона»
      // announced aloud is the same claim, to someone who cannot see the red.
      await tester.pumpWidget(MaterialApp(
          home: HealthDashboardView(samples: _tempSamples(38.6, ReadingSource.sensor))));
      expect(_semanticLabels(tester).where((s) => s.contains('38.6')), isNotEmpty,
          reason: 'the reading is still announced — it is the claim about it that goes');
      expect(_semanticLabels(tester).where((s) => s.contains('outside the safe range')),
          isEmpty);
    });

    testWidgets('a thermometer reading of the same value still is', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: HealthDashboardView(samples: _tempSamples(38.6, ReadingSource.manual))));
      expect(_semanticLabels(tester).where((s) => s.contains('outside the safe range')),
          isNotEmpty);
    });

    testWidgets('a device temperature leaves the peace ring rather than filling it',
        (tester) async {
      // Counting it "not in danger" would let a wrist estimate raise the ring —
      // reassurance from the reading the review barred from any claim. The one
      // metric that CAN be graded here is a heart rate of 145, so the honest
      // fraction is 0 of 1, not 1 of 2.
      final samples = [
        for (var i = 0; i < 4; i++)
          HealthSample(
              at: DateTime(2026, 8, 13, 9, i * 10),
              heartRate: 145,
              coreTemp: 36.6,
              source: ReadingSource.sensor),
      ];
      await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples)));
      final ring = tester.widget<MetricRing>(find.byType(MetricRing).first);
      expect(ring.fraction, 0.0);
    });
  });

  group('the summary a doctor reads', () {
    final now = DateTime(2026, 8, 13, 12);

    List<HealthSample> temps(ReadingSource source, List<double> cs) => [
          for (var i = 0; i < cs.length; i++)
            HealthSample(
                at: now.subtract(Duration(days: i + 1)),
                coreTemp: cs[i],
                source: source),
        ];

    String visit(List<HealthSample> samples) => buildVisitSummary(
          _en,
          samples: samples,
          dayLogs: const {},
          medications: const [],
          weights: const [],
          now: now,
        );

    test('wrist estimates never reach it', () {
      // The construct the review refused for the admin panel, in the document
      // whose reader is a clinician: «36.9 (36.5–37.2)» carries nothing that
      // says it came off a strap.
      final s = visit(temps(ReadingSource.sensor, [36.9, 37.2, 36.5]));
      expect(s, isNot(contains('°C')));
      expect(s, isNot(contains('36.9')));
      expect(s, isNot(contains('37.2')));
    });

    test('it is silent about them rather than caveated', () {
      // A caveat is not what stops a number in a patient-presented summary from
      // being read as data — the number has to not be there.
      final s = visit(temps(ReadingSource.sensor, [36.9, 37.2]));
      expect(s, isNot(contains(_en.t('temp_device_estimate_note'))));
    });

    test('thermometer readings do, and the row names the instrument', () {
      final s = visit(temps(ReadingSource.manual, [38.6, 38.2]));
      expect(s, contains('°C'));
      expect(s, contains(_en.t('visit_temp_thermometer')));
      expect(s, contains('38.2–38.6'));
    });

    test('a mixed window keeps only what a thermometer measured', () {
      final s = visit([
        ...temps(ReadingSource.sensor, [36.9, 36.5]),
        HealthSample(
            at: now.subtract(const Duration(hours: 3)),
            coreTemp: 37.2,
            source: ReadingSource.manual),
      ]);
      expect(s, contains('37.2'));
      expect(s, isNot(contains('36.9')));
      expect(s, isNot(contains('36.5')));
      // One reading is not a series: no mean, no span.
      expect(s, isNot(contains(_en.t('visit_avg'))));
    });

    test('an unlabelled stored row is treated as a device one here too', () {
      final legacy = HealthSample.fromJson(const {
        'recordedAt': '2026-08-12T09:00:00.000',
        'coreTempC': 36.7,
      });
      expect(visit([legacy]), isNot(contains('36.7')));
    });

    test('the shared health summary qualifies the temperature it prints', () {
      // buildHealthSummary goes to the clipboard and then to whoever she sends
      // it to; a bare «Temperature: 38.6 °C» is read as a measurement.
      final device = buildHealthSummary(
          _en, _tempSamples(38.6, ReadingSource.sensor));
      expect(device, contains('38.6'));
      expect(device, contains(_en.t('temp_device_estimate_note')));

      final manual = buildHealthSummary(
          _en, _tempSamples(38.6, ReadingSource.manual));
      expect(manual, contains('38.6'));
      expect(manual,
          isNot(contains(_en.t('temp_device_estimate_note'))));
    });

    test('the instrument label ships in all three languages, without a number', () {
      for (final locale in AppLocale.values) {
        final text = L10n(locale).t('visit_temp_thermometer');
        expect(text, isNot('visit_temp_thermometer'),
            reason: 'missing in ${locale.name}');
        expect(text, isNot(contains('37.8')));
        expect(text, isNot(contains('38.5')));
      }
    });
  });

  group('no surface grades a temperature without asking where it came from', () {
    // metricStatus and bandFor default to ReadingSource.manual, which is right
    // for the vocabulary and wrong as a fallback: a call site that forgets would
    // colour a wrist estimate red again. Nothing stops that at compile time, so
    // this stops it here.
    test('every call that can see a temperature states a source', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final path = f.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart')) continue;
        if (path == 'lib/domain/health_series.dart') continue; // the declarations
        final source = f.readAsStringSync();
        for (final fn in const ['metricStatus', 'bandFor', 'latestInDanger']) {
          for (final m in RegExp('(?<![A-Za-z0-9_.])$fn\\(([^;]*?)\\)[,;)\\s]')
              .allMatches(source)) {
            final args = m.group(1)!;
            // A literal metric key that is not temperature cannot reach the
            // branch, so it needs nothing.
            final literal = RegExp("^'([a-zA-Z0-9]+)'").firstMatch(args.trim());
            if (literal != null && literal.group(1) != 'temp') continue;
            if (args.contains('source:')) continue;
            offenders.add('$path → $fn($args)');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'a temperature graded without its provenance is a wrist '
              'estimate drawn in red and announced as out of range:\n'
              '${offenders.join('\n')}');
    });

    test('the scan can see the call sites at all', () {
      // A scan that matches nothing passes trivially.
      final source =
          File('lib/ui/dashboard/health_dashboard_screen.dart').readAsStringSync();
      expect(source, contains('metricStatus(spec.key, stats.latest, source: source)'));
      expect(source, contains('bandFor(spec.key, source: source)'));
    });
  });
}

/// Every non-empty semantics label in the rendered tree — what a screen reader
/// would have to announce.
Iterable<String> _semanticLabels(WidgetTester tester) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .map((w) => w.properties.label ?? '')
    .where((s) => s.isNotEmpty);

/// The scope sits ABOVE MaterialApp, not at `home:`. Below the Navigator it
/// only covers the first route, and `L10nScope.of` falls back to English
/// silently instead of throwing — so a screen reached by a push reads fine here
/// and is untranslated in the app.
Widget _detail(String metricKey, List<HealthSample> samples) => L10nScope(
      l10n: _en,
      child: MaterialApp(
        home: MetricDetailScreen(
          metricKey: metricKey,
          unit: metricKey == 'temp' ? '°C' : 'bpm',
          icon: Icons.thermostat,
          color: const Color(0xFFFF5A7A),
          samples: samples,
        ),
      ),
    );
