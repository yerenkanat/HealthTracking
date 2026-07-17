/// Widget tests for the health dashboard (run with `flutter test`).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';

void main() {
  DateTime t(int m) => DateTime.utc(2026, 7, 15, 8, m);

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
}
