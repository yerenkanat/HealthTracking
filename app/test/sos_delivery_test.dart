/// TODO §10.1–10.3 — the SOS path told her three untrue things.
///
/// One press, three separate lies, and they compound: she is told it was sent
/// when nothing left the phone, told the app has no idea where her child is
/// while holding the coordinates it was just handed, and shown a full-red
/// alarm about something that finished twelve hours ago.
///
/// WHAT WOULD FAIL IF EACH FIX WERE REVERTED, per group — the only property of
/// a test that matters:
///
///   * «отправлен» is a fact — restore `void logChildEvent` /
///     `onSos: VoidCallback?` and the snackbar prints «Сигнал SOS отправлен»
///     over an offline failure, a 5xx, a timeout and an expired session alike.
///   * the feed row — restore it and an SOS the family never received looks
///     identical in «Лента безопасности» to one they did.
///   * the retry — restore it and a signal that failed in a car park never
///     goes, even when the phone reconnects thirty seconds later.
///   * the coordinates — restore the dropped `NotifyTap.coords` and screen 21
///     prints «Приложение не получало координат» while holding them.
///   * the age gate — restore `raiseSosAlert` called directly and a tap at
///     21:00 on a 09:00 SOS raises red, a heavy haptic and `canPop: false`.
///
/// The live case is the pin throughout: a staleness rule that swallows a real
/// SOS would be a far worse defect than the one being fixed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/domain/child_emergency.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/geofence_alerts.dart';
import 'package:fcs_app/domain/notification_route.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/main.dart' show handleNotificationTap;
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/alerts_screen.dart';
import 'package:fcs_app/ui/tracking/child_map_screen.dart';
import 'package:fcs_app/ui/tracking/sos_alert_screen.dart';

const ru = L10n(AppLocale.ru);

/// 21:00 — the evening she clears her notification tray.
final now = DateTime(2026, 8, 19, 21, 0);

/// The press, at nine that morning. Seen, answered, over.
final thisMorning = DateTime(2026, 8, 19, 9, 0);

/// Four minutes ago. This is happening.
final justNow = now.subtract(const Duration(minutes: 4));

/// Her child's school, and a position near it.
const school = Coordinates(43.25, 76.95);
const parkGate = Coordinates(43.2402, 76.9111);

AppController controllerWithChild(DateTime clock, {String name = 'Алия'}) {
  final c = AppController(now: () => clock, locale: AppLocale.ru);
  c.debugMarkOnboarded();
  c.configureChild(
    name: name,
    fences: [Geofence.circle('school', 'Мектеп №25', school, 120)],
  );
  return c;
}

/// The payload the SERVER sends for an SOS, built the way push.ts builds it —
/// ISO-8601 UTC, `lat`/`lng` as strings, because an FCM data block is
/// Record<string,string>. Hand-typed here rather than reused from
/// `sosNotificationPayload`, which cannot carry coordinates at all: the point
/// of §10.2 is that the SERVER sends a field this app dropped.
String serverSosPayload({
  String childName = 'Алия',
  DateTime? at,
  Coordinates? coords,
  String zoneName = '',
}) =>
    '{"screen":"SosAlert","childId":"srv-1"'
    '${childName.isEmpty ? '' : ',"childName":"$childName"'}'
    '${at == null ? '' : ',"at":"${at.toUtc().toIso8601String()}"'}'
    '${zoneName.isEmpty ? '' : ',"zoneName":"$zoneName"'}'
    '${coords == null ? '' : ',"lat":"${coords.lat}","lng":"${coords.lng}"'}'
    '}';

/// L10nScope ABOVE MaterialApp. Below the Navigator it silently falls back to
/// English and every Russian assertion here would be asserting the wrong
/// language — including the two that are the whole point of the file.
Widget host(Widget child, {AppLocale locale = AppLocale.ru}) => L10nScope(
      l10n: L10n(locale),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: FcsTheme.light(locale),
        home: child,
      ),
    );

Widget mapScreen({required Future<bool> Function() onSos}) => ChildMapScreen(
      childName: 'Алия',
      childLocation: school,
      updatedAt: now.subtract(const Duration(minutes: 2)),
      fences: [Geofence.circle('school', 'Мектеп №25', school, 120)],
      now: now,
      mapBuilder: (_, __, ___) => const SizedBox(key: Key('map-stub')),
      onSos: onSos,
    );

/// Tap SOS and confirm the dialog. Returns with the send in flight settled.
Future<void> pressSos(WidgetTester tester) async {
  await tester.tap(find.text(ru.t('child_sos')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(ru.t('sos_confirm_send')));
  // NOT pumpAndSettle: the pending snackbar is deliberately long-lived, and
  // settling would wait it out rather than watch it be replaced.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // ---- §10.1 · «отправлен» has to be a fact -------------------------------

  group('an SOS that did not reach the server is not reported as sent', () {
    test('with no sync attached at all — she is signed out', () async {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      expect(await c.logChildEvent(AlertKind.sos), isFalse,
          reason: 'signed out is not a send; the family were not told');
      expect(c.alerts.single.delivered, isFalse);
    });

    test('when the push throws — offline, 5xx, timeout, expired session',
        () async {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      c.attachAlertSync(upsert: (_) async => throw Exception('no route to host'));
      expect(await c.logChildEvent(AlertKind.sos), isFalse);
      expect(c.alerts.single.delivered, isFalse);
    });

    test('when the sink itself reports a refusal — the unmatched-child drop',
        () async {
      // main.dart drops an alert whose child name matches no synced child
      // BEFORE the request is attempted. It used to `return;`, which was
      // indistinguishable from success all the way up to the snackbar.
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      c.attachAlertSync(upsert: (_) async => false);
      expect(await c.logChildEvent(AlertKind.sos), isFalse);
      expect(c.alerts.single.delivered, isFalse);
    });

    test('and when it DID land, it says so and the row is clean', () async {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      final sent = <SafetyAlert>[];
      c.attachAlertSync(upsert: (a) async {
        sent.add(a);
        return true;
      });
      expect(await c.logChildEvent(AlertKind.sos), isTrue);
      expect(sent.single.kind, AlertKind.sos);
      expect(c.alerts.single.delivered, isTrue,
          reason: 'the ordinary case must be completely unchanged');
    });

    test('a check-in follows the same rule', () async {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      c.attachAlertSync(upsert: (_) async => false);
      expect(await c.logChildEvent(AlertKind.checkIn), isFalse);
      expect(c.alerts.single.delivered, isFalse);
    });
  });

  group('the confirmation on screen 12 says which of the two happened', () {
    testWidgets('a failed send does NOT print «Сигнал SOS отправлен»',
        (tester) async {
      await tester.pumpWidget(host(mapScreen(onSos: () async => false)));
      await pressSos(tester);

      expect(find.text(ru.t('sos_sent')), findsNothing,
          reason: 'this is the sentence the whole defect consisted of');
      expect(find.text(ru.t('sos_not_sent')), findsOneWidget);
      // It must not merely withhold the good news — it has to tell her what to
      // do instead, because nothing else is going to reach her family.
      expect(ru.t('sos_not_sent'), contains('103'));
    });

    testWidgets('a successful send still prints it', (tester) async {
      await tester.pumpWidget(host(mapScreen(onSos: () async => true)));
      await pressSos(tester);
      expect(find.text(ru.t('sos_sent')), findsOneWidget);
      expect(find.text(ru.t('sos_not_sent')), findsNothing);
    });

    testWidgets('while it is in flight it claims nothing', (tester) async {
      // A slow request is the ordinary case in a car park. Neither sentence may
      // be on screen while the answer is unknown.
      final gate = Completer<bool>();
      await tester.pumpWidget(host(mapScreen(onSos: () => gate.future)));
      await tester.tap(find.text(ru.t('child_sos')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ru.t('sos_confirm_send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(ru.t('sos_sent')), findsNothing);
      expect(find.text(ru.t('sos_not_sent')), findsNothing);
      expect(find.text(ru.t('sos_sending')), findsOneWidget);

      gate.complete(false);
      await tester.pump();
      // The pending bar has to animate OUT before the answer animates in, so
      // this needs longer than a single transition. Explicit durations rather
      // than pumpAndSettle: the answer's own bar is a timed one.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(ru.t('sos_sending')), findsNothing);
      expect(find.text(ru.t('sos_not_sent')), findsOneWidget);
    });

    testWidgets('the Kazakh exists and is not the Russian', (tester) async {
      // Nothing user-visible ships without it. (The Kazakh in this block was
      // written with the widget, not by the language gate — TODO §9.12.)
      for (final key in ['sos_sending', 'sos_not_sent', 'alert_not_sent']) {
        final kk = const L10n(AppLocale.kk).t(key);
        expect(kk, isNotEmpty);
        expect(kk, isNot(ru.t(key)));
      }
    });
  });

  group('the safety feed marks what never left the phone', () {
    testWidgets('an undelivered SOS carries «не отправлено»', (tester) async {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      await c.logChildEvent(AlertKind.sos); // no sync attached → not sent
      c.dismissSos(); // close the takeover so the feed is what is on screen

      await tester.pumpWidget(host(AlertsScreen(controller: c, now: () => now)));
      await tester.pumpAndSettle();

      expect(find.text(ru.t('alert_not_sent')), findsOneWidget,
          reason: 'a row that looks the same either way is the same lie, one '
              'screen later');
    });

    testWidgets('a delivered one does not', (tester) async {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      c.attachAlertSync(upsert: (_) async => true);
      await c.logChildEvent(AlertKind.sos);
      c.dismissSos();

      await tester.pumpWidget(host(AlertsScreen(controller: c, now: () => now)));
      await tester.pumpAndSettle();

      expect(find.text(ru.t('alert_not_sent')), findsNothing);
      expect(find.text(ru.t('alert_sos')), findsOneWidget,
          reason: 'the row itself must still be there — this asserts the '
              'absence is not the whole list being empty');
    });

    test('a zone crossing is never marked — it is derived on the server', () {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      c.mergeRemoteAlerts([
        SafetyAlert(
            kind: AlertKind.entered,
            childName: 'Алия',
            zoneName: 'Мектеп №25',
            at: justNow),
      ]);
      expect(c.alerts.single.delivered, isTrue);
    });

    test('a row stored before the field existed reads as delivered', () {
      // «Мы не знаем» must not render as «не отправлено» on a month of history.
      final a = SafetyAlert.fromJson({
        'kind': 'sos',
        'childName': 'Алия',
        'zoneName': '',
        'at': thisMorning.toIso8601String(),
      });
      expect(a.delivered, isTrue);
      // …and a row that DID record a failure survives a restart.
      final failed = SafetyAlert(
          kind: AlertKind.sos,
          childName: 'Алия',
          zoneName: '',
          at: thisMorning,
          delivered: false);
      expect(SafetyAlert.fromJson(failed.toJson()).delivered, isFalse);
    });
  });

  group('what is owed after the failure: a bounded retry', () {
    test('reconnecting re-sends it, and the row stops saying «не отправлено»',
        () async {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      var up = false;
      final attempts = <SafetyAlert>[];
      c.attachAlertSync(upsert: (a) async {
        attempts.add(a);
        return up;
      });
      c.setOnline(false);
      expect(await c.logChildEvent(AlertKind.sos), isFalse);
      expect(c.alerts.single.delivered, isFalse);

      up = true;
      c.setOnline(true);
      await pumpEventQueue();

      expect(attempts, hasLength(2), reason: 'it was never retried');
      expect(c.alerts.single.delivered, isTrue);
      expect(c.alerts.where((a) => !a.delivered), isEmpty);
    });

    test('signing in re-sends what was pressed while signed out', () async {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      expect(await c.logChildEvent(AlertKind.sos), isFalse);

      final attempts = <SafetyAlert>[];
      c.attachAlertSync(upsert: (a) async {
        attempts.add(a);
        return true;
      });
      await pumpEventQueue();

      expect(attempts, hasLength(1));
      expect(c.alerts.single.delivered, isTrue);
    });

    test('but it never replays an SOS that is over', () async {
      // The mirror of the "no first-sync replay" decision in main.dart. An
      // unbounded outbox would run the family fan-out — every relative's phone
      // screaming — about a child who came home hours ago.
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      final attempts = <SafetyAlert>[];
      c.attachAlertSync(upsert: (a) async {
        attempts.add(a);
        return false;
      });
      c.mergeRemoteAlerts(const []); // no-op; keeps the feed empty
      // Press it, then move the clock past the window.
      await c.logChildEvent(AlertKind.sos);
      attempts.clear();

      final later = AppController(
          now: () => now.add(AppController.sosTakeoverMaxAge +
              const Duration(minutes: 1)),
          locale: AppLocale.ru);
      addTearDown(later.dispose);
      later.debugMarkOnboarded();
      later.configureChild(name: 'Алия', fences: const []);
      later.mergeRemoteAlerts([
        SafetyAlert(
            kind: AlertKind.sos,
            childName: 'Алия',
            zoneName: '',
            at: now,
            delivered: false),
      ]);
      final lateAttempts = <SafetyAlert>[];
      later.attachAlertSync(upsert: (a) async {
        lateAttempts.add(a);
        return true;
      });
      await pumpEventQueue();
      expect(lateAttempts, isEmpty,
          reason: 'a retry with no age bound is the replay this app already '
              'refused once');
      expect(later.alerts.where((a) => !a.delivered), hasLength(1),
          reason: 'and the row keeps saying so, which is true');
    });
  });

  // ---- §10.2 · the coordinates the push carried ---------------------------

  group('a tapped SOS uses the position the notification carried', () {
    /// Two children. She is TRACKING the elder — so the only polled fix on the
    /// phone is the elder's — and the younger presses SOS.
    AppController twoChildren() {
      final c = controllerWithChild(now, name: 'Дана'); // elder, selected
      c.addChild(const ChildProfile(id: 'kid-2', name: 'Алия'));
      c.setEmergencyInfo(
        'kid-2',
        const ChildEmergencyInfo(
            contactName: 'Нұржан', contactPhone: '+77011234567'),
      );
      c.onChildLocation(school, at: now.subtract(const Duration(minutes: 2)));
      return c;
    }

    test('the younger child\'s SOS carries the younger child\'s position', () {
      final c = twoChildren();
      addTearDown(c.dispose);
      handleNotificationTap(
        c,
        serverSosPayload(childName: 'Алия', at: justNow, coords: parkGate),
      );
      expect(c.route, AppRoute.sos);
      expect(c.sos!.childName, 'Алия');
      expect(c.sos!.coords?.lat, parkGate.lat);
      expect(c.sos!.coords?.lng, parkGate.lng);
      expect(c.sos!.coordsAt, justNow,
          reason: 'the card prints the age of the position; inventing that '
              'age would be inventing a freshness');
    });

    test('the tracked sibling\'s fix is still never borrowed', () {
      final c = twoChildren();
      addTearDown(c.dispose);
      handleNotificationTap(c, serverSosPayload(childName: 'Алия', at: justNow));
      expect(c.route, AppRoute.sos);
      expect(c.sos!.coords, isNull,
          reason: 'no coordinates in the payload and none for this child — '
              'the honest wording is the right answer here');
    });

    test('a fresher polled fix for the SAME child still wins', () {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      c.onChildLocation(school, at: now.subtract(const Duration(minutes: 1)));
      handleNotificationTap(
        c,
        serverSosPayload(
            childName: 'Алия',
            at: now.subtract(const Duration(minutes: 10)),
            coords: parkGate),
      );
      expect(c.sos!.coords?.lat, school.lat,
          reason: 'whichever we can PROVE is newer, never whichever is handier');
    });

    testWidgets('screen 21 prints the position instead of «не получало координат»',
        (tester) async {
      final c = twoChildren();
      addTearDown(c.dispose);
      handleNotificationTap(
        c,
        serverSosPayload(childName: 'Алия', at: justNow, coords: parkGate),
      );
      final view = c.sos!;

      await tester.pumpWidget(host(SosAlertScreen(
        childName: view.childName,
        at: view.at,
        now: () => now,
        zoneName: view.zoneName,
        coords: view.coords,
        coordsAt: view.coordsAt,
        contactName: view.contactName,
        contactPhone: view.contactPhone,
        onCall: (_) async => true,
        onDismissConfirmed: () async {},
      )));
      await tester.pumpAndSettle();

      expect(find.text(ru.t('sos21_where_unknown')), findsNothing,
          reason: 'that sentence was false — the position was in the payload '
              'she had just tapped');
      expect(
          find.text('${parkGate.lat.toStringAsFixed(5)}, '
              '${parkGate.lng.toStringAsFixed(5)}'),
          findsOneWidget);
    });

    testWidgets('and keeps the honest wording when there really are none',
        (tester) async {
      await tester.pumpWidget(host(SosAlertScreen(
        childName: 'Алия',
        at: justNow,
        now: () => now,
        onCall: (_) async => true,
        onDismissConfirmed: () async {},
      )));
      await tester.pumpAndSettle();
      expect(find.text(ru.t('sos21_where_unknown')), findsOneWidget);
    });
  });

  // ---- §10.3 · the age of a tapped SOS ------------------------------------

  group('a tapped SOS from this morning does not seize the screen', () {
    test('twelve hours later it opens the feed, not the red takeover', () {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      handleNotificationTap(c, serverSosPayload(at: thisMorning));

      expect(c.route, AppRoute.home,
          reason: 'red, a heavy haptic, an assertive announcement and '
              'canPop: false, about something that finished at nine');
      expect(c.takePendingDestination(), NotifyDestination.notificationCentre);
    });

    test('and it is still READABLE — the event lands on the feed, dated', () {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      handleNotificationTap(c, serverSosPayload(at: thisMorning));
      expect(c.alerts.single.kind, AlertKind.sos);
      expect(c.alerts.single.at, thisMorning,
          reason: 'the sender\'s time, never the moment of the tap');
    });

    test('one it cannot date raises nothing and invents nothing', () {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      handleNotificationTap(c, serverSosPayload(at: null));

      expect(c.route, AppRoute.home,
          reason: 'not knowing is not permission to assume «сейчас»');
      expect(c.alerts, isEmpty,
          reason: 'it used to write `at: DateTime.now()` — a press at 09:00 '
              'listed, and printed on screen 21, as «в 21:14 · только что»');
      expect(c.takePendingDestination(), NotifyDestination.notificationCentre);
    });
  });

  group('a live SOS is completely unchanged — this is the pin', () {
    test('four minutes ago still takes the screen over', () {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      handleNotificationTap(c, serverSosPayload(at: justNow));
      expect(c.route, AppRoute.sos);
      expect(c.sos!.at, justNow);
      expect(c.pendingDestination, isNull,
          reason: 'nothing may be staged behind the takeover');
    });

    test('at the edge of the window it is still live', () {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      handleNotificationTap(
          c, serverSosPayload(at: now.subtract(sosTakeoverMaxAge)));
      expect(c.route, AppRoute.sos);
    });

    test('a minute past the edge it is not', () {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      handleNotificationTap(
          c,
          serverSosPayload(
              at: now.subtract(sosTakeoverMaxAge + const Duration(minutes: 1))));
      expect(c.route, isNot(AppRoute.sos));
    });

    test('ordinary phone-vs-server skew is not staleness', () {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      handleNotificationTap(
          c, serverSosPayload(at: now.add(const Duration(minutes: 1))));
      expect(c.route, AppRoute.sos,
          reason: 'two clocks disagreeing slightly must not silence an alarm');
    });

    test('tapping the SAME live SOS twice opens it both times', () {
      final c = controllerWithChild(now);
      addTearDown(c.dispose);
      final payload = serverSosPayload(at: justNow);
      handleNotificationTap(c, payload);
      c.dismissSos();
      handleNotificationTap(c, payload);
      expect(c.route, AppRoute.sos,
          reason: 'the second tap deduplicated against the feed and, without '
              'the direct raise, would open nothing');
    });
  });

  test('there is ONE notion of a stale SOS, not two', () {
    // The window a tap is measured against and the window mergeRemoteAlerts
    // uses are the same constant. Two numbers for one event would mean an
    // alarm the app refuses to raise on sign-in is raised by a tap on the
    // notification about that same event.
    expect(AppController.sosTakeoverMaxAge, sosTakeoverMaxAge);
    // …and it is deliberately NOT the medical one. See notification_route.dart
    // for the justification; this pins that they were considered together.
    expect(sosTakeoverMaxAge, isNot(emergencyTakeoverMaxAge));
  });
}
