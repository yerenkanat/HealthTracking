/// Screen 27 — «Гиды», and the pure rules behind it.
///
/// The defect this covers is not a broken screen; it is a library nobody could
/// open. 364 published items were downloaded to every phone and exactly one
/// stage was ever rendered, and a woman with neither a due date nor a child
/// had no stage — so she could reach none of it. The first widget test below
/// is that exact person, driven from the real shell rather than by
/// constructing GuidesScreen, because constructing it is what a test would do
/// happily while nothing in the app pushed it.
///
/// L10nScope wraps MaterialApp, never `home:` — under `home:` it sits below the
/// Navigator and every PUSHED route falls back to English, which has made
/// working screens look broken on this project before.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/content/guides_screen.dart';
import 'package:fcs_app/ui/content/lesson_player_screen.dart';
import 'package:fcs_app/ui/calendar/labour_signs_screen.dart';
import 'package:fcs_app/ui/content/timeline_content_screen.dart';
import 'package:fcs_app/ui/emergency/emergency_rescue_screen.dart';
import 'package:fcs_app/ui/home_shell.dart';
import 'package:fcs_app/ui/theme.dart';

const l = L10n(AppLocale.ru);
final today = DateTime(2026, 8, 12);

ContentItem _lesson(
  String id,
  String title,
  String summary, {
  String? topic,
  List<String> alsoStages = const [],
}) =>
    ContentItem(
      id: id,
      kind: ContentKind.lesson,
      title: LocalizedText({'ru': title, 'kk': title, 'en': title}),
      summary: LocalizedText({'ru': summary, 'kk': summary, 'en': summary}),
      // HLS, so opening it lands on OUR player rather than the browser: a
      // widget test cannot drive url_launcher, and the point of the tap is
      // that something opens.
      videoSource: VideoSource(provider: VideoProvider.hls, url: 'https://cdn/$id.m3u8'),
      durationMin: 6,
      topic: topic,
      alsoStages: alsoStages,
    );

/// A catalogue that spans the whole timeline, the way the real one does.
///
/// `w14-nutrition` is the shape that made deduplication necessary: authored
/// once at week 14 and shared into thirteen more.
final catalog = ContentCatalog({
  'w14': [
    _lesson('w14-nutrition', 'Питание во втором триместре', 'Что есть каждый день.',
        alsoStages: stageRange('w15', 'w27')),
  ],
  'w20': [_lesson('w20-breathing', 'Дыхание в родах', 'Короткий урок про дыхание.')],
  'm4': [_lesson('m4-sleep', 'Сон малыша', 'Как укладывать в четыре месяца.')],
  'm7': [
    _lesson('m7-food', 'Прикорм', 'С чего начать.'),
    _lesson('m7-teeth', 'Первые зубы', 'Чего ждать.'),
    _lesson('m7-play', 'Игры', 'Что развивает.'),
    _lesson('m7-walk', 'Прогулки', 'Сколько гулять.'),
  ],
  'm30': [_lesson('m30-speech', 'Речь', 'Слова в два с половиной года.')],
  // The one shelf nothing about a stage implies: about HER, filed in a
  // pregnancy week and tagged by hand.
  'w30': [_lesson('w30-mother', 'Тревога перед родами', 'Про вас, не про малыша.', topic: 'mother')],
});

Future<void> pumpShell(WidgetTester tester, AppController c) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: HomeShell(controller: c, catalog: catalog),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('the rules, without a widget tree', () {
    test('an item shared into fourteen weeks is listed once', () {
      // ContentCatalog.itemsFor answers "what shows at this stage" and would
      // return this lesson at each of the fourteen. A library that repeats the
      // same card fourteen times is one nobody scrolls twice.
      final shared = catalog.byStage['w14']!.single;
      expect(shared.alsoStages.length, 13);
      for (final week in ['w15', 'w20', 'w27']) {
        expect(
          catalog.itemsFor(TimelineStage.fromKey(week)!).map((i) => i.id),
          contains('w14-nutrition'),
          reason: 'the sharing itself must still work',
        );
      }

      final guides = allGuides(catalog);
      final copies = guides.where((g) => g.item.id == 'w14-nutrition');
      expect(copies.length, 1);
      expect(copies.single.homeStage, 'w14', reason: 'it belongs to where it is authored');
    });

    test('the same id filed in two stages is still one entry', () {
      // A bad import, or a card copied rather than shared. Two identical rows
      // in a library is indistinguishable from a rendering bug, and the reader
      // has no way to tell which one is current.
      final duplicated = ContentCatalog({
        'm7': [_lesson('same', 'Прикорм', 'С чего начать.')],
        'm4': [_lesson('same', 'Прикорм', 'Копия.')],
      });
      final guides = allGuides(duplicated);
      expect(guides.length, 1);
      // The earlier stage in timeline order wins — deterministically, not by
      // whichever key the JSON happened to list first.
      expect(guides.single.homeStage, 'm4');
    });

    test('every published item appears exactly once, in timeline order', () {
      final guides = allGuides(catalog);
      final ids = guides.map((g) => g.item.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.length, 9);
      // Weeks before months, whatever order the map arrived in.
      expect(ids.first, 'w14-nutrition');
      expect(ids.last, 'm30-speech');
    });

    test('an untagged item lands on the shelf its stage implies', () {
      expect(topicForStage('w20'), ContentTopic.pregnancy);
      expect(topicForStage('m0'), ContentTopic.baby);
      expect(topicForStage('m12'), ContentTopic.baby);
      expect(topicForStage('m13'), ContentTopic.child);
      expect(topicForStage('m60'), ContentTopic.child);
    });

    test('«Мама» is never inferred, only stated', () {
      // Nothing about a week says the material is about her rather than about
      // the pregnancy, so the fallback must not be able to reach this shelf.
      for (final s in allTimelineStages()) {
        expect(topicForStage(s.key), isNot(ContentTopic.mother));
      }
      final guides = allGuides(catalog);
      final mother = guidesForTopic(guides, ContentTopic.mother);
      expect(mother.map((g) => g.item.id), ['w30-mother']);
      // …and it is NOT also counted as pregnancy, though it lives in week 30.
      expect(guidesForTopic(guides, ContentTopic.pregnancy).map((g) => g.item.id),
          isNot(contains('w30-mother')));
    });

    test('an unrecognised topic falls back rather than picking a tile', () {
      final odd = ContentItem(
        id: 'x',
        kind: ContentKind.lesson,
        title: const LocalizedText({'ru': 'x'}),
        summary: const LocalizedText({'ru': 'x'}),
        topic: 'nutrition',
      );
      expect(parseContentTopic('nutrition'), isNull);
      expect(topicOf(odd, 'm4'), ContentTopic.baby);
    });

    test('the tiles carry a count each, zero included', () {
      final counts = guideTopicCounts(allGuides(catalog));
      expect(counts.keys.toSet(), ContentTopic.values.toSet());
      expect(counts[ContentTopic.pregnancy], 2); // w14, w20
      expect(counts[ContentTopic.baby], 5); // m4 + four at m7
      expect(counts[ContentTopic.child], 1); // m30
      expect(counts[ContentTopic.mother], 1);
      expect(counts.values.reduce((a, b) => a + b), allGuides(catalog).length);
    });

    test('search matches the title and the summary', () {
      final guides = allGuides(catalog);
      expect(searchGuides(guides, 'дыхание', 'ru').map((g) => g.item.id), ['w20-breathing']);
      expect(searchGuides(guides, 'укладывать', 'ru').map((g) => g.item.id), ['m4-sleep']);
    });

    test('two words narrow rather than widen', () {
      // OR would be the opposite of what the second word was typed for.
      final guides = allGuides(catalog);
      expect(searchGuides(guides, 'сон малыша', 'ru').map((g) => g.item.id), ['m4-sleep']);
      expect(searchGuides(guides, 'сон прикорм', 'ru'), isEmpty);
    });

    test('an empty query is not a filter', () {
      final guides = allGuides(catalog);
      expect(searchGuides(guides, '   ', 'ru').length, guides.length);
    });

    test('it searches the locale she is reading, not the fallback', () {
      // LocalizedText falls back ru → en, so searching the raw map would match
      // Russian for a Kazakh reader and then hand her a card containing
      // nothing she typed.
      final kkOnly = ContentCatalog({
        'w20': [
          ContentItem(
            id: 'k1',
            kind: ContentKind.lesson,
            title: const LocalizedText({'ru': 'Дыхание', 'kk': 'Тыныс алу'}),
            summary: const LocalizedText({'ru': 'Урок', 'kk': 'Сабақ'}),
          ),
        ],
      });
      final guides = allGuides(kkOnly);
      expect(searchGuides(guides, 'тыныс', 'kk').length, 1);
      expect(searchGuides(guides, 'дыхание', 'kk'), isEmpty);
      expect(searchGuides(guides, 'дыхание', 'ru').length, 1);
    });

    test('a city-limited item is not offered to somebody it cannot reach', () {
      final limited = ContentCatalog({
        'm4': [
          ContentItem(
            id: 'almaty-only',
            kind: ContentKind.product,
            title: const LocalizedText({'ru': 'Слинг'}),
            summary: const LocalizedText({'ru': 'Доставка по Алматы'}),
            cities: const ['Алматы'],
          ),
        ],
      });
      expect(allGuides(limited), isEmpty);
      expect(allGuides(limited, viewer: const ContentViewer(city: 'Almaty')).length, 1);
    });

    test('a lesson with a video and no url is openable', () {
      // The way the CMS actually authors one: the stream goes in `video`, not
      // in `url`, which is where a product's shop page lives. Judging
      // openability by `url` alone made every such lesson render «Скоро» —
      // the player was built and working and nothing could reach it.
      final videoOnly = _lesson('v', 'Урок', 'Про сон.');
      expect(videoOnly.url, isEmpty);
      expect(videoOnly.hasLink, isTrue);
      expect(videoOnly.playsInApp, isTrue);

      // A product still needs a real page: `video` is a lesson's field, so
      // nothing here makes an unlinked product look buyable.
      const unlinked = ContentItem(
        id: 'p',
        kind: ContentKind.product,
        title: LocalizedText({'ru': 'Слинг'}),
        summary: LocalizedText({'ru': 'Пока без ссылки'}),
      );
      expect(unlinked.hasLink, isFalse);
    });

    test('a topic survives the wire', () {
      // The panel can only set it if it round-trips; z.object on the server
      // strips what it does not name, and this side must not drop it either.
      final json = _lesson('x', 't', 's', topic: 'mother').toJson();
      expect(json['topic'], 'mother');
      expect(ContentItem.fromJson(json).topic, 'mother');
      expect(ContentItem.fromJson({'id': 'y', 'kind': 'lesson'}).topic, isNull);
    });
  });

  group('from the shell, with no due date and no child', () {
    testWidgets('she can reach the library, search it, and open something',
        (tester) async {
      // The exact person the old app served nothing: no pregnancy, no
      // children, therefore no stage, therefore — until now — not one of the
      // 364 published items.
      final c = AppController(now: () => today, locale: AppLocale.ru);
      addTearDown(c.dispose);
      expect(c.isPregnant, isFalse);
      expect(c.children, isEmpty);

      await pumpShell(tester, c);

      final entry = find.text(l.t('tl_open_guides'));
      await tester.scrollUntilVisible(entry, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(find.byType(GuidesScreen), findsOneWidget);
      // In Russian — proof the scope is above the Navigator, not at `home:`.
      expect(find.text(l.t('gd_topics').toUpperCase()), findsOneWidget);
      // The amber card leads, before anything to browse.
      expect(find.text(l.t('gd_call_title')), findsOneWidget);

      // Search.
      await tester.enterText(find.byType(TextField), 'прикорм');
      await tester.pumpAndSettle();
      expect(find.text(l.t('gd_results', {'n': 1}).toUpperCase()), findsOneWidget);
      expect(find.text('Прикорм'), findsOneWidget);
      expect(find.text('Дыхание в родах'), findsNothing);

      // Back to browsing, and into a topic.
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      final babyTile = find.text(l.t('gd_topic_baby'));
      await tester.scrollUntilVisible(babyTile, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(babyTile);
      await tester.pumpAndSettle();

      // Five items: m4 plus the four at m7.
      expect(find.byType(ContentTile), findsNWidgets(5));

      // …and one of them opens. pump(duration), never pumpAndSettle: the
      // player shows an indeterminate spinner while it reaches for the
      // stream, and pumpAndSettle waits on that for ever.
      await tester.tap(find.text('Прикорм'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LessonPlayerScreen), findsOneWidget);
    });

    testWidgets('a lesson shared into fourteen weeks is on the shelf once',
        (tester) async {
      final c = AppController(now: () => today, locale: AppLocale.ru);
      addTearDown(c.dispose);
      await pumpShell(tester, c);

      final entry = find.text(l.t('tl_open_guides'));
      await tester.scrollUntilVisible(entry, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'триместре');
      await tester.pumpAndSettle();
      expect(find.text(l.t('gd_results', {'n': 1}).toUpperCase()), findsOneWidget);
      expect(find.text('Питание во втором триместре'), findsOneWidget);
    });

    testWidgets('and from Профиль too, not only from the Today card',
        (tester) async {
      // One entry point, at the bottom of a tab she may never scroll, is how
      // a library goes unfound. This is the second.
      final c = AppController(now: () => today, locale: AppLocale.ru);
      addTearDown(c.dispose);
      await pumpShell(tester, c);

      await tester.tap(find.text(l.t('nav_profile')));
      await tester.pumpAndSettle();

      final row = find.text(l.t('gd_title'));
      await tester.scrollUntilVisible(row, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(GuidesScreen), findsOneWidget);
    });

    testWidgets('«Мама» is a shelf of its own, not a count of nothing',
        (tester) async {
      final c = AppController(now: () => today, locale: AppLocale.ru);
      addTearDown(c.dispose);
      await pumpShell(tester, c);

      final entry = find.text(l.t('tl_open_guides'));
      await tester.scrollUntilVisible(entry, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      final tile = find.text(l.t('gd_topic_mother'));
      await tester.scrollUntilVisible(tile, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.text('Тревога перед родами'), findsOneWidget);
    });
  });

  group('«Когда сразу звонить 103»', () {
    Future<void> pumpGuides(WidgetTester tester, {required bool pregnant}) async {
      tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(L10nScope(
        l10n: l,
        child: MaterialApp(
          theme: FcsTheme.light(AppLocale.ru),
          home: GuidesScreen(
            catalog: catalog,
            pregnant: pregnant,
            onOpen: (_) {},
            // Injected so the tap never reaches a dialler this process has
            // no plugin for.
            onCall: (_) async => true,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('gd_call_title')));
      await tester.pumpAndSettle();
    }

    testWidgets('expecting: the signs of labour and when to go in',
        (tester) async {
      await pumpGuides(tester, pregnant: true);
      expect(find.byType(LabourSignsScreen), findsOneWidget);
      // In Russian, from a PUSHED route — the scope really is above
      // MaterialApp and not at `home:`.
      expect(find.text(l.t('lab_title')), findsWidgets);
    });

    testWidgets('otherwise: the screen whose one action is the call',
        (tester) async {
      await pumpGuides(tester, pregnant: false);
      expect(find.byType(EmergencyRescueScreen), findsOneWidget);
      expect(find.textContaining('103'), findsWidgets);
    });

    testWidgets('the signs are readable on the card, not behind the tap',
        (tester) async {
      // Somebody scrolling at 2am has to be able to recognise herself without
      // opening anything first.
      await tester.pumpWidget(L10nScope(
        l10n: l,
        child: MaterialApp(
          theme: FcsTheme.light(AppLocale.ru),
          home: GuidesScreen(catalog: catalog),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Кровотечение'), findsOneWidget);
    });
  });

  group('with a stage', () {
    testWidgets('the section is titled for her stage, never for a readership',
        (tester) async {
      // The spec draws this as «Читают в 7 месяцев». Nothing in this app
      // measures who reads what — telemetry carries vitals and location and
      // nothing else — so any number here would be invented, which is the
      // same manufactured social proof the dashboard card refuses by name.
      await tester.pumpWidget(L10nScope(
        l10n: l,
        child: MaterialApp(
          theme: FcsTheme.light(AppLocale.ru),
          home: GuidesScreen(
            catalog: catalog,
            stage: TimelineStage.childMonth(7),
            onOpen: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final section = find.text(l.t('gd_for_stage', {'stage': '7 мес.'}).toUpperCase());
      await tester.scrollUntilVisible(section, 200,
          scrollable: find.byType(Scrollable).first);
      expect(section, findsOneWidget);
      expect(find.textContaining('Читают'), findsNothing);

      // Three of the four previewed, and the rest a tap away — the stage
      // screen is still reachable, from here.
      final seeAll = find.text(l.t('tl_see_all'));
      await tester.scrollUntilVisible(seeAll, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(seeAll);
      await tester.pumpAndSettle();
      expect(find.byType(TimelineContentScreen), findsOneWidget);
      expect(find.byType(ContentTile), findsNWidgets(4));
    });

    testWidgets('with no stage there is no section pretending to have one',
        (tester) async {
      await tester.pumpWidget(L10nScope(
        l10n: l,
        child: MaterialApp(
          theme: FcsTheme.light(AppLocale.ru),
          home: GuidesScreen(catalog: catalog, onOpen: (_) {}),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('ДЛЯ '), findsNothing);
      expect(find.text(l.t('gd_topics').toUpperCase()), findsOneWidget);
    });

    testWidgets('an empty catalogue says so rather than drawing four zeroes',
        (tester) async {
      await tester.pumpWidget(L10nScope(
        l10n: l,
        child: const MaterialApp(
          home: GuidesScreen(catalog: ContentCatalog({})),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(l.t('gd_empty')), findsOneWidget);
      // The one thing that is still true with no catalogue at all.
      expect(find.text(l.t('gd_call_title')), findsOneWidget);
    });
  });
}
