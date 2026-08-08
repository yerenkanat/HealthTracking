/// Screen 41 — «Магазин».
///
/// «герой комплекта → секция «Для вашего этапа» с товарами → плашка про
/// WhatsApp → «Заказать комплект».»
///
/// The whole offer in one place, inside the app. Until now the only way to buy
/// anything was the landing page in a browser, which a customer who already has
/// the app is unlikely to be looking at.
///
/// «Для вашего этапа» is derived from what the app knows — whether she is
/// expecting, and how old her children are — not from a stage field on a
/// product, which does not exist. The reason is printed with the suggestion so
/// it never reads as an unexplained upsell, and every ordering rule is one
/// sentence long and defensible out loud. She is being asked for 39 000 ₸.
library;

import 'package:flutter/material.dart';

import '../../domain/course_prices.dart';
import '../../domain/my_order.dart' show formatTenge;
import '../../domain/shop_stage.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../ds_widgets.dart';
import '../theme.dart';

class ShopScreen extends StatelessWidget {
  final bool pregnant;
  final List<int> childAgesMonths;

  /// Opens WhatsApp with the given message. Null when no number is configured,
  /// and every buy button then disappears rather than opening nothing.
  final void Function(String message)? onOrder;

  const ShopScreen({
    super.key,
    required this.pregnant,
    required this.childAgesMonths,
    this.onOrder,
  });

  int _priceOf(ShopItem item) => switch (item) {
        ShopItem.watch => coursePrices.watchMinor,
        ShopItem.tracker => coursePrices.trackerMinor,
        ShopItem.bundle => coursePrices.bundleMinor,
      };

  String _nameOf(L10n l, ShopItem item) => switch (item) {
        ShopItem.watch => l.t('shop_item_watch'),
        ShopItem.tracker => l.t('shop_item_tracker'),
        ShopItem.bundle => l.t('crs_bundle_name'),
      };

  String _whatOf(L10n l, ShopItem item) => switch (item) {
        ShopItem.watch => l.t('shop_item_watch_what'),
        ShopItem.tracker => l.t('shop_item_tracker_what'),
        ShopItem.bundle => l.t('crs_bundle_what'),
      };

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final suggestion = stageSuggestion(
      pregnant: pregnant,
      childAgesMonths: childAgesMonths,
    );

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(title: Text(l.t('shop_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _BundleHero(
            onOrder: onOrder == null
                ? null
                : () => onOrder!(
                      l.t('shop_wa_item', {'item': l.t('crs_bundle_name')}),
                    ),
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

          for (final item in suggestion.items)
            // The bundle is already the hero above; repeating it in the list
            // would be the same product twice on one screen.
            if (item != ShopItem.bundle)
              _ProductRow(
                name: _nameOf(l, item),
                what: _whatOf(l, item),
                price: formatTenge(_priceOf(item)),
                onOrder: onOrder == null
                    ? null
                    : () => onOrder!(
                          l.t('shop_wa_item', {'item': _nameOf(l, item)}),
                        ),
              ),

          const SizedBox(height: 18),
          _WhatsAppNote(),
        ],
      ),
    );
  }
}

/// The комплект, and why it is the one to buy: it costs less than its parts.
class _BundleHero extends StatelessWidget {
  final VoidCallback? onOrder;
  const _BundleHero({this.onOrder});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('crs_bundle_name'),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(l.t('crs_bundle_what'),
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
              Text(formatTenge(coursePrices.bundleMinor),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800)),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  formatTenge(coursePrices.separatelyMinor),
                  style: const TextStyle(
                    fontSize: 15,
                    color: Palette.textDim,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Ds.pastelMint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              l.t('shop_saving',
                  {'amount': formatTenge(coursePrices.savingMinor)}),
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: Ds.mintText),
            ),
          ),
          if (onOrder != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: DsShape.minTapTarget,
              child: FilledButton(
                onPressed: onOrder,
                child: Text(l.t('shop_order_bundle'),
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
  final VoidCallback? onOrder;

  const _ProductRow({
    required this.name,
    required this.what,
    required this.price,
    this.onOrder,
  });

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: 4),
          Text(what,
              style: const TextStyle(
                  fontSize: 12.5, height: 1.4, color: Palette.textDim)),
          if (onOrder != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: DsShape.minTapTarget,
              child: OutlinedButton(
                onPressed: onOrder,
                child: Text(L10nScope.of(context).t('shop_order_bundle')),
              ),
            ),
          ],
        ],
      ),
    );
  }
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
