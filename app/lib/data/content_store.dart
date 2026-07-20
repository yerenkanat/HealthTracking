/// Holds the timeline catalogue currently in use, and lets the tree rebuild
/// when a fresher one arrives.
///
/// Startup loads locally so first paint never waits on the network; the API
/// refresh lands a moment later and swaps in through this notifier. Without it
/// the app would show whatever it had at launch until the next cold start,
/// which means content published in the back-office wouldn't appear for hours.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/timeline_content.dart';
import 'content_repository.dart';

class ContentStore extends ValueNotifier<ContentCatalog> {
  CatalogSource source;
  ContentStore(super.initial, {this.source = CatalogSource.demo});

  /// Swap in a newer catalogue. Ignores an empty one: an API that answers with
  /// nothing should not blank a shelf that currently has content.
  void adopt(ContentCatalog next, CatalogSource from) {
    if (next.byStage.isEmpty) return;
    source = from;
    value = next;
  }
}

/// [ContentCache] over shared_preferences — the same store the rest of the
/// app's durable state uses, so there is no second persistence mechanism.
class PrefsContentCache implements ContentCache {
  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(contentCacheKey);
  }

  @override
  Future<void> write(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(contentCacheKey, json);
  }
}
