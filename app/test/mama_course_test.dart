/// The Ма!Ма! course in the app.
///
/// The комплект costs 39 000 ₸ against 29 800 for the two devices, and the
/// difference is this course. So the two states are not a display detail: one
/// is what a customer paid for, the other is an offer to buy it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/course_lesson.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/content/course_video_screen.dart';
import 'package:fcs_app/ui/content/mama_course_screen.dart';

CourseLesson _lesson({
  String id = 'l1',
  String titleRu = 'Первые дни дома',
  String? titleKk,
  String url = 'https://youtu.be/abc123',
  int sort = 10,
}) =>
    CourseLesson(id: id, titleRu: titleRu, titleKk: titleKk, youtubeUrl: url, sort: sort);

Widget _wrap(Widget child, {AppLocale locale = AppLocale.ru}) => L10nScope(
      l10n: L10n(locale),
      child: MaterialApp(home: child),
    );

void main() {
  group('parsing what the server sends', () {
    test('keeps the lessons in order regardless of how they arrive', () {
      final a = CourseAccess.fromJson({
        'entitled': true,
        'lessons': [
          {'id': 'c', 'titleRu': 'Третий', 'youtubeUrl': 'https://youtu.be/c', 'sort': 30},
          {'id': 'a', 'titleRu': 'Первый', 'youtubeUrl': 'https://youtu.be/a', 'sort': 10},
          {'id': 'b', 'titleRu': 'Второй', 'youtubeUrl': 'https://youtu.be/b', 'sort': 20},
        ],
      });
      expect(a.lessons.map((l) => l.titleRu), ['Первый', 'Второй', 'Третий']);
    });

    test('drops a malformed lesson rather than losing the whole course', () {
      // One bad row must not empty the course for somebody who paid for it.
      final a = CourseAccess.fromJson({
        'entitled': true,
        'lessons': [
          {'id': 'a', 'titleRu': 'Хороший', 'youtubeUrl': 'https://youtu.be/a'},
          {'id': 'b', 'titleRu': '', 'youtubeUrl': 'https://youtu.be/b'}, // no title
          {'id': '', 'titleRu': 'X', 'youtubeUrl': 'https://youtu.be/c'}, // no id
          {'id': 'd', 'titleRu': 'Y'}, // no link
        ],
      });
      expect(a.lessons.map((l) => l.id), ['a']);
    });

    test('entitled is carried separately from "there are no lessons"', () {
      // "You have not bought this" and "nothing is up yet" need different
      // screens — one is an offer, the other an apology.
      final bought = CourseAccess.fromJson({'entitled': true, 'lessons': []});
      final not = CourseAccess.fromJson({'entitled': false, 'lessons': []});
      expect(bought.entitled, isTrue);
      expect(not.entitled, isFalse);
    });

    test('a Kazakh reader falls back to the Russian title', () {
      // Lessons go up in Russian first; blocking one until it is translated
      // would mean nothing ships.
      expect(_lesson().title('kk'), 'Первые дни дома');
      expect(_lesson(titleKk: 'Үйдегі алғашқы күндер').title('kk'), 'Үйдегі алғашқы күндер');
    });
  });

  group('what she sees', () {
    testWidgets('not bought: an offer that names the bundle', (tester) async {
      await tester.pumpWidget(_wrap(const MamaCourseScreen(access: CourseAccess.none)));
      await tester.pumpAndSettle();

      expect(find.text('Курс входит в комплект'), findsOneWidget);
      // It has to say HOW to get it, or the lock is just a dead end.
      expect(find.textContaining('комплект'), findsWidgets);
    });

    /// The offer has to be actionable, not just informative.
    ///
    /// Opened on a real phone, this card told her to message us and then gave
    /// her nothing to tap: the entire pitch for a 39 000 ₸ комплект ended on
    /// a sentence. The number is whatever staff set in the back office, so it
    /// cannot go stale here and is never invented.
    testWidgets('not bought: offers a way to actually get in touch', (tester) async {
      Uri? opened;
      await tester.pumpWidget(_wrap(MamaCourseScreen(
        access: CourseAccess.none,
        whatsapp: '+7 (701) 555-11-22',
        launch: (u) async {
          opened = u;
          return true;
        },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Написать в WhatsApp'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      // Digits only — wa.me rejects anything else.
      expect(opened!.toString(), startsWith('https://wa.me/77015551122'));
      // And the chat opens saying what she wants, so staff need not ask.
      expect(Uri.decodeComponent(opened!.query), contains('Ма!Ма!'));
    });

    testWidgets('not bought: no button when no number is configured', (tester) async {
      // A button that opens a chat with nobody is worse than no button.
      await tester.pumpWidget(_wrap(const MamaCourseScreen(access: CourseAccess.none)));
      await tester.pumpAndSettle();

      expect(find.text('Написать в WhatsApp'), findsNothing);
      // The explanation still stands on its own.
      expect(find.text('Курс входит в комплект'), findsOneWidget);
    });

    testWidgets('bought: no sales button over the lessons she paid for', (tester) async {
      final access = CourseAccess(entitled: true, lessons: [_lesson()]);
      await tester.pumpWidget(_wrap(MamaCourseScreen(
          access: access, whatsapp: '+77015551122')));
      await tester.pumpAndSettle();

      expect(find.text('Написать в WhatsApp'), findsNothing);
    });

    testWidgets('bought: the lessons, numbered', (tester) async {
      final access = CourseAccess(entitled: true, lessons: [
        _lesson(id: 'a', titleRu: 'Первый', sort: 10),
        _lesson(id: 'b', titleRu: 'Второй', sort: 20),
      ]);
      await tester.pumpWidget(_wrap(MamaCourseScreen(access: access)));
      await tester.pumpAndSettle();

      expect(find.text('Первый'), findsOneWidget);
      expect(find.text('Второй'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      // And no offer to buy what she already owns.
      expect(find.text('Курс входит в комплект'), findsNothing);
    });

    testWidgets('bought but nothing published yet says so, and does not sell', (tester) async {
      // Showing the offer here would tell a paying customer to buy what she has.
      await tester.pumpWidget(
          _wrap(const MamaCourseScreen(access: CourseAccess(entitled: true, lessons: []))));
      await tester.pumpAndSettle();

      expect(find.textContaining('Доступ у вас уже есть'), findsOneWidget);
      expect(find.text('Курс входит в комплект'), findsNothing);
    });

    testWidgets('while loading it shows a spinner, not the offer', (tester) async {
      // Drawing the offer during the request would flash "buy this" at somebody
      // who owns it, every single time she opens the screen.
      await tester.pumpWidget(_wrap(const MamaCourseScreen(access: null)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Курс входит в комплект'), findsNothing);
    });

    testWidgets('tapping a lesson plays it inside the app, not in YouTube', (tester) async {
      // The course is the entire difference between 39 000 ₸ and 29 800. This
      // used to hand the customer to the YouTube app, where she landed among
      // recommendations for everything else and usually did not come back.
      Uri? launched;
      final access = CourseAccess(entitled: true, lessons: [
        _lesson(url: 'https://youtu.be/dQw4w9WgXcQ'),
      ]);
      await tester.pumpWidget(_wrap(MamaCourseScreen(
        access: access,
        launch: (u) async { launched = u; return true; },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Первые дни дома'));
      await tester.pumpAndSettle();

      expect(find.byType(CourseVideoScreen), findsOneWidget,
          reason: 'the lesson must open on our own screen');
      expect(launched, isNull, reason: 'nothing may leave the app on a tap');
    });
  });

  /// The player screen itself.
  ///
  /// [CourseVideoScreen.debugWithoutPlayer] skips building the real IFrame
  /// player, which needs a webview and therefore a device. Everything the
  /// customer can do around it is still on this screen and still testable.
  group('the lesson player', () {
    testWidgets('keeps the way out to YouTube', (tester) async {
      // Their terms are satisfied either way; leaving is her choice, not ours.
      Uri? opened;
      await tester.pumpWidget(_wrap(CourseVideoScreen(
        lesson: _lesson(url: 'https://youtu.be/dQw4w9WgXcQ'),
        debugWithoutPlayer: true,
        launch: (u) async { opened = u; return true; },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.open_in_new_rounded).first);
      await tester.pumpAndSettle();
      expect(opened.toString(), 'https://youtu.be/dQw4w9WgXcQ');
    });

    testWidgets('says something when the video will not open', (tester) async {
      // Otherwise the tap does nothing, which reads as a broken lesson rather
      // than a missing YouTube app.
      await tester.pumpWidget(_wrap(CourseVideoScreen(
        lesson: _lesson(),
        debugWithoutPlayer: true,
        launch: (_) async => false,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.open_in_new_rounded).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Не удалось открыть'), findsOneWidget);
    });

    testWidgets('a link that is not a video says so instead of playing nothing',
        (tester) async {
      // A channel or playlist URL saved before the server validated links. It
      // must read as a link we have to fix, not as a dead tap.
      await tester.pumpWidget(_wrap(CourseVideoScreen(
        lesson: _lesson(url: 'https://www.youtube.com/@anabala'),
        launch: (_) async => true,
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ссылка на этот урок не открывается'), findsOneWidget);
      // And no "open on YouTube" button, because there is nothing to open.
      expect(find.text('Открыть на YouTube'), findsNothing);
    });

    testWidgets('shows the lesson summary under the video', (tester) async {
      // Written in the back office and, until the player existed, shown only as
      // a subtitle in the list.
      await tester.pumpWidget(_wrap(CourseVideoScreen(
        lesson: CourseLesson(
          id: 'l1',
          titleRu: 'Первые дни дома',
          youtubeUrl: 'https://youtu.be/dQw4w9WgXcQ',
          summaryRu: 'Что происходит с телом.',
          sort: 10,
        ),
        debugWithoutPlayer: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Что происходит с телом.'), findsOneWidget);
    });
  });
}
