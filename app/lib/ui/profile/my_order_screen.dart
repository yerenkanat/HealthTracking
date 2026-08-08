/// Screen 42 — «Мой заказ».
///
/// «карточка «Курьер везёт сегодня» → таймлайн статусов → состав заказа →
/// «Написать / Отменить».»
///
/// She paid 39 000 ₸ and the app has never mentioned it since. The headline
/// card is the whole screen's job: one sentence answering the question she
/// opened it with. Everything below is for the second question.
library;

import 'package:flutter/material.dart';
import '../../domain/my_order.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../widgets/confirm.dart';

class MyOrderScreen extends StatefulWidget {
  final Future<MyOrders> Function() load;

  /// Returns the server's verdict; `too_late` needs different words from a
  /// failure, because it needs a different next step.
  final Future<({bool ok, String? reason})> Function(MyOrder) onCancel;

  /// Open WhatsApp. Null where no number is configured, and the button is then
  /// absent rather than opening nothing.
  final VoidCallback? onWrite;

  /// Take her to the profile editor — the only fix for a missing phone.
  final VoidCallback? onAddPhone;

  const MyOrderScreen({
    super.key,
    required this.load,
    required this.onCancel,
    this.onWrite,
    this.onAddPhone,
  });

  @override
  State<MyOrderScreen> createState() => _MyOrderScreenState();
}

class _MyOrderScreenState extends State<MyOrderScreen> {
  MyOrders? _data;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
        _data = null;
      });
    }
  }

  Future<void> _cancel(MyOrder o) async {
    final l = L10nScope.of(context);
    final ok = await confirmDestructive(
      context,
      title: l.t('ord_cancel_confirm'),
      message: l.t('ord_cancel_body'),
      confirmLabel: l.t('ord_cancel'),
    );
    if (!ok || !mounted) return;
    final r = await widget.onCancel(o);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.ok
          ? l.t('ord_cancelled_ok')
          // «Курьер уже забрал» is not a failure — it is a fact with a
          // different next step, and saying «не удалось» would send her to
          // press the button again.
          : l.t(r.reason == 'too_late' ? 'ord_cancel_too_late' : 'ord_failed')),
      behavior: SnackBarBehavior.floating,
    ));
    if (r.ok) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final d = _data;

    return Scaffold(
      backgroundColor: Ds.cream,
      appBar: AppBar(title: Text(l.t('ord_title'))),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_failed || d == null)
              _Card(
                title: l.t('ord_failed'),
                body: '',
                action: l.t('day_retry'),
                onAction: _reload,
              )
            // A customer who HAS ordered but never filled in her phone must not
            // be told she has no orders. It is the one of the two states she
            // can actually do something about.
            else if (!d.hasPhone)
              _Card(
                title: l.t('ord_no_phone'),
                body: l.t('ord_no_phone_why'),
                action: widget.onAddPhone == null ? null : l.t('ord_add_phone'),
                onAction: widget.onAddPhone,
              )
            else if (d.orders.isEmpty)
              _Card(title: l.t('ord_none'), body: l.t('ord_none_why'))
            else
              for (final o in d.orders) ...[
                _OrderCard(
                  order: o,
                  onWrite: widget.onWrite,
                  onCancel: () => _cancel(o),
                ),
                const SizedBox(height: 16),
              ],
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final MyOrder order;
  final VoidCallback? onWrite;
  final VoidCallback onCancel;

  const _OrderCard({
    required this.order,
    required this.onCancel,
    this.onWrite,
  });

  String _headline(L10n l) {
    if (order.cancelled) return l.t('ord_now_cancelled');
    return switch (order.currentStep) {
      OrderStep.placed => l.t('ord_now_placed'),
      OrderStep.confirmed => l.t('ord_now_confirmed'),
      OrderStep.shipped => l.t('ord_now_shipped'),
      OrderStep.delivered => l.t('ord_now_delivered'),
      // No current step and not cancelled means a status this build does not
      // know. Saying nothing beats guessing at where somebody's parcel is.
      null => l.t('ord_title'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The headline. Coral while it is moving, muted once it is over.
          Text(
            _headline(l),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: order.cancelled ? Ds.textSecondary : Ds.coralText,
            ),
          ),
          if (order.address.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l.t('ord_deliver_to', {'city': order.city, 'address': order.address}),
              style: const TextStyle(fontSize: 13, color: Ds.textSecondary),
            ),
          ],

          if (!order.cancelled) ...[
            const SizedBox(height: 18),
            for (final s in order.steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      s.done ? Icons.check_circle_rounded : Icons.circle_outlined,
                      size: 19,
                      color: s.done ? Ds.mintText : Ds.chevron,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l.t(s.step.l10nKey),
                      style: TextStyle(
                        fontSize: 14.5,
                        color: s.done ? Ds.text : Ds.textSecondary,
                        fontWeight: s.current ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],

          const SizedBox(height: 18),
          Text(l.t('ord_contents'),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: Ds.text)),
          const SizedBox(height: 8),
          for (final line in order.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      line.color.isEmpty
                          ? line.productName
                          : '${line.productName} · ${line.color}',
                      style: const TextStyle(fontSize: 14, color: Ds.text),
                    ),
                  ),
                  Text(l.t('ord_qty', {'n': line.qty}),
                      style: const TextStyle(
                          fontSize: 13, color: Ds.textSecondary)),
                ],
              ),
            ),
          const Divider(height: 22),
          Row(
            children: [
              Text(l.t('ord_total'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: Ds.text)),
              const Spacer(),
              Text(formatTenge(order.totalMinor),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
            ],
          ),

          const SizedBox(height: 14),
          if (onWrite != null)
            SizedBox(
              width: double.infinity,
              height: DsShape.minTapTarget,
              child: FilledButton.icon(
                onPressed: onWrite,
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: Text(l.t('ord_write')),
              ),
            ),
          // Offered only while the SERVER says it can still be stopped.
          // Cancelling in an app does not turn a van around, and a button that
          // implies otherwise is found out on the doorstep.
          if (order.cancellable)
            SizedBox(
              width: double.infinity,
              height: DsShape.minTapTarget,
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: Ds.coralText),
                child: Text(l.t('ord_cancel')),
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  const _Card({
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(body,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.4, color: Ds.textSecondary)),
          ],
          if (action != null && onAction != null) ...[
            const SizedBox(height: 14),
            FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}
