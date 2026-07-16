/// Widget tests for the safe-zones manager and the safety-alerts feed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
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
  });
}
