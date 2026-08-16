/// «Не удалось проверить доступ» — the course when the server said NOTHING.
///
/// A paying customer was shown the sales offer for the course she already
/// owned whenever her network dropped: the entitlement read was caught and
/// turned into `CourseAccess.none`, and none is «она не купила». A failed
/// request is not an answer, and this state is what the app shows instead of
/// guessing one — modelled on «История зон», which draws loading / loaded /
/// FAILED for exactly this reason.
///
/// The two assertions that matter are negative and are made on every path
/// below: it may not show the offer (she may own it) and it may not show the
/// course unlocked (she may not).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/course_lesson.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/content/course_route.dart';
import 'package:fcs_app/ui/content/mama_course_screen.dart';
import 'package:fcs_app/ui/theme.dart';

const _l = L10n(AppLocale.ru);

/// Answers /course/lessons, or refuses to, on demand.
class _Transport implements HttpTransport {
  final Map<String, dynamic> course;

  /// How many of the first course requests throw. 1 = one tunnel, then out.
  int failFirst;
  int courseCalls = 0;

  _Transport(this.course, {this.failFirst = 0});

  @override
  Future<HttpResponse> get(String path) async {
    if (path == '/course/lessons') {
      courseCalls++;
      if (courseCalls <= failFirst) throw Exception('no network');
      return HttpResponse(200, jsonEncode(course));
    }
    // The shop config and catalogue the offer needs. Answered, so that a
    // missing offer below can only be this screen's decision.
    if (path == '/shop/config') {
      return const HttpResponse(200, '{"whatsapp":"+7 707 345 22 44"}');
    }
    return const HttpResponse(200, '{}');
  }

  @override
  Future<HttpResponse> post(String path, Object body) async =>
      const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);
  @override
  Future<HttpResponse> delete(String path) => get(path);
}

Map<String, dynamic> _lesson(String id, int sort) => {
      'id': id,
      'titleRu': 'Урок $sort',
      'youtubeUrl': 'https://youtu.be/dQw4w9WgXcQ',
      'sort': sort,
    };

Widget _wrap(Widget child) => L10nScope(
      // Above MaterialApp, not at home:, so a pushed route keeps its Russian.
      l10n: _l,
      child: MaterialApp(theme: FcsTheme.light(AppLocale.ru), home: child),
    );

/// Neither of the two claims is on screen.
void expectAssertsNothing() {
  // The offer, by all three of its parts.
  expect(find.text('Курс входит в комплект'), findsNothing);
  expect(find.text('Написать в WhatsApp'), findsNothing);
  expect(find.textContaining('входит в комплект'), findsNothing);
  // The course, by the header the entitled screen always draws.
  expect(find.byKey(const Key('course-progress-line')), findsNothing);
  expect(find.textContaining('Урок '), findsNothing);
}

/// Frames, without pumpAndSettle: the loading state is an indeterminate
/// CircularProgressIndicator and settling on one never returns.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('the fourth state exists at all', () {
    test('unknown is not "she has not bought it"', () {
      expect(CourseAccess.unknown.checkFailed, isTrue);
      expect(CourseAccess.none.checkFailed, isFalse);
      expect(CourseAccess.unknown == CourseAccess.none, isFalse);
    });

    test('unknown can never claim an entitlement', () {
      // The client granting itself access is the one thing worse than the bug
      // this fixes.
      expect(CourseAccess.unknown.entitled, isFalse);
      expect(CourseAccess.unknown.lessons, isEmpty);
      expect(
        () => CourseAccess(entitled: true, lessons: const [], checkFailed: true),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a parsed response is an answer, however empty', () {
      expect(CourseAccess.fromJson({'entitled': false, 'lessons': []}).checkFailed,
          isFalse);
      expect(CourseAccess.fromJson(const {}).checkFailed, isFalse);
    });
  });

  group('the screen', () {
    testWidgets('says the check failed instead of selling or unlocking',
        (tester) async {
      await tester.pumpWidget(_wrap(const MamaCourseScreen(
        access: CourseAccess.unknown,
        whatsapp: '+77015551122',
      )));
      await _settle(tester);

      expect(find.byKey(const Key('course-check-failed')), findsOneWidget);
      expect(find.text('Не удалось проверить доступ к курсу'), findsOneWidget);
      // The sentence that keeps this apart from the offer.
      expect(find.textContaining('Это не значит'), findsOneWidget);
      expectAssertsNothing();
      // And no price card: quoting 39 000 ₸ IS the pitch.
      expect(find.textContaining('39'), findsNothing);
    });

    testWidgets('offers a retry, and it retries', (tester) async {
      var retries = 0;
      await tester.pumpWidget(_wrap(MamaCourseScreen(
        access: CourseAccess.unknown,
        onRetry: () async => retries++,
      )));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('course-check-retry')));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('still says it in Kazakh', (tester) async {
      await tester.pumpWidget(L10nScope(
        l10n: const L10n(AppLocale.kk),
        child: MaterialApp(
          theme: FcsTheme.light(AppLocale.kk),
          home: const MamaCourseScreen(access: CourseAccess.unknown),
        ),
      ));
      await _settle(tester);
      expect(find.text('Курсқа қолжетімділікті тексеру мүмкін болмады'),
          findsOneWidget);
      expect(find.text('Курс жинаққа кіреді'), findsNothing);
    });
  });

  group('the route, which is where the failure actually comes from', () {
    Future<_Transport> pumpRoute(WidgetTester tester, _Transport t) async {
      final c = AppController(
          now: () => DateTime.utc(2026, 8, 15), locale: AppLocale.ru);
      addTearDown(c.dispose);
      c.attachRuntime(api: ApiClient(t));
      await tester.pumpWidget(_wrap(CourseRoute(controller: c)));
      await _settle(tester);
      return t;
    }

    testWidgets('a thrown entitlement read renders neither the offer nor the '
        'course', (tester) async {
      await pumpRoute(
          tester,
          _Transport({
            'entitled': true,
            'lessons': [_lesson('a', 10)],
          }, failFirst: 99));

      expect(find.byKey(const Key('course-check-failed')), findsOneWidget);
      expectAssertsNothing();
    });

    testWidgets('the retry on that screen re-asks the server', (tester) async {
      final t = await pumpRoute(
          tester,
          _Transport({
            'entitled': true,
            'lessons': [_lesson('a', 10), _lesson('b', 20)],
          }, failFirst: 1));
      expect(t.courseCalls, 1);

      await tester.tap(find.byKey(const Key('course-check-retry')));
      await _settle(tester);

      expect(t.courseCalls, 2);
      // Out of the tunnel: her lessons, and no offer anywhere near them.
      expect(find.byKey(const Key('course-check-failed')), findsNothing);
      expect(find.text('Урок 10'), findsOneWidget);
      expect(find.text('Написать в WhatsApp'), findsNothing);
    });

    testWidgets('a refresh that fails does not take her course away',
        (tester) async {
      // The one place a last-known answer is kept: it came from the server,
      // for this account, in this session. Blanking a course she is in the
      // middle of watching would be the same defect pointing the other way.
      final t = await pumpRoute(
          tester,
          _Transport({
            'entitled': true,
            'lessons': [_lesson('a', 10)],
          }));
      expect(find.text('Урок 10'), findsOneWidget);

      t.failFirst = 99;
      await tester.fling(find.text('Урок 10'), const Offset(0, 300), 1000);
      await _settle(tester);
      await _settle(tester);

      expect(find.text('Урок 10'), findsOneWidget);
      expect(find.byKey(const Key('course-check-failed')), findsNothing);
      // Said out loud, though: a refresh that quietly does nothing teaches her
      // the button is broken.
      expect(find.widgetWithText(SnackBar, 'Не удалось проверить доступ к курсу'),
          findsOneWidget);
    });

    testWidgets('a server that answers "not bought" still gets the offer',
        (tester) async {
      // The offer is not collateral damage here — it is what a genuine
      // «entitled: false» must still produce, or this fix costs every sale.
      await pumpRoute(tester, _Transport({'entitled': false, 'lessons': []}));
      expect(find.text('Курс входит в комплект'), findsOneWidget);
      expect(find.byKey(const Key('course-check-failed')), findsNothing);
    });
  });

  group('the Kazakh is Kazakh', () {
    // verify_l10n has only ever checked that three locales are DEFINED, so
    // Russian text has shipped under AppLocale.kk and passed. These three
    // strings are checked here where they are added.
    const keys = [
      'course_check_failed',
      'course_check_failed_why',
      'course_entry_uncheckable',
    ];

    test('kk differs from ru and en, and is spelled in Kazakh', () {
      const ru = L10n(AppLocale.ru);
      const kk = L10n(AppLocale.kk);
      const en = L10n(AppLocale.en);
      // ә ғ қ ң ө ұ ү һ і — the letters Russian does not have.
      final kazakh = RegExp('[әғқңөұүһі]');
      for (final k in keys) {
        expect(kk.t(k), isNot(ru.t(k)), reason: '$k is Russian under kk');
        expect(kk.t(k), isNot(en.t(k)), reason: '$k is English under kk');
        expect(kk.t(k), matches(kazakh), reason: '$k has no Kazakh letter');
        expect(kk.t(k), isNot(k), reason: '$k is undefined for kk');
      }
    });
  });
}
