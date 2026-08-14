/// A guide that has text — the screen, and the rules behind it.
///
/// The defect: a published guide was a heading, a one-line summary and an
/// external `url`. Tapping one threw a woman into a browser; with the url empty
/// it was not tappable at all and the card said «Скоро». 364 items reached
/// every phone and not one of them held a sentence she could read in the app.
///
/// The widget tests drive the REAL SHELL rather than constructing ArticleScreen
/// directly, because constructing it is exactly what a test would do happily
/// while nothing in the app pushed it — this repo's commonest defect is
/// finished code with no caller.
///
/// L10nScope wraps MaterialApp, never `home:` — under `home:` it sits below the
/// Navigator and every PUSHED route falls back to English, which has made
/// working screens look broken on this project before. The article IS a pushed
/// route, so that mistake would be invisible except here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/content/article_screen.dart';
import 'package:fcs_app/ui/content/lesson_player_screen.dart';
import 'package:fcs_app/ui/content/timeline_content_screen.dart';
import 'package:fcs_app/ui/home_shell.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/widgets/call_ambulance.dart';

const l = L10n(AppLocale.ru);
final today = DateTime(2026, 8, 12);

const bodyRu = 'Кровотечение во втором триместре бывает разным.\n\n'
    'Мажущие выделения после осмотра — обычно не опасно.\n\n'
    'Алая кровь со сгустками — повод звонить сейчас.';
const bodyKk = 'Екінші триместрдегі қан кету әртүрлі болады.\n\n'
    'Тексерістен кейінгі дақ — әдетте қауіпті емес.\n\n'
    'Ұйыған қызыл қан — қазір қоңырау шалу себебі.';
const flagsRu = 'Прокладка полностью промокает за час.\nБоль в животе не проходит.';
const flagsKk = 'Прокладка бір сағатта толық су болады.\nІш ауруы басылмайды.';

/// The shape frame 16a produces: text, red flags, and NOTHING else to open.
ContentItem article({
  String id = 'w23-bleeding',
  Map<String, String> body = const {'ru': bodyRu, 'kk': bodyKk},
  Map<String, String> flags = const {'ru': flagsRu, 'kk': flagsKk},
  VideoSource? video,
  String url = '',
}) =>
    ContentItem(
      id: id,
      kind: ContentKind.lesson,
      title: const LocalizedText({'ru': 'Кровотечение', 'kk': 'Қан кету'}),
      summary: const LocalizedText({'ru': 'Когда звонить', 'kk': 'Қашан қоңырау шалу'}),
      body: LocalizedText(body),
      redFlags: LocalizedText(flags),
      videoSource: video,
      url: url,
    );

ContentCatalog catalogWith(ContentItem item) => ContentCatalog({'w23': [item]});

Future<void> pumpShell(
  WidgetTester tester,
  AppController c,
  ContentCatalog catalog, {
  AppLocale locale = AppLocale.ru,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(L10nScope(
    l10n: L10n(locale),
    child: MaterialApp(
      theme: FcsTheme.light(locale),
      home: HomeShell(controller: c, catalog: catalog),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Reach the article from where a reader actually is: Гиды → search → tap.
Future<void> openTheGuide(WidgetTester tester, String query, String title) async {
  final entry = find.text(l.t('tl_open_guides'));
  await tester.scrollUntilVisible(entry, 200, scrollable: find.byType(Scrollable).first);
  await tester.tap(entry);
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  group('the rules, without a widget tree', () {
    test('an article is split into paragraphs, and nothing else is interpreted', () {
      expect(articleParagraphs(bodyRu).length, 3);
      expect(articleParagraphs(bodyRu).first, 'Кровотечение во втором триместре бывает разным.');
      // One blank line or none — both authoring habits produce paragraphs, and
      // a document pasted out of Word full of stray returns does not produce
      // gaps of varying height.
      expect(articleParagraphs('раз\nдва\nтри').length, 3);
      expect(articleParagraphs('раз\n\n\n\nдва').length, 2);
      expect(articleParagraphs('   '), isEmpty);
      expect(articleParagraphs(''), isEmpty);
      // Markup is text. An article renderer that interpreted tags would let a
      // pasted `<` from a document break the page from a content field.
      expect(articleParagraphs('<b>жирный</b>').single, '<b>жирный</b>');
    });

    test('a guide with only text is openable', () {
      // Judged by `url` and `video` alone, an article-only guide rendered as
      // «Скоро» — a finished, translated, doctor-approved piece of writing that
      // nothing in the app could reach.
      final a = article();
      expect(a.url, isEmpty);
      expect(a.video, isNull);
      expect(a.hasArticle, isTrue);
      expect(a.hasSource, isFalse);
      expect(a.hasLink, isTrue);
    });

    test('an empty article is not an article', () {
      final none = article(body: const {}, flags: const {});
      expect(none.hasArticle, isFalse);
      expect(none.hasRedFlags, isFalse);
      expect(none.hasLink, isFalse, reason: 'nothing to open, so «Скоро» is honest');
      // Whitespace is not text: a body of spaces would render a blank screen.
      expect(article(body: const {'ru': '   '}).hasArticle, isFalse);
    });

    test('the article survives the wire in both directions', () {
      // The server's z.object strips what it does not name, and this side must
      // not drop it either — one round trip through either would erase text
      // somebody spent an hour writing.
      final json = article().toJson();
      expect(json['body'], {'ru': bodyRu, 'kk': bodyKk});
      expect(json['redFlags'], {'ru': flagsRu, 'kk': flagsKk});
      final back = ContentItem.fromJson(json);
      expect(back.body('ru'), bodyRu);
      expect(back.redFlags('kk'), flagsKk);

      // …and an item authored before articles existed round-trips without
      // growing empty maps that would be downloaded and rendered nowhere.
      final bare = ContentItem.fromJson({'id': 'x', 'kind': 'lesson'});
      expect(bare.hasArticle, isFalse);
      expect(bare.toJson().containsKey('body'), isFalse);
      expect(bare.toJson().containsKey('redFlags'), isFalse);
    });

    test('a Kazakh reader with a Russian-only article gets the Russian', () {
      // The back office is gated against this (content/bilingual.ts), but the
      // gate is on new saves. The wrong language is a known, bounded failure;
      // a blank screen is not, and judging «is there an article» by HER locale
      // would make the card untappable for exactly the reader the fallback
      // exists to serve.
      final ruOnly = article(body: const {'ru': bodyRu}, flags: const {'ru': flagsRu});
      expect(ruOnly.hasArticle, isTrue);
      expect(ruOnly.body('kk'), bodyRu);
      expect(ruOnly.redFlags('kk'), flagsRu);
    });
  });

  group('from the shell', () {
    testWidgets('a guide with only text opens, and reads', (tester) async {
      final c = AppController(now: () => today, locale: AppLocale.ru);
      addTearDown(c.dispose);
      await pumpShell(tester, c, catalogWith(article()));

      // The card offers «Читать», not «Смотреть» and not «Скоро».
      final entry = find.text(l.t('tl_open_guides'));
      await tester.scrollUntilVisible(entry, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'кровотечение');
      await tester.pumpAndSettle();
      expect(find.byType(ContentTile), findsOneWidget);
      expect(find.text(l.t('tl_read')), findsOneWidget);
      expect(find.text(l.t('tl_soon')), findsNothing);

      await tester.tap(find.text('Кровотечение'));
      await tester.pumpAndSettle();

      expect(find.byType(ArticleScreen), findsOneWidget);
      // In Russian — proof L10nScope is above the Navigator, not at `home:`.
      expect(find.text(l.t('art_red_flag')), findsOneWidget);
      // Every paragraph, not a truncated preview.
      for (final p in articleParagraphs(bodyRu)) {
        expect(find.text(p), findsOneWidget, reason: 'missing paragraph: $p');
      }
      // …and 103 at the bottom, because writing the signs down is only worth
      // it if she knows what to do next.
      expect(find.byType(CallAmbulanceFooter), findsOneWidget);
    });

    testWidgets('the red flags are above the article and never behind a tap',
        (tester) async {
      // docs/CLAUDE-app-design.md §4.6. A disclosure here is the difference
      // between a woman reading the line that says call and scrolling past it.
      final c = AppController(now: () => today, locale: AppLocale.ru);
      addTearDown(c.dispose);
      await pumpShell(tester, c, catalogWith(article()));
      await openTheGuide(tester, 'кровотечение', 'Кровотечение');

      expect(find.byType(ExpansionTile), findsNothing);
      for (final line in articleParagraphs(flagsRu)) {
        expect(find.text(line), findsOneWidget, reason: 'a red flag is hidden: $line');
      }

      // ABOVE: every red-flag line sits higher on the screen than every
      // paragraph of the article.
      final lowestFlag = articleParagraphs(flagsRu)
          .map((t) => tester.getBottomLeft(find.text(t)).dy)
          .reduce((a, b) => a > b ? a : b);
      final highestParagraph = articleParagraphs(bodyRu)
          .map((t) => tester.getTopLeft(find.text(t)).dy)
          .reduce((a, b) => a < b ? a : b);
      expect(lowestFlag, lessThan(highestParagraph));
    });

    testWidgets('a guide with a video AND an article shows the article first',
        (tester) async {
      // The ordering that made this a wiring decision rather than a screen.
      // Straight to the player, and the red-flag block — required above the
      // text and never behind a disclosure — is drawn nowhere at all.
      final c = AppController(now: () => today, locale: AppLocale.ru);
      addTearDown(c.dispose);
      final withVideo = article(
        video: const VideoSource(provider: VideoProvider.hls, url: 'https://cdn/x.m3u8'),
      );
      expect(withVideo.playsInApp, isTrue);
      await pumpShell(tester, c, catalogWith(withVideo));
      await openTheGuide(tester, 'кровотечение', 'Кровотечение');

      expect(find.byType(ArticleScreen), findsOneWidget);
      expect(find.byType(LessonPlayerScreen), findsNothing);
      expect(find.text(l.t('art_red_flag')), findsOneWidget);

      // Nothing is lost: the video is offered at the end, and it opens.
      final watch = find.text(l.t('tl_watch'));
      await tester.scrollUntilVisible(watch, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(watch);
      // pump(duration), never pumpAndSettle: the player shows an indeterminate
      // spinner while it reaches for the stream, and pumpAndSettle waits for ever.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LessonPlayerScreen), findsOneWidget);
    });

    testWidgets('a guide with no article still goes straight to its video',
        (tester) async {
      // The 364 items already published. Nothing about this feature may put a
      // screen between a reader and a lesson that has no text on it.
      final c = AppController(now: () => today, locale: AppLocale.ru);
      addTearDown(c.dispose);
      await pumpShell(tester, c, catalogWith(article(
        body: const {},
        flags: const {},
        video: const VideoSource(provider: VideoProvider.hls, url: 'https://cdn/x.m3u8'),
      )));

      final entry = find.text(l.t('tl_open_guides'));
      await tester.scrollUntilVisible(entry, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'кровотечение');
      await tester.pumpAndSettle();
      expect(find.text(l.t('tl_watch')), findsOneWidget, reason: 'not «Читать»: there is no text');

      // pump(duration), never pumpAndSettle: the player it lands on shows an
      // indeterminate spinner while it reaches for the stream.
      await tester.tap(find.text('Кровотечение'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ArticleScreen), findsNothing);
      expect(find.byType(LessonPlayerScreen), findsOneWidget);
    });

    testWidgets('a Kazakh reader with a Russian-only article sees the Russian',
        (tester) async {
      // Not a blank screen. The back office is gated against publishing this,
      // but anything already stored has to render.
      const kk = L10n(AppLocale.kk);
      final c = AppController(now: () => today, locale: AppLocale.kk);
      addTearDown(c.dispose);
      await pumpShell(
        tester,
        c,
        catalogWith(article(body: const {'ru': bodyRu}, flags: const {'ru': flagsRu})),
        locale: AppLocale.kk,
      );

      final entry = find.text(kk.t('tl_open_guides'));
      await tester.scrollUntilVisible(entry, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'қан');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Қан кету'));
      await tester.pumpAndSettle();

      expect(find.byType(ArticleScreen), findsOneWidget);
      // The chrome is Kazakh; the article is the Russian that exists.
      expect(find.text(kk.t('art_red_flag')), findsOneWidget);
      expect(find.text(articleParagraphs(bodyRu).first), findsOneWidget);
    });
  });
}
