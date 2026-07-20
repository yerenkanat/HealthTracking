/// The content loader's fallback chain.
///
/// This decides what a user actually sees, and every step down is a
/// degradation rather than a failure: a missing backend, a corrupt cache or an
/// absent asset must each fall through quietly rather than blanking the shelf
/// or crashing.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/content_repository.dart';
import 'package:fcs_app/data/content_store.dart';
import 'package:fcs_app/domain/timeline_content.dart';

class _MemCache implements ContentCache {
  String? stored;
  bool failReads = false;
  _MemCache([this.stored]);

  @override
  Future<String?> read() async {
    if (failReads) throw StateError('cache unreadable');
    return stored;
  }

  @override
  Future<void> write(String json) async => stored = json;
}

String catalogJson(String stage, String id, {bool envelope = false}) {
  final body = '{"$stage":[{"id":"$id","kind":"lesson",'
      '"title":{"ru":"Урок"},"summary":{"ru":"Описание"}}]}';
  return envelope ? '{"stages":$body}' : body;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Make the bundled asset absent, so tests exercise the lower rungs. Without
  /// this the real catalog.json answers and the demo path is never reached.
  void withoutAsset() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null));
  }

  group('loading without a network', () {
    test('a cached response is preferred over the bundled asset', () async {
      final cache = _MemCache(catalogJson('w12', 'cached-1'));
      final loaded = await loadCatalogFast(cache: cache);
      expect(loaded.source, CatalogSource.cache);
      expect(loaded.catalog.itemsFor(TimelineStage.pregnancyWeek(12)).single.id, 'cached-1');
    });

    test('the API envelope and a bare stage map are both accepted', () async {
      // The backend answers {"stages": {...}}; the asset file stores the bare
      // map. One parser has to take both or the cache would reject its own
      // saved bytes on the next launch.
      final enveloped = _MemCache(catalogJson('w12', 'x', envelope: true));
      expect((await loadCatalogFast(cache: enveloped)).source, CatalogSource.cache);
      final bare = _MemCache(catalogJson('w12', 'x'));
      expect((await loadCatalogFast(cache: bare)).source, CatalogSource.cache);
    });

    test('a corrupt cache falls through instead of throwing', () async {
      withoutAsset();
      final loaded = await loadCatalogFast(cache: _MemCache('{not json'));
      expect(loaded.source, CatalogSource.demo);
      expect(loaded.catalog.byStage, isNotEmpty);
    });

    test('an unreadable cache falls through instead of throwing', () async {
      withoutAsset();
      final cache = _MemCache('{}')..failReads = true;
      expect((await loadCatalogFast(cache: cache)).source, CatalogSource.demo);
    });

    test('a cache holding only unusable stages is ignored', () async {
      // Every key unrecognised means the file is junk or a stub. Showing an
      // empty shelf would look like the feature is broken.
      withoutAsset();
      final loaded = await loadCatalogFast(cache: _MemCache('{"w99":[],"nonsense":[]}'));
      expect(loaded.source, CatalogSource.demo);
    });

    test('with nothing at all the seeded catalogue still covers the timeline', () async {
      withoutAsset();
      final loaded = await loadCatalogFast();
      expect(loaded.source, CatalogSource.demo);
      expect(loaded.catalog.missingStages(), isEmpty);
      expect(loaded.fallbackReason, isNotNull); // and it says why
    });

    test('the bundled asset is used when there is no cache', () async {
      // rootBundle doesn't serve real asset files under flutter_test, so the
      // asset rung has to be mocked to be exercised at all.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        if (key != contentCatalogAsset) return null;
        final bytes = utf8.encode(catalogJson('w30', 'from-asset'));
        return ByteData.view(Uint8List.fromList(bytes).buffer);
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null));
      // rootBundle is a CachingAssetBundle and caches the FUTURE, including a
      // failed one — the earlier tests that made the asset absent would
      // otherwise poison this lookup.
      rootBundle.clear();
      addTearDown(rootBundle.clear);

      final loaded = await loadCatalogFast(cache: _MemCache());
      expect(loaded.source, CatalogSource.asset);
      expect(loaded.catalog.itemsFor(TimelineStage.pregnancyWeek(30)).single.id, 'from-asset');
    });
  });

  group('the store', () {
    test('adopting a fresher catalogue notifies listeners', () {
      final store = ContentStore(const ContentCatalog({}));
      var notified = 0;
      store.addListener(() => notified++);
      store.adopt(
        const ContentCatalog({'w12': [
          ContentItem(
            id: 'a', kind: ContentKind.lesson,
            title: LocalizedText({'ru': 'Урок'}), summary: LocalizedText({'ru': 'О'}),
          ),
        ]}),
        CatalogSource.api,
      );
      expect(notified, 1);
      expect(store.source, CatalogSource.api);
      expect(store.value.byStage, isNotEmpty);
    });

    test('an empty catalogue never replaces one that has content', () {
      // A backend answering with nothing must not blank a working shelf.
      const populated = ContentCatalog({'w12': [
        ContentItem(
          id: 'a', kind: ContentKind.lesson,
          title: LocalizedText({'ru': 'Урок'}), summary: LocalizedText({'ru': 'О'}),
        ),
      ]});
      final store = ContentStore(populated, source: CatalogSource.asset);
      var notified = 0;
      store.addListener(() => notified++);
      store.adopt(const ContentCatalog({}), CatalogSource.api);
      expect(notified, 0);
      expect(store.source, CatalogSource.asset);
      expect(store.value.byStage, isNotEmpty);
    });
  });
}
