/// A picture of the Home screen.
///
/// The design-system conversion changes how every surface on this screen looks —
/// the card outline, the icon chips, the stat tiles — and none of that is
/// visible to a test that only asks whether a string is present. This renders
/// the real dashboard with real data and stores the image, so a change to the
/// shared primitives shows up as a diff someone has to look at.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/sleep.dart';
import 'package:fcs_app/domain/wearable_metrics.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  DateTime t(int m) => DateTime.utc(2026, 7, 15, 8, m);

  testWidgets('golden: the home screen', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 1500 * 3); // the spec's canvas
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final samples = [
      for (var i = 0; i < 12; i++)
        HealthSample(at: t(i * 5), heartRate: 70 + i % 7, spo2: 97 + i % 2, coreTemp: 36.5 + (i % 3) * 0.1),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: HealthDashboardView(
        samples: samples,
        greetingName: 'Айгерім',
        sleepNights: [
          SleepSummary(night: DateTime(2026, 7, 15), deepMin: 95, remMin: 70, lightMin: 280, awakeMin: 12),
        ],
        wearable: WearableMetrics(
          at: t(0), steps: 8200, meters: 6100, kcal: 420,
          sleepMinutes: 465, stress: 34, breathRate: 15, worn: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(HealthDashboardView),
      matchesGoldenFile('goldens/home_dashboard.png'),
    );
  });
}
