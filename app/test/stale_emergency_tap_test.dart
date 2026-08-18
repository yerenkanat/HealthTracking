/// TODO §2.3 — a tapped emergency notification had no age.
///
/// `handleNotificationTap` read `code` out of an `EmergencyRescue` payload and
/// raised the full takeover, unconditionally. A notification stays in the tray
/// until it is dismissed, so a woman who found one in the evening from a
/// crossing at nine that morning — measured again, called her doctor, done —
/// got «Обратитесь за неотложной помощью» in the present tense about a body
/// that had since moved, eaten and slept. That is the alarm fatigue
/// emergency_confirmation.dart exists to prevent, reintroduced at the last
/// step of the chain.
///
/// WHAT WOULD FAIL IF THE FIX WERE REVERTED, per group:
///
///   * "still happening" — nothing. This is the pin: the live case must behave
///     EXACTLY as it did before, and a staleness rule that quietly swallows a
///     real emergency is a worse defect than the one being fixed.
///   * "over" — the takeover is raised and `c.route` is `AppRoute.emergency`.
///   * "undatable" — same; every payload without a usable `at` raises it.
///   * "she is shown when it happened" — the shell has no vitalsHistory branch
///     to push, so nothing opens and the reading's age is never rendered.
///   * "the server sends the timestamp this depends on" — push.ts composes an
///     emergency `data` block with no `at`, so in production EVERY tap would be
///     undatable and no takeover would ever be raised again.
///
/// The window is not a new number: [emergencyTakeoverMaxAge] IS
/// `latestTelemetryMaxAge`, the app's existing definition of «how long does a
/// reading still describe how she is now» (health_monitor.dart), which was
/// written against this exact failure in the chat guardrail.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/health_monitor.dart' show latestTelemetryMaxAge;
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/notification_route.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/main.dart' show handleNotificationTap;
import 'package:fcs_app/ui/dashboard/metric_detail_screen.dart';
import 'package:fcs_app/ui/home_shell.dart';
import 'package:fcs_app/ui/theme.dart';

const l = L10n(AppLocale.ru);

/// 20:30 — the evening she finds the notification.
final now = DateTime(2026, 8, 17, 20, 30);

/// The morning crossing, eleven and a half hours earlier.
final thisMorning = DateTime(2026, 8, 17, 9, 0);

/// Four minutes ago — this is happening.
final justNow = now.subtract(const Duration(minutes: 4));

/// The payload the server sends for a medical emergency, with [at] as the
/// instant of the crossing. Built the way push.ts builds it (UTC ISO-8601)
/// rather than hand-typed, so this file cannot drift into testing a shape
/// nothing sends.
String emergencyPayload({String code = 'PREECLAMPSIA_BP', DateTime? at}) =>
    '{"screen":"EmergencyRescue","code":"$code"'
    '${at == null ? '' : ',"at":"${at.toUtc().toIso8601String()}"'}}';

AppController controllerAt(DateTime clock) {
  final c = AppController(now: () => clock, locale: AppLocale.ru);
  c.debugMarkOnboarded();
  return c;
}

Future<void> pumpShell(WidgetTester tester, AppController c) async {
  tester.view.physicalSize = const Size(390 * 3, 1000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // L10nScope ABOVE MaterialApp. MetricDetailScreen is PUSHED, and below the
  // Navigator the scope silently falls back to English — the age line this
  // whole test is about would be asserted in the wrong language.
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      // The StreamBuilder is not scaffolding — it is how FcsApp mounts the
      // shell (app/app.dart), and it is the thing that rebuilds it when a
      // notification tap stages a destination from outside the widget tree.
      // Without it the shell never builds again and nothing is ever spent.
      home: StreamBuilder<void>(
        stream: c.changes,
        builder: (_, __) =>
            HomeShell(controller: c, catalog: const ContentCatalog({})),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // ---- Still happening: nothing about this may change ---------------------

  group('an emergency from four minutes ago still takes the screen over', () {
    test('the takeover is raised, localized by code', () {
      final c = controllerAt(now);
      addTearDown(c.dispose);
      handleNotificationTap(c, emergencyPayload(at: justNow));
      expect(c.route, AppRoute.emergency,
          reason: 'a live emergency must behave exactly as it always has');
      expect(c.emergency!.message, l.triageMessage('PREECLAMPSIA_BP'));
    });

    test('and nothing is staged behind it', () {
      // A live tap must not ALSO queue a history screen for the shell to push
      // over the takeover the moment she dismisses it.
      final c = controllerAt(now);
      addTearDown(c.dispose);
      handleNotificationTap(c, emergencyPayload(at: justNow));
      expect(c.pendingDestination, isNull);
      expect(c.pendingMetricKey, isNull);
    });

    test('the window is the app\'s existing one, not a second opinion', () {
      expect(emergencyTakeoverMaxAge, latestTelemetryMaxAge);
    });

    test('at the edge of the window it is still live', () {
      final c = controllerAt(now);
      addTearDown(c.dispose);
      handleNotificationTap(
          c, emergencyPayload(at: now.subtract(emergencyTakeoverMaxAge)));
      expect(c.route, AppRoute.emergency);
    });

    test('a minute past the edge it is not', () {
      final c = controllerAt(now);
      addTearDown(c.dispose);
      handleNotificationTap(
          c,
          emergencyPayload(
              at: now.subtract(
                  emergencyTakeoverMaxAge + const Duration(minutes: 1))));
      expect(c.route, isNot(AppRoute.emergency));
    });

    test('ordinary phone-vs-server skew is not staleness', () {
      // A timestamp a minute AHEAD of us is two clocks disagreeing slightly,
      // not a reading from the future. Treating it as undatable would silence
      // live emergencies on every phone whose clock runs a little slow.
      final c = controllerAt(now);
      addTearDown(c.dispose);
      handleNotificationTap(
          c, emergencyPayload(at: now.add(const Duration(minutes: 1))));
      expect(c.route, AppRoute.emergency);
    });
  });

  // ---- Over: the defect itself --------------------------------------------

  group('an emergency from this morning does not', () {
    test('no takeover is raised', () {
      final c = controllerAt(now);
      addTearDown(c.dispose);
      handleNotificationTap(c, emergencyPayload(at: thisMorning));
      expect(c.route, isNot(AppRoute.emergency),
          reason: 'a crossing eleven hours old was re-raised as though it were '
              'happening now — TODO §2.3');
      expect(c.emergency, isNull);
    });

    test('the reading is opened in its own history instead', () {
      final c = controllerAt(now);
      addTearDown(c.dispose);
      handleNotificationTap(c, emergencyPayload(at: thisMorning));
      expect(c.pendingDestination, NotifyDestination.vitalsHistory);
      expect(c.pendingMetricKey, 'systolic',
          reason: 'a blood-pressure crossing must open the blood-pressure '
              'series, not whatever the shell would have guessed');
    });

    test('each family of finding opens its own series', () {
      for (final (code, metric) in [
        ('PREECLAMPSIA_BP_SEVERE', 'systolic'),
        ('HIGH_FEVER', 'temp'),
        ('HYPOXIA', 'spo2'),
        ('TACHYCARDIA', 'hr'),
      ]) {
        final c = controllerAt(now);
        addTearDown(c.dispose);
        handleNotificationTap(c, emergencyPayload(code: code, at: thisMorning));
        expect(c.pendingDestination, NotifyDestination.vitalsHistory,
            reason: code);
        expect(c.pendingMetricKey, metric, reason: code);
      }
    });

    test('a finding with no number behind it falls back to the dashboard', () {
      // SYMPTOM_RED_FLAG has no series to open. The dashboard is the honest
      // destination — never nothing, and never a blank metric screen.
      final c = controllerAt(now);
      addTearDown(c.dispose);
      handleNotificationTap(
          c, emergencyPayload(code: 'SYMPTOM_RED_FLAG', at: thisMorning));
      expect(c.route, isNot(AppRoute.emergency));
      expect(c.pendingDestination, NotifyDestination.dashboard);
      expect(c.pendingMetricKey, isNull);
    });
  });

  // ---- Undatable: fail toward NOT raising it ------------------------------

  group('an emergency the app cannot date does not either', () {
    final undatable = <String, String>{
      'no at at all (a push from an older build)': emergencyPayload(),
      'an at that is not a date': '{"screen":"EmergencyRescue",'
          '"code":"PREECLAMPSIA_BP","at":"вчера"}',
      'an empty at': '{"screen":"EmergencyRescue",'
          '"code":"PREECLAMPSIA_BP","at":""}',
      'a clock far enough ahead that we do not know the age':
          emergencyPayload(at: now.add(const Duration(hours: 3))),
    };

    for (final entry in undatable.entries) {
      test(entry.key, () {
        final c = controllerAt(now);
        addTearDown(c.dispose);
        handleNotificationTap(c, entry.value);
        expect(c.route, isNot(AppRoute.emergency),
            reason: 'not knowing the age is not permission to claim it is now');
        expect(c.emergency, isNull);
        expect(c.pendingDestination, NotifyDestination.vitalsHistory);
      });
    }
  });

  // ---- What she actually sees ---------------------------------------------
  //
  // Driven through the real shell. A destination staged on the controller that
  // no branch of `_goTo` spends is the defect this repo is full of, and it
  // would look identical in every controller-level test above.

  group('she is shown WHEN it happened', () {
    testWidgets('a stale tap pushes the reading\'s history, with its age on it',
        (tester) async {
      final c = controllerAt(now);
      addTearDown(c.dispose);
      c.debugSeed([
        HealthSample(
          at: thisMorning,
          systolic: 165,
          diastolic: 110,
          source: ReadingSource.manual,
        ),
      ]);
      await pumpShell(tester, c);

      handleNotificationTap(c, emergencyPayload(at: thisMorning));
      await tester.pumpAndSettle();

      expect(find.byType(MetricDetailScreen), findsOneWidget,
          reason: 'the shell staged a destination it never spent');
      // The reading she was pushed about, as the 44px headline number — the
      // chart's guide labels repeat it, so the size is what identifies it.
      expect(
        tester
            .widgetList<Text>(find.text('165'))
            .where((t) => t.style?.fontSize == 44),
        hasLength(1),
      );
      // And — the point of the whole change — the time, directly under it.
      final ago = l.agoIfKnown(now.difference(thisMorning));
      expect(ago, isNotNull);
      expect(find.text(ago!), findsOneWidget,
          reason: 'she must be able to read that this was hours ago');
    });

    testWidgets('a live tap pushes nothing — the takeover is the screen',
        (tester) async {
      final c = controllerAt(now);
      addTearDown(c.dispose);
      await pumpShell(tester, c);

      handleNotificationTap(c, emergencyPayload(at: justNow));
      await tester.pumpAndSettle();

      expect(find.byType(MetricDetailScreen), findsNothing);
      expect(c.route, AppRoute.emergency);
    });
  });

  // ---- The other codebase -------------------------------------------------

  group('the server sends the timestamp this depends on', () {
    // Read from source because there is no Dart-side behaviour that can see it,
    // and the failure mode is silent and total: strip `at` from the emergency
    // push and every tap becomes undatable, so the takeover — the highest-stakes
    // screen in the app — simply stops being raised. Nothing else in this repo
    // would go red.
    final source =
        File('../packages/backend/src/notifications/push.ts').readAsStringSync();
    final fn = source.substring(source.indexOf('export function emergencyCopy'));
    // The DATA block only — not the signature, which also mentions `at` and
    // would make this pass while the payload carried nothing.
    final start = fn.indexOf("screen: 'EmergencyRescue'");
    final block = fn.substring(start, fn.indexOf('};', start));

    test('emergencyCopy puts `at` in the EmergencyRescue data block', () {
      expect(start, isNonNegative);
      expect(block, contains('code:'));
      expect(block, contains('at:'),
          reason: 'without it handleNotificationTap can never date a tap, and '
              'no emergency notification raises the takeover for anyone');
    });
  });
}
