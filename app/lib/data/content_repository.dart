/// Where timeline content comes from.
///
/// Order of preference:
///   1. `assets/content/catalog.json` — the authored catalogue. Edit that file
///      to publish real lessons and products; no code change is needed.
///   2. the seeded demo catalogue, when the asset is absent or unreadable.
///
/// Later a third source slots in ahead of both: the backend. Keeping the load
/// behind this one class is what makes that a small change — [loadCatalog] is
/// the only thing the app calls.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/timeline_content.dart';
import 'demo_content.dart';

/// Where the authored catalogue lives, relative to the app bundle.
const contentCatalogAsset = 'assets/content/catalog.json';

/// How the catalogue currently in use was obtained — surfaced so a build can
/// say plainly whether it is showing real content or placeholders.
enum CatalogSource { asset, demo }

class LoadedCatalog {
  final ContentCatalog catalog;
  final CatalogSource source;

  /// Why the asset was not used, when it wasn't. Null on success.
  final String? fallbackReason;

  const LoadedCatalog(this.catalog, this.source, {this.fallbackReason});
}

/// Read the authored catalogue, falling back to the demo one.
///
/// A missing or malformed asset must never take the app down — content is not
/// worth a crash — so every failure degrades to the seeded catalogue and
/// records why. Run `dart run tool/verify_content_catalog.dart` to find out
/// before shipping; this is the last resort, not the check.
Future<LoadedCatalog> loadCatalog() async {
  String raw;
  try {
    raw = await rootBundle.loadString(contentCatalogAsset);
  } catch (_) {
    return LoadedCatalog(demoContentCatalog(), CatalogSource.demo,
        fallbackReason: 'no $contentCatalogAsset in the bundle');
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return LoadedCatalog(demoContentCatalog(), CatalogSource.demo,
          fallbackReason: 'the catalogue is not a JSON object');
    }
    final catalog = ContentCatalog.fromJson(decoded.cast<String, dynamic>());
    if (catalog.byStage.isEmpty) {
      // An empty catalogue is almost certainly a mistake — every stage key was
      // unrecognised, or the file is a stub. Showing nothing at all would look
      // like the feature is broken.
      return LoadedCatalog(demoContentCatalog(), CatalogSource.demo,
          fallbackReason: 'the catalogue contained no usable stages');
    }
    return LoadedCatalog(catalog, CatalogSource.asset);
  } catch (e) {
    return LoadedCatalog(demoContentCatalog(), CatalogSource.demo,
        fallbackReason: 'the catalogue could not be parsed: $e');
  }
}
