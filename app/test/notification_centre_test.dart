/// Screen 39 — «Центр уведомлений».
///
/// The badge counted everything that had ever happened, so it never went down
/// and stopped meaning anything — which is worst on the day something actually
/// is wrong. These tests are about the badge reaching zero, and about the one
/// promise on the screen that must be true: «экстренные отключить нельзя».
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/announcement.dart';
import 'package:fcs_app/domain/geofence_alerts.dart';
import 'package:fcs_app/domain/notification_centre.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/notification_centre_screen.dart';

const l = L10n(AppLocale.ru);
final now = DateTime(2026, 8, 8, 15, 0);

SafetyAlert alert(AlertKind kind, DateTime at, {String zone = 'Школа'}) =>
    SafetyAlert(kind: kind, childName: 'Алия', zoneName: zone, at: at);

/// A рассылка as the server sends one — both languages, always.
Announcement announcement(
  DateTime at, {
  String id = 'bc-1',
  String titleRu = 'Второй скрининг',
  String bodyRu = 'Окно 18–21 неделя.',
  String titleKk = 'Екінші скрининг',
  String bodyKk = '18–21 апта.',
}) =>
    Announcement(
      id: id,
      at: at,
      ru: AnnouncementText(title: titleRu, body: bodyRu),
      kk: AnnouncementText(title: titleKk, body: bodyKk),
    );

Future<List<DateTime>> pump(
  WidgetTester tester, {
  required List<SafetyAlert> alerts,
  List<Announcement> announcements = const [],
  DateTime? readUpTo,
  bool withConfigure = false,
  AppLocale locale = AppLocale.ru,
}) async {
  final marked = <DateTime>[];
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(L10nScope(
    l10n: L10n(locale),
    child: MaterialApp(
      theme: FcsTheme.light(locale),
      home: NotificationCentreScreen(
        alerts: alerts,
        announcements: announcements,
        now: now,
        readUpTo: readUpTo,
        onReadAll: marked.add,
        onConfigure: withConfigure ? () {} : null,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return marked;
}

void main() {
  group('the emergency channel', () {
    test('cannot be muted, and it is the only one', () {
      // The card on screen reads this. If somebody ever made emergencies
      // mutable, the promise stops being made rather than becoming a lie.
      expect(NotificationChannel.emergency.canBeMuted, isFalse);
      for (final c in NotificationChannel.values) {
        if (c != NotificationChannel.emergency) {
          expect(c.canBeMuted, isTrue, reason: '$c should be mutable');
        }
      }
    });

    test('an SOS is an emergency however it arrived', () {
      expect(channelOf(AlertKind.sos), NotificationChannel.emergency);
      expect(channelOf(AlertKind.entered), isNot(NotificationChannel.emergency));
    });
  });

  group('grouping', () {
    test('splits today from earlier, newest first', () {
      final s = groupNotifications([
        alert(AlertKind.entered, now.subtract(const Duration(hours: 2))),
        alert(AlertKind.left, now.subtract(const Duration(days: 2))),
        alert(AlertKind.checkIn, now.subtract(const Duration(minutes: 10))),
      ], now);
      expect(s.today, hasLength(2));
      expect(s.earlier, hasLength(1));
      expect(s.today.first.alert!.kind, AlertKind.checkIn);
    });

    test('with no watermark everything is unread', () {
      final s = groupNotifications([
        alert(AlertKind.entered, now.subtract(const Duration(hours: 1))),
      ], now);
      expect(s.unreadCount, 1);
    });

    test('an alert AT the watermark counts as read', () {
      // Otherwise «Прочитать всё» leaves the newest one unread and the badge
      // never reaches zero, which is the bug this screen exists to end.
      final at = now.subtract(const Duration(hours: 1));
      final s = groupNotifications([alert(AlertKind.entered, at)], now,
          readUpTo: at);
      expect(s.unreadCount, 0);
    });

    test('something newer than the watermark stays unread', () {
      final s = groupNotifications([
        alert(AlertKind.entered, now.subtract(const Duration(hours: 2))),
        alert(AlertKind.sos, now.subtract(const Duration(minutes: 5))),
      ], now, readUpTo: now.subtract(const Duration(hours: 1)));
      expect(s.unreadCount, 1);
      expect(s.today.first.alert!.kind, AlertKind.sos);
      expect(s.today.first.unread, isTrue);
    });
  });

  group('рассылки share the centre with the alerts', () {
    test('are sorted into the same two sections, by time alone', () {
      final s = groupNotifications(
        [alert(AlertKind.entered, now.subtract(const Duration(hours: 2)))],
        now,
        announcements: [
          announcement(now.subtract(const Duration(hours: 1))),
          announcement(now.subtract(const Duration(days: 4)), id: 'bc-old'),
        ],
      );
      expect(s.today, hasLength(2));
      expect(s.earlier, hasLength(1));
      // Newest first, and the newest thing today is the рассылка.
      expect(s.today.first.announcement?.id, 'bc-1');
      expect(s.today.last.alert?.kind, AlertKind.entered);
      expect(s.earlier.single.announcement?.id, 'bc-old');
    });

    test('are «что нового», never an emergency', () {
      // A message from the back office must not be able to inherit the
      // emergency treatment by landing in the wrong branch of a widget.
      final s = groupNotifications([], now, announcements: [announcement(now)]);
      expect(s.today.single.channel, NotificationChannel.updates);
      expect(s.today.single.isEmergency, isFalse);
    });

    test('count towards the badge', () {
      final s = groupNotifications([], now,
          announcements: [announcement(now.subtract(const Duration(minutes: 3)))]);
      expect(s.unreadCount, 1);
    });

    test('one watermark clears both kinds at once', () {
      // Two watermarks would let «Прочитать всё» clear the alerts and leave the
      // badge at 1 over a list she has just read.
      final newest = now.subtract(const Duration(minutes: 5));
      final s = groupNotifications(
        [alert(AlertKind.sos, now.subtract(const Duration(hours: 2)))],
        now,
        readUpTo: newest,
        announcements: [announcement(newest)],
      );
      expect(s.unreadCount, 0);
    });
  });

  group('the read-all watermark', () {
    test('is the newest of everything on screen, alerts or рассылки', () {
      // Taken from the alerts alone it would leave a рассылка sent five minutes
      // ago permanently unread, and the badge stuck at 1 over a cleared list.
      final newest = now.subtract(const Duration(minutes: 5));
      expect(
        readAllWatermark(
          [alert(AlertKind.entered, now.subtract(const Duration(hours: 3)))],
          [announcement(newest)],
        ),
        newest,
      );
    });

    test('is null when neither list has anything', () {
      expect(readAllWatermark([], []), isNull);
    });

    test('is the newest alert, not «now»', () {
      // Recording `now` would also mark read an alert that arrives in the same
      // second and is not on screen yet.
      final newest = now.subtract(const Duration(minutes: 5));
      expect(
        readAllWatermark([
          alert(AlertKind.entered, now.subtract(const Duration(hours: 3))),
          alert(AlertKind.sos, newest),
        ]),
        newest,
      );
    });

    test('is null with nothing to read', () {
      expect(readAllWatermark([]), isNull);
    });
  });

  testWidgets('shows both sections with their headings', (tester) async {
    await pump(tester, alerts: [
      alert(AlertKind.entered, now.subtract(const Duration(hours: 1))),
      alert(AlertKind.left, now.subtract(const Duration(days: 3))),
    ]);
    expect(find.text(l.t('ntf_today')), findsOneWidget);
    expect(find.text(l.t('ntf_earlier')), findsOneWidget);
  });

  testWidgets('«Прочитать всё» records the newest alert\'s time',
      (tester) async {
    final newest = now.subtract(const Duration(minutes: 5));
    final marked = await pump(tester, alerts: [
      alert(AlertKind.entered, now.subtract(const Duration(hours: 4))),
      alert(AlertKind.sos, newest),
    ]);
    await tester.tap(find.text(l.t('ntf_read_all')));
    await tester.pumpAndSettle();
    expect(marked, [newest]);
  });

  testWidgets('«Прочитать всё» is disabled when nothing is unread',
      (tester) async {
    // A button that looks live and does nothing teaches distrust of every
    // other button on the screen.
    final at = now.subtract(const Duration(hours: 1));
    await pump(tester, alerts: [alert(AlertKind.entered, at)], readUpTo: at);
    final btn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, l.t('ntf_read_all')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('and with no alerts at all', (tester) async {
    await pump(tester, alerts: []);
    final btn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, l.t('ntf_read_all')));
    expect(btn.onPressed, isNull);
    expect(find.text(l.t('ntf_empty')), findsOneWidget);
  });

  testWidgets('says emergencies cannot be turned off, even when empty',
      (tester) async {
    // It is the answer to «а если я всё отключу?», and she may well ask it on
    // a day when nothing has happened.
    await pump(tester, alerts: []);
    expect(find.text(l.t('ntf_emergency_locked')), findsOneWidget);
    expect(find.text(l.t('ntf_emergency_why')), findsOneWidget);
  });

  testWidgets('offers to configure the rest only when there is somewhere to go',
      (tester) async {
    await pump(tester, alerts: []);
    expect(find.text(l.t('ntf_configure_rest')), findsNothing);

    await pump(tester, alerts: [], withConfigure: true);
    expect(find.text(l.t('ntf_configure_rest')), findsOneWidget);
  });

  group('a рассылка on screen', () {
    testWidgets('paints its title, its body and who it is from', (tester) async {
      await pump(tester, alerts: [], announcements: [
        announcement(now.subtract(const Duration(hours: 1))),
      ]);
      expect(find.text('Второй скрининг'), findsOneWidget);
      expect(find.text('Окно 18–21 неделя.'), findsOneWidget);
      // Where a child's name stands on a safety alert. One is about her child,
      // the other is us writing to her, and they must not be confused.
      expect(find.textContaining(l.t('ntf_from_team')), findsOneWidget);
      // ...and it is no longer the empty state.
      expect(find.text(l.t('ntf_empty')), findsNothing);
    });

    testWidgets('reads in Kazakh when the app is in Kazakh', (tester) async {
      // Both languages travel with the message precisely so switching after it
      // arrived is not a bug she cannot fix.
      await pump(tester,
          alerts: [],
          locale: AppLocale.kk,
          announcements: [announcement(now.subtract(const Duration(hours: 1)))]);
      expect(find.text('Екінші скрининг'), findsOneWidget);
      expect(find.text('Второй скрининг'), findsNothing);
    });

    testWidgets('falls back to Russian rather than painting a blank card',
        (tester) async {
      // The publication gate should make this impossible; a row written before
      // the gate existed must still say something.
      await pump(tester, alerts: [], locale: AppLocale.kk, announcements: [
        announcement(now.subtract(const Duration(hours: 1)),
            titleKk: '', bodyKk: ''),
      ]);
      expect(find.text('Второй скрининг'), findsOneWidget);
    });

    testWidgets('«Прочитать всё» clears it and the button goes dead',
        (tester) async {
      final at = now.subtract(const Duration(minutes: 5));
      final marked = await pump(tester, alerts: [], announcements: [
        announcement(at),
      ]);
      await tester.tap(find.text(l.t('ntf_read_all')));
      await tester.pumpAndSettle();
      expect(marked, [at]);

      // Re-render at that watermark: nothing unread, so the button is disabled.
      await pump(tester,
          alerts: [], announcements: [announcement(at)], readUpTo: at);
      final btn = tester.widget<TextButton>(
          find.widgetWithText(TextButton, l.t('ntf_read_all')));
      expect(btn.onPressed, isNull);
    });
  });
}
