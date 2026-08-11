/// The live shop catalogue: parsing it, caching it, and ordering it for her.
///
/// The feature this covers is one join. An operator has been able to set a
/// price, a Kazakh name, a stage and a child age band since migration 033, and
/// the app could not see any of it — it sold three hard-coded products at
/// compile-time prices. So the tests below are mostly about the places that
/// join can quietly fail: a missing Kazakh name rendering as blank, an
/// unreachable shop silently showing last year's figures as if they were
/// current, and an operator's dropdown reordering — never hiding — the shelf.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/course_prices.dart';
import 'package:fcs_app/domain/shop_catalogue.dart';
import 'package:fcs_app/domain/shop_stage.dart';

/// A transport that answers /shop/products with whatever it is given, or
/// throws, which is what being offline looks like from here.
class _FakeTransport implements HttpTransport {
  Object? body;
  int status;
  bool throws;
  final gets = <String>[];

  _FakeTransport({this.body, this.status = 200, this.throws = false});

  @override
  Future<HttpResponse> get(String path) async {
    gets.add(path);
    if (throws) throw const SocketExceptionStub();
    return HttpResponse(status, jsonEncode(body ?? {}));
  }

  @override
  Future<HttpResponse> post(String path, Object b) async => const HttpResponse(201, '{}');
  @override
  Future<HttpResponse> put(String path, Object b) async => const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');
}

/// Stands in for a real socket failure without importing dart:io.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

class _MemoryCache implements JsonCache {
  String? value;
  int writes = 0;
  bool failWrites = false;

  _MemoryCache([this.value]);

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async {
    writes++;
    if (failWrites) throw const SocketExceptionStub();
    value = json;
  }
}

Map<String, dynamic> _product(
  String id,
  String name,
  int priceMinor, {
  String? nameKk,
  String? descriptionRu,
  String? descriptionKk,
  String kind = 'simple',
  String? stage,
  int? ageMin,
  int? ageMax,
  bool inStock = true,
  List<String> parts = const [],
}) =>
    {
      'id': id,
      'name': name,
      'priceMinor': priceMinor,
      'kind': kind,
      'nameKk': nameKk,
      'descriptionRu': descriptionRu,
      'descriptionKk': descriptionKk,
      'stage': stage,
      'category': null,
      'ageMinMonths': ageMin,
      'ageMaxMonths': ageMax,
      'photoUrl': null,
      'inStock': inStock,
      'variants': const [],
      'parts': [for (final p in parts) {'partId': p, 'qty': 1}],
    };

final _wire = {
  'products': [
    _product('watch', 'Смарт-часы Ana-Bala', 2490000,
        nameKk: 'Ana-Bala смарт-сағаты', stage: 'pregnancy'),
    _product('tracker', 'Детский трекер Ana-Bala', 490000,
        ageMin: 18, ageMax: 84),
    _product('combo', 'Комплект «Мама и ребёнок»', 3900000,
        kind: 'bundle', parts: ['watch', 'tracker']),
  ],
};

void main() {
  group('reading the wire', () {
    test('carries the operator-owned fields, not just id and price', () {
      final c = ShopCatalogue.fromJson(_wire, fetchedAt: DateTime(2026, 8, 11));
      final tracker = c.byId('tracker')!;
      expect(tracker.priceMinor, 490000);
      expect(tracker.ageMinMonths, 18);
      expect(tracker.ageMaxMonths, 84);
      expect(c.byId('watch')!.stage, ProductStage.pregnancy);
    });

    test('an unset stage stays null — the app falls back, it does not guess', () {
      // A default of «any» here would replace a working heuristic with a wrong
      // fact, and nobody downstream could tell which they were looking at.
      final c = ShopCatalogue.fromJson(_wire);
      expect(c.byId('tracker')!.stage, isNull);
      expect(c.byId('tracker')!.hasPersonalisation, isTrue); // it has a band
      expect(c.byId('combo')!.hasPersonalisation, isFalse);
    });

    test('a stage this build has never heard of is null, not a crash', () {
      // The panel's vocabulary can gain a value before an app update ships.
      final c = ShopCatalogue.fromJson({
        'products': [_product('x', 'X', 100, stage: 'menopause')],
      });
      expect(c.products, hasLength(1));
      expect(c.byId('x')!.stage, isNull);
    });

    test('one malformed row does not empty the shop', () {
      final c = ShopCatalogue.fromJson({
        'products': [
          {'id': 'broken'}, // no name, no price
          _product('watch', 'Часы', 2490000),
        ],
      });
      expect(c.products.map((p) => p.id), ['watch']);
    });

    test('a bundle keeps its parts and its kind', () {
      final combo = ShopCatalogue.fromJson(_wire).byId('combo')!;
      expect(combo.isBundle, isTrue);
      expect(combo.partIds..sort(), ['tracker', 'watch']);
    });
  });

  group('bilingual', () {
    test('kk uses name_kk', () {
      final w = ShopCatalogue.fromJson(_wire).byId('watch')!;
      expect(w.name('kk'), 'Ana-Bala смарт-сағаты');
      expect(w.name('ru'), 'Смарт-часы Ana-Bala');
    });

    test('a missing Kazakh name shows the Russian one — NEVER blank', () {
      // The panel blocks publication without it, but a product activated
      // before that rule existed is still on the shelf. A nameless row on the
      // screen that asks for 39 000 ₸ is the worst of the three outcomes.
      final t = ShopCatalogue.fromJson(_wire).byId('tracker')!;
      expect(t.nameKk, isNull);
      expect(t.name('kk'), 'Детский трекер Ana-Bala');
      expect(t.name('kk'), isNotEmpty);
    });

    test('an EMPTY Kazakh name is treated as missing, not shown', () {
      final c = ShopCatalogue.fromJson({
        'products': [_product('x', 'Часы', 100, nameKk: '   ')],
      });
      expect(c.byId('x')!.name('kk'), 'Часы');
    });

    test('descriptions fall back the same way, and null when there are none', () {
      final c = ShopCatalogue.fromJson({
        'products': [
          _product('a', 'A', 1, descriptionRu: 'Давление и пульс'),
          _product('b', 'B', 1),
        ],
      });
      expect(c.byId('a')!.description('kk'), 'Давление и пульс');
      expect(c.byId('b')!.description('ru'), isNull);
    });
  });

  group('ApiClient.getShopCatalogue', () {
    test('reads the storefront and stamps it with the moment it was read', () async {
      final t = _FakeTransport(body: _wire);
      final before = DateTime.now();
      final c = await ApiClient(t).getShopCatalogue();
      expect(t.gets, ['/shop/products']);
      expect(c.products, hasLength(3));
      expect(c.fromCache, isFalse);
      expect(c.fetchedAt!.isBefore(before.subtract(const Duration(seconds: 1))),
          isFalse);
    });

    test('caches the last good payload', () async {
      final cache = _MemoryCache();
      await ApiClient(_FakeTransport(body: _wire), catalogueCache: cache)
          .getShopCatalogue();
      expect(cache.writes, 1);
      final stored = jsonDecode(cache.value!) as Map<String, dynamic>;
      expect((stored['products'] as List), hasLength(3));
      // Without the date the cache cannot be labelled, and an unlabelled price
      // is the thing the whole offline path exists to avoid.
      expect(stored['fetchedAt'], isNotNull);
    });

    test('offline: serves the cache, marked as such, with its date', () async {
      final cache = _MemoryCache();
      final api = ApiClient(_FakeTransport(body: _wire), catalogueCache: cache);
      final live = await api.getShopCatalogue();

      final offline = ApiClient(_FakeTransport(throws: true), catalogueCache: cache);
      final c = await offline.getShopCatalogue();
      expect(c.products, hasLength(3));
      expect(c.fromCache, isTrue);
      expect(c.fetchedAt!.toIso8601String(), live.fetchedAt!.toIso8601String());
    });

    test('offline with NO cache: empty, so the screen says «ориентировочные»', () async {
      final c = await ApiClient(_FakeTransport(throws: true)).getShopCatalogue();
      expect(c.isEmpty, isTrue);
      expect(c.fetchedAt, isNull);
    });

    test('never throws — not on a 500, not on a body that is not JSON', () async {
      expect((await ApiClient(_FakeTransport(status: 500)).getShopCatalogue()).isEmpty,
          isTrue);
      expect((await ApiClient(_BrokenBodyTransport()).getShopCatalogue()).isEmpty,
          isTrue);
    });

    test('a 200 carrying an empty list does not clobber the cache', () async {
      // Every product withdrawn at once is indistinguishable on the wire from a
      // half-deployed server. Keeping real prices on screen is the safer read.
      final cache = _MemoryCache();
      await ApiClient(_FakeTransport(body: _wire), catalogueCache: cache)
          .getShopCatalogue();
      final writesAfterGood = cache.writes;

      final c = await ApiClient(_FakeTransport(body: const {'products': []}),
              catalogueCache: cache)
          .getShopCatalogue();
      expect(cache.writes, writesAfterGood);
      expect(c.products, hasLength(3));
      expect(c.fromCache, isTrue);
    });

    test('a cache that cannot be written still returns the live catalogue', () async {
      final cache = _MemoryCache()..failWrites = true;
      final c = await ApiClient(_FakeTransport(body: _wire), catalogueCache: cache)
          .getShopCatalogue();
      expect(c.products, hasLength(3));
      expect(c.fromCache, isFalse);
    });

    test('a corrupt cache reads as nothing rather than throwing', () async {
      final cache = _MemoryCache('not json at all');
      final c = await ApiClient(_FakeTransport(throws: true), catalogueCache: cache)
          .getShopCatalogue();
      expect(c.isEmpty, isTrue);
    });
  });

  group('«Для вашего этапа» — ordering by what an operator said', () {
    List<String> order(
      List<Map<String, dynamic>> products, {
      bool pregnant = false,
      List<int> ages = const [],
    }) =>
        rankForStage(
          ShopCatalogue.fromJson({'products': products}).products,
          pregnant: pregnant,
          childAgesMonths: ages,
        ).map((r) => r.product.id).toList();

    test('stage=pregnancy puts that product first for an expecting mother', () {
      final ids = order([
        _product('tracker', 'Трекер', 490000, stage: 'toddler'),
        _product('watch', 'Часы', 2490000, stage: 'pregnancy'),
      ], pregnant: true);
      expect(ids.first, 'watch');
    });

    test('an age band puts that product first for a child of that age', () {
      final ids = order([
        _product('watch', 'Часы', 2490000),
        _product('tracker', 'Трекер', 490000, ageMin: 18, ageMax: 84),
      ], ages: [30]);
      expect(ids.first, 'tracker');
    });

    test('a band that does not cover her child does NOT promote it', () {
      final ids = order([
        _product('watch', 'Часы', 2490000),
        _product('tracker', 'Трекер', 490000, ageMin: 18, ageMax: 84),
      ], ages: [4]);
      expect(ids.first, 'watch');
    });

    test('an open-ended band is open, not zero', () {
      final ids = order([
        _product('watch', 'Часы', 2490000),
        _product('tracker', 'Трекер', 490000, ageMin: 18),
      ], ages: [200]);
      expect(ids.first, 'tracker');
    });

    test('nothing tagged: the old heuristic still decides', () {
      // The whole catalogue is untagged today. Falling back is the difference
      // between a defensible order and an arbitrary one.
      final ids = order([
        _product('watch', 'Часы', 2490000),
        _product('tracker', 'Трекер', 490000),
      ], ages: [30]);
      expect(ids.first, 'tracker'); // a walking child — StageReason.childOnTheMove
    });

    test('nothing is ever HIDDEN, only moved', () {
      final ids = order([
        _product('watch', 'Часы', 2490000, stage: 'planning'),
        _product('tracker', 'Трекер', 490000, stage: 'pregnancy'),
      ], pregnant: true);
      expect(ids, containsAll(['watch', 'tracker']));
      expect(ids.first, 'tracker');
    });

    test('«any» beats untagged but loses to a real match', () {
      final ids = order([
        _product('a', 'A', 1),
        _product('b', 'B', 1, stage: 'any'),
        _product('c', 'C', 1, stage: 'pregnancy'),
      ], pregnant: true);
      expect(ids, ['c', 'b', 'a']);
    });

    test('a product tagged for somebody else sinks BELOW an untagged one', () {
      final ids = order([
        _product('foreign', 'F', 1, stage: 'newborn'),
        _product('unknown', 'U', 1),
      ], pregnant: true);
      expect(ids, ['unknown', 'foreign']);
    });

    test('the match reason is carried, so the row can state it', () {
      final ranked = rankForStage(
        ShopCatalogue.fromJson({
          'products': [
            _product('tracker', 'Трекер', 1, ageMin: 18, ageMax: 84),
            _product('watch', 'Часы', 1, stage: 'pregnancy'),
            _product('plain', 'П', 1),
          ]
        }).products,
        pregnant: true,
        childAgesMonths: const [30],
      );
      final by = {for (final r in ranked) r.product.id: r.match};
      expect(by['tracker'], StageMatch.ageBand);
      expect(by['watch'], StageMatch.stage);
      expect(by['plain'], StageMatch.untagged);
    });
  });

  group('what the app may say about her', () {
    test('a pregnant mother of a toddler is at BOTH stages', () {
      final s = viewerStages(pregnant: true, childAgesMonths: const [30]);
      expect(s, containsAll([ProductStage.pregnancy, ProductStage.toddler]));
    });

    test('«planning» is never claimed — the app does not ask', () {
      // Deriving it from "no children" would put a claim about her fertility on
      // a shop screen.
      expect(viewerStages(pregnant: false, childAgesMonths: const []),
          isNot(contains(ProductStage.planning)));
      expect(stageOfChildMonths(0), ProductStage.newborn);
      expect(stageOfChildMonths(6), ProductStage.infant);
      expect(stageOfChildMonths(30), ProductStage.toddler);
      // A six-year-old is none of them, and nothing is invented.
      expect(stageOfChildMonths(72), isNull);
    });
  });

  group('the price card reads the catalogue', () {
    test('the комплект price comes off the wire', () {
      final c = ShopCatalogue.fromJson({
        'products': [_product('combo', 'Комплект', 4450000, kind: 'bundle')],
      }, fetchedAt: DateTime(2026, 8, 11));
      final p = coursePricesFrom(c);
      expect(p.bundleMinor, 4450000);
      expect(p.isApproximate, isFalse);
    });

    test('the course-only price stays a CONSTANT — there is no such product', () {
      // 018_landing_prices: the course is what the комплект grants. There is
      // nothing in the catalogue to read, so nothing is read.
      final p = coursePricesFrom(ShopCatalogue.fromJson(_wire));
      expect(p.courseOnlyMinor, coursePrices.courseOnlyMinor);
    });

    test('with nothing fetched the constants are used AND flagged', () {
      final p = coursePricesFrom(ShopCatalogue.empty);
      expect(p.bundleMinor, coursePrices.bundleMinor);
      expect(p.isApproximate, isTrue);
    });

    test('a set priced above its parts reports no saving rather than a negative one',
        () {
      // «Выгода −3 000 ₸» is the failure this guards.
      final c = ShopCatalogue.fromJson({
        'products': [
          _product('watch', 'Часы', 100000),
          _product('tracker', 'Трекер', 100000),
          _product('combo', 'Комплект', 9900000, kind: 'bundle'),
        ],
      }, fetchedAt: DateTime(2026, 8, 11));
      final p = coursePricesFrom(c);
      expect(p.savingMinor, lessThan(0));
      expect(p.savingIsReal, isFalse);
    });

    test('a catalogue WITHOUT the комплект does not price it from the build', () {
      // Frame 08: PATCH /admin/shop/products/combo {active:false} withdraws the
      // set and the storefront omits the row. A perfectly good catalogue of the
      // other two products used to set pricedAt — so isApproximate went false
      // and both screens quoted the compile-time 39 000 ₸ as if an operator had
      // just confirmed it.
      final c = ShopCatalogue.fromJson({
        'products': [
          _product('watch', 'Часы', 2490000),
          _product('tracker', 'Трекер', 490000),
        ],
      }, fetchedAt: DateTime(2026, 8, 11));
      final p = coursePricesFrom(c);
      expect(p.bundleAvailable, isFalse);
      expect(p.bundleIsLive, isFalse);
      expect(p.isApproximate, isTrue);
      // And no «выгода», which would be live parts measured against a price
      // nobody charges.
      expect(p.savingIsReal, isFalse);
    });

    test('nothing fetched keeps the built-in offer, because nothing is known', () {
      // The difference from the case above: an unreachable shop is not a shop
      // that has withdrawn the set.
      final p = coursePricesFrom(ShopCatalogue.empty);
      expect(p.bundleAvailable, isTrue);
      expect(p.savingIsReal, isTrue);
    });

    test('a cached catalogue prices the card from cache, and says so', () {
      final c = ShopCatalogue.fromJson(_wire,
          fetchedAt: DateTime(2026, 3, 2), fromCache: true);
      final p = coursePricesFrom(c);
      expect(p.fromCache, isTrue);
      expect(p.pricedAt, DateTime(2026, 3, 2));
      expect(p.isApproximate, isFalse);
    });
  });
}

/// A 200 whose body is not JSON — a captive-portal login page, typically.
class _BrokenBodyTransport implements HttpTransport {
  @override
  Future<HttpResponse> get(String path) async =>
      const HttpResponse(200, '<html>hotel wifi</html>');
  @override
  Future<HttpResponse> post(String path, Object b) async => const HttpResponse(201, '{}');
  @override
  Future<HttpResponse> put(String path, Object b) async => const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');
}
