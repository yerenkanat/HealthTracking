/// Screen 19 — «Скелет загрузки».
///
/// The assertions that matter are the two that keep a skeleton honest: it must
/// stop moving when the platform asks for reduced motion, and it must repeat
/// the home layout rather than being a generic grey rectangle — a skeleton that
/// promises the wrong shape makes the content JUMP when it lands, which is the
/// problem it was added to solve.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/ui/common/skeleton.dart';

Future<void> pump(WidgetTester tester, Widget child, {bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: child,
    ),
  ));
  await tester.pump();
}

void main() {
  group('the home skeleton repeats the home layout', () {
    testWidgets('has a greeting, a hero, three actions and cards', (tester) async {
      await pump(tester, const HomeSkeleton());
      // Not one grey rectangle. The count is the shape: two greeting lines,
      // the hero, three quick actions, three cards.
      expect(find.byType(SkeletonBox), findsNWidgets(9));
    });

    testWidgets('the hero is the biggest block on the screen', (tester) async {
      await pump(tester, const HomeSkeleton());
      final heights = tester
          .widgetList<SkeletonBox>(find.byType(SkeletonBox))
          .map((b) => b.height)
          .toList();
      // 168 — the pregnancy week / child day card. If the home hero shrinks
      // below the cards under it, this skeleton is lying about the layout.
      expect(heights.reduce((a, b) => a > b ? a : b), 168);
    });

    testWidgets('does not invite a pull-to-refresh on a screen with nothing to refresh',
        (tester) async {
      await pump(tester, const HomeSkeleton());
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.physics, isA<NeverScrollableScrollPhysics>());
    });
  });

  group('reduced motion', () {
    testWidgets('stops the shimmer entirely when the platform asks', (tester) async {
      await pump(tester, const HomeSkeleton(), reduceMotion: true);
      // No Opacity wrapper means no animation is driving anything. A shimmer is
      // decoration, and decoration is the first thing to drop when somebody has
      // asked for less movement.
      expect(
        find.descendant(of: find.byType(Shimmer), matching: find.byType(Opacity)),
        findsNothing,
      );
    });

    testWidgets('shimmers when motion is allowed', (tester) async {
      await pump(tester, const HomeSkeleton());
      expect(
        find.descendant(of: find.byType(Shimmer), matching: find.byType(Opacity)),
        findsOneWidget,
      );
    });

    testWidgets('the shimmer stays gentle — never fully transparent', (tester) async {
      // Opened at three in the morning by somebody holding a baby. A pulse to
      // zero reads as a flash.
      await pump(tester, const HomeSkeleton());
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        final o = tester.widget<Opacity>(
          find.descendant(of: find.byType(Shimmer), matching: find.byType(Opacity)));
        expect(o.opacity, greaterThanOrEqualTo(0.55));
        expect(o.opacity, lessThanOrEqualTo(0.86));
      }
    });

    testWidgets('disposes its controller without complaint', (tester) async {
      await pump(tester, const HomeSkeleton());
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(tester.takeException(), isNull);
    });
  });

  group('the list skeleton', () {
    testWidgets('draws the number of rows asked for', (tester) async {
      await pump(tester, const ListSkeleton(rows: 3));
      expect(find.byType(SkeletonBox), findsNWidgets(3));
    });

    testWidgets('defaults to a screenful rather than one lonely row', (tester) async {
      await pump(tester, const ListSkeleton());
      expect(find.byType(SkeletonBox), findsNWidgets(5));
    });
  });
}
