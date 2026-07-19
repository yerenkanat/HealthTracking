/// Widget tests for the safe-zones manager and the safety-alerts feed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/geofence_alerts.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/alerts_screen.dart';
import 'package:fcs_app/ui/tracking/zones_screen.dart';

final _home = Geofence.circle('home', 'Home', const Coordinates(43.238949, 76.889709), 100);
final _school = Geofence.circle('school', 'School', const Coordinates(43.25, 76.95), 120);

Widget wrap(Widget child) =>
    MaterialApp(home: L10nScope(l10n: const L10n(AppLocale.en), child: child));

void main() {
  group('ZonesScreen', () {
    AppController withZones() {
      final c = AppController();
      c.configureChild(name: 'Sultan', fences: [_home, _school]);
      return c;
    }

    testWidgets('lists a child\'s zones with radius + an add button', (tester) async {
      final c = withZones();
      await tester.pumpWidget(wrap(ZonesScreen(controller: c, childId: 'child-1')));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('School'), findsOneWidget);
      expect(find.textContaining('100 m'), findsOneWidget);
      expect(find.text('Add zone'), findsOneWidget);
      addTearDown(c.dispose);
    });

    testWidgets('zone rows show a visit count once entries are recorded', (tester) async {
      final c = withZones();
      // No visits yet → no badge.
      await tester.pumpWidget(wrap(ZonesScreen(controller: c, childId: 'child-1')));
      expect(find.textContaining('visits'), findsNothing);

      // Two entries into Home, one into School.
      c.onChildLocation(_home.center!);
      c.onChildLocation(_school.center!);
      c.onChildLocation(_home.center!);
      await tester.pumpWidget(wrap(ZonesScreen(controller: c, childId: 'child-1')));
      await tester.pumpAndSettle();
      expect(find.text('2 visits'), findsOneWidget); // Home
      expect(find.text('1 visits'), findsOneWidget); // School
      addTearDown(c.dispose);
    });

    testWidgets('deleting a zone asks for confirmation; cancel keeps it', (tester) async {
      final c = withZones();
      await tester.pumpWidget(wrap(ZonesScreen(controller: c, childId: 'child-1')));
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(find.text('Remove zone?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.selectedChild!.geofences.length, 2); // nothing removed
      addTearDown(c.dispose);
    });
  });

  group('AlertsScreen', () {
    testWidgets('empty state when there are no alerts', (tester) async {
      final c = AppController();
      await tester.pumpWidget(wrap(AlertsScreen(controller: c)));
      expect(find.textContaining('No alerts yet'), findsOneWidget);
      addTearDown(c.dispose);
    });

    testWidgets('shows zone enter/exit events newest-first with the child name', (tester) async {
      final c = AppController(now: () => DateTime(2026, 7, 16, 9));
      c.configureChild(name: 'Sultan', fences: [_home, _school]);
      c.onChildLocation(_home.center!); // entered Home
      c.onChildLocation(_school.center!); // left Home + entered School
      await tester.pumpWidget(wrap(AlertsScreen(controller: c)));
      expect(find.text('Entered School'), findsOneWidget);
      expect(find.text('Left Home'), findsOneWidget);
      expect(find.textContaining('Sultan'), findsWidgets);
      // Clear empties the feed.
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No alerts yet'), findsOneWidget);
      addTearDown(c.dispose);
    });

    testWidgets('filter chips narrow the feed to a category', (tester) async {
      final c = AppController(now: () => DateTime(2026, 7, 16, 9));
      c.configureChild(name: 'Sultan', fences: [_home, _school]);
      c.onChildLocation(_home.center!); // entered Home (zone)
      c.logChildEvent(AlertKind.sos); // an SOS
      await tester.pumpWidget(wrap(AlertsScreen(controller: c)));

      // Both categories shown initially.
      expect(find.text('Entered Home'), findsOneWidget);
      expect(find.text('SOS — emergency signal'), findsOneWidget);

      // Filter to SOS only.
      await tester.tap(find.widgetWithText(ChoiceChip, 'SOS'));
      await tester.pumpAndSettle();
      expect(find.text('SOS — emergency signal'), findsOneWidget);
      expect(find.text('Entered Home'), findsNothing);

      // Back to All.
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(find.text('Entered Home'), findsOneWidget);
      addTearDown(c.dispose);
    });

    testWidgets('today summary counts the day\'s activity', (tester) async {
      final now = DateTime(2026, 7, 16, 9);
      final c = AppController(now: () => now);
      c.configureChild(name: 'Sultan', fences: [_home, _school]);
      c.onChildLocation(_home.center!); // entered Home (a zone event)
      c.logChildEvent(AlertKind.checkIn); // a check-in
      await tester.pumpWidget(wrap(AlertsScreen(controller: c, now: () => now)));

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('zone events'), findsOneWidget);
      expect(find.text('check-ins'), findsOneWidget);
      addTearDown(c.dispose);
    });

    testWidgets('all-clear banner counts days since the last SOS', (tester) async {
      // SOS raised on Jul 10; viewing on Jul 16 → 6 days clear.
      final sosDay = DateTime(2026, 7, 10, 15);
      final viewDay = DateTime(2026, 7, 16, 9);
      final c = AppController(now: () => sosDay);
      c.configureChild(name: 'Sultan', fences: [_home]);
      c.logChildEvent(AlertKind.sos);
      await tester.pumpWidget(wrap(AlertsScreen(controller: c, now: () => viewDay)));
      expect(find.text('6 days without an SOS'), findsOneWidget);
      addTearDown(c.dispose);
    });

    testWidgets('no all-clear banner for a same-day SOS', (tester) async {
      final now = DateTime(2026, 7, 16, 9);
      final c = AppController(now: () => now);
      c.configureChild(name: 'Sultan', fences: [_home]);
      c.logChildEvent(AlertKind.sos);
      await tester.pumpWidget(wrap(AlertsScreen(controller: c, now: () => now)));
      expect(find.textContaining('without an SOS'), findsNothing);
      addTearDown(c.dispose);
    });

    testWidgets('per-child chips narrow the feed to one child', (tester) async {
      final c = AppController(now: () => DateTime(2026, 7, 16, 9));
      c.configureChild(name: 'Aisha', fences: [_home, _school]);
      c.addChild(const ChildProfile(id: 'child-2', name: 'Timur'));
      c.onChildLocation(_home.center!); // Aisha entered Home (child-1 selected)
      c.selectChild('child-2');
      c.logChildEvent(AlertKind.sos); // Timur SOS
      await tester.pumpWidget(wrap(AlertsScreen(controller: c)));

      // Both children's events are visible under "all children".
      expect(find.text('Entered Home'), findsOneWidget);
      expect(find.text('SOS — emergency signal'), findsOneWidget);

      // Filter to Aisha only.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Aisha'));
      await tester.pumpAndSettle();
      expect(find.text('Entered Home'), findsOneWidget);
      expect(find.text('SOS — emergency signal'), findsNothing);

      // Back to all children.
      await tester.tap(find.widgetWithText(ChoiceChip, 'All children'));
      await tester.pumpAndSettle();
      expect(find.text('SOS — emergency signal'), findsOneWidget);
      addTearDown(c.dispose);
    });
  });
}
