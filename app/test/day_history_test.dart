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
  SosOutcomeSaver? onSaveOutcome,
}) async {
  drawnPoints = [];
  drawnEvents = [];
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // L10nScope ABOVE MaterialApp, exactly as app.dart builds it. Under `home:`
  // it sits below the Navigator, so a PUSHED route cannot see it and
  // L10nScope.of falls back to English — the screen then renders in a language
  // the app never selected, and only on the second screen. Getting this wrong
  // here made a working feature look broken.
  await tester.pumpWidget(const L10nScope(l10n: l, child: SizedBox.shrink()));
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: DayHistoryScreen(
        childName: 'Алия',
        load: load,
        routeMapBuilder: stubMap,
        now: now,
        onSaveOutcome: onSaveOutcome,
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

  group('the retention card at the bottom', () {
    // TODO §9.9. The card used to read «Маршруты хранятся 90 дней, потом
    // удаляются автоматически» on every state, directly under a list of zone
    // crossings and SOS events. That sentence is true about location_history,
    // which really is swept every six hours, and false about everything the
    // list contains: geofence_events and safety_alerts have no sweep at all and
    // live until the account is deleted. A mother reading it over her
    // daughter's SOS was told the opposite of what happens to it.

    testWidgets('says what happens to the crossings and the SOS, on every state',
        (tester) async {
      // Loaded.
      await pumpHistory(
        tester,
        load: (_) async =>
            history(events: [DayEvent(at: at(9), kind: DayEventKind.sos)]),
      );
      expect(find.text(l.t('day_retention_events')), findsOneWidget);

      // Empty — a promise about the data that is not there as much as about
      // the data that is.
      await pumpHistory(tester,
          load: (_) async => history(points: const [], events: const []));
      expect(find.text(l.t('day_retention_events')), findsOneWidget);

      // Failed.
      await pumpHistory(tester, load: (_) async => throw Exception('offline'));
      expect(find.text(l.t('day_retention_events')), findsOneWidget);
    });

    testWidgets('never prints a period over data that nothing sweeps',
        (tester) async {
      // A real day as the server answers it today: SOS rows arrive over
      // POST /alerts, and no route does — nothing in app/lib calls
      // TelemetryBatcher.enqueueLocation, so location_history stays empty and
      // its 90-day sweep governs nothing that is on this screen. Printing a
      // number here would be a retention promise over the two tables beneath
      // it, neither of which is ever deleted.
      await pumpHistory(
        tester,
        load: (_) async => history(
          points: const [],
          events: [
            DayEvent(at: at(8, 10), kind: DayEventKind.exit, zoneName: 'Дом'),
            DayEvent(at: at(9), kind: DayEventKind.sos),
          ],
        ),
      );
      expect(find.text(l.t('day_retention_events')), findsOneWidget);
      expect(find.text(l.t('day_retention_route', {'n': 90})), findsNothing);
      // And no other phrasing of it either: the number itself must not be on
      // screen when there is no route for it to describe.
      expect(find.textContaining('90'), findsNothing);
    });

    testWidgets('prints the period beside a real route, and never alone',
        (tester) async {
      // The moment somebody wires enqueueLocation the points arrive, the sweep
      // starts governing something visible, and the line comes back — still
      // paired with the sentence about the events, which it does not cover.
      await pumpHistory(tester, load: (_) async => history());
      expect(find.text(l.t('day_retention_route', {'n': 90})), findsOneWidget);
      expect(find.text(l.t('day_retention_events')), findsOneWidget);
    });

    test('the sentence about the events names no period, in any language', () {
      for (final locale in AppLocale.values) {
        final s = L10n(locale).t('day_retention_events');
        // §9.6: nobody has chosen a period for geofence_events or
        // safety_alerts, and none may be printed before there is code that
        // deletes. A digit in this string is that invented number.
        expect(RegExp(r'\d').hasMatch(s), isFalse,
            reason: '$locale: «$s» names a period for data nothing deletes');
        // It has to be recognisable as being about what is listed above it.
        expect(s, contains('SOS'), reason: '$locale: «$s»');
      }
    });
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

  /// THE JOIN, which is what was actually broken.
  ///
  /// Every test above this built a DayEventScreen by hand and passed it a
  /// saver, so all of them passed while the real list screen — the only thing
  /// that ever pushes that route — never passed one. «Чем закончилось» could
  /// not be reached by anybody holding a phone. These drive the list.
  group('reaching the outcome chips the way a parent does', () {
    final sosDay = history(events: [DayEvent(at: at(16, 41), kind: DayEventKind.sos)]);

    testWidgets('tapping the SOS row reaches the chips', (tester) async {
      await pumpHistory(
        tester,
        load: (_) async => sosDay,
        onSaveOutcome: (_, __) async => true,
      );
      await tester.tap(find.text(l.t('day_sos')));
      await tester.pumpAndSettle();

      expect(find.text(l.t('sos_how_ended')), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(SosOutcome.values.length));
    });

    testWidgets('the verdict reaches the saver and the screen closes',
        (tester) async {
      final saved = <SosOutcome>[];
      await pumpHistory(
        tester,
        load: (_) async => sosDay,
        onSaveOutcome: (_, o) async {
          saved.add(o);
          return true;
        },
      );
      await tester.tap(find.text(l.t('day_sos')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('sos_out_false')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('sos_save_mark')));
      await tester.pumpAndSettle();

      expect(saved, [SosOutcome.falsePress]);
      expect(find.text(l.t('sos_mark_saved')), findsOneWidget);
      // Back on the list, not stranded on a screen with nothing left to do.
      expect(find.text(l.t('sos_how_ended')), findsNothing);
    });

    testWidgets('a failed save says so and stays put', (tester) async {
      await pumpHistory(
        tester,
        load: (_) async => sosDay,
        onSaveOutcome: (_, __) async => false,
      );
      await tester.tap(find.text(l.t('day_sos')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('sos_out_scared')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('sos_save_mark')));
      await tester.pumpAndSettle();

      // A tick over a write that failed is how a parent believes the alarm is
      // closed when the server never heard about it.
      expect(find.text(l.t('sos_mark_saved')), findsNothing);
      expect(find.text(l.t('day_failed')), findsOneWidget);
      expect(find.text(l.t('sos_how_ended')), findsOneWidget);
    });

    testWidgets('reopening shows the verdict already recorded', (tester) async {
      await pumpHistory(
        tester,
        load: (_) async => history(events: [
          DayEvent(
              at: at(16, 41),
              kind: DayEventKind.sos,
              outcome: SosOutcome.neededHelp),
        ]),
        onSaveOutcome: (_, __) async => true,
      );
      await tester.tap(find.text(l.t('day_sos')));
      await tester.pumpAndSettle();

      // Asking again is how a second answer overwrites a first.
      final chip = tester.widget<ChoiceChip>(
        find.ancestor(
            of: find.text(l.t('sos_out_help')), matching: find.byType(ChoiceChip)),
      );
      expect(chip.selected, isTrue);
    });

    testWidgets('without a saver the section is absent, not dead', (tester) async {
      await pumpHistory(tester, load: (_) async => sosDay);
      await tester.tap(find.text(l.t('day_sos')));
      await tester.pumpAndSettle();

      expect(find.text(l.t('sos_how_ended')), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    });
  });
}
