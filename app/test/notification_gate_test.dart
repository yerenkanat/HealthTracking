/// The one gate every OS notification passes through: [AppController.shouldDeliverAlert].
///
/// The defect these tests exist for: delivery was decided at each emit site by
/// `_notificationsEnabled` alone — a switch that Settings labels «Оповещения о
/// входе и выходе из зон». Turning off what reads as ZONE alerts also silenced
/// an SOS, while notif_sos_note, NotificationChannel.canBeMuted and
/// tool/verify_notification_prefs.dart all promised an emergency can never be
/// muted. The per-category switches and the quiet hours never reached an emit
/// site at all.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/domain/geofence_alerts.dart';
import 'package:fcs_app/domain/notification_prefs.dart';

final _home =
    Geofence.circle('home', 'Home', const Coordinates(43.238949, 76.889709), 100);

/// Every switch a mother has, off, plus quiet hours over the whole night.
const _everythingOff = NotificationPrefs(
  zoneEvents: false,
  checkIn: false,
  lowBattery: false,
  quietStart: 1320, // 22:00
  quietEnd: 420, // 07:00
);

const _night = NotificationPrefs(quietStart: 1320, quietEnd: 420);

AppController _at(DateTime clock) {
  final c = AppController(now: () => clock);
  c.configureChild(name: 'Sultan', fences: [_home]);
  return c;
}

/// What actually reached the OS-notification stream while [act] ran.
Future<List<SafetyAlert>> _delivered(
  AppController c,
  void Function() act,
) async {
  final fired = <SafetyAlert>[];
  final sub = c.newAlerts.listen(fired.add);
  act();
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  return fired;
}

void main() {
  final threeAM = DateTime(2026, 8, 11, 3, 0);
  final noon = DateTime(2026, 8, 11, 12, 0);

  test('an SOS delivers with every switch off, at 03:00, inside quiet hours', () async {
    final c = _at(threeAM);
    c.setNotificationsEnabled(false); // the «зоны» master switch
    c.setNotificationPrefs(_everythingOff);

    final fired = await _delivered(c, () => c.logChildEvent(AlertKind.sos));

    expect(fired.map((a) => a.kind), [AlertKind.sos]);
    c.dispose();
  });

  test('the master switch still silences a non-emergency', () async {
    final c = _at(noon);
    c.setNotificationsEnabled(false);

    final fired = await _delivered(c, () => c.logChildEvent(AlertKind.checkIn));

    expect(fired, isEmpty);
    // …but the in-app feed fills regardless.
    expect(c.alerts.where((a) => a.kind == AlertKind.checkIn).length, 1);
    c.dispose();
  });

  test('quiet hours hold a 03:00 battery warning', () async {
    final c = _at(threeAM);
    c.setNotificationPrefs(_night); // all categories still ON

    final id = c.selectedChild!.id;
    final fired = await _delivered(c, () => c.setChildBattery(id, 6));

    expect(fired, isEmpty);
    expect(c.alerts.where((a) => a.kind == AlertKind.lowBattery).length, 1);
    c.dispose();
  });

  test('the same battery warning at noon delivers', () async {
    final c = _at(noon);
    c.setNotificationPrefs(_night);

    final id = c.selectedChild!.id;
    final fired = await _delivered(c, () => c.setChildBattery(id, 6));

    expect(fired.map((a) => a.kind), [AlertKind.lowBattery]);
    c.dispose();
  });

  test('a muted category stays muted outside quiet hours', () async {
    final c = _at(noon);
    c.setNotificationPrefs(const NotificationPrefs(checkIn: false));

    final fired = await _delivered(c, () => c.logChildEvent(AlertKind.checkIn));

    expect(fired, isEmpty);
    expect(c.alerts.where((a) => a.kind == AlertKind.checkIn).length, 1);
    c.dispose();
  });

  test('a muted zone event is held on the location path too', () async {
    final c = _at(noon);
    c.setNotificationPrefs(const NotificationPrefs(zoneEvents: false));

    // A zone change takes two agreeing fixes (zone_hysteresis.dart).
    final fired = await _delivered(c, () {
      c.onChildLocation(_home.center!);
      c.onChildLocation(_home.center!);
    });

    expect(fired, isEmpty);
    expect(c.alerts.where((a) => a.kind == AlertKind.entered).length, 1);
    c.dispose();
  });

  test('a zone event delivers when its own switch is on', () async {
    final c = _at(noon);

    final fired = await _delivered(c, () {
      c.onChildLocation(_home.center!);
      c.onChildLocation(_home.center!);
    });

    expect(fired.map((a) => a.kind), [AlertKind.entered]);
    c.dispose();
  });

  test('shouldDeliverAlert itself: SOS true, everything else false, all off', () {
    final c = _at(threeAM);
    c.setNotificationsEnabled(false);
    c.setNotificationPrefs(_everythingOff);

    SafetyAlert a(AlertKind k) =>
        SafetyAlert(kind: k, childName: 'Sultan', zoneName: 'Home', at: threeAM);

    expect(c.shouldDeliverAlert(a(AlertKind.sos)), isTrue);
    expect(c.shouldDeliverAlert(a(AlertKind.entered)), isFalse);
    expect(c.shouldDeliverAlert(a(AlertKind.left)), isFalse);
    expect(c.shouldDeliverAlert(a(AlertKind.checkIn)), isFalse);
    expect(c.shouldDeliverAlert(a(AlertKind.lowBattery)), isFalse);
    c.dispose();
  });

  // ---- Scheduled reminders under the same master switch ----
  //
  // The switch reached only the three safety-alert emit sites, while its label
  // promises «Все, кроме экстренных: SOS придёт всегда». Everything the OS
  // raises LATER — the daily water and medication reminders, appointments,
  // vaccination visits, the cycle reminders — was armed regardless, so a mother
  // who turned notifications off still got her 20:00 water reminder.

  Future<List<int?>> daily(Stream<int?> s, void Function() act) async {
    final got = <int?>[];
    final sub = s.listen(got.add);
    act();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    return got;
  }

  Future<List<ReminderCommand>> scheduled(
      AppController c, void Function() act) async {
    final got = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(got.add);
    act();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    return got;
  }

  test('notifications off: the daily water reminder is never armed', () async {
    final c = _at(noon);
    c.setNotificationsEnabled(false);

    final got = await daily(c.waterReminderCommands, () => c.setWaterReminder(20 * 60));

    expect(got, [null], reason: 'null is "cancel"; 1200 would arm it at 20:00');
    // The setting itself is kept, so turning the switch back on restores it.
    expect(c.waterReminderMinutes, 20 * 60);
    c.dispose();
  });

  test('notifications off: the daily medication reminder is never armed', () async {
    final c = _at(noon);
    c.setNotificationsEnabled(false);

    final got = await daily(c.medReminderCommands, () => c.setMedReminder(9 * 60));

    expect(got, [null]);
    expect(c.medReminderMinutes, 9 * 60);
    c.dispose();
  });

  test('notifications off: a future appointment schedules nothing', () async {
    final c = _at(noon);
    c.setNotificationsEnabled(false);

    final got = await scheduled(
        c, () => c.addAppointment('Гинеколог', noon.add(const Duration(days: 1))));

    expect(got, hasLength(1));
    expect(got.single.at, isNull, reason: 'a schedule must degrade to a cancel');
    // The appointment still exists in the app — only the OS alarm is withheld.
    expect(c.appointments, hasLength(1));
    c.dispose();
  });

  test('turning the switch off cancels what is already armed, and on re-arms it',
      () async {
    final c = _at(noon);
    final tomorrow = noon.add(const Duration(days: 1));
    c.addAppointment('Гинеколог', tomorrow);
    c.setWaterReminder(20 * 60);

    final off = <ReminderCommand>[];
    final offDaily = <int?>[];
    var subs = [
      c.reminderCommands.listen(off.add),
      c.waterReminderCommands.listen(offDaily.add),
    ];
    c.setNotificationsEnabled(false);
    await Future<void>.delayed(Duration.zero);
    for (final s in subs) {
      await s.cancel();
    }
    expect(off.map((r) => r.id), contains(AppController.reminderIdFor(c.appointments.single.id)));
    expect(off.every((r) => r.at == null), isTrue, reason: 'cancels only');
    expect(offDaily, contains(null));

    final on = <ReminderCommand>[];
    final onDaily = <int?>[];
    subs = [
      c.reminderCommands.listen(on.add),
      c.waterReminderCommands.listen(onDaily.add),
    ];
    c.setNotificationsEnabled(true);
    await Future<void>.delayed(Duration.zero);
    for (final s in subs) {
      await s.cancel();
    }
    expect(on.where((r) => r.at == tomorrow), hasLength(1),
        reason: 'the appointment is armed again from the settings kept');
    expect(onDaily, contains(20 * 60));
    c.dispose();
  });

  test('an SOS still delivers while every scheduled reminder is withheld', () async {
    final c = _at(threeAM);
    c.setNotificationsEnabled(false);
    c.setWaterReminder(20 * 60);

    final fired = await _delivered(c, () => c.logChildEvent(AlertKind.sos));

    expect(fired.map((a) => a.kind), [AlertKind.sos]);
    c.dispose();
  });

  test('categoryOfAlert maps every kind, and only SOS to sos', () {
    expect(categoryOfAlert(AlertKind.sos), NotifyCategory.sos);
    expect(categoryOfAlert(AlertKind.entered), NotifyCategory.zoneEvents);
    expect(categoryOfAlert(AlertKind.left), NotifyCategory.zoneEvents);
    expect(categoryOfAlert(AlertKind.checkIn), NotifyCategory.checkIn);
    expect(categoryOfAlert(AlertKind.lowBattery), NotifyCategory.lowBattery);
  });
}
