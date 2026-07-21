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

  // ---- Targeting by city and age ----
  // City and birth date are optional in the profile, so the rule that matters
  // most is what happens when they are missing: the baseline shelf must be
  // completely unaffected, and nothing we cannot honour may be shown.
  const plain = ContentItem(
    id: 'plain', kind: ContentKind.lesson,
    title: LocalizedText({'ru': 'Everyone'}), summary: LocalizedText({'ru': 'x'}),
  );
  const almatyOnly = ContentItem(
    id: 'almaty', kind: ContentKind.product,
    title: LocalizedText({'ru': 'Almaty'}), summary: LocalizedText({'ru': 'x'}),
    cities: ['Алматы'],
  );
  const over35 = ContentItem(
    id: 'over35', kind: ContentKind.lesson,
    title: LocalizedText({'ru': '35+'}), summary: LocalizedText({'ru': 'x'}),
    minAgeYears: 35,
  );
  const under30 = ContentItem(
    id: 'under30', kind: ContentKind.lesson,
    title: LocalizedText({'ru': '-30'}), summary: LocalizedText({'ru': 'x'}),
    maxAgeYears: 29,
  );
  const shelf = [plain, almatyOnly, over35, under30];

  _chk('an unconstrained item is for everyone', plain.isForEveryone);
  _chk('a city-bound item is not', !almatyOnly.isForEveryone);

  // An empty profile still gets the whole baseline shelf...
  final anon = itemsForViewer(shelf, ContentViewer.anonymous);
  _chk('an empty profile keeps every unconstrained item',
      anon.map((i) => i.id).join(',') == 'plain');
  // ...and is never shown something we cannot deliver.
  _chk('an unknown city hides a city-bound product',
      !suitsViewer(almatyOnly, ContentViewer.anonymous));
  _chk('an unknown age hides an age-bound lesson',
      !suitsViewer(over35, ContentViewer.anonymous));

  // City matching survives the ways a user might actually write the place.
  _chk('the Cyrillic spelling matches',
      suitsViewer(almatyOnly, const ContentViewer(city: 'Алматы')));
  _chk('the Latin spelling matches too',
      suitsViewer(almatyOnly, const ContentViewer(city: 'Almaty')));
  _chk('the old name matches too',
      suitsViewer(almatyOnly, const ContentViewer(city: 'Алма-Ата')));
  _chk('surrounding space and case do not matter',
      suitsViewer(almatyOnly, const ContentViewer(city: '  ALMATY ')));
  _chk('a different city does not match',
      !suitsViewer(almatyOnly, const ContentViewer(city: 'Астана')));
  // Astana was renamed and renamed back; a match must survive both names.
  _chk('a renamed city still matches',
      normalizeCity('Nur-Sultan') == normalizeCity('Астана'));
  // A spelling we do not know is a miss, never a wrong hit.
  _chk('an unknown city normalizes to itself', normalizeCity('Kokshetau') == 'kokshetau');
  _chk('an unknown city matches only itself',
      !suitsViewer(almatyOnly, const ContentViewer(city: 'Kokshetau')));

  // Age bounds are inclusive at both ends.
  _chk('exactly the minimum age qualifies',
      suitsViewer(over35, const ContentViewer(ageYears: 35)));
  _chk('a year under the minimum does not',
      !suitsViewer(over35, const ContentViewer(ageYears: 34)));
  _chk('exactly the maximum age qualifies',
      suitsViewer(under30, const ContentViewer(ageYears: 29)));
  _chk('a year over the maximum does not',
      !suitsViewer(under30, const ContentViewer(ageYears: 30)));

  // A full profile sees the baseline plus what it qualifies for, in order.
  final full = itemsForViewer(shelf, const ContentViewer(city: 'Almaty', ageYears: 36));
  _chk('a full profile gains the targeted items',
      full.map((i) => i.id).join(',') == 'plain,almaty,over35');

  // Constraints combine: both must hold, not either.
  const both = ContentItem(
    id: 'both', kind: ContentKind.product,
    title: LocalizedText({'ru': 'B'}), summary: LocalizedText({'ru': 'x'}),
    cities: ['Almaty'], minAgeYears: 35,
  );
  _chk('meeting only the city is not enough',
      !suitsViewer(both, const ContentViewer(city: 'Almaty', ageYears: 20)));
  _chk('meeting only the age is not enough',
      !suitsViewer(both, const ContentViewer(city: 'Астана', ageYears: 40)));
  _chk('meeting both is', suitsViewer(both, const ContentViewer(city: 'Almaty', ageYears: 40)));

  // Targeting has to survive the wire, or the back-office cannot set it.
  final wired =
      ContentItem.fromJson(jsonDecode(jsonEncode(both.toJson())) as Map<String, dynamic>);
  _chk('city targeting round-trips through JSON',
      wired.cities.length == 1 && normalizeCity(wired.cities.single) == 'алматы');
  _chk('age targeting round-trips through JSON', wired.minAgeYears == 35);
  _chk('an unconstrained item stays unconstrained through JSON',
      ContentItem.fromJson(jsonDecode(jsonEncode(plain.toJson())) as Map<String, dynamic>)
          .isForEveryone);
  // Junk in the cities list must not become a constraint nobody can satisfy.
  _chk('blank city entries are dropped',
      ContentItem.fromJson({'id': 'j', 'kind': 'lesson', 'cities': ['  ', '']}).isForEveryone);

  // ---- Where a lesson's video comes from ----
  // The lessons should feel like this app's, not like a third party's, so a
  // white-labelled host plays inline. YouTube deliberately does not: its terms
  // require its own player with its branding, and the penalty for hiding that
  // lands on the whole channel at once.
  ContentItem lessonWith(Object? video, {String url = ''}) => ContentItem.fromJson({
        'id': 'v', 'kind': 'lesson',
        'title': {'ru': 'Урок'}, 'summary': {'ru': 'О'},
        if (url.isNotEmpty) 'url': url,
        if (video != null) 'video': video,
      });

  _chk('an HLS lesson plays in our own player',
      lessonWith({'provider': 'hls', 'url': 'https://cdn.example/v.m3u8'}).playsInApp);
  _chk('an MP4 lesson plays in our own player',
      lessonWith({'provider': 'mp4', 'url': 'https://cdn.example/v.mp4'}).playsInApp);
  _chk('a YouTube lesson does NOT play inline',
      !lessonWith({'provider': 'youtube', 'url': 'https://youtu.be/abc'}).playsInApp);

  // A catalogue authored before the field existed still works.
  _chk('a bare .m3u8 url is recognised as inline-playable',
      lessonWith(null, url: 'https://cdn.example/v.m3u8').playsInApp);
  _chk('a bare youtube url falls back to opening externally',
      !lessonWith(null, url: 'https://www.youtube.com/watch?v=abc').playsInApp);
  _chk('a youtu.be short link is recognised too',
      VideoSource.guessProvider('https://youtu.be/abc') == VideoProvider.youtube);

  // The direction to be wrong in: an unidentifiable URL must not be streamed
  // into our player on the assumption that it is fine.
  _chk('an unrecognised url is treated as external, not inline',
      !lessonWith(null, url: 'https://example.com/watch/123').playsInApp);
  _chk('an unknown provider name falls back rather than trusting it',
      !lessonWith({'provider': 'vimeo-embed', 'url': 'https://example.com/x'}).playsInApp);

  _chk('a lesson with no link at all has no video', lessonWith(null).video == null);
  _chk('an empty video url yields no source',
      lessonWith({'provider': 'hls', 'url': '   '}).video == null);
  _chk('a product is never treated as a video', ContentItem.fromJson({
        'id': 'p', 'kind': 'product', 'title': {'ru': 'Т'}, 'summary': {'ru': 'О'},
        'url': 'https://shop.example/item',
      }).video == null);

  // Round-trips, so the back-office can set it and the app reads it back.
  final withVideo = lessonWith({
    'provider': 'hls', 'url': 'https://cdn.example/v.m3u8', 'posterUrl': 'https://cdn/p.jpg',
  });
  final rewired = ContentItem.fromJson(
      jsonDecode(jsonEncode(withVideo.toJson())) as Map<String, dynamic>);
  _chk('a video source round-trips through JSON',
      rewired.video?.provider == VideoProvider.hls && rewired.playsInApp);
  _chk('the poster survives the round trip',
      rewired.video?.posterUrl == 'https://cdn/p.jpg');

  // ---- One item serving several stages ----
  // Most guidance is not week-specific. Filed one stage at a time, a lesson
  // covering the second trimester meant fourteen copies with fourteen ids, and
  // fourteen places to edit when the video URL changed.
  {
    ContentItem shared(String id, {List<String> also = const []}) => ContentItem(
          id: id,
          kind: ContentKind.lesson,
          title: const LocalizedText({'ru': 'Питание'}),
          summary: const LocalizedText({'ru': 'Второй триместр'}),
          alsoStages: also,
        );

    final cat = ContentCatalog({
      'w14': [shared('nutrition', also: ['w15', 'w16'])],
      'w20': [shared('sleep')],
    });

    _chk('an item shows at the stage it is filed under',
        cat.itemsFor(TimelineStage.pregnancyWeek(14)).single.id == 'nutrition');
    _chk('and at every stage it is shared into',
        cat.itemsFor(TimelineStage.pregnancyWeek(15)).single.id == 'nutrition' &&
            cat.itemsFor(TimelineStage.pregnancyWeek(16)).single.id == 'nutrition');
    _chk('but not at stages it does not name',
        cat.itemsFor(TimelineStage.pregnancyWeek(17)).isEmpty);
    _chk('an item with no shares behaves exactly as before',
        cat.itemsFor(TimelineStage.pregnancyWeek(20)).single.id == 'sleep');

    // There is ONE copy. That is the whole point: editing it edits every
    // appearance, because every appearance is the same object.
    final atHome = cat.itemsFor(TimelineStage.pregnancyWeek(14)).single;
    final atShare = cat.itemsFor(TimelineStage.pregnancyWeek(15)).single;
    _chk('every appearance is the same item', identical(atHome, atShare));

    _chk('the authored map still holds it exactly once',
        cat.byStage.values.expand((v) => v).where((i) => i.id == 'nutrition').length == 1);
    _chk('the CMS can find where it lives', cat.homeStageOf('nutrition') == 'w14');
    _chk('an unknown id has no home', cat.homeStageOf('nope') == null);

    // Someone selecting a range that includes the item's own week has done
    // nothing wrong, and must not get it twice.
    final selfNaming = ContentCatalog({
      'w14': [shared('n', also: ['w14', 'w15'])],
    });
    _chk('an item naming its own stage appears once',
        selfNaming.itemsFor(TimelineStage.pregnancyWeek(14)).length == 1);

    // Two stages sharing the same id: it belongs to whoever files it, and is
    // never listed twice at one stage.
    final dupes = ContentCatalog({
      'w14': [shared('same', also: ['w16'])],
      'w15': [shared('same', also: ['w16'])],
    });
    _chk('a duplicated id is not listed twice at a shared stage',
        dupes.itemsFor(TimelineStage.pregnancyWeek(16)).length == 1);

    // Coverage has to count shared stages, or a week fully served by a shared
    // lesson still reads as a hole in the authoring dashboard.
    _chk('a stage covered only by a shared item counts as covered',
        cat.hasContentFor(TimelineStage.pregnancyWeek(15)));
    _chk('and does not appear in the missing list',
        !cat.missingStages().any((s) => s.key == 'w15'));
    _chk('a genuinely empty stage still appears in the missing list',
        cat.missingStages().any((s) => s.key == 'w17'));

    // A typo in the CMS must not invent a stage.
    final bad = ContentCatalog({
      'w14': [shared('x', also: ['w99', 'nonsense', ''])],
    });
    _chk('unknown stage keys are ignored',
        stagesForItem(bad.byStage['w14']!.single, 'w14').length == 1);

    // Round trip.
    final rt = ContentItem.fromJson(
        jsonDecode(jsonEncode(shared('r', also: ['w15', 'w16']).toJson())) as Map<String, dynamic>);
    _chk('shared stages survive JSON', rt.alsoStages.join(',') == 'w15,w16');
    _chk('an item with no shares writes no key',
        !shared('r').toJson().containsKey('alsoStages'));
    final legacy = ContentItem.fromJson({'id': 'old', 'kind': 'lesson'});
    _chk('a catalogue authored before this field still loads', legacy.alsoStages.isEmpty);
  }

  // ---- Authoring a range ----
  {
    _chk('a range covers both ends', stageRange('w20', 'w23').join(',') == 'w20,w21,w22,w23');
    _chk('a single-stage range is just that stage', stageRange('w20', 'w20').join(',') == 'w20');
    _chk('months work too', stageRange('m0', 'm2').join(',') == 'm0,m1,m2');
    // "weeks 20 to month 4" is a mistake; silently returning 40 weeks of
    // content assignments would bury it.
    _chk('a range across kinds is refused', stageRange('w20', 'm4').isEmpty);
    _chk('a reversed range is refused', stageRange('w23', 'w20').isEmpty);
    _chk('an unparseable range is refused', stageRange('nonsense', 'w20').isEmpty);
    _chk('a full pregnancy range is 40 weeks', stageRange('w1', 'w40').length == 40);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
