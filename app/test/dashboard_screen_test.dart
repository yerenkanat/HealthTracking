/// Widget tests for the health dashboard (run with `flutter test`).
library;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/appointment.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/setup_checklist.dart';
import 'package:fcs_app/domain/weekly_digest.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/widgets/glass.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/ble/link_policy.dart';
import 'package:fcs_app/domain/wearable_metrics.dart';

const _notMeasuring = 'Device not connected — these readings may be out of date.';

void main() {
  DateTime t(int m) => DateTime.utc(2026, 7, 15, 8, m);

  testWidgets('shows the activity & wellness panel with the watch metrics', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72, spo2: 98, coreTemp: 36.6)];
    final w = WearableMetrics(
      at: t(0), steps: 8200, meters: 6100, kcal: 420, sleepMinutes: 465, stress: 34, breathRate: 15, worn: true,
    );
    await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples, wearable: w)));
    await tester.scrollUntilVisible(find.text('ACTIVITY & WELLNESS'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('8 200'), findsOneWidget); // grouped thousands
    expect(find.text('6.1'), findsOneWidget); // distance km
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Breathing'), findsOneWidget);
  });

  testWidgets('the activity panel is hidden with no watch data', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72, spo2: 98, coreTemp: 36.6)];
    await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples)));
    expect(find.text('ACTIVITY & WELLNESS'), findsNothing);
  });

  testWidgets('an off-wrist watch is flagged in the panel', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72, spo2: 98, coreTemp: 36.6)];
    final w = WearableMetrics(at: t(0), steps: 500, worn: false);
    await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples, wearable: w)));
    await tester.scrollUntilVisible(find.text('ACTIVITY & WELLNESS'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Watch is off the wrist — data may be incomplete.'), findsOneWidget);
  });

  testWidgets('shows a not-measuring chip when the wearable is not delivering', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72, spo2: 98, coreTemp: 36.6)];
    await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples, bandNotMeasuring: true)));
    expect(find.text(_notMeasuring), findsOneWidget);
  });

  testWidgets('no chip when the wearable is measuring (the default)', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72, spo2: 98, coreTemp: 36.6)];
    await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples)));
    expect(find.text(_notMeasuring), findsNothing);
  });

  test('band link state drives the not-measuring flag', () {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    addTearDown(c.dispose);
    // No device wired this run → nothing to report.
    expect(c.isBandNotMeasuring, isFalse);
    c.onBandLinkState(BandLinkState.connecting);
    expect(c.isBandNotMeasuring, isTrue);
    c.onBandLinkState(BandLinkState.connected);
    expect(c.isBandNotMeasuring, isFalse);
    c.onBandLinkState(BandLinkState.lost);
    expect(c.isBandNotMeasuring, isTrue);
  });

  testWidgets('renders empty state with no samples', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HealthDashboardView(samples: [])));
    expect(find.text('No readings yet'), findsOneWidget);
  });

  testWidgets('renders metric cards (incl. merged blood pressure) and latest values', (tester) async {
    final samples = [
      HealthSample(at: t(0), heartRate: 72, spo2: 98, systolic: 118, diastolic: 76, coreTemp: 36.6),
      HealthSample(at: t(1), heartRate: 80, spo2: 97, systolic: 122, diastolic: 79, coreTemp: 36.8),
    ];
    await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples)));
    expect(find.text('Heart rate'), findsOneWidget);
    expect(find.text('Blood oxygen'), findsOneWidget);
    expect(find.text('Blood pressure'), findsOneWidget); // merged sys/dia card
    expect(find.text('80'), findsOneWidget); // latest HR
    // Temperature is in the second grid row — scroll the outer list into view.
    await tester.scrollUntilVisible(find.text('36.8'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('36.8'), findsOneWidget); // latest temp
  });

  testWidgets('share button copies a summary to the clipboard and confirms', (tester) async {
    final samples = [
      HealthSample(at: t(0), heartRate: 72, spo2: 98, systolic: 118, diastolic: 76, coreTemp: 36.6),
      HealthSample(at: t(1), heartRate: 80, spo2: 97, systolic: 122, diastolic: 79, coreTemp: 36.8),
      HealthSample(at: t(2), heartRate: 78, spo2: 98, systolic: 120, diastolic: 77, coreTemp: 36.7),
    ];
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples, greetingName: 'Aizhan')));
    await tester.tap(find.byIcon(Icons.ios_share_rounded));
    await tester.pump(); // start the snackbar
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Summary copied to clipboard'), findsOneWidget);
    expect(copied, isNotNull);
    expect(copied, contains('Heart rate:'));
    expect(copied, contains('Aizhan'));
  });

  testWidgets('no share button when there are no samples', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HealthDashboardView(samples: [])));
    expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
  });

  testWidgets('status chip shows the cycle/pregnancy label and taps through', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: HealthDashboardView(
        samples: samples,
        statusChip: 'Cycle · Day 14',
        onOpenStatus: () => opened = true,
      ),
    ));
    expect(find.text('Cycle · Day 14'), findsOneWidget);
    await tester.tap(find.text('Cycle · Day 14'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('a late period gets its own amber chip treatment', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    await tester.pumpWidget(MaterialApp(
      home: HealthDashboardView(
        samples: samples,
        statusChip: 'Period 3 days late',
        statusChipLate: true,
        onOpenStatus: () {},
      ),
    ));
    expect(find.text('Period 3 days late'), findsOneWidget);
    // Amber + a clock icon, distinct from the routine rose spa icon.
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.byIcon(Icons.spa_rounded), findsNothing);
  });

  testWidgets('an on-time cycle keeps the routine chip', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    await tester.pumpWidget(MaterialApp(
      home: HealthDashboardView(
        samples: samples,
        statusChip: 'Cycle · Day 14',
        onOpenStatus: () {},
      ),
    ));
    expect(find.byIcon(Icons.spa_rounded), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
  });

  testWidgets('weekly digest card shows the week roll-up', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    await tester.pumpWidget(MaterialApp(
      home: HealthDashboardView(
        samples: samples,
        weeklyDigest: const WeeklyDigest(
          daysLogged: 4, waterGlasses: 23, waterGoalDays: 2, avgSleepMin: 360, sleepNights: 3),
      ),
    ));
    await tester.scrollUntilVisible(find.text('This week'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // days logged
    // 360 min. The shared formatter drops a zero minutes component, so this
    // reads "6h" rather than the "6h 0m" the hand-written version produced.
    expect(find.text('6h'), findsOneWidget);
  });

  testWidgets('setup card reaches a brand-new user with no readings', (tester) async {
    // Regression: the checklist used to be stranded behind the populated
    // dashboard, so the one user who most needed it never saw it.
    await tester.pumpWidget(MaterialApp(
      home: HealthDashboardView(
        samples: const [],
        setupProgress: computeSetupProgress(
          hasName: false, hasHealthData: false, hasChild: false, hasZone: false, hasDetails: false, hasBackup: false),
      ),
    ));
    expect(find.text('No readings yet'), findsOneWidget); // still the empty state
    expect(find.text('Finish setting up'), findsOneWidget); // ...plus the guidance
    expect(find.text('Add your name in your profile'), findsOneWidget);
  });

  testWidgets('setup card sits above the metric grid, not below it', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    await tester.pumpWidget(MaterialApp(
      home: HealthDashboardView(
        samples: samples,
        setupProgress: computeSetupProgress(
          hasName: true, hasHealthData: false, hasChild: false, hasZone: false, hasDetails: false, hasBackup: false),
      ),
    ));
    // Visible without scrolling, and above the first metric card.
    expect(find.text('Finish setting up'), findsOneWidget);
    final setupY = tester.getTopLeft(find.text('Finish setting up')).dy;
    final metricY = tester.getTopLeft(find.text('Heart rate')).dy;
    expect(setupY, lessThan(metricY));
  });

  testWidgets('setup card shows progress and the next outstanding step', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: HealthDashboardView(
        samples: samples,
        setupProgress: computeSetupProgress(
          hasName: true, hasHealthData: true, hasChild: false, hasZone: false, hasDetails: false, hasBackup: false),
        onOpenSetup: () => opened = true,
      ),
    ));
    await tester.scrollUntilVisible(find.text('Finish setting up'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('2/6'), findsOneWidget); // 6 steps since birth date + city joined
    expect(find.text('Add a child'), findsOneWidget); // the next step
    await tester.tap(find.text('Finish setting up'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('setup card disappears once everything is done', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    await tester.pumpWidget(MaterialApp(
      home: HealthDashboardView(
        samples: samples,
        setupProgress: computeSetupProgress(
          hasName: true, hasHealthData: true, hasChild: true, hasZone: true, hasDetails: true, hasBackup: true),
      ),
    ));
    expect(find.text('Finish setting up'), findsNothing);
  });

  testWidgets('next appointment card shows the countdown and taps through', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    final now = DateTime(2026, 7, 15, 8);
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: HealthDashboardView(
        samples: samples,
        nextAppointment: Appointment(id: 'a', title: 'Ultrasound', at: DateTime(2026, 7, 20, 10)),
        nowForAppointment: now,
        onOpenAppointments: () => opened = true,
      ),
    ));
    await tester.scrollUntilVisible(find.text('Ultrasound'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('NEXT APPOINTMENT'), findsOneWidget);
    expect(find.text('in 5 days'), findsOneWidget); // Jul 15 → Jul 20
    await tester.tap(find.text('Ultrasound'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('weekly digest card hidden when there is no data', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    await tester.pumpWidget(MaterialApp(
      home: HealthDashboardView(
        samples: samples,
        weeklyDigest: const WeeklyDigest(daysLogged: 0, waterGlasses: 0, waterGoalDays: 0, avgSleepMin: 0, sleepNights: 0),
      ),
    ));
    expect(find.text('This week'), findsNothing);
  });

  testWidgets('status chip is hidden without an onOpenStatus callback', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    await tester.pumpWidget(MaterialApp(
      home: HealthDashboardView(samples: samples, statusChip: 'Cycle · Day 14'), // no onOpenStatus
    ));
    expect(find.text('Cycle · Day 14'), findsNothing);
  });

  testWidgets('water card adds a glass and reflects the goal', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    var count = 3;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => MaterialApp(
        home: HealthDashboardView(
          samples: samples,
          waterCount: count,
          waterGoal: 8,
          onAddWater: () => setState(() => count++),
          onRemoveWater: () => setState(() => count--),
          onSetWaterGoal: (_) {},
        ),
      ),
    ));
    await tester.scrollUntilVisible(find.text('Water'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('3 of 8 glasses'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(count, 4);
    expect(find.text('4 of 8 glasses'), findsOneWidget);
  });

  testWidgets('no water card when hydration is not wired', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples)));
    expect(find.text('Water'), findsNothing);
  });

  testWidgets('tapping the water ring opens the weekly history', (tester) async {
    final samples = [HealthSample(at: t(0), heartRate: 72), HealthSample(at: t(1), heartRate: 74)];
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: HealthDashboardView(
        samples: samples,
        waterCount: 4,
        waterGoal: 8,
        onAddWater: () {},
        onOpenWaterHistory: () => opened = true,
      ),
    ));
    await tester.scrollUntilVisible(find.text('Water'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byType(MetricRing).last); // the water ring
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('danger reading gets alert styling (semantics mentions safe range)', (tester) async {
    final samples = [
      HealthSample(at: t(0), systolic: 120, diastolic: 78),
      HealthSample(at: t(1), systolic: 150, diastolic: 96), // preeclampsia range
    ];
    await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples)));
    expect(
      find.bySemanticsLabel(RegExp('Blood pressure: 150 / 96 mmHg, outside the safe range')),
      findsOneWidget,
    );
  });

  group('the repeat-reading prompt', () {
    final samples = [
      HealthSample(at: t(0), heartRate: 72, spo2: 98, systolic: 152, diastolic: 96, coreTemp: 36.6),
    ];

    testWidgets('is absent when nothing is awaiting confirmation', (tester) async {
      await tester.pumpWidget(MaterialApp(home: HealthDashboardView(samples: samples)));
      expect(find.textContaining('Measure again'), findsNothing);
    });

    testWidgets('asks calmly for another reading, without claiming an emergency',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: HealthDashboardView(
          samples: samples, awaitingRepeat: 'bp', onLogVitals: () {},
        ),
      ));
      expect(find.text('Higher blood pressure than usual'), findsOneWidget);
      expect(find.text('Measure again'), findsOneWidget);
      // The wording is the whole point of the mechanism: one wrist estimate
      // must never be dressed up as a diagnosis or an emergency.
      for (final alarming in ['preeclampsia', 'emergency', 'urgent', 'danger']) {
        expect(
          find.textContaining(RegExp(alarming, caseSensitive: false)),
          findsNothing,
          reason: 'an unconfirmed reading must not say "$alarming"',
        );
      }
    });

    testWidgets('names the measurement it is about', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: HealthDashboardView(samples: samples, awaitingRepeat: 'fever'),
      ));
      expect(find.text('Higher temperature than usual'), findsOneWidget);
      expect(find.text('Higher blood pressure than usual'), findsNothing);
    });

    testWidgets('still explains itself when there is no way to log by hand',
        (tester) async {
      // Without onLogVitals there is no button, but the message must remain —
      // otherwise a user with no manual entry wired up sees nothing at all.
      await tester.pumpWidget(MaterialApp(
        home: HealthDashboardView(samples: samples, awaitingRepeat: 'bp'),
      ));
      expect(find.text('Higher blood pressure than usual'), findsOneWidget);
      expect(find.text('Measure again'), findsNothing);
    });
  });
}
