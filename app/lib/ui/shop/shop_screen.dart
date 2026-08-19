/// Screen 41 — «Магазин».
///
/// «герой комплекта → секция «Для вашего этапа» с товарами → плашка про
/// WhatsApp → «Заказать комплект».»
///
/// The whole offer in one place, inside the app. Until now the only way to buy
/// anything was the landing page in a browser, which a customer who already has
/// the app is unlikely to be looking at.
///
/// **What is on this screen is now an operator's, not a build's.** The prices,
/// the Kazakh names, the descriptions, the stage and the child age band come
/// off `/shop/products`, which is the panel's frame 08a read back. Before that
/// the screen hard-coded three products and their prices, so changing the price
/// of the 39 000 ₸ комплект in the back office changed nothing a customer saw.
///
/// Three rules the screen keeps, in order of how badly breaking them would go:
///
/// * **Never quote a price without saying what it is.** A cached catalogue is
///   labelled with the date it was fetched; a phone that has never reached the
///   server falls back to the compile-time constants and says they are
///   approximate. A confident stale number on the screen that asks for
///   39 000 ₸ is the worst thing here.
/// * **Never hide what she can still buy.** «Для вашего этапа» REORDERS the
///   catalogue; it does not filter it. An operator's dropdown must not be able
///   to conceal two thirds of the shop.
/// * **Never claim a basis it does not have.** Where an operator has said who a
///   product is for, the row says so. Where nobody has, the old heuristic
///   orders it and the section prints the reason, exactly as before.
library;

import 'package:flutter/material.dart';

import '../../domain/course_prices.dart';
import '../../domain/my_order.dart' show formatTenge;
import '../../domain/shop_catalogue.dart';
import '../../domain/shop_stage.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../ds_widgets.dart';
import '../theme.dart';

class ShopScreen extends StatelessWidget {
  final bool pregnant;
  final List<int> childAgesMonths;

  /// What the back office is selling today.
  ///
  /// Defaults to [ShopCatalogue.empty] — a phone that has never reached the
  /// server — and the screen then shows the constants, labelled. It is a
  /// parameter rather than a fetch inside the screen for the same reason
  /// [onOrder] is: the answer decides which buttons EXIST, and a shop that
  /// grows buttons a second after opening is one somebody taps by accident.
  final ShopCatalogue catalogue;

  /// Opens WhatsApp with the given message. Null when no number is configured,
  /// and every buy button then disappears rather than opening nothing.
  final void Function(String message)? onOrder;

  const ShopScreen({
    super.key,
    required this.pregnant,
    required this.childAgesMonths,
    this.catalogue = ShopCatalogue.empty,
    this.onOrder,
  });

  /// The app's own copy for the products it was built around, used when an
  /// operator has not written a description. Null for anything else — a
  /// product this build has never heard of gets no invented blurb.
  String? _fallbackWhat(L10n l, String productId) => switch (productId) {
        watchProductId => l.t('shop_item_watch_what'),
        trackerProductId => l.t('shop_item_tracker_what'),
        bundleProductId => l.t('crs_bundle_what'),
        _ => null,
      };

  /// The name for a product the catalogue could not supply.
  String _fallbackName(L10n l, ShopItem item) => switch (item) {
        ShopItem.watch => l.t('shop_item_watch'),
        ShopItem.tracker => l.t('shop_item_tracker'),
        ShopItem.bundle => l.t('crs_bundle_name'),
      };

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final lang = l.localeCode;
    final prices = coursePricesFrom(catalogue);
    final bundle = catalogue.byId(bundleProductId);

    final suggestion = stageSuggestion(
      pregnant: pregnant,
      childAgesMonths: childAgesMonths,
    );

    // The комплект is the hero above; repeating it in the list below would be
    // the same product twice on one screen.
    final rows = [
      for (final r in rankForStage(catalogue.products,
          pregnant: pregnant, childAgesMonths: childAgesMonths))
        if (r.product.id != bundleProductId) r,
    ];

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(title: Text(l.t('shop_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Before anything with a price on it, because it changes how every
          // number below should be read.
          _FreshnessNote(catalogue: catalogue),

          // No hero when a catalogue was read and the комплект was not in it:
          // an operator has taken the set off sale, and the built-in name at
          // the built-in 39 000 ₸ with a working «Заказать комплект» button
          // would be the app selling something the shop has withdrawn. The
          // constants path (nothing fetched at all) still shows it — see
          // [CoursePrices.bundleAvailable].
          if (prices.bundleAvailable)
            _BundleHero(
              name: bundle?.name(lang) ?? l.t('crs_bundle_name'),
              what: bundle?.description(lang) ?? l.t('crs_bundle_what'),
              prices: prices,
              // Null when the catalogue has no комплект at all: the screen then
              // knows nothing about stock and says nothing, rather than
              // claiming the set is available or that it is not.
              inStock: bundle?.inStock,
              onOrder: onOrder == null
                  ? null
                  : () => onOrder!(_orderMessage(
                        l,
                        bundle?.name(lang) ?? l.t('crs_bundle_name'),
                        inStock: bundle?.inStock ?? true,
                      )),
            ),

          const SizedBox(height: 24),
          Text(l.t('shop_for_your_stage'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          // The reason travels with the suggestion. A recommendation with no
          // stated basis is indistinguishable from an advert.
          Text(l.t(suggestion.reason.l10nKey),
              style: const TextStyle(
                  fontSize: 13, height: 1.4, color: Palette.textDim)),
          const SizedBox(height: 12),

          // Spread on both branches, deliberately. Written as a bare
          // `if (…) for (…) if (…) X else for (…) Y`, the `else` binds to the
          // INNER if — Dart's dangling-else rule applies to collection
          // elements too — and the loaded branch renders nothing at all. That
          // is not hypothetical: it is what the first draft of this screen did,
          // and the analyzer had nothing to say about it.
          if (catalogue.isEmpty) ...[
            // No catalogue at all. The three products this build knows about,
            // at the constants — already labelled approximate above.
            for (final item in suggestion.items)
              if (item != ShopItem.bundle)
                _ProductRow(
                  name: _fallbackName(l, item),
                  what: item == ShopItem.watch
                      ? l.t('shop_item_watch_what')
                      : l.t('shop_item_tracker_what'),
                  price: formatTenge(item == ShopItem.watch
                      ? prices.watchMinor
                      : prices.trackerMinor),
                  onOrder: onOrder == null
                      ? null
                      : () => onOrder!(l.t('shop_wa_item',
                          {'item': _fallbackName(l, item)})),
                ),
          ] else ...[
            for (final r in rows)
              _ProductRow(
                name: r.product.name(lang),
                what: r.product.description(lang) ??
                    _fallbackWhat(l, r.product.id) ??
                    '',
                price: formatTenge(r.product.priceMinor),
                inStock: r.product.inStock,
                match: r.match,
                ageBand: _ageBandLabel(l, r.product),
                onOrder: onOrder == null
                    ? null
                    : () => onOrder!(_orderMessage(l, r.product.name(lang),
                        inStock: r.product.inStock)),
              ),
          ],

          // «Не удалось загрузить товары» is a claim about the network, and the
          // screen may only make it when it is showing nothing. It used to be
          // gated on `rows` alone — but `rows` is the catalogue MINUS the
          // комплект, so a catalogue containing only the set printed a load
          // failure directly beneath that set's live price and order button.
          if (rows.isEmpty && !prices.bundleAvailable) ...[
            Text(l.t('shop_empty'),
                style: const TextStyle(
                    fontSize: 13, height: 1.4, color: Palette.textDim)),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 18),
          _WhatsAppNote(),
        ],
      ),
    );
  }

  /// What she sends on WhatsApp.
  ///
  /// An out-of-stock product says «под заказ» IN THE MESSAGE, not only on the
  /// screen: whoever answers needs to know she already knows, or the reply is
  /// "sorry, we don't have it" and the sale is lost to a misunderstanding.
  String _orderMessage(L10n l, String item, {required bool inStock}) =>
      l.t(inStock ? 'shop_wa_item' : 'shop_wa_backorder', {'item': item});
}

/// «Подходит детям 18–84 мес.» — the consumer side of frame 08a's age band.
///
/// Months, because months are what the operator typed and what the panel
/// shows; converting to years would round a band somebody set deliberately.
/// Null when no band is set, and the row then shows nothing rather than «не
/// указан», which is panel vocabulary for an operator's unfinished work.
String? _ageBandLabel(L10n l, CatalogueProduct p) {
  final lo = p.ageMinMonths, hi = p.ageMaxMonths;
  if (lo != null && hi != null) return l.t('shop_age_band', {'from': lo, 'to': hi});
  if (lo != null) return l.t('shop_age_from', {'from': lo});
  if (hi != null) return l.t('shop_age_to', {'to': hi});
  return null;
}

/// How old the prices on this screen are.
///
/// Nothing at all when the catalogue is live — a banner on every visit trains
/// people to ignore banners, and there is nothing to warn about.
/// True only when the «Выгода» / «отдельно» comparison is both SHOWN and partly
/// built from a compile-time price. See [CoursePrices.comparisonIsApproximate].
bool _comparisonIsGuessed(ShopCatalogue c) {
  final p = coursePricesFrom(c);
  return p.savingIsReal && p.comparisonIsApproximate;
}

class _FreshnessNote extends StatelessWidget {
  final ShopCatalogue catalogue;
  const _FreshnessNote({required this.catalogue});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final at = catalogue.fetchedAt;

    final String text;
    if (catalogue.isEmpty) {
      text = l.t('shop_prices_approx');
    } else if (catalogue.fromCache && at != null) {
      text = l.t('shop_prices_cached', {'date': _dmy(at)});
    } else if (_comparisonIsGuessed(catalogue)) {
      // The комплект is live but a part is not, so the struck-through
      // «отдельно» figure and the «Выгода» beside it are partly built from a
      // price nobody confirmed. The set's own price is fine, which is why this
      // note does not suppress the card — it is about the comparison.
      //
      // Gated on that comparison actually being DRAWN. Warning whenever a part
      // is missing would fire on a catalogue that simply does not sell one,
      // and «a warning on every visit trains people to ignore warnings» is a
      // rule this screen already keeps.
      text = l.t('shop_prices_approx');
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Ds.pastelButter,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 17, color: Ds.amberText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.4, color: Ds.text)),
          ),
        ],
      ),
    );
  }
}

/// dd.MM.yyyy — how a date is written in Kazakhstan, and unambiguous in all
/// three of this app's languages.
String _dmy(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}';
}

/// The комплект, and why it is the one to buy: it costs less than its parts.
class _BundleHero extends StatelessWidget {
  final String name;
  final String what;
  final CoursePrices prices;

  /// Null when the catalogue does not carry the set — then nothing is claimed.
  final bool? inStock;
  final VoidCallback? onOrder;

  const _BundleHero({
    required this.name,
    required this.what,
    required this.prices,
    this.inStock,
    this.onOrder,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final outOfStock = inStock == false;
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(what,
              style: const TextStyle(color: Palette.textDim, height: 1.4)),
          const SizedBox(height: 14),
          // Wrap, not Row. Two tenge figures side by side — one at 28pt —
          // overflowed a 390 dp phone by 36 px, and a price that runs off the
          // edge is the worst thing on the screen to lose.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            runSpacing: 2,
            children: [
              Text(formatTenge(prices.bundleMinor),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800)),
              // Only while the set really is cheaper. An operator may price it
              // above its parts, and a struck-through number LOWER than the one
              // beside it reads as a con.
              if (prices.savingIsReal)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    formatTenge(prices.separatelyMinor),
                    style: const TextStyle(
                      fontSize: 15,
                      color: Palette.textDim,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
            ],
          ),
          if (prices.savingIsReal) ...[
            const SizedBox(height: 6),
            _Chip(
              text: l.t('shop_saving',
                  {'amount': formatTenge(prices.savingMinor)}),
              bg: Ds.pastelMint,
              fg: Ds.mintText,
            ),
          ],
          if (outOfStock) ...[
            const SizedBox(height: 6),
            _Chip(
              text: l.t('shop_out_of_stock'),
              bg: Ds.pastelButter,
              fg: Ds.amberText,
            ),
          ],
          if (onOrder != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: DsShape.minTapTarget,
              child: FilledButton(
                onPressed: onOrder,
                child: Text(
                    l.t(outOfStock ? 'shop_order_backorder' : 'shop_order_bundle'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final String name;
  final String what;
  final String price;

  /// Null when there is no catalogue to ask — the constants path.
  final bool? inStock;

  /// Why this row is where it is. Null on the constants path, where the answer
  /// is "the heuristic", and the section already prints that above.
  final StageMatch? match;

  /// «Подходит детям 18–84 мес.», when an operator set a band.
  final String? ageBand;

  final VoidCallback? onOrder;

  const _ProductRow({
    required this.name,
    required this.what,
    required this.price,
    this.inStock,
    this.match,
    this.ageBand,
    this.onOrder,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final outOfStock = inStock == false;

    // Why she is being shown this, stated per product rather than as one
    // unexplained ordering. Only for a match an operator actually authored:
    // «untagged» and «notForYou» say nothing, because the honest line for them
    // is the section's own subtitle.
    final matchLabel = switch (match) {
      StageMatch.stage => l.t('shop_match_stage'),
      StageMatch.ageBand => l.t('shop_match_age'),
      _ => null,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Text(price,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          if (what.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(what,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.4, color: Palette.textDim)),
          ],
          if (matchLabel != null || ageBand != null || outOfStock) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (matchLabel != null)
                  _Chip(text: matchLabel, bg: Ds.pastelMint, fg: Ds.mintText),
                if (ageBand != null)
                  _Chip(text: ageBand!, bg: Ds.pastelSky, fg: Ds.blueText),
                if (outOfStock)
                  _Chip(
                      text: l.t('shop_out_of_stock'),
                      bg: Ds.pastelButter,
                      fg: Ds.amberText),
              ],
            ),
          ],
          if (onOrder != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: DsShape.minTapTarget,
              child: OutlinedButton(
                onPressed: onOrder,
                // «Заказать комплект» on a watch row was wrong copy: this
                // button orders THIS product, and the one that orders the set
                // is the filled one in the hero above.
                child: Text(l.t(
                    outOfStock ? 'shop_order_backorder' : 'shop_order_item')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small pill. Colour carries no meaning on its own here — every chip also
/// says what it is in words, because a colour is not readable.
class _Chip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Chip({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
      );
}

/// «плашка про WhatsApp» — how buying actually works here.
class _WhatsAppNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Ds.pastelButter,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.chat_bubble_outline_rounded,
              size: 19, color: Ds.amberText),
          const SizedBox(width: 12),
          Expanded(
            child: Text(l.t('shop_wa_note'),
                style: const TextStyle(
                    fontSize: 13, height: 1.45, color: Ds.text)),
          ),
        ],
      ),
    );
  }
}
