/// Screen 41 — «Магазин».
///
/// «Для вашего этапа» is a recommendation, and a recommendation that is
/// confident and wrong is worse than a plain list — she is being asked for
/// 39 000 ₸. So the tests are mostly about the reasoning being defensible and
/// about it never claiming a basis it does not have.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/course_prices.dart';
import 'package:fcs_app/domain/my_order.dart' show formatTenge;
import 'package:fcs_app/domain/shop_stage.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/shop/shop_screen.dart';
import 'package:fcs_app/ui/theme.dart';

const l = L10n(AppLocale.ru);

Future<List<String>> pump(
  WidgetTester tester, {
  bool pregnant = false,
  List<int> ages = const [],
  bool canOrder = true,
}) async {
  final orders = <String>[];
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: ShopScreen(
        pregnant: pregnant,
        childAgesMonths: ages,
        onOrder: canOrder ? orders.add : null,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return orders;
}

void main() {
  _overflowSweep();

  group('what to suggest', () {
    test('a walking child puts the tracker first', () {
      final s = stageSuggestion(pregnant: false, childAgesMonths: [24]);
      expect(s.reason, StageReason.childOnTheMove);
      expect(s.items.first, ShopItem.tracker);
    });

    test('a walking child outranks a pregnancy', () {
      // The toddler is the one who can already be somewhere she is not.
      final s = stageSuggestion(pregnant: true, childAgesMonths: [30]);
      expect(s.reason, StageReason.childOnTheMove);
      expect(s.items.first, ShopItem.tracker);
    });

    test('a baby too young to go anywhere is said so, not sold a tracker', () {
      final s = stageSuggestion(pregnant: false, childAgesMonths: [4]);
      expect(s.reason, StageReason.babyTooYoungToTrack);
      expect(s.items.first, isNot(ShopItem.tracker));
    });

    test('expecting leads with the set', () {
      final s = stageSuggestion(pregnant: true, childAgesMonths: []);
      expect(s.reason, StageReason.pregnant);
      expect(s.items.first, ShopItem.bundle);
    });

    test('knowing nothing says so rather than guessing', () {
      // «Заполните профиль» is honest. A confident recommendation built on no
      // data is the one thing this section must not produce.
      final s = stageSuggestion(pregnant: false, childAgesMonths: []);
      expect(s.reason, StageReason.unknown);
    });

    test('the oldest child decides, not the youngest', () {
      // A family with a toddler AND a newborn still needs a tracker.
      final s = stageSuggestion(pregnant: false, childAgesMonths: [2, 36]);
      expect(s.reason, StageReason.childOnTheMove);
    });

    test('every branch offers something', () {
      for (final s in [
        stageSuggestion(pregnant: true, childAgesMonths: []),
        stageSuggestion(pregnant: false, childAgesMonths: []),
        stageSuggestion(pregnant: false, childAgesMonths: [3]),
        stageSuggestion(pregnant: false, childAgesMonths: [40]),
      ]) {
        expect(s.items, isNotEmpty);
      }
    });
  });

  testWidgets('leads with the set and shows what it saves', (tester) async {
    await pump(tester, pregnant: true);
    expect(find.text(l.t('crs_bundle_name')), findsOneWidget);
    expect(find.text(formatTenge(coursePrices.bundleMinor)), findsOneWidget);
    expect(find.text(formatTenge(coursePrices.separatelyMinor)), findsOneWidget);
    expect(
      find.text(l.t('shop_saving',
          {'amount': formatTenge(coursePrices.savingMinor)})),
      findsOneWidget,
    );
  });

  testWidgets('prints the REASON beside the suggestion', (tester) async {
    // A recommendation with no stated basis is indistinguishable from an ad.
    await pump(tester, ages: [30]);
    expect(find.text(l.t('shop_for_your_stage')), findsOneWidget);
    expect(find.text(l.t('shop_why_moving')), findsOneWidget);
  });

  testWidgets('says «заполните профиль» when it knows nothing', (tester) async {
    await pump(tester);
    expect(find.text(l.t('shop_why_unknown')), findsOneWidget);
  });

  testWidgets('does not show the set twice', (tester) async {
    // It is already the hero; repeating it in the list below is the same
    // product twice on one screen.
    await pump(tester, pregnant: true);
    expect(find.text(l.t('crs_bundle_name')), findsOneWidget);
  });

  testWidgets('explains that ordering happens on WhatsApp', (tester) async {
    await pump(tester);
    expect(find.text(l.t('shop_wa_note')), findsOneWidget);
  });

  testWidgets('ordering sends a message naming what she picked',
      (tester) async {
    final orders = await pump(tester, ages: [30]);
    await tester.tap(find.text(l.t('shop_order_bundle')).first);
    await tester.pumpAndSettle();
    expect(orders, hasLength(1));
    expect(orders.first, contains(l.t('crs_bundle_name')));
  });

  testWidgets('every buy button disappears when there is no number',
      (tester) async {
    // A button that opens a chat with nobody, on the screen where money is
    // asked for.
    await pump(tester, pregnant: true, canOrder: false);
    expect(find.text(l.t('shop_order_bundle')), findsNothing);
    // The prices stay — she can still see what it costs.
    expect(find.text(formatTenge(coursePrices.bundleMinor)), findsOneWidget);
  });
}

/// Every state of this screen, at 360 dp, with overflow made fatal.
///
/// A widget test does not fail on a RenderFlex overflow by default — it prints
/// a yellow bar nobody sees in CI. Two of them shipped from this file's own
/// first draft, so the sweep is explicit.
void _overflowSweep() {
  for (final (name, pregnant, ages) in <(String, bool, List<int>)>[
    ('expecting', true, <int>[]),
    ('newborn', false, [2]),
    ('toddler', false, [30]),
    ('nothing known', false, <int>[]),
  ]) {
    testWidgets('$name fits a 360 dp phone', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final prev = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = prev);

      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(L10nScope(
        l10n: l,
        child: MaterialApp(
          theme: FcsTheme.light(AppLocale.ru),
          home: ShopScreen(
            pregnant: pregnant,
            childAgesMonths: ages,
            onOrder: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        errors.where((e) => '${e.exception}'.contains('overflowed')),
        isEmpty,
        reason: '$name overflowed',
      );
    });
  }
}
