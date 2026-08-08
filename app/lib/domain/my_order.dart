/// Screen 42 — «Мой заказ».
///
/// What the app knows about an order she has placed. The server decides where
/// the parcel is and whether it can still be called off; this parses and
/// formats, and does not form a second opinion about either — a screen that
/// offered «Отменить» on its own reckoning would offer it after the van left.
library;

/// The four steps of the journey. Mirrors ORDER_STEPS on the server.
///
/// Cancellation is not among them: it is not a later stage of delivery, and
/// drawing it as one implies the parcel is still coming.
enum OrderStep { placed, confirmed, shipped, delivered }

OrderStep? orderStepFrom(String? wire) => switch (wire) {
      'new' => OrderStep.placed,
      'confirmed' => OrderStep.confirmed,
      'shipped' => OrderStep.shipped,
      'delivered' => OrderStep.delivered,
      _ => null,
    };

extension OrderStepKeys on OrderStep {
  String get l10nKey => switch (this) {
        OrderStep.placed => 'ord_step_placed',
        OrderStep.confirmed => 'ord_step_confirmed',
        OrderStep.shipped => 'ord_step_shipped',
        OrderStep.delivered => 'ord_step_delivered',
      };
}

class OrderLine {
  final String productName;
  final String color;
  final int qty;
  final int unitPriceMinor;

  const OrderLine({
    required this.productName,
    required this.color,
    required this.qty,
    required this.unitPriceMinor,
  });

  static OrderLine? fromJson(Map<String, dynamic> j) {
    final name = j['productName'] as String?;
    if (name == null || name.isEmpty) return null;
    return OrderLine(
      productName: name,
      color: (j['color'] as String?) ?? '',
      qty: (j['qty'] as num?)?.toInt() ?? 1,
      unitPriceMinor: (j['unitPriceMinor'] as num?)?.toInt() ?? 0,
    );
  }
}

class OrderProgressStep {
  final OrderStep step;
  final bool done;
  final bool current;
  const OrderProgressStep({
    required this.step,
    required this.done,
    required this.current,
  });
}

class MyOrder {
  final String orderId;
  final bool cancelled;

  /// Whether the SERVER says it can still be called off. Not re-derived here.
  final bool cancellable;
  final List<OrderProgressStep> steps;
  final List<OrderLine> items;
  final int totalMinor;
  final DateTime? createdAt;
  final String city;
  final String address;

  const MyOrder({
    required this.orderId,
    required this.cancelled,
    required this.cancellable,
    required this.steps,
    required this.items,
    required this.totalMinor,
    required this.city,
    required this.address,
    this.createdAt,
  });

  /// The step the parcel is on, or null when it was cancelled — there is no
  /// current step then, which is the point.
  OrderStep? get currentStep {
    for (final s in steps) {
      if (s.current) return s.step;
    }
    return null;
  }

  static MyOrder? fromJson(Map<String, dynamic> j) {
    final id = j['orderId'] as String?;
    if (id == null || id.isEmpty) return null;
    return MyOrder(
      orderId: id,
      cancelled: j['cancelled'] == true,
      cancellable: j['cancellable'] == true,
      steps: [
        for (final s in (j['steps'] as List? ?? const []))
          if (s is Map<String, dynamic>)
            if (orderStepFrom(s['step'] as String?) case final step?)
              OrderProgressStep(
                step: step,
                done: s['done'] == true,
                current: s['current'] == true,
              ),
      ],
      items: [
        for (final i in (j['items'] as List? ?? const []))
          if (i is Map<String, dynamic>)
            if (OrderLine.fromJson(i) case final line?) line,
      ],
      totalMinor: (j['totalMinor'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal(),
      city: (j['city'] as String?) ?? '',
      address: (j['address'] as String?) ?? '',
    );
  }
}

class MyOrders {
  final List<MyOrder> orders;

  /// The number the orders were matched against. Null means there is none on
  /// the profile — a different thing from having ordered nothing, and the only
  /// one of the two she can do something about.
  final String? phone;

  const MyOrders({this.orders = const [], this.phone});

  bool get hasPhone => phone != null && phone!.isNotEmpty;

  static MyOrders fromJson(Map<String, dynamic> j) => MyOrders(
        phone: (j['phone'] as String?)?.isEmpty ?? true ? null : j['phone'] as String,
        orders: [
          for (final o in (j['orders'] as List? ?? const []))
            if (o is Map<String, dynamic>)
              if (MyOrder.fromJson(o) case final v?) v,
        ],
      );
}

/// A NON-BREAKING space between the thousands and before the ₸.
///
/// Written as an escape rather than typed, because typed it is invisible: an
/// ordinary space and this one are indistinguishable in a diff AND in a
/// failing test message, which is how an hour goes into
/// "expected 39 000 ₸, got 39 000 ₸". Money must not wrap between its digits
/// or away from its currency, so this is the right character — it just has to
/// be one somebody can see in the source.
const nbsp = '\u00A0';

/// «39 000 ₸» — no decimal part, because nothing here is ever priced in tiyn.
String formatTenge(int minor) {
  final whole = (minor / 100).round();
  final digits = whole.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(nbsp);
    out.write(digits[i]);
  }
  return '$out$nbsp₸';
}
