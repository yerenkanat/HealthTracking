/// Screen 41 — «Магазин».
///
/// «Для вашего этапа» is a recommendation, and a recommendation that is
/// confident and wrong is worse than a plain list — she is being asked for
/// 39 000 ₸. So the tests are mostly about the reasoning being defensible and
/// about it never claiming a basis it does not have.
///
/// Since frames 08 / 08a the prices and names on this screen belong to an
/// operator, so a second class of failure joins the first: quoting a number
/// the shop no longer charges, and quoting it with no hint of where it came
/// from. The catalogue group below is about that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/course_prices.dart';
import 'package:fcs_app/domain/my_order.dart' show formatTenge;
import 'package:fcs_app/domain/shop_catalogue.dart';
import 'package:fcs_app/domain/shop_stage.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/shop/shop_screen.dart';
import 'package:fcs_app/ui/theme.dart';

const l = L10n(AppLocale.ru);
const lkk = L10n(AppLocale.kk);

Future<List<String>> pump(
  WidgetTester tester, {
  bool pregnant = false,
  List<int> ages = const [],
  bool canOrder = true,
  ShopCatalogue catalogue = ShopCatalogue.empty,
  L10n l10n = l,
}) async {
  final orders = <String>[];
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(L10nScope(
    l10n: l10n,
    child: MaterialApp(
      theme: FcsTheme.light(l10n.locale),
      home: ShopScreen(
        pregnant: pregnant,
        childAgesMonths: ages,
        catalogue: catalogue,
        onOrder: canOrder ? orders.add : null,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return orders;
}

/// A catalogue as `/shop/products` sends one.
ShopCatalogue catalogue({
  required List<CatalogueProduct> products,
  DateTime? fetchedAt,
  bool fromCache = false,
}) =>
    ShopCatalogue(
      products: products,
      fetchedAt: fetchedAt ?? DateTime(2026, 8, 11),
      fromCache: fromCache,
    );

CatalogueProduct product(
  String id,
  String nameRu,
  int priceMinor, {
  String? nameKk,
  String? descriptionRu,
  bool isBundle = false,
  ProductStage? stage,
  int? ageMin,
  int? ageMax,
  bool inStock = true,
}) =>
    CatalogueProduct(
      id: id,
      nameRu: nameRu,
      nameKk: nameKk,
      descriptionRu: descriptionRu,
      priceMinor: priceMinor,
      isBundle: isBundle,
      partIds: isBundle ? const ['watch', 'tracker'] : const [],
      stage: stage,
      ageMinMonths: ageMin,
      ageMaxMonths: ageMax,
      inStock: inStock,
    );

void main() {
  _overflowSweep();

  group('what to suggest', () {
    test('a walking child puts the tracker first', () {
      final s = stageSuggestion(pregnant: false, childAgesMonths: [24]);
      expect(s.reason, StageReason.childOnTheMove);
      expect(s.items.first, ShopItem.tracker);
    });

    test('a walking child outranks a pregnancy', () {
      // The toddler is the one who can already be somewhere she is not.
      final s = stageSuggestion(pregnant: true, childAgesMonths: [30]);
      expect(s.reason, StageReason.childOnTheMove);
      expect(s.items.first, ShopItem.tracker);
    });

    test('a baby too young to go anywhere is said so, not sold a tracker', () {
      final s = stageSuggestion(pregnant: false, childAgesMonths: [4]);
      expect(s.reason, StageReason.babyTooYoungToTrack);
      expect(s.items.first, isNot(ShopItem.tracker));
    });

    test('expecting leads with the set', () {
      final s = stageSuggestion(pregnant: true, childAgesMonths: []);
      expect(s.reason, StageReason.pregnant);
      expect(s.items.first, ShopItem.bundle);
    });

    test('knowing nothing says so rather than guessing', () {
      // «Заполните профиль» is honest. A confident recommendation built on no
      // data is the one thing this section must not produce.
      final s = stageSuggestion(pregnant: false, childAgesMonths: []);
      expect(s.reason, StageReason.unknown);
    });

    test('the oldest child decides, not the youngest', () {
      // A family with a toddler AND a newborn still needs a tracker.
      final s = stageSuggestion(pregnant: false, childAgesMonths: [2, 36]);
      expect(s.reason, StageReason.childOnTheMove);
    });

    test('every branch offers something', () {
      for (final s in [
        stageSuggestion(pregnant: true, childAgesMonths: []),
        stageSuggestion(pregnant: false, childAgesMonths: []),
        stageSuggestion(pregnant: false, childAgesMonths: [3]),
        stageSuggestion(pregnant: false, childAgesMonths: [40]),
      ]) {
        expect(s.items, isNotEmpty);
      }
    });
  });

  testWidgets('leads with the set and shows what it saves', (tester) async {
    await pump(tester, pregnant: true);
    expect(find.text(l.t('crs_bundle_name')), findsOneWidget);
    expect(find.text(formatTenge(coursePrices.bundleMinor)), findsOneWidget);
    expect(find.text(formatTenge(coursePrices.separatelyMinor)), findsOneWidget);
    expect(
      find.text(l.t('shop_saving',
          {'amount': formatTenge(coursePrices.savingMinor)})),
      findsOneWidget,
    );
  });

  testWidgets('prints the REASON beside the suggestion', (tester) async {
    // A recommendation with no stated basis is indistinguishable from an ad.
    await pump(tester, ages: [30]);
    expect(find.text(l.t('shop_for_your_stage')), findsOneWidget);
    expect(find.text(l.t('shop_why_moving')), findsOneWidget);
  });

  testWidgets('says «заполните профиль» when it knows nothing', (tester) async {
    await pump(tester);
    expect(find.text(l.t('shop_why_unknown')), findsOneWidget);
  });

  testWidgets('does not show the set twice', (tester) async {
    // It is already the hero; repeating it in the list below is the same
    // product twice on one screen.
    await pump(tester, pregnant: true);
    expect(find.text(l.t('crs_bundle_name')), findsOneWidget);
  });

  testWidgets('explains that ordering happens on WhatsApp', (tester) async {
    await pump(tester);
    expect(find.text(l.t('shop_wa_note')), findsOneWidget);
  });

  testWidgets('ordering sends a message naming what she picked',
      (tester) async {
    final orders = await pump(tester, ages: [30]);
    await tester.tap(find.text(l.t('shop_order_bundle')).first);
    await tester.pumpAndSettle();
    expect(orders, hasLength(1));
    expect(orders.first, contains(l.t('crs_bundle_name')));
  });

  testWidgets('every buy button disappears when there is no number',
      (tester) async {
    // A button that opens a chat with nobody, on the screen where money is
    // asked for.
    await pump(tester, pregnant: true, canOrder: false);
    expect(find.text(l.t('shop_order_bundle')), findsNothing);
    expect(find.text(l.t('shop_order_item')), findsNothing);
    // The prices stay — she can still see what it costs.
    expect(find.text(formatTenge(coursePrices.bundleMinor)), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // The live catalogue (frames 08 / 08a)
  // -------------------------------------------------------------------------

  group('what an operator set is what she sees', () {
    testWidgets('the комплект price is the catalogue\'s, not the build\'s',
        (tester) async {
      // The headline claim. Changing this price in the panel used to change
      // nothing a customer could see.
      await pump(tester,
          pregnant: true,
          catalogue: catalogue(products: [
            product('combo', 'Комплект «Мама и ребёнок»', 4450000,
                isBundle: true),
          ]));
      expect(find.text(formatTenge(4450000)), findsOneWidget);
      expect(find.text(formatTenge(coursePrices.bundleMinor)), findsNothing);
    });

    testWidgets('a renamed product is renamed here', (tester) async {
      await pump(tester,
          catalogue: catalogue(products: [
            product('watch', 'Смарт-часы Ana-Bala Pro', 2990000),
          ]));
      expect(find.text('Смарт-часы Ana-Bala Pro'), findsOneWidget);
      expect(find.text(formatTenge(2990000)), findsOneWidget);
    });

    testWidgets('kk renders name_kk', (tester) async {
      await pump(tester,
          l10n: lkk,
          catalogue: catalogue(products: [
            product('watch', 'Смарт-часы', 2490000,
                nameKk: 'Ana-Bala смарт-сағаты'),
          ]));
      expect(find.text('Ana-Bala смарт-сағаты'), findsOneWidget);
    });

    testWidgets('kk with no name_kk shows the Russian name, never a blank row',
        (tester) async {
      await pump(tester,
          l10n: lkk,
          catalogue: catalogue(products: [
            product('tracker', 'Детский трекер Ana-Bala', 490000),
          ]));
      expect(find.text('Детский трекер Ana-Bala'), findsOneWidget);
    });

    testWidgets('an operator\'s description replaces the built-in copy',
        (tester) async {
      await pump(tester,
          catalogue: catalogue(products: [
            product('watch', 'Часы', 2490000,
                descriptionRu: 'Теперь и с ЭКГ'),
          ]));
      expect(find.text('Теперь и с ЭКГ'), findsOneWidget);
      expect(find.text(l.t('shop_item_watch_what')), findsNothing);
    });

    testWidgets('a product this build has never heard of renders fine',
        (tester) async {
      // No invented blurb for it — a name and a price is an honest row.
      await pump(tester,
          catalogue: catalogue(products: [
            product('bottle', 'Бутылочка Ana-Bala', 350000),
          ]));
      expect(find.text('Бутылочка Ana-Bala'), findsOneWidget);
      expect(find.text(formatTenge(350000)), findsOneWidget);
    });
  });

  group('«нет в наличии»', () {
    testWidgets('says so, and the WhatsApp text says «под заказ»',
        (tester) async {
      final orders = await pump(tester,
          catalogue: catalogue(products: [
            product('watch', 'Часы', 2490000, inStock: false),
          ]));
      expect(find.text(l.t('shop_out_of_stock')), findsOneWidget);

      await tester.tap(find.text(l.t('shop_order_backorder')));
      await tester.pumpAndSettle();
      expect(orders, hasLength(1));
      expect(orders.first, l.t('shop_wa_backorder', {'item': 'Часы'}));
      expect(orders.first, contains('под заказ'));
    });

    testWidgets('an in-stock product says nothing about stock', (tester) async {
      final orders = await pump(tester,
          catalogue: catalogue(products: [product('watch', 'Часы', 2490000)]));
      expect(find.text(l.t('shop_out_of_stock')), findsNothing);
      await tester.tap(find.text(l.t('shop_order_item')));
      await tester.pumpAndSettle();
      expect(orders.first, l.t('shop_wa_item', {'item': 'Часы'}));
    });

    testWidgets('an out-of-stock комплект is still priced and still orderable',
        (tester) async {
      // The set carries the whole course. Hiding it because a part is out of
      // stock loses the sale the shop exists for.
      final orders = await pump(tester,
          pregnant: true,
          catalogue: catalogue(products: [
            product('combo', 'Комплект', 3900000,
                isBundle: true, inStock: false),
          ]));
      expect(find.text(formatTenge(3900000)), findsOneWidget);
      expect(find.text(l.t('shop_out_of_stock')), findsOneWidget);
      await tester.tap(find.text(l.t('shop_order_backorder')));
      await tester.pumpAndSettle();
      expect(orders.first, contains('под заказ'));
    });
  });

  group('saying where the numbers came from', () {
    testWidgets('a live catalogue shows no banner at all', (tester) async {
      // A warning on every visit trains people to ignore warnings.
      await pump(tester,
          catalogue: catalogue(products: [product('watch', 'Часы', 2490000)]));
      expect(find.text(l.t('shop_prices_approx')), findsNothing);
      expect(
          find.textContaining(l.t('shop_prices_cached', {'date': ''}).split('{')[0]),
          findsNothing);
    });

    testWidgets('a cached catalogue is dated', (tester) async {
      await pump(tester,
          catalogue: catalogue(
            products: [product('watch', 'Часы', 2490000)],
            fetchedAt: DateTime(2026, 3, 2),
            fromCache: true,
          ));
      expect(find.text(l.t('shop_prices_cached', {'date': '02.03.2026'})),
          findsOneWidget);
    });

    testWidgets('no catalogue at all: the constants, labelled approximate',
        (tester) async {
      await pump(tester, pregnant: true);
      expect(find.text(l.t('shop_prices_approx')), findsOneWidget);
      // And the constants are still shown — she can see roughly what it costs.
      expect(find.text(formatTenge(coursePrices.bundleMinor)), findsOneWidget);
    });
  });

  group('«Для вашего этапа» follows the catalogue', () {
    testWidgets('stage=pregnancy reorders the section', (tester) async {
      await pump(tester,
          pregnant: true,
          catalogue: catalogue(products: [
            product('tracker', 'Трекер', 490000, stage: ProductStage.toddler),
            product('watch', 'Часы', 2490000, stage: ProductStage.pregnancy),
          ]));
      final watch = tester.getTopLeft(find.text('Часы')).dy;
      final tracker = tester.getTopLeft(find.text('Трекер')).dy;
      expect(watch, lessThan(tracker));
      expect(find.text(l.t('shop_match_stage')), findsOneWidget);
    });

    testWidgets('an age band reorders it and is printed', (tester) async {
      await pump(tester,
          ages: [30],
          catalogue: catalogue(products: [
            product('watch', 'Часы', 2490000),
            product('tracker', 'Трекер', 490000, ageMin: 18, ageMax: 84),
          ]));
      expect(tester.getTopLeft(find.text('Трекер')).dy,
          lessThan(tester.getTopLeft(find.text('Часы')).dy));
      expect(find.text(l.t('shop_match_age')), findsOneWidget);
      expect(find.text(l.t('shop_age_band', {'from': 18, 'to': 84})),
          findsOneWidget);
    });

    testWidgets('an untagged product never shows «не указан»', (tester) async {
      // That is panel vocabulary for an operator's unfinished work; a customer
      // has no use for it.
      await pump(tester,
          ages: [30],
          catalogue: catalogue(products: [product('watch', 'Часы', 2490000)]));
      expect(find.textContaining('не указан'), findsNothing);
      expect(find.text(l.t('shop_match_stage')), findsNothing);
      expect(find.text(l.t('shop_match_age')), findsNothing);
      // The heuristic's reason is still printed, because that is the real basis.
      expect(find.text(l.t('shop_why_moving')), findsOneWidget);
    });

    testWidgets('a product for another stage is moved down, not hidden',
        (tester) async {
      await pump(tester,
          pregnant: true,
          catalogue: catalogue(products: [
            product('watch', 'Часы', 2490000, stage: ProductStage.newborn),
            product('tracker', 'Трекер', 490000, stage: ProductStage.pregnancy),
          ]));
      expect(find.text('Часы'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Трекер')).dy,
          lessThan(tester.getTopLeft(find.text('Часы')).dy));
    });

    testWidgets('the set is not listed twice when it is in the catalogue',
        (tester) async {
      await pump(tester,
          pregnant: true,
          catalogue: catalogue(products: [
            product('combo', 'Комплект «Мама и ребёнок»', 3900000,
                isBundle: true),
            product('watch', 'Часы', 2490000),
          ]));
      expect(find.text('Комплект «Мама и ребёнок»'), findsOneWidget);
    });
  });

  group('a комплект the shop has withdrawn', () {
    testWidgets('is not shown at all, at any price', (tester) async {
      // An operator sets the set inactive in frame 08; the storefront then
      // omits the row. The screen used to keep the hero — the build's name, the
      // build's 39 000 ₸ and a working «Заказать комплект» — for a product
      // nobody can buy.
      final orders = await pump(tester,
          pregnant: true,
          catalogue: catalogue(products: [
            product('watch', 'Часы', 2490000),
            product('tracker', 'Трекер', 490000),
          ]));
      expect(find.text(l.t('crs_bundle_name')), findsNothing);
      expect(find.text(formatTenge(coursePrices.bundleMinor)), findsNothing);
      expect(find.text(l.t('shop_order_bundle')), findsNothing);
      // The «выгода» line went with it: it measured live parts against a price
      // the shop does not charge.
      expect(
          find.textContaining(
              l.t('shop_saving', {'amount': ''}).split('{')[0].trim()),
          findsNothing);
      // What IS on sale is still on sale.
      expect(find.text('Часы'), findsOneWidget);
      expect(find.text(formatTenge(2490000)), findsOneWidget);
      expect(orders, isEmpty);
    });

    testWidgets('and no load-failure notice, because nothing failed',
        (tester) async {
      await pump(tester,
          catalogue: catalogue(products: [product('watch', 'Часы', 2490000)]));
      expect(find.text(l.t('shop_empty')), findsNothing);
    });

    testWidgets('a catalogue of ONLY the set is not a failed load',
        (tester) async {
      // «rows» is the catalogue minus the комплект, so a shop selling only the
      // set satisfied «loaded but empty» and printed «Не удалось загрузить
      // товары» directly beneath that set's live price and order button.
      final orders = await pump(tester,
          pregnant: true,
          catalogue: catalogue(products: [
            product('combo', 'Комплект «Мама и ребёнок»', 3900000,
                isBundle: true),
          ]));
      expect(find.text(l.t('shop_empty')), findsNothing);
      expect(find.text(formatTenge(3900000)), findsOneWidget);
      await tester.tap(find.text(l.t('shop_order_bundle')));
      await tester.pumpAndSettle();
      expect(orders, hasLength(1));
    });
  });

  group('the saving line', () {
    testWidgets('is hidden when the live prices make it zero or negative',
        (tester) async {
      // An operator may price the set above its parts. «Выгода −3 000 ₸» and a
      // struck-through number LOWER than the one beside it both read as a con.
      await pump(tester,
          pregnant: true,
          catalogue: catalogue(products: [
            product('watch', 'Часы', 100000),
            product('tracker', 'Трекер', 100000),
            product('combo', 'Комплект', 11000000, isBundle: true),
          ]));
      expect(find.textContaining(l.t('shop_saving', {'amount': ''}).split('{')[0].trim()),
          findsNothing);
      expect(find.text(formatTenge(11000000)), findsOneWidget);
    });

    testWidgets('is shown, with the live figures, when there IS a saving',
        (tester) async {
      await pump(tester,
          pregnant: true,
          catalogue: catalogue(products: [
            product('watch', 'Часы', 2000000),
            product('tracker', 'Трекер', 500000),
            product('combo', 'Комплект', 3900000, isBundle: true),
          ]));
      // 20 000 + 5 000 + 99 000 (the course constant) − 39 000 = 85 000 ₸.
      final prices = coursePricesFrom(catalogue(products: [
        product('watch', 'Часы', 2000000),
        product('tracker', 'Трекер', 500000),
        product('combo', 'Комплект', 3900000, isBundle: true),
      ]));
      expect(prices.savingMinor, 8500000);
      expect(
          find.text(
              l.t('shop_saving', {'amount': formatTenge(prices.savingMinor)})),
          findsOneWidget);
    });
  });
}

/// Every state of this screen, at 360 dp, with overflow made fatal.
///
/// A widget test does not fail on a RenderFlex overflow by default — it prints
/// a yellow bar nobody sees in CI. Two of them shipped from this file's own
/// first draft, so the sweep is explicit.
void _overflowSweep() {
  // The loaded states carry chips the constants path never draws — an age band,
  // a match reason and «нет в наличии» can all land on one row, in Kazakh,
  // which is the longest of the three languages.
  final loaded = catalogue(products: [
    product('combo', 'Комплект «Мама и ребёнок»', 3900000,
        isBundle: true, inStock: false),
    product('tracker', 'Детский брелок Kid', 490000,
        nameKk: 'Балаларға арналған Kid брелогы',
        ageMin: 18,
        ageMax: 84,
        inStock: false),
    product('watch', 'Смарт-часы Ana-Bala', 2490000,
        nameKk: 'Ana-Bala смарт-сағаты', stage: ProductStage.pregnancy),
  ]);
  final cached = ShopCatalogue(
      products: loaded.products,
      fetchedAt: DateTime(2026, 3, 2),
      fromCache: true);

  for (final (name, pregnant, ages, cat, lang)
      in <(String, bool, List<int>, ShopCatalogue, L10n)>[
    ('expecting', true, <int>[], ShopCatalogue.empty, l),
    ('newborn', false, [2], ShopCatalogue.empty, l),
    ('toddler', false, [30], ShopCatalogue.empty, l),
    ('nothing known', false, <int>[], ShopCatalogue.empty, l),
    ('live catalogue', true, [30], loaded, l),
    (
      'комплект withdrawn',
      true,
      [30],
      catalogue(products: [
        for (final p in loaded.products)
          if (p.id != 'combo') p
      ]),
      lkk
    ),
    ('live catalogue in Kazakh', true, [30], loaded, lkk),
    ('cached catalogue', false, [30], cached, l),
  ]) {
    testWidgets('$name fits a 360 dp phone', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final prev = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = prev);

      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(L10nScope(
        l10n: lang,
        child: MaterialApp(
          theme: FcsTheme.light(lang.locale),
          home: ShopScreen(
            pregnant: pregnant,
            childAgesMonths: ages,
            catalogue: cat,
            onOrder: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        errors.where((e) => '${e.exception}'.contains('overflowed')),
        isEmpty,
        reason: '$name overflowed',
      );
    });
  }
}
