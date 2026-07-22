/// The hospital-bag checklist screen — tick off what's packed.
///
/// Stateless over (checked, onToggle): the caller pushes it inside a
/// StreamBuilder on the controller's changes, so a tick persists and the whole
/// screen — the progress bar and the count — rebuilds from the fresh set. The
/// intro doubles as the caveat: hospitals hand out their own lists.
library;

import 'package:flutter/material.dart';

import '../../domain/hospital_bag.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class HospitalBagScreen extends StatelessWidget {
  final Set<String> checked;
  final ValueChanged<String> onToggle;
  const HospitalBagScreen({super.key, required this.checked, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final packed = packedCount(checked);
    final done = isFullyPacked(checked);

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('bag_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Progress.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Palette.rose.withValues(alpha: 0.14), Palette.violet.withValues(alpha: 0.05)],
              ),
              border: Border.all(color: Palette.rose.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(done ? Icons.check_circle_rounded : Icons.luggage_outlined,
                        size: 20, color: done ? Palette.teal : Palette.roseDeep),
                    const SizedBox(width: 10),
                    Text(
                      done ? l.t('bag_done') : l.t('bag_packed', {'n': packed, 'total': hospitalBagTotal}),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: packedFraction(checked),
                    minHeight: 7,
                    backgroundColor: Palette.rose.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(done ? Palette.teal : Palette.roseDeep),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(l.t('bag_intro'),
              style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.45)),
          const SizedBox(height: 16),

          for (final category in BagCategory.values) ...[
            _CategoryTitle(l.t('bag_cat_${category.name}')),
            for (final item in itemsInCategory(category))
              _ItemRow(
                label: l.t('bag_${item.id}'),
                packed: checked.contains(item.id),
                onTap: () => onToggle(item.id),
              ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _CategoryTitle extends StatelessWidget {
  final String text;
  const _CategoryTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Palette.textDim)),
      );
}

class _ItemRow extends StatelessWidget {
  final String label;
  final bool packed;
  final VoidCallback onTap;
  const _ItemRow({required this.label, required this.packed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Row(
            children: [
              Icon(
                packed ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: packed ? Palette.teal : Palette.border,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: packed ? Palette.textDim : Palette.text,
                    decoration: packed ? TextDecoration.lineThrough : null,
                    decorationColor: Palette.textDim,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
