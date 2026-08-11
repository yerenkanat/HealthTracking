/// The live shop catalogue — what an operator maintains in the back office,
/// as screen 41 «Магазин» sees it.
///
/// Until this existed the app sold three hard-coded products at compile-time
/// prices. Migration 033 gave a product a category, a stage, a Kazakh name and
/// a child age band, the panel gained frames 08 and 08a to edit them, and none
/// of it could reach a customer: `GET /shop/products` answered with
/// id/name/price/kind/variants and the shop screen ignored even those. Changing
/// the price of the 39 000 ₸ комплект in the panel changed nothing anybody
/// could see.
///
/// Two rules run through this file:
///
/// * **Missing is missing.** A null stage is not «any» and a null Kazakh name
///   is not an empty string — those are things an operator has not said yet,
///   and the app falls back rather than inventing an answer or showing a blank.
/// * **Say how old the answer is.** A catalogue restored from cache carries the
///   moment it was fetched, and one that could not be fetched at all is not
///   silently replaced by last year's constants.
library;

/// The ids of the three products this app was built around.
///
/// Written down once, and as CATALOGUE ids — these are the primary keys the
/// server seeds (migration 021), not labels invented here. The app needs them
/// for the two things it cannot learn from a generic catalogue: which row is
/// the комплект whose price screen 34 quotes, and how the old stage heuristic
/// maps onto real products. Everything else about a product now comes off the
/// wire, and a product the app has never heard of renders perfectly well.
const watchProductId = 'watch';
const trackerProductId = 'tracker';
const bundleProductId = 'combo';

/// The stages a product can be FOR — migration 033's vocabulary, exactly.
///
/// [any] is a real answer meaning "for everyone", not a missing one.
enum ProductStage { planning, pregnancy, newborn, infant, toddler, any }

/// Parse the wire value. An unrecognised stage becomes null rather than
/// throwing: the panel's vocabulary can gain a value before an app update
/// ships, and one unknown string must not empty the shop.
ProductStage? productStageFromWire(Object? v) => switch (v) {
      'planning' => ProductStage.planning,
      'pregnancy' => ProductStage.pregnancy,
      'newborn' => ProductStage.newborn,
      'infant' => ProductStage.infant,
      'toddler' => ProductStage.toddler,
      'any' => ProductStage.any,
      _ => null,
    };

/// One product on the storefront.
class CatalogueProduct {
  final String id;

  /// The Russian name — the one column the schema requires, so it is the
  /// fallback for every other locale.
  final String nameRu;
  final String? nameKk;
  final String? descriptionRu;
  final String? descriptionKk;

  /// Tiyn, live from the catalogue.
  final int priceMinor;

  /// A bundle is a SET: it has no colours of its own and [partIds] says which
  /// products a buyer picks a colour of.
  final bool isBundle;
  final List<String> partIds;

  /// Operator-owned personalisation. Null means unsaid — see [rankForStage],
  /// which falls back to the app's own heuristic rather than treating an
  /// unsaid stage as a mismatch.
  final ProductStage? stage;
  final int? ageMinMonths;
  final int? ageMaxMonths;

  /// Usually null: nothing hosts product images yet. Kept so the day one does,
  /// the wire is already carrying it.
  final String? photoUrl;

  /// Derived server-side. For a bundle it means every part can be supplied,
  /// which is not the same as the bundle having stock of its own — it never
  /// has any.
  final bool inStock;

  const CatalogueProduct({
    required this.id,
    required this.nameRu,
    required this.priceMinor,
    this.nameKk,
    this.descriptionRu,
    this.descriptionKk,
    this.isBundle = false,
    this.partIds = const [],
    this.stage,
    this.ageMinMonths,
    this.ageMaxMonths,
    this.photoUrl,
    this.inStock = false,
  });

  /// The name for [languageCode], falling back to Russian.
  ///
  /// A product with no Kazakh name shows its Russian one. Never blank: the
  /// panel refuses to PUBLISH without the Kazakh version, but a product
  /// activated before that rule existed is still on the shelf, and a nameless
  /// row on a screen asking for 39 000 ₸ is worse than a Russian one.
  String name(String languageCode) {
    if (languageCode == 'kk') {
      final kk = nameKk?.trim();
      if (kk != null && kk.isNotEmpty) return kk;
    }
    return nameRu;
  }

  /// The description for [languageCode], or null when there is none in either.
  /// Null is a real answer — the screen then falls back to its own copy for the
  /// products it knows, and prints nothing for the ones it does not.
  String? description(String languageCode) {
    if (languageCode == 'kk') {
      final kk = descriptionKk?.trim();
      if (kk != null && kk.isNotEmpty) return kk;
    }
    final ru = descriptionRu?.trim();
    return (ru == null || ru.isEmpty) ? null : ru;
  }

  /// Whether an operator said anything about who this is for. When nobody has,
  /// the app's own heuristic decides the order — that is not a gap to paper
  /// over, it is the state the catalogue shipped in.
  bool get hasPersonalisation =>
      stage != null || ageMinMonths != null || ageMaxMonths != null;

  /// Does [months] fall inside the band. An open end is open, not zero: «от 0»
  /// and «до 36» are each meaningful alone, which is why both columns are
  /// independently nullable.
  bool coversAgeMonths(int months) {
    if (ageMinMonths == null && ageMaxMonths == null) return false;
    if (ageMinMonths != null && months < ageMinMonths!) return false;
    if (ageMaxMonths != null && months > ageMaxMonths!) return false;
    return true;
  }

  /// Tolerant: a row missing an id, a name or a price is DROPPED rather than
  /// thrown, because one malformed product must not empty a shop.
  static CatalogueProduct? fromJson(Map<String, dynamic> j) {
    final id = (j['id'] as String?)?.trim();
    final name = (j['name'] as String?)?.trim();
    final price = j['priceMinor'];
    if (id == null || id.isEmpty) return null;
    if (name == null || name.isEmpty) return null;
    if (price is! num) return null;

    String? str(String k) {
      final v = j[k];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    int? months(String k) {
      final v = j[k];
      return v is num ? v.round() : null;
    }

    return CatalogueProduct(
      id: id,
      nameRu: name,
      nameKk: str('nameKk'),
      descriptionRu: str('descriptionRu'),
      descriptionKk: str('descriptionKk'),
      priceMinor: price.round(),
      isBundle: j['kind'] == 'bundle',
      partIds: [
        for (final p in (j['parts'] as List?) ?? const [])
          if (p is Map && p['partId'] is String) p['partId'] as String,
      ],
      stage: productStageFromWire(j['stage']),
      ageMinMonths: months('ageMinMonths'),
      ageMaxMonths: months('ageMaxMonths'),
      photoUrl: str('photoUrl'),
      inStock: j['inStock'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': nameRu,
        if (nameKk != null) 'nameKk': nameKk,
        if (descriptionRu != null) 'descriptionRu': descriptionRu,
        if (descriptionKk != null) 'descriptionKk': descriptionKk,
        'priceMinor': priceMinor,
        'kind': isBundle ? 'bundle' : 'simple',
        'parts': [for (final p in partIds) {'partId': p}],
        if (stage != null) 'stage': stage!.name,
        if (ageMinMonths != null) 'ageMinMonths': ageMinMonths,
        if (ageMaxMonths != null) 'ageMaxMonths': ageMaxMonths,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'inStock': inStock,
      };
}

/// A whole catalogue, and how old it is.
///
/// [fetchedAt] is the point of this class. A shop screen that shows prices with
/// no idea whether they came from the network a second ago or from a cache in
/// March is a screen that can quote a stale 39 000 ₸ with total confidence.
class ShopCatalogue {
  final List<CatalogueProduct> products;

  /// When these prices were last read from the server. Null only for [empty].
  final DateTime? fetchedAt;

  /// True when this came out of the cache because the network could not be
  /// reached — the screen says so, with the date.
  final bool fromCache;

  const ShopCatalogue({
    required this.products,
    this.fetchedAt,
    this.fromCache = false,
  });

  /// Nothing known: no network and nothing cached. The screen falls back to its
  /// compile-time constants AND labels them as approximate, because that is
  /// exactly what they are once an operator can change a price.
  static const empty = ShopCatalogue(products: []);

  bool get isEmpty => products.isEmpty;

  CatalogueProduct? byId(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Parse `{"products": [...]}`.
  static ShopCatalogue fromJson(
    Map<String, dynamic> j, {
    DateTime? fetchedAt,
    bool fromCache = false,
  }) {
    final list = <CatalogueProduct>[];
    for (final raw in (j['products'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final p = CatalogueProduct.fromJson(Map<String, dynamic>.from(raw));
      if (p != null) list.add(p);
    }
    final at = fetchedAt ?? DateTime.tryParse((j['fetchedAt'] as String?) ?? '');
    return ShopCatalogue(products: list, fetchedAt: at, fromCache: fromCache);
  }

  Map<String, dynamic> toJson() => {
        'products': [for (final p in products) p.toJson()],
        if (fetchedAt != null) 'fetchedAt': fetchedAt!.toIso8601String(),
      };
}
