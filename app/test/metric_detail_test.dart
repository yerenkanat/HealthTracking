/// Widget test for the metric detail screen (run with `flutter test`).
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/dashboard/metric_detail_screen.dart';

void main() {
  DateTime t(int m) => DateTime.utc(2026, 7, 15, 8, m);

  testWidgets('renders latest value, stats, and chart', (tester) async {
    final samples = [
      HealthSample(at: t(0), heartRate: 72),
      HealthSample(at: t(1), heartRate: 78),
      HealthSample(at: t(2), heartRate: 84),
    ];
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: MetricDetailScreen(
          metricKey: 'hr',
          unit: 'bpm',
          icon: Icons.favorite,
          color: const Color(0xFFFF5A7A),
          samples: samples,
        ),
      ),
    ));

    expect(find.text('Heart rate'), findsOneWidget); // app bar
    expect(find.text('84'), findsWidgets); // latest value (title + stat)
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets); // chart painted
  });

  testWidgets('shows empty-chart message with too few points', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: MetricDetailScreen(
          metricKey: 'hr', unit: 'bpm', icon: Icons.favorite, color: const Color(0xFFFF5A7A),
          samples: [HealthSample(at: t(0), heartRate: 72)],
        ),
      ),
    ));
    expect(find.text('Not enough data to chart yet'), findsOneWidget);
  });
}
