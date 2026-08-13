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
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/content/guides_screen.dart';
import 'package:fcs_app/ui/content/lesson_player_screen.dart';
import 'package:fcs_app/ui/calendar/labour_signs_screen.dart';
import 'package:fcs_app/ui/content/timeline_content_screen.dart';
import 'package:fcs_app/data/emergency_help_repository.dart';
import 'package:fcs_app/domain/emergency_help.dart';
import 'package:fcs_app/ui/emergency/emergency_help_screen.dart';
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
    // The scenarios come from the repository, and a widget test has no asset
    // bundle worth depending on — so the baseline is injected. Two entries,
    // one of each severity, because the screen's whole job is telling them
    // apart.
    setUp(() => debugSetEmergencyHelp(const EmergencyHelp(
          version: 1,
          tel: '103',
          scenarios: [
            EmergencyScenario(
              id: 'bleeding',
              severity: EmergencySeverity.red,
              sort: 10,
              ru: EmergencyText(
                  title: 'Сильное кровотечение',
                  what: 'Прокладка промокает за час.',
                  todo: 'Звоните 103, лягте на бок.'),
              kk: EmergencyText(
                  title: 'Қатты қан кету',
                  what: 'Прокладка бір сағатта малынады.',
                  todo: '103-ке қоңырау шалыңыз.'),
            ),
            // Pregnancy triage, by its own words («после 20 недель»). The
            // scenario the fork used to make unreachable for the only reader
            // it applies to — and unavoidable for the one it does not.
            EmergencyScenario(
              id: 'preeclampsia',
              severity: EmergencySeverity.red,
              sort: 15,
              audience: EmergencyAudience.pregnancy,
              ru: EmergencyText(
                  title: 'Головная боль, мушки в глазах, отёки',
                  what: 'После 20 недель: сильная головная боль.',
                  todo: 'Звоните 103 и назовите срок беременности.'),
              kk: EmergencyText(
                  title: 'Бас ауруы, ұшқындар, ісіну',
                  what: '20 аптадан кейін: қатты бас ауруы.',
                  todo: '103-ке қоңырау шалыңыз.'),
            ),
            EmergencyScenario(
              id: 'fever_newborn',
              severity: EmergencySeverity.amber,
              sort: 20,
              ru: EmergencyText(
                  title: 'Температура у ребёнка до трёх месяцев',
                  what: '38 и выше у малыша младше трёх месяцев.',
                  todo: 'Позвоните педиатру сегодня.'),
              kk: EmergencyText(
                  title: 'Үш айға дейінгі баланың қызуы',
                  what: 'Үш айға толмаған нәрестеде 38 және жоғары.',
                  todo: 'Бүгін педиатрға қоңырау шалыңыз.'),
            ),
          ],
        )));

    Future<void> pumpGuides(
      WidgetTester tester, {
      required bool pregnant,
      String address = '',
      String city = '',
      String doctorPhone = '',
      List<String>? dialled,
    }) async {
      tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
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
            address: address,
            city: city,
            doctorPhone: doctorPhone,
            // Injected so the tap never reaches a dialler this process has
            // no plugin for.
            onCall: (tel) async {
              dialled?.add(tel);
              return true;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('gd_call_title')));
      await tester.pumpAndSettle();
    }

    testWidgets('expecting: screen 37, WITH the pregnancy scenarios on it',
        (tester) async {
      // The card used to fork here and send her to the labour reference, which
      // meant «преэклампсия» — red, «звоните 103 сейчас», written for her and
      // nobody else — could not be opened by a pregnant woman at all, and the
      // screen she did get had no ambulance card, no dispatcher address and no
      // doctor's number on it.
      await pumpGuides(tester, pregnant: true);
      expect(find.byType(EmergencyHelpScreen), findsOneWidget);
      // In Russian, from a PUSHED route — the scope really is above
      // MaterialApp and not at `home:`.
      expect(find.text(l.t('eh_title')), findsWidgets);
      expect(find.text('Головная боль, мушки в глазах, отёки'), findsOneWidget);
      // Not instead of the rest: a pregnant woman may also have a toddler.
      expect(find.text('Сильное кровотечение'), findsOneWidget);
      expect(find.text('Температура у ребёнка до трёх месяцев'), findsOneWidget);
    });

    testWidgets('...and the signs of labour are one tap from it, not instead of it',
        (tester) async {
      // LabourSignsScreen has no navigation of its own, so a fork INTO it was a
      // dead end. Linked FROM screen 37 it is still reachable and the ambulance
      // card is behind the back button rather than behind a re-navigation.
      await pumpGuides(tester, pregnant: true);
      final row = find.text(l.t('eh_labour_signs'));
      await tester.scrollUntilVisible(row, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(LabourSignsScreen), findsOneWidget);
      expect(find.text(l.t('lab_title')), findsWidgets);
    });

    testWidgets('not expecting: no pregnancy triage, and no labour row either',
        (tester) async {
      // «После 20 недель» cannot apply to her, and on this screen every row she
      // has to read past is time. The rest of the list is untouched.
      await pumpGuides(tester, pregnant: false);
      expect(find.text('Головная боль, мушки в глазах, отёки'), findsNothing);
      expect(find.text(l.t('eh_labour_signs')), findsNothing);
      expect(find.text('Сильное кровотечение'), findsOneWidget);
      expect(find.text('Температура у ребёнка до трёх месяцев'), findsOneWidget);
    });

    testWidgets('otherwise: screen 37, not the bare triage screen',
        (tester) async {
      // The wiring this feature exists to fix. Everyone who was not pregnant
      // used to land on the TRIAGE screen — one paragraph, one button — with
      // no scenarios, no address and no way to reach her own doctor.
      final dialled = <String>[];
      await pumpGuides(tester,
          pregnant: false,
          address: 'мкр. Самал-2, д. 33, кв. 12',
          city: 'Алматы',
          doctorPhone: '+77007654321',
          dialled: dialled);

      expect(find.byType(EmergencyHelpScreen), findsOneWidget);
      // In Russian, from a PUSHED route.
      expect(find.text(l.t('eh_title')), findsWidgets);
      // 1 · the 103 card.
      expect(find.text('103'), findsOneWidget);
      // 2 · «Что происходит?» and both scenarios, each with its severity in
      // words as well as in colour.
      expect(find.text(l.t('eh_whats_happening').toUpperCase()), findsOneWidget);
      expect(find.text('Сильное кровотечение'), findsOneWidget);
      expect(find.text(l.t('eh_sev_red')), findsOneWidget);
      expect(find.text(l.t('eh_sev_amber')), findsOneWidget);
      // 3 · the address a dispatcher asks for.
      expect(find.text('мкр. Самал-2, д. 33, кв. 12'), findsOneWidget);
      // 4 · her own doctor.
      final doctor = find.textContaining(l.t('eh_call_doctor'));
      await tester.scrollUntilVisible(doctor, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(doctor);
      await tester.pumpAndSettle();
      expect(dialled, ['+77007654321']);
    });

    testWidgets('the 103 card dials 103', (tester) async {
      final dialled = <String>[];
      await pumpGuides(tester, pregnant: false, dialled: dialled);
      await tester.tap(find.text('103'));
      await tester.pumpAndSettle();
      expect(dialled, ['103']);
    });

    testWidgets('no address: her city and «Добавьте адрес», never an invented one',
        (tester) async {
      await pumpGuides(tester, pregnant: false, city: 'Алматы');
      final prompt = find.textContaining(l.t('eh_address_missing_body'));
      await tester.scrollUntilVisible(prompt, 200,
          scrollable: find.byType(Scrollable).first);
      expect(prompt, findsOneWidget);
      expect(find.text('Алматы'), findsOneWidget);
    });

    testWidgets('no doctor: the row says where to add one, not a dead button',
        (tester) async {
      await pumpGuides(tester, pregnant: false);
      final note = find.text(l.t('eh_no_doctor'));
      await tester.scrollUntilVisible(note, 200,
          scrollable: find.byType(Scrollable).first);
      expect(note, findsOneWidget);
      expect(find.textContaining(l.t('eh_call_doctor')), findsNothing);
    });

    testWidgets('with no scenarios at all the call button still works',
        (tester) async {
      // Asset missing, cache empty, server unreachable. The half that matters
      // most is still on screen; only the list is gone, and it says so.
      debugSetEmergencyHelp(EmergencyHelp.empty);
      final dialled = <String>[];
      await pumpGuides(tester, pregnant: false, dialled: dialled);
      expect(find.text(l.t('eh_no_scenarios')), findsOneWidget);
      await tester.tap(find.text('103'));
      await tester.pumpAndSettle();
      expect(dialled, ['103']);
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

  /// Screen 37's profile facts, driven from the REAL shell.
  ///
  /// Everything above builds GuidesScreen directly and hands it an address, so
  /// none of it can observe the address ARRIVING from the shell: delete the
  /// four lines in home_shell.dart that pass address/city/doctorPhone and the
  /// whole suite still passed. These tests are that join, and the join is what
  /// puts a dispatcher's answer on the screen at 3am.
  group('the profile reaching screen 37, from the shell', () {
    const scenarios = EmergencyHelp(
      version: 1,
      tel: '103',
      scenarios: [
        EmergencyScenario(
          id: 'bleeding',
          severity: EmergencySeverity.red,
          sort: 10,
          ru: EmergencyText(
              title: 'Сильное кровотечение',
              what: 'Прокладка промокает за час.',
              todo: 'Звоните 103, лягте на бок.'),
          kk: EmergencyText(
              title: 'Қатты қан кету',
              what: 'Прокладка бір сағатта малынады.',
              todo: '103-ке қоңырау шалыңыз.'),
        ),
      ],
    );

    /// Тoday tab → «Гиды» → the amber card → screen 37.
    Future<void> openScreen37(WidgetTester tester) async {
      final entry = find.text(l.t('tl_open_guides'));
      await tester.scrollUntilVisible(entry, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('gd_call_title')));
      await tester.pumpAndSettle();
      expect(find.byType(EmergencyHelpScreen), findsOneWidget);
    }

    testWidgets('her address and her doctor arrive on it', (tester) async {
      debugSetEmergencyHelp(scenarios);
      final c = AppController(now: () => today, locale: AppLocale.ru);
      addTearDown(c.dispose);
      c.updateProfile(const UserProfile(
        displayName: 'Айгерим',
        city: 'Алматы',
        address: 'мкр. Самал-2, д. 33, кв. 12, домофон 12К',
        doctorPhone: '+77007654321',
      ));
      await pumpShell(tester, c);
      await openScreen37(tester);

      // The address a dispatcher asks for — the whole string, entry code
      // included, because that is the half a paramedic at the door needs.
      expect(find.text('мкр. Самал-2, д. 33, кв. 12, домофон 12К'), findsOneWidget);
      expect(find.textContaining(l.t('eh_address_missing_body')), findsNothing);

      // …and her own doctor's number, on the button rather than in a profile
      // screen two taps away. Not tapped: from the shell the dialler is
      // url_launcher, and this process has no plugin for it.
      final doctor = find.textContaining(l.t('eh_call_doctor'));
      await tester.scrollUntilVisible(doctor, 200,
          scrollable: find.byType(Scrollable).first);
      expect(doctor, findsOneWidget);
      expect(find.textContaining('+77007654321'), findsOneWidget);
      expect(find.text(l.t('eh_no_doctor')), findsNothing);
    });

    testWidgets('with nothing saved it says so — her city, never an invented address',
        (tester) async {
      debugSetEmergencyHelp(scenarios);
      final c = AppController(now: () => today, locale: AppLocale.ru);
      addTearDown(c.dispose);
      c.updateProfile(const UserProfile(displayName: 'Айгерим', city: 'Алматы'));
      await pumpShell(tester, c);
      await openScreen37(tester);

      final prompt = find.textContaining(l.t('eh_address_missing_body'));
      await tester.scrollUntilVisible(prompt, 200,
          scrollable: find.byType(Scrollable).first);
      expect(prompt, findsOneWidget);
      expect(find.text('Алматы'), findsOneWidget);
    });

    testWidgets('an address saved from the prompt appears on the card she saved it from',
        (tester) async {
      // The «assumes the request succeeded» family, on the screen where it
      // costs the most: the write landed and the card went on saying «Добавьте
      // адрес» until she popped screen 37, popped Гиды and opened both again.
      debugSetEmergencyHelp(scenarios);
      final c = AppController(now: () => today, locale: AppLocale.ru);
      addTearDown(c.dispose);
      c.updateProfile(const UserProfile(displayName: 'Айгерим', city: 'Алматы'));
      await pumpShell(tester, c);
      await openScreen37(tester);

      final prompt = find.text(l.t('eh_address_missing'));
      await tester.scrollUntilVisible(prompt, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(prompt);
      await tester.pumpAndSettle();

      final addressField = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.labelText == l.t('prof_address'));
      expect(addressField, findsOneWidget, reason: 'the profile sheet opened');
      await tester.enterText(addressField, 'мкр. Самал-2, д. 33, кв. 12');
      final save = find.text(l.t('act_save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      // Still on screen 37 — she never left it — and the card now reads back
      // what she typed.
      expect(find.byType(EmergencyHelpScreen), findsOneWidget);
      expect(c.profile.address, 'мкр. Самал-2, д. 33, кв. 12');
      final saved = find.text('мкр. Самал-2, д. 33, кв. 12');
      await tester.scrollUntilVisible(saved, 200,
          scrollable: find.byType(Scrollable).first);
      expect(saved, findsOneWidget);
      expect(find.text(l.t('eh_address_missing')), findsNothing);
    });

    testWidgets('and so does a doctor’s number added the same way', (tester) async {
      debugSetEmergencyHelp(scenarios);
      final c = AppController(now: () => today, locale: AppLocale.ru);
      addTearDown(c.dispose);
      c.updateProfile(const UserProfile(displayName: 'Айгерим'));
      await pumpShell(tester, c);
      await openScreen37(tester);

      final prompt = find.text(l.t('prof_doctor_hint'));
      await tester.scrollUntilVisible(prompt, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(prompt);
      await tester.pumpAndSettle();

      final doctorField = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.labelText == l.t('prof_doctor_hint'));
      await tester.enterText(doctorField, '+77007654321');
      final save = find.text(l.t('act_save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final doctor = find.textContaining('+77007654321');
      await tester.scrollUntilVisible(doctor, 200,
          scrollable: find.byType(Scrollable).first);
      expect(doctor, findsOneWidget);
      expect(find.text(l.t('eh_no_doctor')), findsNothing);
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
