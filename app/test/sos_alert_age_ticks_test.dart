/// TODO §10.10 — «N минут назад» on the SOS takeover was computed once.
///
/// `app.dart` passed `now: DateTime.now()`, evaluated as `_rootFor` built the
/// screen, and `SosAlertScreen` had no ticker — `initState` fired a haptic and
/// an announcement and nothing else. So the takeover opened at 09:02 saying
/// «в 09:00 · 2 мин назад», she drove for forty minutes with it up, and it
/// still said «2 мин назад». The absolute time stayed correct, which is
/// precisely why it never looked broken.
///
/// The screen's own location card argues against it in a comment: «a position
/// with no age on it claims to be live, and on this screen that is the claim
/// most likely to be wrong». A FROZEN age is worse than an absent one — it goes
/// on asserting something false, on the screen with the least room for that.
///
/// Two properties are pinned here and both matter:
///   · the rendered STRING changes as real time passes (not that a timer
///     exists — a timer that redraws nothing is the same bug);
///   · it does so CHEAPLY. The strings step once a minute, so waking the device
///     every second on the one screen that must survive until she arrives would
///     be a defect of its own. The wake count is measured through the clock
///     closure the screen calls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/domain/child_tracker_state.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/sos_alert_screen.dart';

void main() {
  const ru = L10n(AppLocale.ru);
  final pressed = DateTime(2026, 8, 20, 9, 0);
  const where = Coordinates(43.25, 76.95);

  String whenLine(String ago) =>
      ru.t('sos21_when', {'time': '09:00', 'ago': ago});
  String whereLine(String time, String ago) =>
      ru.t('sos21_where_at', {'time': time, 'ago': ago});
  String minsAgo(int n) => ru.t('ago_min', {'n': n});

  // L10nScope ABOVE MaterialApp: under `home:` it sits below the Navigator and
  // any pushed route silently falls back to English.
  Widget host(Widget child) => L10nScope(
        l10n: ru,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: FcsTheme.light(AppLocale.ru),
          home: child,
        ),
      );

  group('the age on the SOS takeover follows real time', () {
    testWidgets('«2 мин назад» becomes «42 мин назад» after forty minutes',
        (tester) async {
      var clock = pressed.add(const Duration(minutes: 2));
      await tester.pumpWidget(host(SosAlertScreen(
        childName: 'Алия',
        at: pressed,
        now: () => clock,
        onCall: (_) async => true,
        onDismissConfirmed: () async {},
      )));

      expect(find.text(whenLine(minsAgo(2))), findsOneWidget,
          reason: 'the takeover opens two minutes after the button');

      // She drives. The screen stays up; nothing rebuilds it from outside.
      clock = pressed.add(const Duration(minutes: 42));
      await tester.pump(const Duration(minutes: 40));

      expect(find.text(whenLine(minsAgo(42))), findsOneWidget,
          reason: 'the age must follow the clock while the screen is up');
      expect(find.text(whenLine(minsAgo(2))), findsNothing,
          reason: 'this is the string that stayed on screen for forty minutes');
      // The absolute time never moved, which is what made it look fine.
      expect(find.textContaining('09:00'), findsOneWidget);
    });

    testWidgets('it steps at the minute, not only at the end of the drive',
        (tester) async {
      var clock = pressed.add(const Duration(minutes: 2));
      await tester.pumpWidget(host(SosAlertScreen(
        childName: 'Алия',
        at: pressed,
        now: () => clock,
        onCall: (_) async => true,
        onDismissConfirmed: () async {},
      )));

      for (final m in [3, 4, 5]) {
        clock = pressed.add(Duration(minutes: m));
        await tester.pump(const Duration(minutes: 1));
        expect(find.text(whenLine(minsAgo(m))), findsOneWidget,
            reason: 'the age stalled at minute $m');
      }
    });

    testWidgets('the POSITION age ticks too — the claim most likely to be wrong',
        (tester) async {
      final fixAt = pressed.subtract(const Duration(minutes: 1)); // 08:59
      var clock = pressed.add(const Duration(minutes: 2));
      await tester.pumpWidget(host(SosAlertScreen(
        childName: 'Алия',
        at: pressed,
        now: () => clock,
        coords: where,
        coordsAt: fixAt,
        onCall: (_) async => true,
        onDismissConfirmed: () async {},
      )));

      expect(find.text(whereLine('08:59', minsAgo(3))), findsOneWidget);

      clock = pressed.add(const Duration(minutes: 12));
      await tester.pump(const Duration(minutes: 10));

      expect(find.text(whereLine('08:59', minsAgo(13))), findsOneWidget,
          reason: 'a position that stops ageing starts claiming to be live');
      expect(find.text(whereLine('08:59', minsAgo(3))), findsNothing);
    });

    testWidgets('it crosses from minutes into hours', (tester) async {
      var clock = pressed.add(const Duration(minutes: 58));
      await tester.pumpWidget(host(SosAlertScreen(
        childName: 'Алия',
        at: pressed,
        now: () => clock,
        onCall: (_) async => true,
        onDismissConfirmed: () async {},
      )));
      expect(find.text(whenLine(minsAgo(58))), findsOneWidget);

      clock = pressed.add(const Duration(hours: 3));
      await tester.pump(const Duration(hours: 2, minutes: 2));

      expect(find.text(whenLine(ru.t('ago_hour', {'n': 3}))), findsOneWidget,
          reason: 'the hour bucket has to be reached by the same ticker');
    });
  });

  testWidgets('a second alert re-aims the ticker at the new press time',
      (tester) async {
    // The takeover is not pushed — it is RETURNED by `_rootFor`, so a second
    // child pressing the button rebuilds the SAME element with a new `at`
    // rather than mounting a fresh screen. The pending timer belongs to the
    // first alert.
    //
    // The discriminating case is an OLD first alert. At 90 minutes the sentence
    // only changes hourly, so the timer is aimed half an hour out. A fresh
    // press then reads «только что», and without `didUpdateWidget` it goes on
    // reading «только что» for the next twenty-five minutes — the frozen age
    // this file exists for, re-created by the very next alarm.
    final t0 = tester.binding.clock.now();
    final mounted = pressed.add(const Duration(minutes: 90)); // 10:30
    DateTime clock() => mounted.add(tester.binding.clock.now().difference(t0));

    Widget screen(DateTime at) => host(SosAlertScreen(
          childName: 'Алия',
          at: at,
          now: clock,
          onCall: (_) async => true,
          onDismissConfirmed: () async {},
        ));

    await tester.pumpWidget(screen(pressed));
    expect(find.text(whenLine(ru.t('ago_hour', {'n': 1}))), findsOneWidget,
        reason: 'the first alert is an hour and a half old');

    // The second press, right now — 10:30.
    await tester.pumpWidget(screen(mounted));
    expect(
        find.text(ru.t('sos21_when',
            {'time': '10:30', 'ago': ru.t('ago_just_now')})),
        findsOneWidget,
        reason: 'the new alert is seconds old, not an hour and a half');

    await tester.pump(const Duration(minutes: 3));
    expect(
        find.text(ru.t('sos21_when', {'time': '10:30', 'ago': minsAgo(3)})),
        findsOneWidget,
        reason: 'the ticker must be re-aimed at the SECOND press — the first '
            "alert's timer was half an hour away");
  });

  group('and it does so cheaply', () {
    testWidgets('ten minutes on screen costs about ten wake-ups, not six hundred',
        (tester) async {
      // A CONTINUOUS clock, tied to the test's own fake time rather than
      // jumped forward in one step: a discontinuous clock makes the screen's
      // `_now` run ahead of the timer that set it, and the re-armed delay is
      // then measured from the wrong place. That would count wake-ups the
      // production screen never performs.
      final t0 = tester.binding.clock.now();
      var reads = 0;
      DateTime clock() {
        reads++;
        return pressed
            .add(const Duration(seconds: 90))
            .add(tester.binding.clock.now().difference(t0));
      }

      await tester.pumpWidget(host(SosAlertScreen(
        childName: 'Алия',
        at: pressed,
        now: clock,
        onCall: (_) async => true,
        onDismissConfirmed: () async {},
      )));

      final atStart = reads; // the initial reading in initState
      await tester.pump(const Duration(minutes: 10));

      final ticks = reads - atStart;
      expect(ticks, lessThanOrEqualTo(15),
          reason: 'the strings step once a minute; a per-second ticker would '
              'be ~600 wake-ups here, on the screen whose battery has to last '
              'until she gets there');
      expect(ticks, greaterThanOrEqualTo(9),
          reason: 'and it must actually wake — a ticker that stops is the '
              'defect this file exists for');
    });

    test('the wake schedule is the string schedule, and no tighter', () {
      // The buckets in L10n.ago / formatAgo: 45 s, then a minute, then an hour,
      // then a day. agoRefreshDelay must land on those and nowhere else.
      expect(agoRefreshDelay(Duration.zero), const Duration(seconds: 45));
      expect(agoRefreshDelay(const Duration(seconds: 44)),
          const Duration(seconds: 1));
      expect(agoRefreshDelay(const Duration(seconds: 45)),
          const Duration(seconds: 15));
      expect(agoRefreshDelay(const Duration(minutes: 2)),
          const Duration(minutes: 1),
          reason: 'two minutes in, the next change is a minute away — not a '
              'second away');
      expect(agoRefreshDelay(const Duration(minutes: 2, seconds: 20)),
          const Duration(seconds: 40));
      expect(agoRefreshDelay(const Duration(minutes: 90)),
          const Duration(minutes: 30),
          reason: 'past an hour the sentence only changes on the hour');
      expect(agoRefreshDelay(const Duration(hours: 30)),
          const Duration(hours: 18));
    });

    test('it never returns zero, which would spin a re-arming timer', () {
      for (final age in [
        Duration.zero,
        const Duration(seconds: 59),
        const Duration(minutes: 59, seconds: 59),
        const Duration(hours: 23, minutes: 59),
        const Duration(days: 400),
      ]) {
        expect(agoRefreshDelay(age), greaterThan(Duration.zero),
            reason: 'a zero delay re-arms a timer that fires immediately');
      }
    });

    test('a clock that disagrees waits for it, and is re-checked within an hour',
        () {
      // `clockDisagrees` makes L10n.ago fall back for a future timestamp; the
      // sentence changes when the clock catches up. An absurd skew must not
      // schedule a timer years out and then never look again.
      expect(agoRefreshDelay(const Duration(minutes: -3)),
          const Duration(minutes: 3));
      expect(agoRefreshDelay(const Duration(days: -400)),
          const Duration(hours: 1));
    });
  });

  group('the ticker stops when the screen goes', () {
    testWidgets('no clock reads after the takeover is disposed', (tester) async {
      var reads = 0;
      final clock = pressed.add(const Duration(minutes: 2));
      await tester.pumpWidget(host(SosAlertScreen(
        childName: 'Алия',
        at: pressed,
        now: () {
          reads++;
          return clock;
        },
        onCall: (_) async => true,
        onDismissConfirmed: () async {},
      )));

      await tester.pumpWidget(host(const SizedBox.shrink()));
      final afterDispose = reads;

      // Deliberately SHORTER than the pending tick. Letting it fire would prove
      // nothing — the callback's own `mounted` check would swallow it and the
      // count would match either way. Leaving it un-fired hands the assertion
      // to flutter_test itself, which fails a test that ends with a timer
      // pending after the tree was disposed. Confirmed by removing the cancel:
      // «A Timer is still pending even after the widget tree was disposed.»
      await tester.pump(const Duration(seconds: 5));

      expect(reads, afterDispose,
          reason: 'a timer outliving the takeover would call setState on a '
              'dead State every minute for the rest of the session');
    });
  });
}
