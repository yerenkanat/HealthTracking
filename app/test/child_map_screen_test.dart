/// Widget tests for the child tracking screen (run with `flutter test`).
/// The real map is stubbed via mapBuilder so the status card can be tested.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/ui/tracking/child_map_screen.dart';

void main() {
  final home = Geofence.circle('home', 'Home', const Coordinates(43.238949, 76.889709), 100);
  final school = Geofence.circle('school', 'School', const Coordinates(43.25, 76.95), 120);
  final now = DateTime.utc(2026, 7, 15, 9, 0);

  Widget harness({Coordinates? loc, DateTime? updated}) => MaterialApp(
        home: ChildMapScreen(
          childName: 'Sultan',
          childLocation: loc,
          updatedAt: updated,
          fences: [home, school],
          now: now,
          mapBuilder: (_, __, ___) => const SizedBox(key: Key('map-stub')),
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
}
