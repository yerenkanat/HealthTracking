/// The Ма!Ма! course row on the Profile screen.
///
/// It said one thing to everybody — "Уроки для мам — входят в комплект" — so a
/// customer who had paid 39 000 ₸ was pitched the thing she had already bought,
/// every time she opened her profile, with no sign that she was four lessons
/// into it. The server knew both facts and neither reached the screen.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/profile/profile_screen.dart';

/// Answers /course/lessons and nothing else, the way the server does.
class _Transport implements HttpTransport {
  final Map<String, dynamic> course;

  /// The course request fails. The row must fall back rather than break the
  /// whole profile.
  final bool broken;

  /// How many of the first course requests fail before the rest succeed —
  /// a tunnel, and then the train comes out of it.
  final int failFirst;

  /// How many times the course was actually asked for, so a retry can be
  /// proved to be a retry and not a repaint.
  int courseCalls = 0;

  _Transport(this.course, {this.broken = false, this.failFirst = 0});

  @override
  Future<HttpResponse> get(String path) async {
    if (path == '/course/lessons') {
      courseCalls++;
      if (broken || courseCalls <= failFirst) throw Exception('no network');
      return HttpResponse(200, jsonEncode(course));
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

Future<void> _pump(WidgetTester tester, HttpTransport? t) async {
  final c = AppController(now: () => DateTime.utc(2026, 8, 6), locale: AppLocale.ru);
  addTearDown(c.dispose);
  if (t != null) c.attachRuntime(api: ApiClient(t));

  await tester.pumpWidget(L10nScope(
    l10n: L10n(AppLocale.ru),
    child: MaterialApp(home: ProfileScreen(controller: c)),
  ));
  await tester.pumpAndSettle();
}

String _sub(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('course-entry-sub'))).data ?? '';

void main() {
  group('the course row', () {
    testWidgets('pitches the bundle to somebody who has not bought it',
        (tester) async {
      await _pump(tester, _Transport({'entitled': false, 'lessons': []}));
      expect(_sub(tester), contains('комплект'));
    });

    testWidgets('does NOT pitch it to somebody who owns it', (tester) async {
      // The whole defect in one assertion: she paid, and the row kept selling.
      await _pump(tester, _Transport({
        'entitled': true,
        'lessons': [_lesson('a', 10), _lesson('b', 20), _lesson('c', 30)],
        'progress': [
          {'lessonId': 'a', 'completed': true},
          {'lessonId': 'b', 'completed': true},
        ],
      }));
      expect(_sub(tester), 'Пройдено 2 из 3');
    });

    testWidgets('says the course is hers when there is nothing published yet',
        (tester) async {
      // "Пройдено 0 из 0" is not something to say to a customer.
      await _pump(tester, _Transport({'entitled': true, 'lessons': []}));
      expect(_sub(tester), contains('Доступ открыт'));
    });

    testWidgets('counts nothing watched as nothing watched', (tester) async {
      await _pump(tester, _Transport({
        'entitled': true,
        'lessons': [_lesson('a', 10), _lesson('b', 20)],
      }));
      expect(_sub(tester), 'Пройдено 0 из 2');
    });

    testWidgets('sells her nothing when the check could not be made',
        (tester) async {
      // The defect this row was shipped with: a failed request was read as
      // «она не купила», so a customer who had paid was pitched the course
      // again every time her network dropped. It may not guess either way.
      await _pump(tester, _Transport(const {}, broken: true));
      expect(_sub(tester), isNot(contains('комплект')));
      expect(_sub(tester), contains('Не удалось проверить'));
      // And it may not go the other way either and imply she owns it.
      expect(_sub(tester), isNot(contains('Доступ открыт')));
      expect(_sub(tester), isNot(contains('Пройдено')));
      // The profile itself still works — one failed request must not break it.
      expect(find.text('Курс Ма!Ма!'), findsOneWidget);
    });

    testWidgets('tapping the failed row asks again', (tester) async {
      // The retry has to BE something. The line says «нажмите, чтобы
      // повторить», and this is that promise held to.
      final t = _Transport({
        'entitled': true,
        'lessons': [_lesson('a', 10), _lesson('b', 20)],
        'progress': [
          {'lessonId': 'a', 'completed': true},
        ],
      }, failFirst: 1);
      await _pump(tester, t);
      expect(_sub(tester), contains('Не удалось проверить'));
      expect(t.courseCalls, 1);

      // The row is the last one on the profile, below an 800×600 test view.
      await tester.ensureVisible(find.byKey(const Key('course-entry-sub')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('course-entry-sub')));
      // Not pumpAndSettle: the tap also opens the course, whose loading state
      // is an indeterminate spinner.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(t.courseCalls, greaterThan(1));
      // The row is behind the pushed course screen now, but it has the answer.
      expect(
          tester
              .widget<Text>(find.byKey(const Key('course-entry-sub'),
                  skipOffstage: false))
              .data,
          'Пройдено 1 из 2');
    });

    testWidgets('works with no API configured at all', (tester) async {
      // Not the same as a failed check: there is no account here to have
      // bought anything with, and no retry that could ever succeed.
      await _pump(tester, null);
      expect(_sub(tester), contains('комплект'));
    });
  });
}
