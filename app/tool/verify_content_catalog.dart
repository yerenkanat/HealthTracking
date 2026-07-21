/// Validate the authored content catalogue.
/// `dart run tool/verify_content_catalog.dart`
///
/// The catalogue is edited by hand, so the mistakes are human ones: a stage
/// missed, a translation left out, a price typed in tenge instead of tiyn, the
/// same id pasted twice. The app degrades quietly when content is wrong — a
/// card just doesn't appear — which is exactly why it needs checking here
/// instead.
///
/// With no `assets/content/catalog.json` this passes and says so: shipping the
/// seeded catalogue is a valid state until real content exists.
library;

import 'dart:convert';
import 'dart:io';

import '../lib/domain/timeline_content.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

/// A product priced under this is almost certainly major units by mistake —
/// 9900 meaning 9 900 ₸ rather than 99 ₸. Cheap goods exist, but not at 99 ₸.
const _suspiciouslyCheapMinor = 10000; // 100 ₸

void main() {
  final file = File.fromUri(Platform.script.resolve('../assets/content/catalog.json'));

  if (!file.existsSync()) {
    print('No assets/content/catalog.json — the app ships the seeded demo '
        'catalogue. Create one with:');
    print('  dart run tool/export_catalog_template.dart');
    print('\n1 passed, 0 failed');
    exit(0);
  }

  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } catch (e) {
    print('FAIL  the catalogue is not valid JSON: $e');
    print('\n0 passed, 1 failed');
    exit(1);
  }

  _chk('the catalogue is a JSON object', decoded is Map);
  if (decoded is! Map) {
    print('\n$_pass passed, $_fail failed');
    exit(1);
  }
  final rawKeys = decoded.keys.map((k) => '$k').toList();

  // Unrecognised keys are dropped silently on load, so their content would
  // never appear and nobody would be told why.
  final badKeys = [for (final k in rawKeys) if (TimelineStage.fromKey(k) == null) k];
  if (badKeys.isNotEmpty) {
    print('  Unusable stage keys (expected w1..w40 or m0..m60): ${badKeys.join(', ')}');
  }
  _chk('every stage key is one the app can resolve (${badKeys.length} bad)', badKeys.isEmpty);

  final catalog = ContentCatalog.fromJson(decoded.cast<String, dynamic>());

  // Coverage is reported rather than demanded: publishing week by week is a
  // normal way to work, and a half-filled catalogue should not fail the build.
  final missing = catalog.missingStages();
  if (missing.isNotEmpty) {
    final shown = missing.take(12).map((s) => s.key).join(', ');
    print('  ${missing.length} stage(s) have no content yet: $shown'
        '${missing.length > 12 ? ', …' : ''}');
  }
  _chk('the catalogue has content for at least one stage', catalog.byStage.isNotEmpty);

  final ids = <String, String>{}; // id → first stage it appeared in
  final dupes = <String>[];
  final blankText = <String>[];
  final missingLocale = <String>[];
  final badProduct = <String>[];
  final pricedLesson = <String>[];
  final badUrl = <String>[];
  final badShare = <String>[];
  var items = 0, linked = 0;

  // Iterate what was AUTHORED, not what is displayed.
  //
  // itemsFor() also returns items shared into a stage from elsewhere, so
  // walking it would count a lesson covering fourteen weeks fourteen times and
  // report thirteen of them as duplicate ids — a failure describing the exact
  // reuse the catalogue is supposed to support. Coverage still goes through
  // itemsFor above, where borrowing SHOULD count.
  for (final entry in catalog.byStage.entries) {
    for (final item in entry.value) {
      items++;
      final where = '${entry.key}/${item.id}';

      if (ids.containsKey(item.id)) {
        dupes.add('$where (also ${ids[item.id]})');
      } else {
        ids[item.id] = entry.key;
      }

      // A stage an item claims to also serve must be one the app can resolve;
      // a typo attaches it to nothing and the author sees it published with no
      // way to tell it never appears anywhere.
      for (final s in item.alsoStages) {
        if (TimelineStage.fromKey(s) == null) badShare.add('$where → "$s"');
      }

      if (item.title('ru').trim().isEmpty) blankText.add('$where title');
      if (item.summary('ru').trim().isEmpty) blankText.add('$where summary');

      // Falling back is deliberate at runtime, but a missing translation is
      // still something the author wants to know about before release.
      for (final loc in ['ru', 'kk', 'en']) {
        if ((item.title.byLocale[loc] ?? '').trim().isEmpty) {
          missingLocale.add('$where title[$loc]');
        }
      }

      if (item.isProduct) {
        final p = item.priceMinor;
        if (p == null || item.currency == null || p <= 0) {
          badProduct.add('$where has no usable price');
        } else if (p < _suspiciouslyCheapMinor) {
          badProduct.add('$where priced at $p minor units — major units by mistake?');
        }
      }
      if (item.isLesson && item.priceMinor != null) pricedLesson.add(where);

      if (item.hasLink) {
        linked++;
        final uri = Uri.tryParse(item.url);
        if (uri == null || !uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
          badUrl.add('$where → ${item.url}');
        }
      }
    }
  }

  for (final (label, list) in [
    ('duplicate ids', dupes),
    ('blank Russian text', blankText),
    ('products without a usable price', badProduct),
    ('lessons carrying a price', pricedLesson),
    ('links that are not http(s)', badUrl),
    ('shared stage keys the app cannot resolve', badShare),
  ]) {
    if (list.isNotEmpty) {
      print('  $label:');
      for (final e in list.take(10)) {
        print('    $e');
      }
      if (list.length > 10) print('    … and ${list.length - 10} more');
    }
  }

  _chk('every content id is unique (${dupes.length} duplicated)', dupes.isEmpty);
  _chk('nothing is missing its Russian text (${blankText.length} blank)', blankText.isEmpty);
  _chk('every product has a plausible price (${badProduct.length} suspect)', badProduct.isEmpty);
  _chk('no lesson carries a price (${pricedLesson.length} do)', pricedLesson.isEmpty);
  _chk('every link is http(s) (${badUrl.length} are not)', badUrl.isEmpty);
  _chk('every shared stage key resolves (${badShare.length} do not)', badShare.isEmpty);

  // Coverage counts a stage served only by a shared item, so this reports the
  // reuse separately — otherwise "101/101 covered" hides whether that came
  // from 364 items or from 30 items stretched across the whole timeline.
  final shared = [
    for (final list in catalog.byStage.values)
      for (final i in list)
        if (i.alsoStages.isNotEmpty) i
  ];
  if (shared.isNotEmpty) {
    final appearances = shared.fold<int>(0, (n, i) => n + i.alsoStages.length);
    print('  ${shared.length} item(s) shared across other stages '
        '($appearances extra appearance(s))');
  }

  // Reported, not enforced: translations and URLs arrive over time, and
  // failing on them would stop anyone committing work in progress.
  if (missingLocale.isNotEmpty) {
    print('  ${missingLocale.length} field(s) not yet translated — these fall back at runtime');
  }
  print('  $items item(s), $linked linked, ${items - linked} awaiting a URL');

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
