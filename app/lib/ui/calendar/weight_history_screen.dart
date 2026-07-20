/// WeightHistoryScreen — the full weight log, newest first, each entry deletable
/// (with confirm). Pure presentation over the passed entries; the caller persists
/// deletions.
library;

import 'package:flutter/material.dart';
import '../../domain/weight.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
import '../widgets/glass.dart';

class WeightHistoryScreen extends StatelessWidget {
  final List<WeightEntry> entries; // any order; shown newest-first
  final void Function(String dateKey) onDelete;
  const WeightHistoryScreen({super.key, required this.entries, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // Newest first; keep the chronological neighbour for the per-entry delta.
    final chrono = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    final ordered = chrono.reversed.toList();

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('weight_history_title'))),
        body: ordered.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(l.t('weight_empty'),
                      textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: ordered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final e = ordered[i];
                  // Delta vs the previous (older) chronological entry.
                  final idx = chrono.indexWhere((x) => x.date == e.date);
                  final prev = idx > 0 ? chrono[idx - 1] : null;
                  final delta = prev == null ? null : e.kg - prev.kg;
                  return _WeightRow(entry: e, delta: delta, onDelete: () => _confirmDelete(context, e));
                },
              ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WeightEntry e) async {
    final l = L10nScope.of(context);
    final ok = await confirmDestructive(
      context,
      title: l.t('weight_delete_title'),
      message: l.t('weight_delete_body', {'kg': e.kg.toStringAsFixed(1)}),
      confirmLabel: l.t('act_remove'),
    );
    if (ok) onDelete(e.date);
  }
}

class _WeightRow extends StatelessWidget {
  final WeightEntry entry;
  final double? delta;
  final VoidCallback onDelete;
  const _WeightRow({required this.entry, required this.delta, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ml = MaterialLocalizations.of(context);
    final date = entry.day;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Text('${entry.kg.toStringAsFixed(1)} ${l.t('unit_kg')}',
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 17, fontWeight: FontWeight.w700, color: Palette.text)),
          const SizedBox(width: 12),
          if (delta != null && delta!.abs() >= 0.05)
            Text('${delta! >= 0 ? '+' : '−'}${delta!.abs().toStringAsFixed(1)}',
                style: TextStyle(color: delta! >= 0 ? Palette.violet : Palette.blue, fontSize: 12.5, fontWeight: FontWeight.w700)),
          // Expanded, not Spacer + a rigid Text: a formatted date has no fixed
          // width — it varies by locale and by month name — and with a Spacer
          // eating the slack there was nothing left for it to shrink into. The
          // row overflowed by 72px on the right at 360dp, in every language.
          Expanded(
            child: Text(
              date == null ? entry.date : ml.formatMediumDate(date),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Palette.textDim, fontSize: 12.5),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: Palette.textDim),
            tooltip: l.t('act_remove'),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
