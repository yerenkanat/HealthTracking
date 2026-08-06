/// "The tracker is still low" is not news.
///
/// Opened on a real handset, the alert feed was twelve identical
/// «Низкий заряд трекера (8%)» entries — four on one day, four the next — and
/// nothing else was visible. That feed is also where an SOS and every zone
/// crossing land, so burying it is a safety problem dressed as a cosmetic one.
///
/// The raiser already had hysteresis on the READING: it fires when the level
/// worsens. What it missed is that "no previous reading" counts as worsening,
/// and that happens far more than once — a new child id, a reinstall, a
/// restore that did not carry the battery across. Each reset raised the same
/// warning again.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/geofence_alerts.dart';

SafetyAlert battery(String child, String pct, DateTime at) =>
    SafetyAlert(kind: AlertKind.lowBattery, childName: child, zoneName: pct, at: at);

void main() {
  final now = DateTime(2026, 8, 6, 12);

  group('whether a warning is worth raising', () {
    test('the first one always is', () {
      expect(batteryAlertIsNews(const [], 'Сұлтан', '8', now), isTrue);
    });

    test('the same level again within the quiet period is not', () {
      final feed = [battery('Сұлтан', '8', now.subtract(const Duration(hours: 2)))];
      expect(batteryAlertIsNews(feed, 'Сұлтан', '8', now), isFalse);
    });

    test('but the same level a day later is', () {
      // Still low tomorrow is worth saying once more; it is a tracker that has
      // not been charged, and she may not have seen yesterday's.
      final feed = [battery('Сұлтан', '8', now.subtract(const Duration(hours: 20)))];
      expect(batteryAlertIsNews(feed, 'Сұлтан', '8', now), isTrue);
    });

    test('a WORSE level is news immediately', () {
      // 20% → 5% is the transition that matters most and the one a blunt
      // "already warned" check would swallow.
      final feed = [battery('Сұлтан', '20', now.subtract(const Duration(minutes: 5)))];
      expect(batteryAlertIsNews(feed, 'Сұлтан', '5', now), isTrue);
    });

    test('another child is another tracker', () {
      final feed = [battery('Сұлтан', '8', now.subtract(const Duration(minutes: 5)))];
      expect(batteryAlertIsNews(feed, 'Аружан', '8', now), isTrue);
    });

    test('an SOS in between does not make the battery news again', () {
      // Only the last thing said ABOUT THIS CHILD'S BATTERY counts.
      final feed = [
        SafetyAlert(kind: AlertKind.sos, childName: 'Сұлтан', zoneName: '', at: now),
        battery('Сұлтан', '8', now.subtract(const Duration(hours: 1))),
      ];
      expect(batteryAlertIsNews(feed, 'Сұлтан', '8', now), isFalse);
    });
  });

  group('clearing out what earlier builds wrote', () {
    test('a run of identical warnings collapses to the newest', () {
      final feed = [
        battery('Сұлтан', '8', DateTime(2026, 8, 6)),
        battery('Сұлтан', '8', DateTime(2026, 8, 5)),
        battery('Сұлтан', '8', DateTime(2026, 8, 4)),
      ];
      final out = collapseBatteryAlerts(feed);

      expect(out, hasLength(1));
      expect(out.single.at, DateTime(2026, 8, 6), reason: 'the newest is the one still true');
    });

    test('a different level is a different fact', () {
      final feed = [
        battery('Сұлтан', '5', DateTime(2026, 8, 6)),
        battery('Сұлтан', '8', DateTime(2026, 8, 5)),
      ];
      expect(collapseBatteryAlerts(feed), hasLength(2));
    });

    test('two children keep their own warnings', () {
      final feed = [
        battery('Сұлтан', '8', DateTime(2026, 8, 6)),
        battery('Аружан', '8', DateTime(2026, 8, 6)),
      ];
      expect(collapseBatteryAlerts(feed), hasLength(2));
    });

    test('a repeated SOS is NOT collapsed', () {
      // Two SOS presses are two events. Collapsing them would hide the thing
      // this feed exists for.
      final feed = [
        SafetyAlert(kind: AlertKind.sos, childName: 'Сұлтан', zoneName: '', at: DateTime(2026, 8, 6, 12)),
        SafetyAlert(kind: AlertKind.sos, childName: 'Сұлтан', zoneName: '', at: DateTime(2026, 8, 6, 11)),
      ];
      expect(collapseBatteryAlerts(feed), hasLength(2));
    });

    test('and neither are repeated zone crossings', () {
      final feed = [
        SafetyAlert(kind: AlertKind.entered, childName: 'Сұлтан', zoneName: 'Дом', at: DateTime(2026, 8, 6, 12)),
        SafetyAlert(kind: AlertKind.entered, childName: 'Сұлтан', zoneName: 'Дом', at: DateTime(2026, 8, 5, 12)),
      ];
      expect(collapseBatteryAlerts(feed), hasLength(2));
    });

    test('warnings separated by something else both survive', () {
      // Only a consecutive run is a repeat; a warning either side of a real
      // event is a warning she saw in a different context.
      final feed = [
        battery('Сұлтан', '8', DateTime(2026, 8, 6)),
        SafetyAlert(kind: AlertKind.sos, childName: 'Сұлтан', zoneName: '', at: DateTime(2026, 8, 5, 12)),
        battery('Сұлтан', '8', DateTime(2026, 8, 4)),
      ];
      expect(collapseBatteryAlerts(feed), hasLength(3));
    });

    test('an untouched feed is returned unchanged', () {
      final feed = [battery('Сұлтан', '8', DateTime(2026, 8, 6))];
      expect(collapseBatteryAlerts(feed), hasLength(1));
      expect(collapseBatteryAlerts(const []), isEmpty);
    });
  });

  /// Through the controller, which is where the rule has to actually be
  /// applied — the helpers above are only correct if something calls them.
  group('the tracker reporting in', () {
    test('a battery that stays low is announced once, not once per report', () {
      var clock = DateTime(2026, 8, 6, 12);
      final c = AppController(now: () => clock);
      addTearDown(c.dispose);
      c.addChild(const ChildProfile(id: 'k1', name: 'Сұлтан', geofences: []));

      // A tracker checking in every few minutes, still not charged.
      for (var i = 0; i < 6; i++) {
        c.setChildBattery('k1', 8);
        clock = clock.add(const Duration(minutes: 20));
      }

      final warnings = c.alerts.where((a) => a.kind == AlertKind.lowBattery);
      expect(warnings, hasLength(1), reason: 'her feed filled with one repeated fact');
    });

    test('and once more when the SAME child arrives under a new id', () {
      // This is what actually filled the feed. The reading-level hysteresis
      // asks "was the previous percentage better", and a child whose id just
      // changed — a re-issued legacy id, a reinstall, a restore that lost the
      // battery — has no previous percentage at all. So every reset counted as
      // a fresh drop and said the same thing again.
      var clock = DateTime(2026, 8, 6, 12);
      final c = AppController(now: () => clock);
      addTearDown(c.dispose);

      c.addChild(const ChildProfile(id: 'old-id', name: 'Сұлтан', geofences: []));
      c.setChildBattery('old-id', 8);

      clock = clock.add(const Duration(minutes: 30));
      // Same tracker, same child, new id — and therefore no previous reading.
      c.addChild(const ChildProfile(id: 'new-id', name: 'Сұлтан', geofences: []));
      c.setChildBattery('new-id', 8);

      expect(c.alerts.where((a) => a.kind == AlertKind.lowBattery), hasLength(1),
          reason: 'the same 8% was announced twice');
    });

    test('and again when it gets worse', () {
      var clock = DateTime(2026, 8, 6, 12);
      final c = AppController(now: () => clock);
      addTearDown(c.dispose);
      c.addChild(const ChildProfile(id: 'k1', name: 'Сұлтан', geofences: []));

      c.setChildBattery('k1', 20);
      clock = clock.add(const Duration(minutes: 10));
      c.setChildBattery('k1', 4);

      expect(c.alerts.where((a) => a.kind == AlertKind.lowBattery), hasLength(2),
          reason: '20% → 4% is the transition that matters most');
    });
  });
}
