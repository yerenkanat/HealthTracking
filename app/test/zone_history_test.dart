/// «История зон» — the app's half of `GET /children/:id/events`.
///
/// The route has been access-controlled and tested on the backend since
/// geofencing shipped and had no caller in `app/lib`: the back office could
/// read a child's boundary crossings and the mother could not. These tests
/// cover the three things that make the difference real — the call exists and
/// hits the right path, a screen renders what it returns, and something
/// OUTSIDE this file pushes that screen.
///
/// The assertions that matter most are the pair this screen exists to keep
/// apart: an empty history and a server that did not answer. Everything else
/// here is a companion to those.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/geofence_alerts.dart';
import 'package:fcs_app/domain/zone_crossing.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/alerts_screen.dart';
import 'package:fcs_app/ui/tracking/zone_history_screen.dart';

const ru = L10n(AppLocale.ru);
const kk = L10n(AppLocale.kk);
final now = DateTime(2026, 8, 15, 18);

Map<String, dynamic> wire(String at, String transition,
        {String name = 'Мектеп', String source = 'gps'}) =>
    {
      'childId': 'c1',
      'geofenceId': 'g1',
      'geofenceName': name,
      'transition': transition,
      'at': at,
      'source': source,
    };

/// Records what was asked for, and answers whatever the test set.
class _FakeTransport implements HttpTransport {
  final List<String> gets = [];
  HttpResponse answer = const HttpResponse(200, '{"events":[]}');

  @override
  Future<HttpResponse> get(String path) async {
    gets.add(path);
    return answer;
  }

  @override
  Future<HttpResponse> post(String path, Object jsonBody) async =>
      const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> put(String path, Object jsonBody) async =>
      const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> delete(String path) async =>
      const HttpResponse(200, '{}');
}

List<ZoneCrossing> _page(int n) => [
      for (var i = 0; i < n; i++)
        ZoneCrossing(
            transition: ZoneTransition.entered,
            at: DateTime(2026, 8, 15, 9).subtract(Duration(minutes: i)),
            zoneName: 'Үй'),
    ];

Future<void> pumpHistory(
  WidgetTester tester, {
  required ZoneCrossingLoader load,
  L10n l = ru,
  int limit = 50,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // L10nScope ABOVE MaterialApp, as app.dart builds it. Under `home:` it sits
  // below the Navigator and a PUSHED route falls back to English silently.
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(l.locale),
      home: ZoneHistoryScreen(
        childName: 'Алия',
        load: load,
        now: now,
        limit: limit,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('parsing what the route sends', () {
    test('reads a crossing, its zone, its source and its local time', () {
      final xs = ZoneCrossing.listFromJson([
        wire('2026-08-15T09:14:00.000Z', 'enter'),
      ]);
      expect(xs, hasLength(1));
      expect(xs.single.transition, ZoneTransition.entered);
      expect(xs.single.zoneName, 'Мектеп');
      expect(xs.single.source, 'gps');
      expect(xs.single.at.isUtc, isFalse,
          reason: 'a wall-clock time on a timeline must be her clock');
    });

    test('exit becomes left — the wire spelling never reaches the app', () {
      final xs = ZoneCrossing.listFromJson([
        wire('2026-08-15T09:14:00.000Z', 'exit'),
      ]);
      expect(xs.single.transition, ZoneTransition.left);
    });

    test('a row with an unknown transition is dropped, never defaulted', () {
      // THE assertion of this group. Defaulting an unreadable direction to
      // `entered` would put «Пришла в зону «Мектеп»» on screen for an event
      // that may have been the opposite one.
      final xs = ZoneCrossing.listFromJson([
        wire('2026-08-15T09:14:00.000Z', 'teleported'),
        wire('2026-08-15T10:00:00.000Z', 'enter'),
      ]);
      expect(xs, hasLength(1));
      expect(xs.single.at.hour, isNot(9));
    });

    test('a row with no usable timestamp is dropped', () {
      expect(
          ZoneCrossing.listFromJson([
            {'transition': 'enter', 'geofenceName': 'Үй'},
            {'transition': 'enter', 'at': 'not-a-date'},
          ]),
          isEmpty);
    });

    test('an unknown positioning source hides the label rather than printing it',
        () {
      final xs = ZoneCrossing.listFromJson(
          [wire('2026-08-15T09:14:00.000Z', 'enter', source: 'quantum')]);
      expect(xs.single.source, isNull);
    });

    test('newest first, whatever order the repository returned', () {
      final xs = ZoneCrossing.listFromJson([
        wire('2026-08-14T09:00:00.000Z', 'enter'),
        wire('2026-08-15T09:00:00.000Z', 'exit'),
      ]);
      expect(xs.first.transition, ZoneTransition.left);
    });
  });

  group('grouping by day', () {
    test('splits on the calendar day and keeps each day newest first', () {
      final xs = [
        ZoneCrossing(transition: ZoneTransition.entered, at: DateTime(2026, 8, 15, 9)),
        ZoneCrossing(transition: ZoneTransition.left, at: DateTime(2026, 8, 15, 14)),
        ZoneCrossing(transition: ZoneTransition.entered, at: DateTime(2026, 8, 14, 9)),
      ];
      final days = groupCrossingsByDay(xs);
      expect(days, hasLength(2));
      expect(days.first.day, DateTime(2026, 8, 15));
      expect(days.first.crossings.first.at.hour, 14);
      expect(days.last.crossings, hasLength(1));
    });

    test('a month boundary is two days, not one', () {
      final days = groupCrossingsByDay([
        ZoneCrossing(transition: ZoneTransition.entered, at: DateTime(2026, 9, 1, 0, 5)),
        ZoneCrossing(transition: ZoneTransition.left, at: DateTime(2026, 8, 31, 23, 55)),
      ]);
      expect(days, hasLength(2));
    });
  });

  group('the API call', () {
    test('asks the route the back office reads, with its limit', () async {
      final t = _FakeTransport();
      t.answer = HttpResponse(
          200, jsonEncode({'events': [wire('2026-08-15T09:14:00.000Z', 'enter')]}));
      final xs = await ApiClient(t).getZoneCrossings('c1', limit: 20);
      expect(t.gets.single, '/children/c1/events?limit=20');
      expect(xs, hasLength(1));
    });

    test('a refusal THROWS rather than reading as an empty history', () async {
      // The whole point of the screen's third state. A 403 flattened into an
      // empty list would render «Пересечений зон не записано» to somebody who
      // was simply not allowed to look.
      final t = _FakeTransport();
      t.answer = const HttpResponse(403, '{"error":"forbidden"}');
      expect(() => ApiClient(t).getZoneCrossings('c1'), throwsA(isA<ApiException>()));
    });
  });

  group('the screen', () {
    testWidgets('prints each crossing with its time, zone and source',
        (tester) async {
      await pumpHistory(tester, load: () async => [
            ZoneCrossing(
                transition: ZoneTransition.entered,
                at: DateTime(2026, 8, 15, 9, 14),
                zoneName: 'Мектеп',
                source: 'gps'),
            ZoneCrossing(
                transition: ZoneTransition.left,
                at: DateTime(2026, 8, 15, 13, 2),
                zoneName: 'Мектеп',
                source: 'lbs'),
          ]);

      expect(find.text('09:14'), findsOneWidget);
      expect(find.text('13:02'), findsOneWidget);
      expect(find.text(ru.t('day_entered_zone', {'zone': 'Мектеп'})), findsOneWidget);
      expect(find.text(ru.t('day_left_zone', {'zone': 'Мектеп'})), findsOneWidget);
      // The instrument is named, not judged. A crossing derived from a cell
      // tower and one derived from GPS are not the same evidence.
      expect(find.text(ru.t('possrc_gps')), findsOneWidget);
      expect(find.text(ru.t('possrc_lbs')), findsOneWidget);
    });

    testWidgets('an arrival and a departure do not render identically',
        (tester) async {
      await pumpHistory(tester, load: () async => [
            ZoneCrossing(
                transition: ZoneTransition.entered,
                at: DateTime(2026, 8, 15, 9),
                zoneName: 'Үй'),
            ZoneCrossing(
                transition: ZoneTransition.left,
                at: DateTime(2026, 8, 15, 8),
                zoneName: 'Үй'),
          ]);
      expect(find.byIcon(Icons.login_rounded), findsOneWidget);
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    });

    testWidgets('an SOS is never implied — the screen says what it is not',
        (tester) async {
      // The panel had this exact defect: a button somebody pressed and a child
      // walking past a boundary rendered as one kind of thing. `geofence_events`
      // holds enter/exit only, so the screen must say so rather than let a
      // parent read it as everything that happened.
      await pumpHistory(tester, load: () async => [
            ZoneCrossing(
                transition: ZoneTransition.entered,
                at: DateTime(2026, 8, 15, 9),
                zoneName: 'Мектеп'),
          ]);
      expect(find.text(ru.t('zonehist_scope')), findsOneWidget);
      expect(find.text(ru.t('day_sos')), findsNothing);
      expect(find.byIcon(Icons.sos_rounded), findsNothing);
    });

    testWidgets('an empty history says nothing was recorded, not that it failed',
        (tester) async {
      await pumpHistory(tester, load: () async => []);
      expect(find.text(ru.t('zonehist_empty')), findsOneWidget);
      expect(find.text(ru.t('zonehist_empty_why')), findsOneWidget);
      expect(find.text(ru.t('day_failed')), findsNothing);
    });

    testWidgets('a failed load never renders as an empty history',
        (tester) async {
      // THE assertion of this file. A dead network must not read as a quiet
      // week, and this app keeps conflating the two.
      await pumpHistory(tester, load: () async => throw Exception('offline'));
      expect(find.text(ru.t('day_failed')), findsOneWidget);
      expect(find.text(ru.t('zonehist_failed_why')), findsOneWidget);
      expect(find.text(ru.t('zonehist_empty')), findsNothing);
      expect(find.text(ru.t('zonehist_empty_why')), findsNothing);
    });

    testWidgets('the failure offers a retry, and the retry re-asks',
        (tester) async {
      var calls = 0;
      await pumpHistory(tester, load: () async {
        calls++;
        if (calls == 1) throw Exception('offline');
        return [
          ZoneCrossing(
              transition: ZoneTransition.entered,
              at: DateTime(2026, 8, 15, 9),
              zoneName: 'Үй'),
        ];
      });
      expect(find.text(ru.t('day_failed')), findsOneWidget);
      await tester.tap(find.text(ru.t('day_retry')));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text(ru.t('day_entered_zone', {'zone': 'Үй'})), findsOneWidget);
      expect(find.text(ru.t('day_failed')), findsNothing);
    });

    testWidgets('says there are no coordinates instead of drawing a place',
        (tester) async {
      // On every state, empty included: it is a statement about what this data
      // IS, and it stays true when there is none of it.
      await pumpHistory(tester, load: () async => []);
      expect(find.text(ru.t('zonehist_no_coords')), findsOneWidget);
    });

    testWidgets('a full page says so rather than implying it is everything',
        (tester) async {
      await pumpHistory(tester, load: () async => _page(5), limit: 5);
      expect(find.text(ru.t('zonehist_capped', {'n': 5})), findsOneWidget);
    });

    testWidgets('a short page claims nothing about a cap', (tester) async {
      await pumpHistory(tester, load: () async => _page(3), limit: 5);
      expect(find.text(ru.t('zonehist_capped', {'n': 3})), findsNothing);
    });

    testWidgets('today is named; another day carries its date', (tester) async {
      await pumpHistory(tester, load: () async => [
            ZoneCrossing(
                transition: ZoneTransition.entered,
                at: DateTime(2026, 8, 15, 9),
                zoneName: 'Үй'),
            ZoneCrossing(
                transition: ZoneTransition.left,
                at: DateTime(2026, 8, 13, 9),
                zoneName: 'Үй'),
          ]);
      expect(find.text(ru.t('today_title')), findsOneWidget);
      expect(find.text('2026-08-13'), findsOneWidget);
    });

    testWidgets('the Kazakh reader gets Kazakh, not a raw key', (tester) async {
      await pumpHistory(tester, l: kk, load: () async => []);
      expect(find.text(kk.t('zonehist_empty')), findsOneWidget);
      expect(find.text(kk.t('zonehist_scope')), findsOneWidget);
      for (final key in ['zonehist_empty', 'zonehist_scope', 'zonehist_no_coords']) {
        expect(kk.t(key), isNot(key), reason: '$key has no Kazakh');
        expect(kk.t(key), isNot(ru.t(key)), reason: '$key is Russian in Kazakh');
      }
    });
  });

  group('something outside the screen pushes it', () {
    // The dominant defect in this repository is a finished screen nothing
    // opens. These two drive the real AlertsScreen.
    Future<void> pumpAlerts(WidgetTester tester, AppController c) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(L10nScope(
        l10n: ru,
        child: MaterialApp(
          theme: FcsTheme.light(AppLocale.ru),
          home: AlertsScreen(controller: c, now: () => now),
        ),
      ));
      await tester.pumpAndSettle();
    }

    AppController wired(_FakeTransport t) {
      final c = AppController();
      addTearDown(c.dispose);
      c.addChild(const ChildProfile(id: 'c1', name: 'Алия'));
      c.attachRuntime(api: ApiClient(t));
      return c;
    }

    testWidgets('the empty feed offers the server record it cannot see',
        (tester) async {
      final t = _FakeTransport();
      t.answer = HttpResponse(200, jsonEncode({
        'events': [wire('2026-08-15T04:14:00.000Z', 'enter')],
      }));
      await pumpAlerts(tester, wired(t));

      // The claim being qualified: this feed is what THIS phone remembers.
      expect(find.text(ru.t('alerts_empty')), findsOneWidget);
      await tester.tap(find.text(ru.t('zonehist_open')));
      await tester.pumpAndSettle();

      // A PUSHED route — the case `home: L10nScope` silently renders in
      // English. Asserting on Russian text here is what catches that.
      expect(find.text(ru.t('zonehist_title', {'name': 'Алия'})), findsOneWidget);
      expect(t.gets.single, startsWith('/children/c1/events'));
      expect(find.text(ru.t('day_entered_zone', {'zone': 'Мектеп'})), findsOneWidget);
    });

    testWidgets('a feed with alerts in it keeps one way through, in the bar',
        (tester) async {
      final t = _FakeTransport();
      final c = wired(t);
      c.mergeRemoteAlerts([
        SafetyAlert(
            kind: AlertKind.entered,
            childName: 'Алия',
            zoneName: 'Мектеп',
            at: now.subtract(const Duration(hours: 2))),
      ]);
      await pumpAlerts(tester, c);

      // Exactly one control, never two: the labelled button belongs to the
      // empty state and the icon to the populated one.
      expect(find.text(ru.t('zonehist_open')), findsNothing);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.history_rounded));
      await tester.pumpAndSettle();
      expect(find.text(ru.t('zonehist_title', {'name': 'Алия'})), findsOneWidget);
    });

    testWidgets('no server configured offers nothing to open', (tester) async {
      final c = AppController();
      addTearDown(c.dispose);
      c.addChild(const ChildProfile(id: 'c1', name: 'Алия'));
      await pumpAlerts(tester, c);
      expect(find.text(ru.t('zonehist_open')), findsNothing);
      expect(find.byIcon(Icons.history_rounded), findsNothing);
    });
  });
}
