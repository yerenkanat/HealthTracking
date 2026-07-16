/// Widget tests for the Child Safety tips screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/child_tracker_state.dart' show Freshness;
import 'package:fcs_app/ui/tracking/child_safety_screen.dart';

void main() {
  testWidgets('school-age child at a zone shows status + age tips', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ChildSafetyScreen(
        childName: 'Sultan',
        ageMonths: 96, // ~8 years → school-age
        currentZone: 'School',
        freshness: Freshness.live,
        hasLocation: true,
      ),
    ));
    expect(find.text('Safety tips'), findsOneWidget);
    expect(find.text('In a safe zone'), findsOneWidget); // status tip, first
    expect(find.text('Safe route'), findsOneWidget); // age-band tip
    expect(find.text('Check-in times'), findsOneWidget);
  });

  testWidgets('no date of birth invites adding one', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ChildSafetyScreen(childName: 'Sultan', hasLocation: false),
    ));
    expect(find.text('Add a birth date'), findsOneWidget);
    expect(find.text('Safe route'), findsNothing); // no age → no age tips
  });

  testWidgets('stale location shows a warm delayed warning', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ChildSafetyScreen(
        childName: 'Sultan',
        ageMonths: 24,
        currentZone: 'Home',
        freshness: Freshness.stale,
        hasLocation: true,
      ),
    ));
    expect(find.text('Location delayed'), findsOneWidget);
    expect(find.text('In a safe zone'), findsNothing); // stale suppresses it
  });
}
