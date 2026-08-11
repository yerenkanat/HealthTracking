/// The last good shop catalogue, kept on the phone.
///
/// The shop is the one screen where being offline changes what the app may
/// honestly claim. Prices come from a back office now, so a cached 39 000 ₸ is
/// a price that WAS true — the screen shows it with the date it was fetched
/// rather than presenting it as current, and shows the compile-time constants
/// as approximate when there is nothing cached at all.
///
/// shared_preferences, like every other durable thing in this app, so there is
/// no second persistence mechanism to reason about.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Key under which the last good `/shop/products` response is cached.
const shopCatalogueCacheKey = 'shop_catalogue_json';

class PrefsShopCatalogueCache implements JsonCache {
  const PrefsShopCatalogueCache();

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(shopCatalogueCacheKey);
  }

  @override
  Future<void> write(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(shopCatalogueCacheKey, json);
  }
}
