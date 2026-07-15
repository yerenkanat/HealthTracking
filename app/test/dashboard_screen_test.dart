/// Widget tests for the health dashboard (run with `flutter test`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';

void main() {
  DateTime t(int m) => DateTime.utc(2026, 7, 15, 8, m);

  testWidgets('renders empty state with no samples', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HealthDashboardScreen(samples: [])));
    expect(find.text('No readings yet'), findsOneWidget);
  });

  testWidgets('renders all five metric tiles and latest values', (tester) async {
    final samples = [
      HealthSample(at: t(0), heartRate: 72, spo2: 98, systolic: 118, diastolic: 76, coreTemp: 36.6),
      HealthSample(at: t(1), heartRate: 80, spo2: 97, systolic: 122, diastolic: 79, coreTemp: 36.8),
    ];
    await tester.pumpWidget(MaterialApp(home: HealthDashboardScreen(samples: samples)));
    expect(find.text('Heart rate'), findsOneWidget);
    expect(find.text('Blood oxygen'), findsOneWidget);
    expect(find.text('80'), findsOneWidget); // latest HR (first tile, on-screen)
    // The temperature tile is the 5th — scroll it into view before asserting.
    await tester.scrollUntilVisible(find.text('36.8'), 200, scrollable: find.byType(Scrollable));
    expect(find.text('36.8'), findsOneWidget); // latest temp
  });

  testWidgets('danger reading gets alert styling (semantics mentions safe range)', (tester) async {
    final samples = [
      HealthSample(at: t(0), systolic: 120, diastolic: 78),
      HealthSample(at: t(1), systolic: 150, diastolic: 96), // preeclampsia range
    ];
    await tester.pumpWidget(MaterialApp(home: HealthDashboardScreen(samples: samples)));
    expect(
      find.bySemanticsLabel(RegExp('Systolic: 150 mmHg, outside the safe range')),
      findsOneWidget,
    );
  });
}
