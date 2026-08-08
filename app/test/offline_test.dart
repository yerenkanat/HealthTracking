/// Screen 20 — «Офлайн».
///
/// The screen exists because of one sentence a parent says to herself: «она
/// дома», read off a map that has not updated for half an hour. So the tests
/// that matter are the ones about the map REFUSING to look live — and about
/// the refresh button admitting when it did not refresh.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/domain/offline.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/child_map_screen.dart';

const l = L10n(AppLocale.ru);
final now = DateTime(2026, 8, 8, 15, 0);

Future<int> pumpMap(
  WidgetTester tester, {
  bool offline = false,
  DateTime? updatedAt,
  Future<bool> Function()? onRefresh,
}) async {
  var refreshes = 0;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: ChildMapScreen(
        childName: 'Алия',
        childLocation: const Coordinates(43.238, 76.889),
        updatedAt: updatedAt,
        fences: const [],
        now: now,
        isOffline: offline,
        onRefresh: onRefresh == null
            ? null
            : () async {
                refreshes++;
                return onRefresh();
              },
        mapBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF88AA88)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return refreshes;
}

void main() {
  group('when the map must stop looking live', () {
    test('with no connection, always', () {
      expect(
        mapShouldLookStale(offline: true, sinceLastFix: const Duration(seconds: 5)),
        isTrue,
      );
    });

    test('with a connection but an old fix', () {
      // Four bars and a tracker that stopped reporting an hour ago still draws
      // a confident pin unless this is checked too.
      expect(
        mapShouldLookStale(offline: false, sinceLastFix: const Duration(minutes: 40)),
        isTrue,
      );
      expect(
        mapShouldLookStale(offline: false, sinceLastFix: const Duration(minutes: 3)),
        isFalse,
      );
    });

    test('with no fix at all', () {
      // Nothing to be confident about.
      expect(mapShouldLookStale(offline: false, sinceLastFix: null), isTrue);
    });
  });

  group('how old the data is', () {
    test('counts whole minutes', () {
      final a = dataAge(now.subtract(const Duration(minutes: 26)), now)!;
      expect(a.minutesAgo, 26);
      expect(a.overAnHour, isFalse);
    });

    test('never goes negative', () {
      // A fix stamped in the future means the clocks disagree, and «−3 минуты
      // назад» on a screen whose whole job is to be believed is worse than
      // saying nothing.
      final a = dataAge(now.add(const Duration(minutes: 3)), now)!;
      expect(a.minutesAgo, 0);
    });

    test('switches to hours past sixty minutes', () {
      final a = dataAge(now.subtract(const Duration(minutes: 190)), now)!;
      expect(a.overAnHour, isTrue);
      expect(a.hoursAgo, 3);
    });

    test('is null when nothing has ever arrived', () {
      expect(dataAge(null, now), isNull);
    });
  });

  group('what still works', () {
    test('leads with the tracker\'s own SOS', () {
      // A parent who has just found out she has no connection is working out
      // whether her child is still protected. That is the answer, and it goes
      // first.
      expect(offlineActions.first, OfflineAction.childSosStillWorks);
      expect(offlineActions, hasLength(4));
    });
  });

  testWidgets('offline: the plate names the reason and the age', (tester) async {
    await pumpMap(
      tester,
      offline: true,
      updatedAt: now.subtract(const Duration(minutes: 26)),
    );
    expect(find.text(l.t('off_no_internet')), findsOneWidget);
    expect(
      find.text(l.t('off_data_from', {'time': '14:34', 'n': 26})),
      findsOneWidget,
    );
  });

  testWidgets('a stale fix ON a connection says the age but not «нет интернета»',
      (tester) async {
    // The two causes are separate and must not be conflated: telling her the
    // internet is down when it is not sends her to reboot a router.
    await pumpMap(tester, updatedAt: now.subtract(const Duration(minutes: 40)));
    expect(find.text(l.t('off_no_internet')), findsNothing);
    expect(find.text(l.t('off_data_from', {'time': '14:20', 'n': 40})),
        findsOneWidget);
  });

  testWidgets('a fresh fix shows no plate at all', (tester) async {
    await pumpMap(tester, updatedAt: now.subtract(const Duration(minutes: 2)));
    expect(find.text(l.t('off_no_internet')), findsNothing);
    expect(find.text(l.t('off_what_now')), findsNothing);
  });

  testWidgets('the map loses its colour when it must not look live',
      (tester) async {
    // A map that looks identical at one minute and at forty is how «она дома»
    // gets said about a position from half an hour ago.
    await pumpMap(tester, offline: true, updatedAt: now);
    expect(find.byType(ColorFiltered), findsWidgets);
  });

  testWidgets('and keeps it when the fix is current', (tester) async {
    await pumpMap(tester, updatedAt: now.subtract(const Duration(minutes: 1)));
    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('with no fix ever, it says so rather than showing a dash',
      (tester) async {
    await pumpMap(tester, offline: true);
    expect(find.text(l.t('off_no_data')), findsOneWidget);
  });

  testWidgets('the status card does not say «В сети» under «Нет интернета»',
      (tester) async {
    // Two of the app's own elements contradicting each other about the one
    // fact the screen exists to state. The fix is that offline forces the
    // freshness the card reads.
    await pumpMap(tester, offline: true, updatedAt: now);
    expect(find.text(l.t('off_no_internet')), findsOneWidget);
    expect(find.text(l.t('fresh_live')), findsNothing);
  });

  testWidgets('the plate fits a 390 dp phone', (tester) async {
    // Its two buttons side by side overflowed by 115 px in Russian, which put
    // «Обновить» off the right edge — unreachable, on the screen a parent
    // opens when she cannot find her child. A widget test does not fail on an
    // overflow by default; this asserts it explicitly.
    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = prev);

    await pumpMap(tester, offline: true, updatedAt: now, onRefresh: () async => true);
    expect(
      errors.where((e) => '${e.exception}'.contains('overflowed')),
      isEmpty,
    );
  });

  testWidgets('«Что можно сделать» lists what still works', (tester) async {
    await pumpMap(tester, offline: true, updatedAt: now);
    await tester.tap(find.text(l.t('off_what_now')));
    await tester.pumpAndSettle();
    for (final a in offlineActions) {
      expect(find.text(l.t(a.l10nKey)), findsOneWidget);
    }
  });

  group('«Обновить»', () {
    testWidgets('asks again, and says nothing when it worked', (tester) async {
      // The counter has to be read AFTER the tap. An earlier version compared
      // the value pumpMap returned — captured before the button was ever
      // pressed — so it asserted 0 == 0 and would have passed against a button
      // wired to nothing.
      var calls = 0;
      await pumpMap(tester, offline: true, updatedAt: now, onRefresh: () async {
        calls++;
        return true;
      });
      await tester.tap(find.text(l.t('off_refresh')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text(l.t('off_refresh_failed')), findsNothing);
    });

    testWidgets('says so when it still could not reach the server',
        (tester) async {
      // A refresh button that quietly does nothing teaches her the app is
      // broken rather than that the connection is.
      await pumpMap(
        tester, offline: true, updatedAt: now, onRefresh: () async => false);
      await tester.tap(find.text(l.t('off_refresh')));
      await tester.pumpAndSettle();
      expect(find.text(l.t('off_refresh_failed')), findsOneWidget);
    });

    testWidgets('is absent with no server to ask', (tester) async {
      await pumpMap(tester, offline: true, updatedAt: now);
      expect(find.text(l.t('off_refresh')), findsNothing);
      // But the help sheet is still offered — it is the more useful half.
      expect(find.text(l.t('off_what_now')), findsOneWidget);
    });
  });
}
