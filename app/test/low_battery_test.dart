/// Unit tests for the low-battery alert emitted by setChildBattery.
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/geofence_alerts.dart';

void main() {
  AppController make() {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    c.addChild(ChildProfile(id: 'child-1', name: 'Sultan', geofences: [
      Geofence.circle('home', 'Home', const Coordinates(43.2, 76.8), 100),
    ]));
    return c;
  }

  test('dropping into the low range raises exactly one low-battery alert', () {
    final c = make();
    c.setChildBattery('child-1', 62); // ok → no alert
    expect(c.alerts.where((a) => a.kind == AlertKind.lowBattery), isEmpty);

    c.setChildBattery('child-1', 8); // crosses into low → one alert
    final low = c.alerts.where((a) => a.kind == AlertKind.lowBattery).toList();
    expect(low.length, 1);
    expect(low.first.childName, 'Sultan');
    expect(low.first.zoneName, '8'); // carries the percentage

    // Still low (and lower) → does NOT re-fire.
    c.setChildBattery('child-1', 5);
    expect(c.alerts.where((a) => a.kind == AlertKind.lowBattery).length, 1);

    c.dispose();
  });

  test('recovering then dropping again re-fires', () {
    final c = make();
    c.setChildBattery('child-1', 9); // low → alert 1
    c.setChildBattery('child-1', 80); // recovered
    c.setChildBattery('child-1', 10); // low again → alert 2
    expect(c.alerts.where((a) => a.kind == AlertKind.lowBattery).length, 2);
    c.dispose();
  });

  test('a first reading already low still alerts once', () {
    final c = make();
    c.setChildBattery('child-1', 7); // unknown → low → alert
    expect(c.alerts.where((a) => a.kind == AlertKind.lowBattery).length, 1);
    c.dispose();
  });

  test('emits on the notification stream for OS delivery', () async {
    final c = make();
    final fired = <SafetyAlert>[];
    final sub = c.newAlerts.listen(fired.add);
    c.setChildBattery('child-1', 6);
    await Future<void>.delayed(Duration.zero);
    expect(fired.where((a) => a.kind == AlertKind.lowBattery).length, 1);
    await sub.cancel();
    c.dispose();
  });
}
