/// Widget tests for the per-child detail/overview screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/domain/geofence_alerts.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/child_detail_screen.dart';

void main() {
  final home = Geofence.circle('home', 'Home', const Coordinates(43.238949, 76.889709), 100);
  final school = Geofence.circle('school', 'School', const Coordinates(43.25, 76.95), 120);
  final now = DateTime(2026, 7, 16, 12);

  AppController seeded() {
    final c = AppController(now: () => now);
    c.configureChild(name: 'Sultan', fences: [home, school]);
    return c;
  }

  Widget wrap(AppController c) => MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: ChildDetailScreen(controller: c, childId: 'child-1', now: () => now),
        ),
      );

  testWidgets('shows the child name and their zone count', (tester) async {
    final c = seeded();
    await tester.pumpWidget(wrap(c));
    expect(find.text('Sultan'), findsOneWidget);
    expect(find.text('SAFE ZONES'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // two zones
    addTearDown(c.dispose);
  });

  testWidgets('quiet state before any activity', (tester) async {
    final c = seeded();
    await tester.pumpWidget(wrap(c));
    expect(find.text('No activity recorded yet.'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('surfaces battery, check-in and visited zones', (tester) async {
    final c = seeded();
    c.setChildBattery('child-1', 62);
    c.logChildEvent(AlertKind.checkIn);
    c.onChildLocation(home.center!); // entered Home
    await tester.pumpWidget(wrap(c));

    expect(find.text('Tracker battery'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('Last check-in'), findsOneWidget);
    expect(find.text('Last activity'), findsOneWidget);
    // Visited zone with its count.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('1 visits'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('alert count reflects only this child', (tester) async {
    final c = seeded();
    c.logChildEvent(AlertKind.checkIn);
    c.logChildEvent(AlertKind.sos);
    await tester.pumpWidget(wrap(c));
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('2'), findsWidgets); // 2 alerts (also 2 zones)
    addTearDown(c.dispose);
  });

  testWidgets('handles the child being deleted underneath it', (tester) async {
    final c = seeded();
    await tester.pumpWidget(wrap(c));
    expect(find.text('Sultan'), findsOneWidget);

    c.removeChild('child-1');
    await tester.pumpAndSettle();
    expect(find.text('This child is no longer in your list.'), findsOneWidget);
    addTearDown(c.dispose);
  });
}
