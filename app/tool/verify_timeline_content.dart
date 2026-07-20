/// Pure-Dart verification of the timeline content catalogue.
/// `dart run tool/verify_timeline_content.dart`
library;

import 'dart:convert';
import 'dart:io';
import '../lib/data/demo_content.dart';
import '../lib/domain/timeline_content.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- Stages ----
  _chk('the timeline is 40 weeks plus 61 months', allTimelineStages().length == 101);
  _chk('a pregnancy week keys as wN', TimelineStage.pregnancyWeek(20).key == 'w20');
  _chk('a child month keys as mN', TimelineStage.childMonth(4).key == 'm4');
  _chk('a key round-trips', TimelineStage.fromKey('w20') == TimelineStage.pregnancyWeek(20));
  _chk('month 0 is a real stage (a newborn)', TimelineStage.fromKey('m0') != null);

  // Week 20 and month 20 are different places on the timeline.
  _chk('week N and month N are distinct',
      TimelineStage.pregnancyWeek(20) != TimelineStage.childMonth(20));

  // Out-of-range input clamps rather than creating an unreachable stage.
  _chk('week 0 clamps to 1', TimelineStage.pregnancyWeek(0).index == minPregnancyWeek);
  _chk('week 99 clamps to 40', TimelineStage.pregnancyWeek(99).index == maxPregnancyWeek);
  _chk('month 999 clamps to 60', TimelineStage.childMonth(999).index == maxChildMonth);

  // Malformed keys are refused, not guessed at.
  for (final bad in ['', 'x', 'w', 'w0', 'w41', 'm-1', 'm61', 'week20', '20']) {
    _chk('key "$bad" is refused', TimelineStage.fromKey(bad) == null);
  }

  // ---- Which stage a family is at ----
  _chk('pregnancy wins when both apply',
      currentStage(gestationWeek: 20, childAgeMonths: 30) == TimelineStage.pregnancyWeek(20));
  _chk('a child month is used when not pregnant',
      currentStage(gestationWeek: null, childAgeMonths: 4) == TimelineStage.childMonth(4));
  _chk('a newborn maps to month 0',
      currentStage(gestationWeek: null, childAgeMonths: 0) == TimelineStage.childMonth(0));
  _chk('nothing tracked means no stage',
      currentStage(gestationWeek: null, childAgeMonths: null) == null);
  // Past five years the timeline ends; repeating month 60 forever would be
  // worse than showing nothing.
  _chk('past five years there is no stage',
      currentStage(gestationWeek: null, childAgeMonths: 61) == null);

  // ---- The seeded catalogue covers the whole timeline ----
  final cat = demoContentCatalog();
  _chk('every stage has content', cat.missingStages().isEmpty);
  _chk('every pregnancy week has a lesson', () {
    for (var w = minPregnancyWeek; w <= maxPregnancyWeek; w++) {
      if (cat.lessonsFor(TimelineStage.pregnancyWeek(w)).isEmpty) return false;
    }
    return true;
  }());
  _chk('every pregnancy week has a product', () {
    for (var w = minPregnancyWeek; w <= maxPregnancyWeek; w++) {
      if (cat.productsFor(TimelineStage.pregnancyWeek(w)).isEmpty) return false;
    }
    return true;
  }());
  _chk('every child month has a lesson and a product', () {
    for (var m = minChildMonth; m <= maxChildMonth; m++) {
      final s = TimelineStage.childMonth(m);
      if (cat.lessonsFor(s).isEmpty || cat.productsFor(s).isEmpty) return false;
    }
    return true;
  }());

  // Ids must be unique, or a list with keys would misbehave and analytics
  // would merge two different items.
  final ids = <String>{};
  var dupes = 0;
  for (final s in allTimelineStages()) {
    for (final i in cat.itemsFor(s)) {
      if (!ids.add(i.id)) dupes++;
    }
  }
  _chk('every content id is unique ($dupes duplicates)', dupes == 0);

  // Every item is presentable in all three languages.
  var blank = 0;
  for (final s in allTimelineStages()) {
    for (final i in cat.itemsFor(s)) {
      for (final loc in ['ru', 'kk', 'en']) {
        if (i.title(loc).trim().isEmpty || i.summary(loc).trim().isEmpty) blank++;
      }
    }
  }
  _chk('every item has a title and summary in ru/kk/en ($blank blank)', blank == 0);

  // Products are priced; lessons are not pretending to be.
  var unpriced = 0, pricedLesson = 0;
  for (final s in allTimelineStages()) {
    for (final i in cat.itemsFor(s)) {
      if (i.isProduct && (i.priceMinor == null || i.currency == null)) unpriced++;
      if (i.isLesson && i.priceMinor != null) pricedLesson++;
    }
  }
  _chk('every product carries a price and currency', unpriced == 0);
  _chk('no lesson carries a price', pricedLesson == 0);

  // ---- Round-trip through the backend's shape ----
  final back = ContentCatalog.fromJson(
      (jsonDecode(jsonEncode(cat.toJson())) as Map).cast<String, dynamic>());
  _chk('the catalogue round-trips', back.missingStages().isEmpty);
  _chk('a round-tripped item keeps its price',
      back.productsFor(TimelineStage.childMonth(4)).first.priceMinor ==
          cat.productsFor(TimelineStage.childMonth(4)).first.priceMinor);
  _chk('a round-tripped item keeps all three languages',
      back.lessonsFor(TimelineStage.pregnancyWeek(20)).first.title('kk') ==
          cat.lessonsFor(TimelineStage.pregnancyWeek(20)).first.title('kk'));

  // Content filed under a stage that cannot exist is dropped, so bad authoring
  // fails visibly rather than being kept where nothing can ever look it up.
  final withJunk = ContentCatalog.fromJson({
    'w20': [
      {'id': 'ok', 'kind': 'lesson', 'title': {'ru': 'Тест'}, 'summary': {'ru': 'Тест'}}
    ],
    'w99': [
      {'id': 'bad', 'kind': 'lesson', 'title': {'ru': 'Нет'}, 'summary': {'ru': 'Нет'}}
    ],
    'nonsense': [
      {'id': 'worse', 'kind': 'lesson', 'title': {'ru': 'Нет'}, 'summary': {'ru': 'Нет'}}
    ],
  });
  _chk('content under an impossible stage is dropped', withJunk.byStage.length == 1);
  _chk('valid content beside it survives',
      withJunk.itemsFor(TimelineStage.pregnancyWeek(20)).single.id == 'ok');

  // A partially translated item still shows something rather than a blank card.
  final partial = ContentItem(
    id: 'p',
    kind: ContentKind.lesson,
    title: const LocalizedText({'ru': 'Только по-русски'}),
    summary: const LocalizedText({}),
  );
  _chk('a missing translation falls back', partial.title('kk') == 'Только по-русски');
  _chk('a wholly missing text is empty, not an error', partial.summary('ru') == '');

  // ---- Price formatting ----
  const priced = ContentItem(
    id: 'x',
    kind: ContentKind.product,
    title: LocalizedText({'ru': 'X'}),
    summary: LocalizedText({'ru': 'X'}),
    priceMinor: 1290000,
    currency: 'KZT',
  );
  // NON-BREAKING spaces ( ), written as escapes so the intent is visible
  // in the source: a price must never wrap between "12" and "900", nor between
  // the amount and its symbol.
  _chk('a price is grouped and carries its symbol',
      formatPrice(priced) == '12 900 ₸');
  _chk('the grouping uses non-breaking spaces, never ordinary ones',
      !formatPrice(priced).contains(' '));
  _chk('a lesson has no price string',
      formatPrice(const ContentItem(
            id: 'y',
            kind: ContentKind.lesson,
            title: LocalizedText({'ru': 'Y'}),
            summary: LocalizedText({'ru': 'Y'}),
          )) ==
          '');

  // An unlinked item is offered without an action rather than a dead link.
  _chk('an item with no url reports no link', !priced.hasLink);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
