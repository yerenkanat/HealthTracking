/// Pictures of the three child-safety screens.
///
/// These are the densest floating-chrome screens in the app — pills, selectors
/// and action chips layered over a map — and they are exactly where a
/// half-applied surface language shows: a chip that kept a soft edge is
/// invisible to any assertion about text, and there was no golden covering any
/// of them.
///
/// The map itself is stubbed with the design system's striped placeholder,
/// which is also what a real device shows before tiles arrive.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/domain/battery.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/alerts_screen.dart';
import 'package:fcs_app/ui/tracking/child_map_screen.dart';
import 'package:fcs_app/ui/tracking/zones_screen.dart';

void main() {
  final home = Geofence.circle('home', 'Дом', const Coordinates(43.238949, 76.889709), 100);
  final school = Geofence.circle('school', 'Школа', const Coordinates(43.25, 76.95), 120);
  final now = DateTime.utc(2026, 7, 15, 9, 0);

  Future<void> shoot(WidgetTester tester, Widget screen, String name, {double h = 900}) async {
    tester.view.physicalSize = Size(402 * 3, h * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false, // otherwise it lands in the image
      theme: FcsTheme.light(AppLocale.ru),
      home: L10nScope(l10n: const L10n(AppLocale.ru), child: screen),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('golden: the child map', (tester) async {
    await shoot(
      tester,
      ChildMapScreen(
        childName: 'Сұлтан',
        childLocation: school.center,
        updatedAt: now.subtract(const Duration(minutes: 1)),
        fences: [home, school],
        now: now,
        // The striped placeholder, which is what the real screen shows until
        // map tiles load.
        mapBuilder: (_, __, ___) => const DsMapPlaceholder(caption: 'map', height: 420),
        batteryPct: 68,
        batteryHistory: const <BatteryReading>[],
        zoneEnteredAt: now.subtract(const Duration(minutes: 40)),
        lastCheckInAt: now.subtract(const Duration(hours: 2)),
        onCheckIn: () {},
        onSos: () {},
      ),
      'child_map',
    );
  });

  testWidgets('golden: safe zones', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await shoot(tester, ZonesScreen(controller: c, childId: 'demo'), 'zones', h: 700);
  });

  testWidgets('golden: the alerts feed', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await shoot(tester, AlertsScreen(controller: c), 'alerts', h: 700);
  });
}
