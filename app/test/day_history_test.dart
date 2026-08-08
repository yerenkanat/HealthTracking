/// Screens 47/48 — «История дня» and one event from it.
///
/// The map is a platform view and cannot render here, so it is stubbed; what
/// is tested is everything floating above it, which is where the screen either
/// tells the truth or does not. The assertions that matter are the ones about
/// the three states — loaded, empty, failed — because an empty day and a
/// failed load are the pair this screen exists to keep apart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/day_history.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/day_event_screen.dart';
import 'package:fcs_app/ui/tracking/day_history_screen.dart';

const l = L10n(AppLocale.ru);
final now = DateTime(2026, 8, 8, 18);

DateTime at(int h, [int m = 0]) => DateTime(2026, 8, 8, h, m);

RoutePoint p(int h, double lat) =>
    RoutePoint(at: at(h), lat: lat, lng: 76.889);

DayHistory history({
  List<RoutePoint>? points,
  List<DayEvent>? events,
  int distanceM = 3200,
  int rawCount = 4,
}) =>
    DayHistory(
      day: '2026-08-08',
      points: points ?? [p(8, 43.238), p(9, 43.248), p(15, 43.240), p(17, 43.238)],
      distanceM: distanceM,
      rawCount: rawCount,
      events: events ?? const [],
      retentionDays: 90,
    );

/// Stands in for the platform-view map and records what it was handed.
List<RoutePoint> drawnPoints = [];
List<DayEvent> drawnEvents = [];

Widget stubMap(BuildContext _, List<RoutePoint> pts, List<DayEvent> evs) {
  drawnPoints = pts;
  drawnEvents = evs;
  return const ColoredBox(color: Color(0xFFDDDDDD));
}

Future<void> pumpHistory(
  WidgetTester tester, {
  required DayLoader load,
}) async {
  drawnPoints = [];
  drawnEvents = [];
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: FcsTheme.light(AppLocale.ru),
    home: const L10nScope(
      l10n: l,
      child: SizedBox.shrink(),
    ),
  ));
  await tester.pumpWidget(MaterialApp(
    theme: FcsTheme.light(AppLocale.ru),
    home: L10nScope(
      l10n: l,
      child: DayHistoryScreen(
        childName: 'Алия',
        load: load,
        routeMapBuilder: stubMap,
        now: now,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('formatting a distance', () {
    test('uses a comma and one decimal, as both languages write it', () {
      // «3,17 км» claims a precision GPS does not have over a day's walk.
      expect(formatDistance(3200), '3,2 км');
      expect(formatDistance(3170), '3,2 км');
    });

    test('stays in metres below a kilometre', () {
      expect(formatDistance(450), '450 м');
      expect(formatDistance(0), '0 м');
    });
  });

  group('parsing', () {
    test('drops an event kind this build does not know', () {
      // A server newer than the app. Dropping the row beats crashing the
      // screen and beats inventing a kind for it.
      final h = DayHistory.fromJson({
        'day': '2026-08-08',
        'events': [
          {'at': '2026-08-08T08:00:00.000Z', 'kind': 'teleported'},
          {'at': '2026-08-08T09:00:00.000Z', 'kind': 'sos'},
        ],
      });
      expect(h.events, hasLength(1));
      expect(h.events.single.kind, DayEventKind.sos);
    });

    test('an empty zone name reads as no zone, not as a zone called ""', () {
      final h = DayHistory.fromJson({
        'day': '2026-08-08',
        'events': [
          {'at': '2026-08-08T08:00:00.000Z', 'kind': 'exit', 'zoneName': ''},
        ],
      });
      expect(h.events.single.zoneName, isNull);
    });

    test('knows when the line was simplified', () {
      expect(history(rawCount: 900).wasSimplified, isTrue);
      expect(history(rawCount: 4).wasSimplified, isFalse);
    });
  });

  testWidgets('draws the badge with the distance and the point count',
      (tester) async {
    await pumpHistory(tester, load: (_) async => history());
    expect(find.text(l.t('day_route_badge', {'d': '3,2 км', 'n': 4})),
        findsOneWidget);
    expect(drawnPoints, hasLength(4));
  });

  testWidgets('says the line was simplified rather than leaving a discrepancy',
      (tester) async {
    // Otherwise «4 точки» beside a tracker that reports every thirty seconds
    // reads as a tracker that barely reported.
    await pumpHistory(tester, load: (_) async => history(rawCount: 900));
    expect(find.text(l.t('day_simplified', {'raw': 900, 'n': 4})),
        findsOneWidget);
  });

  testWidgets('an empty day explains itself instead of showing a blank map',
      (tester) async {
    await pumpHistory(
      tester,
      load: (_) async => history(points: const [], events: const []),
    );
    expect(find.text(l.t('day_empty')), findsOneWidget);
    expect(find.text(l.t('day_empty_why')), findsOneWidget);
    // And it is NOT the failure message — the two call for opposite responses.
    expect(find.text(l.t('day_failed')), findsNothing);
  });

  testWidgets('a failed load says so and offers to retry', (tester) async {
    var calls = 0;
    await pumpHistory(tester, load: (_) async {
      calls++;
      throw Exception('offline');
    });
    expect(find.text(l.t('day_failed')), findsOneWidget);
    // Emphatically not the empty state: «браслет ничего не записал» over a
    // request that 500ed is calmly, confidently wrong.
    expect(find.text(l.t('day_empty')), findsNothing);

    await tester.tap(find.text(l.t('day_retry')));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('prints the retention promise on every state', (tester) async {
    // Including the empty one — it is a promise about the data that is not
    // there as much as about the data that is.
    await pumpHistory(tester, load: (_) async => history(points: const []));
    expect(find.text(l.t('day_retention', {'n': 90})), findsOneWidget);
  });

  group('the timeline', () {
    testWidgets('names the zone she left and the one she arrived at',
        (tester) async {
      await pumpHistory(
        tester,
        load: (_) async => history(events: [
          DayEvent(at: at(8, 10), kind: DayEventKind.exit, zoneName: 'Дом'),
          DayEvent(
              at: at(8, 40), kind: DayEventKind.enter, zoneName: 'Школа №25'),
        ]),
      );
      expect(find.text(l.t('day_left_zone', {'zone': 'Дом'})), findsOneWidget);
      expect(find.text(l.t('day_entered_zone', {'zone': 'Школа №25'})),
          findsOneWidget);
      expect(find.text('08:10'), findsOneWidget);
    });

    testWidgets('still shows a crossing whose zone has been deleted',
        (tester) async {
      // The zone was tidied away afterwards. The crossing still happened, and
      // «зоны null» or dropping the row would both be worse than saying so.
      await pumpHistory(
        tester,
        load: (_) async => history(events: [
          DayEvent(at: at(8, 10), kind: DayEventKind.exit),
        ]),
      );
      expect(find.text(l.t('day_left_unknown')), findsOneWidget);
    });

    testWidgets('only an SOS opens a detail screen', (tester) async {
      // A row that looks tappable and does nothing is worse than one that
      // plainly is not.
      await pumpHistory(
        tester,
        load: (_) async => history(events: [
          DayEvent(at: at(8, 10), kind: DayEventKind.exit, zoneName: 'Дом'),
          DayEvent(at: at(16, 41), kind: DayEventKind.sos),
        ]),
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      await tester.tap(find.text(l.t('day_sos')));
      await tester.pumpAndSettle();
      expect(find.text(l.t('sos_event_title', {'time': '16:41'})),
          findsOneWidget);
    });
  });

  group('screen 48 — one SOS', () {
    Future<List<SosOutcome>> pumpEvent(
      WidgetTester tester, {
      List<DayEvent> later = const [],
      SosOutcomeSaver? onSave,
    }) async {
      final saved = <SosOutcome>[];
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: FcsTheme.light(AppLocale.ru),
        home: L10nScope(
          l10n: l,
          child: DayEventScreen(
            childName: 'Алия',
            event: DayEvent(at: at(16, 41), kind: DayEventKind.sos),
            laterEvents: later,
            routeMapBuilder: stubMap,
            onSaveOutcome: onSave ??
                (_, o) async {
                  saved.add(o);
                  return true;
                },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return saved;
    }

    testWidgets('names the child and the time', (tester) async {
      await pumpEvent(tester);
      expect(find.text(l.t('sos_event_title', {'time': '16:41'})),
          findsOneWidget);
      expect(find.text(l.t('sos_event_card', {'name': 'Алия'})), findsOneWidget);
    });

    testWidgets('puts the SOS on the map alone', (tester) async {
      await pumpEvent(tester);
      expect(drawnEvents, hasLength(1));
      expect(drawnEvents.single.kind, DayEventKind.sos);
    });

    testWidgets('offers four outcomes and no free-text box', (tester) async {
      // A parent closing an alarm at midnight will not write a paragraph, and
      // an outcome field that is usually empty tells nobody anything.
      await pumpEvent(tester);
      expect(find.byType(ChoiceChip), findsNWidgets(4));
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('cannot be saved until something is chosen', (tester) async {
      // Saving «ничего» as an outcome is worse than leaving the event open.
      await pumpEvent(tester);
      final btn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, l.t('sos_save_mark')));
      expect(btn.onPressed, isNull);
    });

    testWidgets('records the chosen outcome', (tester) async {
      final saved = await pumpEvent(tester);
      await tester.tap(find.text(l.t('sos_out_scared')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('sos_save_mark')));
      await tester.pumpAndSettle();
      expect(saved, [SosOutcome.scared]);
      expect(SosOutcome.scared.wire, 'scared');
    });

    testWidgets('says so when the save fails, rather than showing a tick',
        (tester) async {
      // A confirmation over a request that failed is how a parent believes the
      // alarm is closed when it is not.
      await pumpEvent(tester, onSave: (_, __) async => false);
      await tester.tap(find.text(l.t('sos_out_help')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('sos_save_mark')));
      await tester.pumpAndSettle();
      expect(find.text(l.t('day_failed')), findsOneWidget);
      expect(find.text(l.t('sos_mark_saved')), findsNothing);
    });

    testWidgets('«Что было дальше» lists what followed, and says when nothing did',
        (tester) async {
      await pumpEvent(tester);
      expect(find.text(l.t('sos_no_events')), findsOneWidget);

      await pumpEvent(tester, later: [
        DayEvent(at: at(17, 5), kind: DayEventKind.enter, zoneName: 'Дом'),
      ]);
      expect(find.text(l.t('day_entered_zone', {'zone': 'Дом'})), findsOneWidget);
      expect(find.text('17:05'), findsOneWidget);
    });

    testWidgets('hides the outcome section where nothing can record one',
        (tester) async {
      // Rather than offering a button that does nothing.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: FcsTheme.light(AppLocale.ru),
        home: L10nScope(
          l10n: l,
          child: DayEventScreen(
            childName: 'Алия',
            event: DayEvent(at: at(16, 41), kind: DayEventKind.sos),
            routeMapBuilder: stubMap,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(l.t('sos_how_ended')), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    });
  });
}
