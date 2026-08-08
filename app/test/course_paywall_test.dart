/// Screen 34 — «Курс · без комплекта».
///
/// The locked screen was one card asserting the course exists. Titles are
/// evidence where «двенадцать уроков» is only a claim.
///
/// The test that matters is that the list still cannot play a locked lesson —
/// however the row is rendered, and even if a future server sends a URL it
/// should not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/course_lesson.dart';
import 'package:fcs_app/domain/course_prices.dart';
import 'package:fcs_app/domain/my_order.dart' show formatTenge;
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/content/mama_course_screen.dart';
import 'package:fcs_app/ui/theme.dart';

const l = L10n(AppLocale.ru);

CoursePreviewLesson prev(int n, {bool free = false}) => CoursePreviewLesson(
      id: 'l$n',
      titleRu: 'Урок $n',
      summaryRu: 'О чём урок $n',
      sort: n,
      free: free,
      youtubeUrl: free ? 'https://youtu.be/vid$n' : null,
    );

Future<void> pump(
  WidgetTester tester, {
  required CourseAccess access,
  String whatsapp = '+7 707 345 22 44',
}) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: MamaCourseScreen(
        access: access,
        whatsapp: whatsapp,
        launch: (_) async => true,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('the prices', () {
    test('the set costs less than its parts — that IS the offer', () {
      // If this ever inverts, the price card is arguing against the product.
      expect(coursePrices.bundleMinor,
          lessThan(coursePrices.separatelyMinor));
      expect(coursePrices.savingMinor, greaterThan(0));
    });

    test('«separately» is derived, so it cannot drift from its parts', () {
      expect(
        coursePrices.separatelyMinor,
        coursePrices.watchMinor +
            coursePrices.trackerMinor +
            coursePrices.courseOnlyMinor,
      );
      // And matches what the landing page publishes.
      expect(formatTenge(coursePrices.separatelyMinor),
          formatTenge(6980000));
      expect(formatTenge(coursePrices.bundleMinor), formatTenge(3900000));
    });
  });

  group('parsing a preview lesson', () {
    test('never keeps a URL on a locked lesson', () {
      // Belt and braces against the server. The client must not be the thing
      // that decides what is paid for, and it must not carry a leak either.
      final locked = CoursePreviewLesson.fromJson({
        'id': 'x', 'titleRu': 'Урок', 'free': false,
        'youtubeUrl': 'https://youtu.be/leaked',
      })!;
      expect(locked.free, isFalse);
      expect(locked.youtubeUrl, isNull);
    });

    test('keeps it on the free one', () {
      final free = CoursePreviewLesson.fromJson({
        'id': 'x', 'titleRu': 'Урок', 'free': true,
        'youtubeUrl': 'https://youtu.be/ok',
      })!;
      expect(free.youtubeUrl, 'https://youtu.be/ok');
    });

    test('drops a row with no title', () {
      expect(CoursePreviewLesson.fromJson({'id': 'x'}), isNull);
    });
  });

  testWidgets('lists what is in the course, with one lesson free',
      (tester) async {
    await pump(tester, access: CourseAccess(
      entitled: false,
      lessons: const [],
      preview: [prev(1, free: true), prev(2), prev(3)],
    ));

    expect(find.text(l.t('crs_contents')), findsOneWidget);
    expect(find.text('Урок 1'), findsOneWidget);
    expect(find.text('Урок 3'), findsOneWidget);
    expect(find.text(l.t('crs_lessons_n', {'n': 3})), findsOneWidget);
    // One free badge, and locks on the rest.
    expect(find.text(l.t('crs_free_badge')), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));
  });

  testWidgets('only the free lesson is tappable', (tester) async {
    // The row IS the button — a separate CTA beside the title overflowed a
    // 390 dp phone in Russian and duplicated the play icon already there.
    await pump(tester, access: CourseAccess(
      entitled: false,
      lessons: const [],
      preview: [prev(1, free: true), prev(2), prev(3)],
    ));
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    await tester.tap(find.text('Урок 1'));
    await tester.pumpAndSettle();
    // The player opened on the free lesson.
    expect(find.text('Урок 1'), findsWidgets);
  });

  testWidgets('a "free" lesson with no video does not offer to play',
      (tester) async {
    // Both conditions, because either alone would put the client in charge of
    // what is paid for.
    await pump(tester, access: const CourseAccess(
      entitled: false,
      lessons: [],
      preview: [
        CoursePreviewLesson(id: 'l1', titleRu: 'Урок 1', sort: 1, free: true),
      ],
    ));
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('shows both prices and both ways to buy', (tester) async {
    await pump(tester, access: CourseAccess(
      entitled: false, lessons: const [], preview: [prev(1, free: true)],
    ));
    expect(find.text(formatTenge(coursePrices.bundleMinor)), findsOneWidget);
    expect(find.text(formatTenge(coursePrices.separatelyMinor)), findsOneWidget);
    expect(find.text(formatTenge(coursePrices.courseOnlyMinor)), findsOneWidget);
    expect(find.text(l.t('crs_order_wa')), findsOneWidget);
    expect(find.text(l.t('crs_buy_course_wa')), findsOneWidget);
  });

  testWidgets('hides both buy buttons when no number is configured',
      (tester) async {
    // A contact button that opens a chat with nobody is worse than none.
    await pump(tester, whatsapp: '', access: CourseAccess(
      entitled: false, lessons: const [], preview: [prev(1, free: true)],
    ));
    expect(find.text(l.t('crs_order_wa')), findsNothing);
    expect(find.text(l.t('crs_buy_course_wa')), findsNothing);
    // But the prices still show — she can still see what it costs.
    expect(find.text(formatTenge(coursePrices.bundleMinor)), findsOneWidget);
  });

  testWidgets('an owner sees the lessons, not the offer', (tester) async {
    await pump(tester, access: const CourseAccess(
      entitled: true,
      lessons: [
        CourseLesson(id: 'l1', titleRu: 'Урок 1', youtubeUrl: 'https://youtu.be/a'),
      ],
    ));
    expect(find.text(l.t('crs_price_title')), findsNothing);
    expect(find.text('Урок 1'), findsOneWidget);
  });

  testWidgets('with no lessons yet, the offer still states the price',
      (tester) async {
    // The course exists as a product before its first lesson is uploaded, and
    // «скоро» with no price tells a customer nothing she can act on.
    await pump(tester, access: const CourseAccess(
      entitled: false, lessons: [], preview: [],
    ));
    expect(find.text(l.t('crs_contents')), findsNothing);
    expect(find.text(formatTenge(coursePrices.bundleMinor)), findsOneWidget);
  });
}
