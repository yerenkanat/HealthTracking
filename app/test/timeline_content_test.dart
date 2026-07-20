/// Widget tests for the timeline content card and screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/demo_content.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/content/timeline_content_card.dart';
import 'package:fcs_app/ui/content/timeline_content_screen.dart';

void main() {
  final catalog = demoContentCatalog();
  final week20 = TimelineStage.pregnancyWeek(20);
  final month4 = TimelineStage.childMonth(4);

  Widget wrap(Widget child, {AppLocale locale = AppLocale.en}) => MaterialApp(
        home: L10nScope(
          l10n: L10n(locale),
          child: Scaffold(body: ListView(children: [child])),
        ),
      );

  testWidgets('the card names the stage and previews its content', (tester) async {
    await tester.pumpWidget(wrap(TimelineContentCard(
      stage: week20,
      items: catalog.itemsFor(week20),
      onOpen: (_) {},
      onSeeAll: () {},
    )));
    expect(find.text('For you now'), findsOneWidget);
    expect(find.text('Week 20'), findsOneWidget);
    // A preview, not the whole list.
    expect(find.byType(ContentTile), findsNWidgets(TimelineContentCard.previewCount));
    // A pregnancy week holds exactly the preview count, so there is nothing
    // further to open — offering "See all" would lead to the same three items.
    expect(find.text('See all'), findsNothing);
  });

  testWidgets('"See all" appears only when there is more to see', (tester) async {
    // A child month carries four items, one more than the card previews.
    await tester.pumpWidget(wrap(TimelineContentCard(
      stage: month4,
      items: catalog.itemsFor(month4),
      onOpen: (_) {},
      onSeeAll: () {},
    )));
    expect(catalog.itemsFor(month4).length, greaterThan(TimelineContentCard.previewCount));
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('a newborn reads as "Newborn", not "0 months"', (tester) async {
    final m0 = TimelineStage.childMonth(0);
    await tester.pumpWidget(wrap(TimelineContentCard(
      stage: m0,
      items: catalog.itemsFor(m0),
      onOpen: (_) {},
    )));
    expect(find.text('Newborn'), findsOneWidget);
    expect(find.text('0 months'), findsNothing);
  });

  testWidgets('with no stage the card explains what to add', (tester) async {
    await tester.pumpWidget(wrap(const TimelineContentCard(stage: null, items: [])));
    expect(find.textContaining('due date'), findsOneWidget);
    expect(find.byType(ContentTile), findsNothing);
  });

  testWidgets('the card leads with lessons, then a product', (tester) async {
    await tester.pumpWidget(wrap(TimelineContentCard(
      stage: month4,
      items: catalog.itemsFor(month4),
      onOpen: (_) {},
    )));
    final tiles = tester.widgetList<ContentTile>(find.byType(ContentTile)).toList();
    expect(tiles.first.item.isLesson, isTrue);
    expect(tiles.any((t) => t.item.isProduct), isTrue);
  });

  testWidgets('the screen groups lessons and products', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: TimelineContentScreen(stage: week20, items: catalog.itemsFor(week20), onOpen: (_) {}),
      ),
    ));
    expect(find.text('VIDEO LESSONS'), findsOneWidget);
    expect(find.text('PRODUCTS'), findsOneWidget);
    expect(find.byType(ContentTile), findsNWidgets(catalog.itemsFor(week20).length));
  });

  testWidgets('an unlinked item is shown but not tappable', (tester) async {
    // Seeded content has no URLs yet, so every item should read "Soon" rather
    // than offering an action that goes nowhere.
    var opened = 0;
    await tester.pumpWidget(wrap(TimelineContentCard(
      stage: week20,
      items: catalog.itemsFor(week20),
      onOpen: (_) => opened++,
    )));
    expect(find.text('Soon'), findsWidgets);
    await tester.tap(find.byType(ContentTile).first);
    await tester.pump();
    expect(opened, 0);
  });

  testWidgets('a linked item opens', (tester) async {
    ContentItem? opened;
    const linked = ContentItem(
      id: 'x',
      kind: ContentKind.lesson,
      title: LocalizedText({'en': 'Breathing basics'}),
      summary: LocalizedText({'en': 'A short lesson'}),
      url: 'https://example.com/v',
      durationMin: 6,
    );
    await tester.pumpWidget(wrap(TimelineContentCard(
      stage: week20,
      items: const [linked],
      onOpen: (i) => opened = i,
    )));
    expect(find.text('Watch'), findsOneWidget);
    await tester.tap(find.byType(ContentTile));
    await tester.pump();
    expect(opened?.id, 'x');
  });

  testWidgets('a product shows its price, a lesson its length', (tester) async {
    const product = ContentItem(
      id: 'p',
      kind: ContentKind.product,
      title: LocalizedText({'en': 'Pregnancy pillow'}),
      summary: LocalizedText({'en': 'Comfort for side sleeping'}),
      url: 'https://example.com/p',
      priceMinor: 1290000,
      currency: 'KZT',
    );
    await tester.pumpWidget(wrap(TimelineContentCard(
      stage: week20,
      items: const [product],
      onOpen: (_) {},
    )));
    // Non-breaking spaces: a price must not wrap mid-number or before the
    // symbol, so the rendered string uses U+00A0 rather than a plain space.
    expect(find.text('12 900 ₸'), findsOneWidget);
    expect(find.text('Buy'), findsOneWidget);
  });

  // The stage label and content must be readable in every shipped language;
  // Russian and Kazakh run longer than the English these were laid out against.
  for (final locale in AppLocale.values) {
    testWidgets('the card renders in ${locale.name} without overflowing at 360dp',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      final overflows = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) {
          overflows.add(details.exceptionAsString().split('\n').first);
        } else {
          previous?.call(details);
        }
      };
      await tester.pumpWidget(wrap(
        TimelineContentCard(
          stage: week20,
          items: catalog.itemsFor(week20),
          onOpen: (_) {},
          onSeeAll: () {},
        ),
        locale: locale,
      ));
      await tester.pumpAndSettle();
      FlutterError.onError = previous;
      expect(overflows, isEmpty, reason: 'overflowed in ${locale.name}: $overflows');
    });
  }

  testWidgets('the content card meets the accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap(TimelineContentCard(
      stage: week20,
      items: catalog.itemsFor(week20),
      onOpen: (_) {},
      onSeeAll: () {},
    )));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
