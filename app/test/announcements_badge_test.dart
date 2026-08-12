/// The bell over the map, once рассылки share the notification centre.
///
/// Admin frame 06 delivers a message; screen 39 is where it lands. Between them
/// sits the badge, and the badge is the only reason she opens the screen at
/// all. Two ways to get this wrong, both of which look fine in a screenshot:
///
///   * the message arrives and the badge does not move, so nobody reads it;
///   * «Прочитать всё» clears the alerts and leaves the badge at 1, which is
///     how a badge stops being believed — including on the day the thing behind
///     it is her child's SOS.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/announcement.dart';
import 'package:fcs_app/domain/notification_centre.dart';
import 'package:fcs_app/domain/phone_auth.dart';

Announcement announcement(DateTime at, {String id = 'bc-1'}) => Announcement(
      id: id,
      at: at,
      ru: const AnnouncementText(title: 'Второй скрининг', body: 'Окно 18–21 неделя.'),
      kk: const AnnouncementText(title: 'Екінші скрининг', body: '18–21 апта.'),
    );

void main() {
  final now = DateTime(2026, 8, 12, 15);
  AppController make() => AppController(now: () => now);

  test('a phone with nothing on it shows no badge', () {
    expect(make().unreadAlertCount, 0);
  });

  test('a delivered рассылка increments it', () {
    final c = make()..setAnnouncements([announcement(now.subtract(const Duration(minutes: 5)))]);
    expect(c.announcements, hasLength(1));
    expect(c.unreadAlertCount, 1);
  });

  test('«Прочитать всё» clears it', () {
    final at = now.subtract(const Duration(minutes: 5));
    final c = make()..setAnnouncements([announcement(at)]);
    final watermark = readAllWatermark(c.alerts, c.announcements);
    expect(watermark, at);
    c.markAlertsRead(watermark!);
    expect(c.unreadAlertCount, 0);
  });

  test('a message that arrives AFTER she read everything is unread again', () {
    final c = make()..setAnnouncements([announcement(now.subtract(const Duration(hours: 2)))]);
    c.markAlertsRead(readAllWatermark(c.alerts, c.announcements)!);
    expect(c.unreadAlertCount, 0);

    c.setAnnouncements([
      announcement(now.subtract(const Duration(hours: 2))),
      announcement(now.subtract(const Duration(minutes: 1)), id: 'bc-2'),
    ]);
    expect(c.unreadAlertCount, 1);
  });

  test('the same list twice does not rebuild the tree', () async {
    // The cache primes before first paint and the network answers a moment
    // later with the same rows; a notify per launch is a free rebuild of the
    // whole shell.
    final c = make();
    var notifications = 0;
    final sub = c.changes.listen((_) => notifications++);
    addTearDown(sub.cancel);

    c.setAnnouncements([announcement(now)]);
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);

    c.setAnnouncements([announcement(now)]);
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
  });

  test('signing out forgets them, and asks the cache to forget too', () {
    // She is mail addressed to an account. The local health history stays —
    // signing out is not erasing — but the next person to sign in on this
    // handset must not find somebody else's messages in the centre.
    var cleared = 0;
    final c = make();
    c.onSignedOut = () async {
      cleared++;
    };
    c.signIn(AuthSession(
      userId: 'u-1', phoneE164: '+77001112233', token: 't', signedInAt: now,
    ));
    c.setAnnouncements([announcement(now)]);
    expect(c.unreadAlertCount, 1);

    c.signOut();
    expect(c.announcements, isEmpty);
    expect(c.unreadAlertCount, 0);
    expect(cleared, 1, reason: 'the cached copy would be re-primed on next launch');
  });
}
