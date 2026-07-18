/// Widget tests for the child tracking screen (run with `flutter test`).
/// The real map is stubbed via mapBuilder so the status card can be tested.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/domain/battery.dart';
import 'package:fcs_app/ui/tracking/child_map_screen.dart';

void main() {
  final home = Geofence.circle('home', 'Home', const Coordinates(43.238949, 76.889709), 100);
  final school = Geofence.circle('school', 'School', const Coordinates(43.25, 76.95), 120);
  final now = DateTime.utc(2026, 7, 15, 9, 0);

  Widget harness({
    Coordinates? loc,
    DateTime? updated,
    VoidCallback? onCheckIn,
    VoidCallback? onSos,
    int? batteryPct,
    List<BatteryReading> batteryHistory = const [],
    DateTime? zoneEnteredAt,
    DateTime? lastCheckInAt,
  }) =>
      MaterialApp(
        home: ChildMapScreen(
          childName: 'Sultan',
          childLocation: loc,
          updatedAt: updated,
          fences: [home, school],
          now: now,
          mapBuilder: (_, __, ___) => const SizedBox(key: Key('map-stub')),
          onCheckIn: onCheckIn,
          onSos: onSos,
          batteryPct: batteryPct,
          batteryHistory: batteryHistory,
          zoneEnteredAt: zoneEnteredAt,
          lastCheckInAt: lastCheckInAt,
        ),
      );

  testWidgets('shows "at School" and Live pill when fresh & inside school', (tester) async {
    await tester.pumpWidget(harness(loc: school.center, updated: now.subtract(const Duration(minutes: 1))));
    expect(find.text('Sultan is at School'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Inside School zone'), findsOneWidget);
    expect(find.byKey(const Key('map-stub')), findsOneWidget);
  });

  testWidgets('shows Delayed pill and last-seen headline when stale', (tester) async {
    await tester.pumpWidget(harness(loc: home.center, updated: now.subtract(const Duration(hours: 3))));
    expect(find.text('Delayed'), findsOneWidget);
    expect(find.textContaining('last seen'), findsOneWidget);
  });

  testWidgets('shows waiting state when no location', (tester) async {
    await tester.pumpWidget(harness(loc: null, updated: null));
    expect(find.textContaining('Waiting for'), findsOneWidget);
  });

  testWidgets('check-in fires immediately and confirms', (tester) async {
    var checkedIn = 0;
    await tester.pumpWidget(harness(loc: home.center, updated: now, onCheckIn: () => checkedIn++, onSos: () {}));
    await tester.tap(find.text('Check in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(checkedIn, 1);
    expect(find.text('Check-in recorded'), findsOneWidget);
  });

  testWidgets('SOS asks to confirm; cancel does nothing, confirm sends', (tester) async {
    var sos = 0;
    await tester.pumpWidget(harness(loc: home.center, updated: now, onCheckIn: () {}, onSos: () => sos++));

    await tester.tap(find.text('SOS'));
    await tester.pumpAndSettle();
    expect(find.text('Send an SOS signal?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sos, 0);

    await tester.tap(find.text('SOS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send SOS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(sos, 1);
    expect(find.text('SOS signal sent'), findsOneWidget);
  });

  testWidgets('no action row when callbacks are not wired', (tester) async {
    await tester.pumpWidget(harness(loc: home.center, updated: now));
    expect(find.text('Check in'), findsNothing);
    expect(find.text('SOS'), findsNothing);
  });

  testWidgets('battery chip shows the tracker percentage', (tester) async {
    await tester.pumpWidget(harness(loc: home.center, updated: now, batteryPct: 62));
    expect(find.text('62%'), findsOneWidget);
  });

  testWidgets('no battery chip when battery is unknown', (tester) async {
    await tester.pumpWidget(harness(loc: home.center, updated: now));
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('battery chip opens a history sheet with recent readings', (tester) async {
    final history = [
      BatteryReading(now.subtract(const Duration(hours: 6)), 88),
      BatteryReading(now.subtract(const Duration(hours: 4)), 80),
      BatteryReading(now.subtract(const Duration(hours: 2)), 62),
    ];
    await tester.pumpWidget(harness(loc: home.center, updated: now, batteryPct: 62, batteryHistory: history));
    await tester.tap(find.text('62%'));
    await tester.pumpAndSettle();
    expect(find.text('Battery history'), findsOneWidget);
    expect(find.text('Down 26% over this period'), findsOneWidget); // 88 → 62
    expect(find.text('88%'), findsOneWidget); // an earlier reading in the list
  });

  testWidgets('battery chip is not tappable with fewer than two readings', (tester) async {
    await tester.pumpWidget(harness(loc: home.center, updated: now, batteryPct: 62, batteryHistory: [BatteryReading(now, 62)]));
    await tester.tap(find.text('62%'));
    await tester.pumpAndSettle();
    expect(find.text('Battery history'), findsNothing);
  });

  testWidgets('zone dwell chip shows how long the child has been in the zone', (tester) async {
    // Inside School, entered 2h 10m before now.
    await tester.pumpWidget(harness(
      loc: school.center,
      updated: now.subtract(const Duration(minutes: 1)),
      zoneEnteredAt: now.subtract(const Duration(hours: 2, minutes: 10)),
    ));
    expect(find.text('Inside School zone'), findsOneWidget);
    expect(find.text('for 2h 10m'), findsOneWidget);
  });

  testWidgets('no dwell chip when the entry time is unknown', (tester) async {
    await tester.pumpWidget(harness(loc: school.center, updated: now.subtract(const Duration(minutes: 1))));
    expect(find.text('Inside School zone'), findsOneWidget);
    expect(find.textContaining('for '), findsNothing);
  });

  testWidgets('shows the last check-in time when available', (tester) async {
    await tester.pumpWidget(harness(
      loc: home.center,
      updated: now.subtract(const Duration(minutes: 1)),
      lastCheckInAt: now.subtract(const Duration(hours: 2)),
    ));
    expect(find.textContaining('Checked in'), findsOneWidget);
  });

  testWidgets('no check-in row when never checked in', (tester) async {
    await tester.pumpWidget(harness(loc: home.center, updated: now.subtract(const Duration(minutes: 1))));
    expect(find.textContaining('Checked in'), findsNothing);
  });
}
