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

  /// What was loaded locally at startup. Kept so a partly-populated API
  /// response can be layered over it rather than replacing it — see [adopt].
  final ContentCatalog _baseline;

  ContentStore(super.initial, {this.source = CatalogSource.demo})
      : _baseline = initial;

  /// Layer a newer catalogue over the local one, stage by stage.
  ///
  /// The backend only returns stages someone has actually published — two of a
  /// hundred, early on. Replacing outright would leave a woman at week 30
  /// staring at an empty shelf that would have had content offline, so the
  /// local catalogue fills every gap the API does not cover.
  ///
  /// A consequence worth naming: clearing a stage in the back-office restores
  /// the bundled entry rather than showing nothing. The wire format cannot
  /// express "deliberately empty" — an empty list is indistinguishable from an
  /// unpublished stage — and of the two readings, falling back is the one that
  /// never leaves a screen blank.
  void adopt(ContentCatalog next, CatalogSource from) {
    if (next.byStage.isEmpty) return;
    source = from;
    value = ContentCatalog({..._baseline.byStage, ...next.byStage});
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
