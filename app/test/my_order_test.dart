/// Screen 42 — «Мой заказ».
///
/// She paid 39 000 ₸ and the app has never mentioned it since. The tests that
/// matter are the ways this screen can be worse than nothing: telling a
/// customer who HAS ordered that she has no orders, and offering to cancel
/// something that is already on a van.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/my_order.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/profile/my_order_screen.dart';
import 'package:fcs_app/ui/theme.dart';

const l = L10n(AppLocale.ru);

MyOrder orderAt(OrderStep at, {bool cancelled = false, bool? cancellable}) {
  const all = OrderStep.values;
  final idx = all.indexOf(at);
  return MyOrder(
    orderId: 'o1',
    cancelled: cancelled,
    cancellable: cancellable ?? (at == OrderStep.placed || at == OrderStep.confirmed),
    steps: [
      for (var i = 0; i < all.length; i++)
        OrderProgressStep(
          step: all[i],
          done: !cancelled && i <= idx,
          current: !cancelled && i == idx,
        ),
    ],
    items: const [
      OrderLine(
          productName: 'Комплект', color: 'Розовый', qty: 1, unitPriceMinor: 3900000),
    ],
    totalMinor: 3900000,
    city: 'Алматы',
    address: 'ул. Абая 1',
  );
}

Future<List<String>> pump(
  WidgetTester tester, {
  MyOrders? data,
  bool fail = false,
  ({bool ok, String? reason}) cancelResult = (ok: true, reason: null),
  bool withWrite = true,
  bool withAddPhone = true,
}) async {
  final cancelled = <String>[];
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: MyOrderScreen(
        load: () async {
          if (fail) throw Exception('offline');
          return data ?? MyOrders(phone: '77073452244', orders: [orderAt(OrderStep.placed)]);
        },
        onCancel: (o) async {
          cancelled.add(o.orderId);
          return cancelResult;
        },
        onWrite: withWrite ? () {} : null,
        onAddPhone: withAddPhone ? () {} : null,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return cancelled;
}

void main() {
  group('money', () {
    test('groups the thousands the way both languages write them', () {
      // Built from the same constant. Typing the separator here compares two
      // characters nobody can tell apart in the failure message.
      expect(formatTenge(3900000), '39${nbsp}000${nbsp}₸');
      expect(formatTenge(490000), '4${nbsp}900${nbsp}₸');
      expect(formatTenge(0), '0${nbsp}₸');
    });
  });

  group('parsing', () {
    test('drops a status this build does not know', () {
      // A server newer than the app. Guessing where somebody's parcel is would
      // be worse than saying nothing.
      final o = MyOrder.fromJson({
        'orderId': 'x',
        'steps': [
          {'step': 'teleported', 'done': true, 'current': true},
          {'step': 'confirmed', 'done': true, 'current': false},
        ],
      })!;
      expect(o.steps, hasLength(1));
      expect(o.steps.single.step, OrderStep.confirmed);
    });

    test('a cancelled order has no current step', () {
      final o = orderAt(OrderStep.confirmed, cancelled: true);
      expect(o.currentStep, isNull);
    });

    test('an empty phone reads as no phone', () {
      expect(MyOrders.fromJson({'phone': '', 'orders': []}).hasPhone, isFalse);
      expect(MyOrders.fromJson({'phone': '77001', 'orders': []}).hasPhone, isTrue);
    });
  });

  testWidgets('leads with where the parcel is', (tester) async {
    await pump(tester, data: MyOrders(
      phone: '7700', orders: [orderAt(OrderStep.shipped)]));
    expect(find.text(l.t('ord_now_shipped')), findsOneWidget);
    // And the timeline behind it.
    expect(find.text(l.t('ord_step_placed')), findsOneWidget);
    expect(find.text(l.t('ord_step_delivered')), findsOneWidget);
  });

  testWidgets('shows what is in it and what it cost', (tester) async {
    await pump(tester);
    expect(find.text(l.t('ord_contents')), findsOneWidget);
    expect(find.textContaining('Комплект'), findsOneWidget);
    expect(find.text(formatTenge(3900000)), findsOneWidget);
  });

  testWidgets('a cancelled order draws no timeline', (tester) async {
    // Steps ticking along under «Заказ отменён» would imply it is still
    // coming.
    await pump(tester, data: MyOrders(
      phone: '7700', orders: [orderAt(OrderStep.confirmed, cancelled: true)]));
    expect(find.text(l.t('ord_now_cancelled')), findsOneWidget);
    expect(find.text(l.t('ord_step_placed')), findsNothing);
  });

  group('«Отменить»', () {
    testWidgets('is offered before it ships', (tester) async {
      await pump(tester, data: MyOrders(
        phone: '7700', orders: [orderAt(OrderStep.confirmed)]));
      expect(find.text(l.t('ord_cancel')), findsOneWidget);
    });

    testWidgets('is gone once a courier has it', (tester) async {
      // Cancelling in an app does not turn a van around. A button that implies
      // otherwise is found out on the doorstep.
      await pump(tester, data: MyOrders(
        phone: '7700', orders: [orderAt(OrderStep.shipped)]));
      expect(find.text(l.t('ord_cancel')), findsNothing);
    });

    testWidgets('asks before it does anything', (tester) async {
      final calls = await pump(tester);
      await tester.tap(find.text(l.t('ord_cancel')));
      await tester.pumpAndSettle();
      expect(find.text(l.t('ord_cancel_confirm')), findsOneWidget);
      expect(calls, isEmpty);
    });

    testWidgets('cancelling the dialog cancels nothing', (tester) async {
      final calls = await pump(tester);
      await tester.tap(find.text(l.t('ord_cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.t('act_cancel')));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });

    testWidgets('confirming sends it', (tester) async {
      final calls = await pump(tester);
      await tester.tap(find.text(l.t('ord_cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l.t('ord_cancel')).last);
      await tester.pumpAndSettle();
      expect(calls, ['o1']);
      expect(find.text(l.t('ord_cancelled_ok')), findsOneWidget);
    });

    testWidgets('«уже забрал» is not reported as a failure', (tester) async {
      // It is a fact with a different next step. «Не удалось» would send her
      // to press the button again.
      await pump(tester, cancelResult: (ok: false, reason: 'too_late'));
      await tester.tap(find.text(l.t('ord_cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l.t('ord_cancel')).last);
      await tester.pumpAndSettle();
      expect(find.text(l.t('ord_cancel_too_late')), findsOneWidget);
      expect(find.text(l.t('ord_cancelled_ok')), findsNothing);
    });
  });

  group('when there is nothing to show', () {
    testWidgets('no phone is NOT «у вас нет заказов»', (tester) async {
      // A customer who has ordered but never filled in her number would be
      // told she has no orders — the one of the two states she can act on.
      await pump(tester, data: const MyOrders(phone: null, orders: []));
      expect(find.text(l.t('ord_no_phone')), findsOneWidget);
      expect(find.text(l.t('ord_none')), findsNothing);
      expect(find.text(l.t('ord_add_phone')), findsOneWidget);
    });

    testWidgets('no orders, with a phone, says so plainly', (tester) async {
      await pump(tester, data: const MyOrders(phone: '7700', orders: []));
      expect(find.text(l.t('ord_none')), findsOneWidget);
      expect(find.text(l.t('ord_none_why')), findsOneWidget);
    });

    testWidgets('a failed load is not an empty list', (tester) async {
      // «Заказов пока нет» over a request that failed is the worst message
      // this screen could print.
      await pump(tester, fail: true);
      expect(find.text(l.t('ord_failed')), findsOneWidget);
      expect(find.text(l.t('ord_none')), findsNothing);
      expect(find.text(l.t('ord_no_phone')), findsNothing);
    });
  });

  testWidgets('«Написать» is absent when no number is configured',
      (tester) async {
    // A contact button that opens nothing, on the screen somebody reaches when
    // a delivery has gone wrong.
    await pump(tester, withWrite: false);
    expect(find.text(l.t('ord_write')), findsNothing);
  });
}
