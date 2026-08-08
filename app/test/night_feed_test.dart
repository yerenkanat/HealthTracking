/// Screen 22 — «Ночь · кормление».
///
/// The newborn log could record that a feed HAPPENED. It could not time one,
/// and at 4am the question is not «did I feed her» but «how long has she been
/// on this side» — the number a mother is trying to hold in her head while half
/// asleep, which is exactly what a phone is for.
///
/// The behavioural rules of §2.17 are what this file mostly checks: big
/// figures, the action in the bottom third, vibration instead of sound. She is
/// holding a baby with one arm in the dark.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/newborn_log.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/design_system.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/night_feed_screen.dart';

void main() {
  var now = DateTime(2026, 8, 8, 4, 0);

  Future<List<NewbornEvent>> pump(
    WidgetTester tester, {
    List<NewbornEvent> events = const [],
  }) async {
    final logged = <NewbornEvent>[];
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: L10nScope(
        l10n: const L10n(AppLocale.ru),
        child: NightFeedScreen(
          childName: 'Алия',
          events: events,
          onLog: logged.add,
          now: () => now,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return logged;
  }

  testWidgets('it is a night screen', (tester) async {
    await pump(tester);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, Ds.nightBg);
  });

  testWidgets('the clock is the biggest thing on it', (tester) async {
    // «крупные цифры» — read at arm's length, in the dark, without glasses.
    await pump(tester);
    final clock = tester.widget<Text>(find.text('0:00'));
    expect(clock.style?.fontSize, 52);
  });

  testWidgets('the action sits in the bottom third', (tester) async {
    // «действие в нижней трети» — reached with a thumb, not aimed at.
    await pump(tester);
    const l = L10n(AppLocale.ru);
    final y = tester.getTopLeft(find.text(l.t('nightfeed_start'))).dy;
    final h = tester.getSize(find.byType(Scaffold).first).height;
    expect(y, greaterThan(h * 0.66));
  });

  group('timing a feed', () {
    testWidgets('runs, pauses and keeps what it counted', (tester) async {
      const l = L10n(AppLocale.ru);
      await pump(tester);

      await tester.tap(find.text(l.t('nightfeed_start')));
      await tester.pump();
      // Move the injected clock rather than waiting eight real minutes.
      now = now.add(const Duration(minutes: 8));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('8:00'), findsOneWidget);

      await tester.tap(find.text(l.t('nightfeed_pause')));
      await tester.pumpAndSettle();
      // Paused time must NOT keep accruing — she has put the baby down.
      now = now.add(const Duration(minutes: 5));
      await tester.pump();
      expect(find.text('8:00'), findsOneWidget);

      await tester.tap(find.text(l.t('nightfeed_resume')));
      await tester.pump();
      now = now.add(const Duration(minutes: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('10:00'), findsOneWidget);
    });

    testWidgets('finishing records the feed with its length', (tester) async {
      const l = L10n(AppLocale.ru);
      final logged = await pump(tester);
      await tester.tap(find.text(l.t('nightfeed_start')));
      await tester.pump();
      now = now.add(const Duration(minutes: 12));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text(l.t('nightfeed_finish')));
      await tester.pumpAndSettle();

      expect(logged, hasLength(1));
      expect(logged.single.kind, NewbornEventKind.feed);
      expect(logged.single.durationMin, 12);
    });

    testWidgets('a mis-tap under a minute records nothing', (tester) async {
      // Otherwise the day averages fill with zero-minute feeds, and those
      // averages are what a clinic asks about.
      const l = L10n(AppLocale.ru);
      final logged = await pump(tester);
      await tester.tap(find.text(l.t('nightfeed_start')));
      await tester.pump();
      now = now.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text(l.t('nightfeed_finish')));
      await tester.pumpAndSettle();
      expect(logged, isEmpty);
    });
  });

  testWidgets('a nappy can be logged without losing the running timer',
      (tester) async {
    // It happens mid-feed, and making her finish the timer to record it is how
    // the timer stops being used.
    const l = L10n(AppLocale.ru);
    final logged = await pump(tester);
    await tester.tap(find.text(l.t('nightfeed_start')));
    await tester.pump();
    now = now.add(const Duration(minutes: 3));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text(l.t('nb_diaper')));
    await tester.pumpAndSettle();

    expect(logged.single.kind, NewbornEventKind.diaper);
    // Still running, still counting.
    expect(find.text('3:00'), findsOneWidget);
  });

  testWidgets('it says when the last feed was, which is the 3am question',
      (tester) async {
    const l = L10n(AppLocale.ru);
    await pump(tester, events: [
      NewbornEvent(
        at: now.subtract(const Duration(minutes: 95)),
        kind: NewbornEventKind.feed,
      ),
    ]);
    expect(find.text(l.t('nightfeed_ago', {'n': 95})), findsOneWidget);
  });

  testWidgets('with no feeds yet it says so rather than showing a dash',
      (tester) async {
    const l = L10n(AppLocale.ru);
    await pump(tester);
    expect(find.text(l.t('nightfeed_none_yet')), findsOneWidget);
  });
}
