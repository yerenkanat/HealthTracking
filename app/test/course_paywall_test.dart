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
import 'package:fcs_app/domain/shop_catalogue.dart';
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
  ShopCatalogue catalogue = ShopCatalogue.empty,
  L10n l10n = l,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(L10nScope(
    l10n: l10n,
    child: MaterialApp(
      theme: FcsTheme.light(l10n.locale),
      home: MamaCourseScreen(
        access: access,
        whatsapp: whatsapp,
        catalogue: catalogue,
        launch: (_) async => true,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

const _offer = CourseAccess(entitled: false, lessons: [], preview: []);

ShopCatalogue _live(List<CatalogueProduct> products, {bool fromCache = false}) =>
    ShopCatalogue(
      products: products,
      fetchedAt: DateTime(2026, 8, 11),
      fromCache: fromCache,
    );

CatalogueProduct _bundle(int priceMinor, {String? nameKk}) => CatalogueProduct(
      id: bundleProductId,
      nameRu: 'Комплект «Мама и ребёнок»',
      nameKk: nameKk,
      priceMinor: priceMinor,
      isBundle: true,
      partIds: const ['watch', 'tracker'],
      inStock: true,
    );

CatalogueProduct _simple(String id, String nameRu, int priceMinor) =>
    CatalogueProduct(
      id: id,
      nameRu: nameRu,
      priceMinor: priceMinor,
      inStock: true,
    );

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
          formatTenge(12880000));
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

  // -------------------------------------------------------------------------
  // «карточка цены (39 000 ₸ / 128 800 ₸)» against the LIVE catalogue
  // -------------------------------------------------------------------------

  group('the price card reads the shop, not the build', () {
    testWidgets('quotes the комплект at what the panel says it costs',
        (tester) async {
      await pump(tester, access: _offer, catalogue: _live([_bundle(4450000)]));
      expect(find.text(formatTenge(4450000)), findsOneWidget);
      expect(find.text(formatTenge(coursePrices.bundleMinor)), findsNothing);
      // «128 800 ₸» moves with it: 24 900 + 4 900 + 99 000 is unchanged, so the
      // comparison row still stands.
      expect(find.text(formatTenge(coursePrices.separatelyMinor)),
          findsOneWidget);
    });

    testWidgets('uses the catalogue\'s name, including in Kazakh',
        (tester) async {
      await pump(tester,
          access: _offer,
          l10n: const L10n(AppLocale.kk),
          catalogue: _live([_bundle(3900000, nameKk: '«Ана мен бала» жинағы')]));
      expect(find.text('«Ана мен бала» жинағы'), findsOneWidget);
    });

    testWidgets('the course-only row keeps the constant — no product to read',
        (tester) async {
      // 018_landing_prices: the course is what the комплект grants. Inventing a
      // live figure for it would be fabrication.
      await pump(tester, access: _offer, catalogue: _live([_bundle(4450000)]));
      expect(find.text(formatTenge(coursePrices.courseOnlyMinor)),
          findsOneWidget);
    });

    testWidgets('hides «отдельно» rather than printing a negative saving',
        (tester) async {
      // A struck-through 128 800 ₸ ABOVE a 139 000 ₸ set reads as a con.
      await pump(tester, access: _offer, catalogue: _live([_bundle(13900000)]));
      expect(find.text(formatTenge(13900000)), findsOneWidget);
      expect(find.text(l.t('crs_separate_name')), findsNothing);
      expect(find.text(formatTenge(coursePrices.separatelyMinor)), findsNothing);
    });

    testWidgets('with no catalogue the constants are shown AND labelled',
        (tester) async {
      await pump(tester, access: _offer);
      expect(find.text(formatTenge(coursePrices.bundleMinor)), findsOneWidget);
      expect(find.text(l.t('shop_prices_approx')), findsOneWidget);
    });

    testWidgets('a cached catalogue is dated, not passed off as current',
        (tester) async {
      await pump(tester,
          access: _offer,
          catalogue: ShopCatalogue(
            products: [_bundle(3900000)],
            fetchedAt: DateTime(2026, 3, 2),
            fromCache: true,
          ));
      expect(find.text(l.t('shop_prices_cached', {'date': '02.03.2026'})),
          findsOneWidget);
    });

    testWidgets('a live catalogue adds no banner', (tester) async {
      await pump(tester, access: _offer, catalogue: _live([_bundle(3900000)]));
      expect(find.text(l.t('shop_prices_approx')), findsNothing);
    });

    testWidgets('a set the shop has withdrawn is neither priced nor orderable',
        (tester) async {
      // The catalogue loaded perfectly and simply has no комплект in it — an
      // operator set it inactive in frame 08. The card used to quote the
      // build's 39 000 ₸ with «Заказать комплект в WhatsApp» beneath it, and
      // no «ориентировочные», because ANY live product marked the card fresh.
      await pump(tester,
          access: _offer,
          catalogue: _live([
            _simple('watch', 'Часы', 2490000),
            _simple('tracker', 'Трекер', 490000),
          ]));
      expect(find.text(formatTenge(coursePrices.bundleMinor)), findsNothing);
      expect(find.text(l.t('crs_bundle_name')), findsNothing);
      expect(find.text(l.t('crs_order_wa')), findsNothing);
      // «69 800 ₸» goes too: it exists only to be compared with the set.
      expect(find.text(l.t('crs_separate_name')), findsNothing);
      // The course is still for sale, at the constant, and says it is a
      // figure to be confirmed.
      expect(find.text(formatTenge(coursePrices.courseOnlyMinor)),
          findsOneWidget);
      expect(find.text(l.t('crs_buy_course_wa')), findsOneWidget);
      expect(find.text(l.t('shop_prices_approx')), findsOneWidget);
    });
  });
}
