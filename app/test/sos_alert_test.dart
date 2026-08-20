/// Screen 21 «Сигнал SOS», and screen 38's other half — where a tapped
/// notification goes.
///
/// These are one feature. An SOS push that opens nothing is the same defect as
/// no screen at all, so the tests run the whole chain: the button is pressed →
/// the controller latches a takeover → `FcsApp` renders it → the notification
/// it fired carries a payload → tapping that payload raises the same screen.
///
/// What each group would fail on if the change were reverted is written above
/// it, because that is the only property of a test that matters.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/app/app.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/data/content_store.dart';
import 'package:fcs_app/domain/child_emergency.dart';
import 'package:fcs_app/domain/geofence_alerts.dart';
import 'package:fcs_app/domain/notification_route.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/main.dart' show handleNotificationTap;
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/child_map_screen.dart';
import 'package:fcs_app/ui/tracking/sos_alert_screen.dart';
import 'package:fcs_app/ui/widgets/call_ambulance.dart';

const ru = L10n(AppLocale.ru);
const kk = L10n(AppLocale.kk);

/// A controller with one child, a medical-ID card naming who to call, and a
/// known position — the state a real SOS arrives into.
AppController controllerWithChild(
  DateTime now, {
  String contactName = 'Нұржан',
  String contactPhone = '+77011234567',
  bool withLocation = true,
}) {
  final c = AppController(now: () => now);
  c.debugMarkOnboarded();
  c.configureChild(
    name: 'Алия',
    fences: [
      Geofence.circle('school', 'Мектеп №25', const Coordinates(43.25, 76.95), 120),
    ],
  );
  final child = c.selectedChild!;
  if (contactPhone.isNotEmpty || contactName.isNotEmpty) {
    c.setEmergencyInfo(
      child.id,
      ChildEmergencyInfo(contactName: contactName, contactPhone: contactPhone),
    );
  }
  if (withLocation) {
    c.onChildLocation(const Coordinates(43.25, 76.95), at: now.subtract(const Duration(minutes: 4)));
  }
  return c;
}

Widget host(Widget child, {AppLocale locale = AppLocale.ru, double textScale = 1.0}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: FcsTheme.light(locale),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: L10nScope(l10n: L10n(locale), child: child),
        ),
      ),
    );

void main() {
  final now = DateTime(2026, 8, 13, 16, 45);
  final pressed = DateTime(2026, 8, 13, 16, 41);

  // ---- The screen itself -------------------------------------------------
  //
  // Without sos_alert_screen.dart there is nothing here to render at all.

  testWidgets('it names who pressed the button, when, and where', (tester) async {
    await tester.pumpWidget(host(SosAlertScreen(
      childName: 'Алия',
      at: pressed,
      now: () => now,
      zoneName: 'Мектеп №25',
      coords: const Coordinates(43.25, 76.95),
      coordsAt: now.subtract(const Duration(minutes: 4)),
      contactName: 'Нұржан',
      contactPhone: '+77011234567',
      onCall: (_) async => true,
      onDismissConfirmed: () async {},
    )));

    expect(find.text(ru.t('sos21_label').toUpperCase()), findsOneWidget);
    expect(find.text('Алия нажала кнопку SOS'), findsOneWidget);
    // The instant it happened, not the instant the screen opened.
    expect(find.text('в 16:41 · 4 мин назад'), findsOneWidget);
    expect(find.text('Мектеп №25'), findsOneWidget);
    // «Плашка свежести — всегда»: the position carries its own age.
    expect(find.text('Место от 16:41 · 4 мин назад'), findsOneWidget);
  });

  testWidgets('«Позвонить: Нуржан» dials the number on the child’s card', (tester) async {
    final dialled = <String>[];
    await tester.pumpWidget(host(SosAlertScreen(
      childName: 'Алия',
      at: pressed,
      now: () => now,
      contactName: 'Нұржан',
      contactPhone: '+77011234567',
      onCall: (tel) async {
        dialled.add(tel);
        return true;
      },
      onDismissConfirmed: () async {},
    )));

    await tester.tap(find.text(ru.t('sos21_call_contact', {'name': 'Нұржан'})));
    await tester.pump();
    expect(dialled, ['+77011234567'],
        reason: 'the button named a person and called nobody');
  });

  // The hard rule, asserted: nothing on this screen may be invented.
  testWidgets('with no contact on the card it says so and offers 103 instead',
      (tester) async {
    await tester.pumpWidget(host(SosAlertScreen(
      childName: 'Алия',
      at: pressed,
      now: () => now,
      onCall: (_) async => true,
      onDismissConfirmed: () async {},
    )));

    expect(find.text(ru.t('sos21_no_contact_title')), findsOneWidget);
    // No call button naming somebody, because there is nobody to name.
    expect(find.textContaining(ru.t('sos21_call_contact', {'name': ''}).trim()), findsNothing);
    // …and the ambulance is on the screen regardless.
    expect(find.byType(CallAmbulanceFooter), findsOneWidget);
    expect(find.textContaining(kAmbulanceTel), findsWidgets);
  });

  testWidgets('with no position it says the app has none rather than drawing a map',
      (tester) async {
    await tester.pumpWidget(host(SosAlertScreen(
      childName: 'Алия',
      at: pressed,
      now: () => now,
      mapBuilder: (_, __, ___) => const SizedBox(key: Key('map'), height: 100),
      onCall: (_) async => true,
      onDismissConfirmed: () async {},
    )));

    expect(find.text(ru.t('sos21_where_unknown')), findsOneWidget);
    expect(find.byKey(const Key('map')), findsNothing,
        reason: 'a map centred on nothing claims to know where she is');
  });

  testWidgets('closing the alarm is confirmed first, and cancelling keeps it',
      (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(host(SosAlertScreen(
      childName: 'Алия',
      at: pressed,
      now: () => now,
      onCall: (_) async => true,
      onDismissConfirmed: () async => dismissed++,
    )));

    await tester.tap(find.text(ru.t('sos21_dismiss')));
    await tester.pumpAndSettle();
    expect(find.text(ru.t('sos21_dismiss_title')), findsOneWidget);

    await tester.tap(find.text(ru.t('act_cancel')));
    await tester.pumpAndSettle();
    expect(dismissed, 0, reason: 'a mis-tap must not be able to hide a real alarm');

    await tester.tap(find.text(ru.t('sos21_dismiss')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ru.t('sos21_dismiss_confirm')));
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });

  // ---- Raising it ---------------------------------------------------------
  //
  // Reverting AppController leaves logChildEvent recording a row in a list and
  // nothing else, which is exactly the state screen 21 was missing from.

  test('pressing SOS raises the takeover, carrying the card’s contact', () {
    final c = controllerWithChild(now);
    expect(c.route, AppRoute.home);

    c.logChildEvent(AlertKind.sos);

    expect(c.route, AppRoute.sos);
    final view = c.sos!;
    expect(view.childName, 'Алия');
    expect(view.contactName, 'Нұржан');
    expect(view.contactPhone, '+77011234567');
    expect(view.coords, isNotNull, reason: 'the last known fix belongs on this screen');
  });

  test('a check-in raises nothing — only an SOS takes the screen', () {
    final c = controllerWithChild(now);
    c.logChildEvent(AlertKind.checkIn);
    expect(c.route, AppRoute.home);
  });

  test('dismissing closes the screen but leaves the alarm on the feed', () {
    final c = controllerWithChild(now);
    c.logChildEvent(AlertKind.sos);
    expect(c.route, AppRoute.sos);
    c.dismissSos();
    expect(c.route, AppRoute.home);
    expect(c.alerts.where((a) => a.kind == AlertKind.sos), hasLength(1));
  });

  test('a fresh SOS pulled from the server raises it; an old one does not', () {
    final fresh = controllerWithChild(now);
    fresh.mergeRemoteAlerts([
      SafetyAlert(
        kind: AlertKind.sos,
        childName: 'Алия',
        zoneName: '',
        at: now.subtract(const Duration(minutes: 5)),
      ),
    ]);
    expect(fresh.route, AppRoute.sos,
        reason: 'the button was pressed while the app was closed — that is the case this exists for');

    final old = controllerWithChild(now);
    old.mergeRemoteAlerts([
      SafetyAlert(
        kind: AlertKind.sos,
        childName: 'Алия',
        zoneName: '',
        at: now.subtract(const Duration(days: 3)),
      ),
    ]);
    expect(old.route, AppRoute.home,
        reason: 'signing in on a new phone must not replay somebody’s alarm from last week');
  });

  test('an SOS for a child this phone does not have carries no name and no contact', () {
    final c = controllerWithChild(now);
    c.mergeRemoteAlerts([
      SafetyAlert(kind: AlertKind.sos, childName: 'Ерсұлтан', zoneName: '', at: now),
    ]);
    expect(c.route, AppRoute.sos);
    expect(c.sos!.childName, isEmpty);
    expect(c.sos!.contactPhone, isEmpty,
        reason: 'another child’s emergency contact must never be offered');
    expect(c.sos!.coords, isNull,
        reason: 'the tracked sibling’s position is not this child’s position');
  });

  // The wiring, not the screen: FcsApp must actually render it.
  testWidgets('FcsApp puts screen 21 over everything when one is latched',
      (tester) async {
    final c = controllerWithChild(now);
    await tester.pumpWidget(
      FcsApp(controller: c, content: ContentStore(const ContentCatalog({}))),
    );
    await tester.pump();
    expect(find.byType(SosAlertScreen), findsNothing);

    c.logChildEvent(AlertKind.sos);
    await tester.pump();
    await tester.pump();

    expect(find.byType(SosAlertScreen), findsOneWidget,
        reason: 'the screen exists and nothing in the app shows it');
    expect(find.text('Алия нажала кнопку SOS'), findsOneWidget);
  });

  testWidgets('«Открыть карту» hands over to the live tracking screen',
      (tester) async {
    // The takeover sits ABOVE the shell's Navigator, so this button cannot
    // simply push: it closes the alarm and asks for the Child tab. Both halves
    // have to happen, or the button either does nothing or leaves her on a red
    // screen with a map behind it.
    final c = controllerWithChild(now);
    await tester.pumpWidget(
      FcsApp(controller: c, content: ContentStore(const ContentCatalog({}))),
    );
    c.logChildEvent(AlertKind.sos);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text(ru.t('sos21_open_map')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SosAlertScreen), findsNothing);
    expect(find.byType(ChildMapScreen), findsOneWidget,
        reason: '«Открыть карту» closed the alarm and opened nothing');
  });

  // ---- Screen 38 · a tapped notification ---------------------------------
  //
  // Revert notification_route.dart / the init callback and every one of these
  // taps resolves to nothing at all, which is what shipped.

  group('the payload a tap carries', () {
    test('the server’s screen names map to real destinations', () {
      expect(parseNotificationPayload('{"screen":"SosAlert"}').destination,
          NotifyDestination.sos);
      expect(parseNotificationPayload('{"screen":"SupportThread","ticketId":"t-9"}').ticketId,
          't-9');
      expect(parseNotificationPayload('{"screen":"SupportThread"}').destination,
          NotifyDestination.supportThread);
      expect(parseNotificationPayload('{"screen":"NotificationCentre"}').destination,
          NotifyDestination.notificationCentre);
      expect(parseNotificationPayload('{"screen":"EmergencyRescue","code":"HIGH_FEVER"}').code,
          'HIGH_FEVER');
    });

    test('anything it cannot understand is the dashboard, never a throw', () {
      for (final raw in <String?>[
        null,
        '',
        '   ',
        'not json',
        '{',
        '[]',
        '{"screen":"SomethingFromANewerServer"}',
        '{"screen":null}',
      ]) {
        expect(parseNotificationPayload(raw).destination, NotifyDestination.dashboard,
            reason: 'payload ${raw ?? "null"} resolved somewhere else');
      }
    });

    test('half a coordinate is no coordinate', () {
      expect(parseNotificationPayload('{"screen":"SosAlert","lat":"43.25"}').coords, isNull);
      expect(parseNotificationPayload('{"screen":"SosAlert","lat":"43.25","lng":"76.95"}').coords,
          isNotNull);
      expect(parseNotificationPayload('{"screen":"SosAlert","lat":"999","lng":"76.95"}').coords,
          isNull);
    });

    test('what the app writes is what the app reads', () {
      final tap = parseNotificationPayload(sosNotificationPayload(
        childName: 'Алия',
        at: pressed,
        zoneName: 'Мектеп №25',
      ));
      expect(tap.destination, NotifyDestination.sos);
      expect(tap.childName, 'Алия');
      expect(tap.zoneName, 'Мектеп №25');
      expect(tap.at, pressed);
    });
  });

  group('tapping one', () {
    test('an SOS opens screen 21, with the name and instant it carried', () {
      final c = controllerWithChild(now);
      handleNotificationTap(
        c,
        sosNotificationPayload(childName: 'Алия', at: pressed, zoneName: 'Мектеп №25'),
      );
      expect(c.route, AppRoute.sos);
      expect(c.sos!.childName, 'Алия');
      expect(c.sos!.at, pressed);
      expect(c.alerts.first.kind, AlertKind.sos,
          reason: 'a pushed alarm the phone never saw belongs on the feed too');
    });

    test('tapping the SAME SOS twice opens it both times', () {
      final c = controllerWithChild(now);
      final payload = sosNotificationPayload(childName: 'Алия', at: pressed);
      handleNotificationTap(c, payload);
      c.dismissSos();
      handleNotificationTap(c, payload);
      expect(c.route, AppRoute.sos,
          reason: 'the second tap deduplicated against the feed and opened nothing');
    });

    test('a support reply asks for the support thread', () {
      final c = controllerWithChild(now);
      handleNotificationTap(c, '{"screen":"SupportThread","ticketId":"t-9"}');
      expect(c.takePendingDestination(), NotifyDestination.supportThread);
    });

    test('a рассылка asks for the notification centre', () {
      final c = controllerWithChild(now);
      handleNotificationTap(c, '{"screen":"NotificationCentre","broadcastId":"b-1"}');
      expect(c.takePendingDestination(), NotifyDestination.notificationCentre);
    });

    test('an unrecognised payload asks for the dashboard and never crashes', () {
      final c = controllerWithChild(now);
      handleNotificationTap(c, 'вчера-ish');
      expect(c.takePendingDestination(), NotifyDestination.dashboard);
      expect(c.route, AppRoute.home);
    });

    test('a medical emergency raises the rescue screen, localized by code', () {
      final c = controllerWithChild(now);
      // `at` is four minutes ago — this is happening. The payload used to carry
      // no time at all and the handler asked for none; see the staleness group
      // below for why both had to change together.
      handleNotificationTap(
        c,
        '{"screen":"EmergencyRescue","code":"HIGH_FEVER",'
            '"at":"${pressed.toUtc().toIso8601String()}"}',
      );
      expect(c.route, AppRoute.emergency);
      expect(c.emergency!.message, ru.triageMessage('HIGH_FEVER'));
    });

    test('a destination is spent once — the shell must not re-open it every build', () {
      final c = controllerWithChild(now);
      handleNotificationTap(c, '{"screen":"NotificationCentre"}');
      expect(c.takePendingDestination(), NotifyDestination.notificationCentre);
      expect(c.takePendingDestination(), isNull);
    });
  });

  // ---- The plugin argument that was simply absent -------------------------
  //
  // Read from source, because there is no behavioural test that can see it: a
  // missing named argument to `initialize` compiles, runs, and silently throws
  // every tap away. That is precisely how it shipped. The plugin cannot be
  // driven in a widget test, so the source IS the evidence here.
  group('the tap handler is actually registered with the plugin', () {
    final source = File('lib/data/notification_service.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('initialize() is given onDidReceiveNotificationResponse', () {
      expect(
        source.contains('onDidReceiveNotificationResponse:'),
        isTrue,
        reason: 'without it flutter_local_notifications discards every tap and '
            'no notification in the app opens anything',
      );
    });

    test('a cold launch by notification is read too', () {
      expect(
        source.contains('getNotificationAppLaunchDetails'),
        isTrue,
        reason: 'when the process was not running Android delivers the tap as '
            'launch data and the response callback never fires — which is the '
            'ordinary case for an SOS',
      );
    });

    test('the SOS asks for a full-screen intent and nothing else does', () {
      expect(source.contains('fullScreenIntent: fullScreen'), isTrue);
      // Read the whole call site: `fullScreen` must be a parameter, not a
      // constant true, or every reminder would take over the lock screen.
      expect(source.contains('fullScreenIntent: true'), isFalse);
    });
  });

  // ---- Kazakh -------------------------------------------------------------

  testWidgets('the Kazakh copy says the same thing, not the key', (tester) async {
    await tester.pumpWidget(host(
      SosAlertScreen(
        childName: 'Алия',
        at: pressed,
        now: () => now,
        contactName: 'Нұржан',
        contactPhone: '+77011234567',
        onCall: (_) async => true,
        onDismissConfirmed: () async {},
      ),
      locale: AppLocale.kk,
    ));
    expect(find.text('Алия SOS түймесін басты'), findsOneWidget);
    expect(find.text(kk.t('sos21_open_map')), findsNothing); // no map callback here
    expect(find.text(kk.t('sos21_call_contact', {'name': 'Нұржан'})), findsOneWidget);
  });
}
