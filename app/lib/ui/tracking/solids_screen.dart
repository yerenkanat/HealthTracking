/// Starting solids — the weaning guide, keyed to the child's age.
///
/// The "what to offer now" list follows the age; the readiness signs, the
/// when-to-begin note, and the short avoid list are always shown. The avoid
/// list is set apart in a warm frame — honey before one year and choking
/// hazards are the safety part, not to be lost among the rest.
library;

import 'package:flutter/material.dart';

import '../../domain/solids_guide.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class SolidsScreen extends StatelessWidget {
  final int ageMonths;
  const SolidsScreen({super.key, required this.ageMonths});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final stages = stagesForMonth(ageMonths);
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('sol_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // When to begin.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Palette.teal.withValues(alpha: 0.12), Palette.violet.withValues(alpha: 0.05)],
              ),
              border: Border.all(color: Palette.teal.withValues(alpha: 0.22)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.restaurant_outlined, size: 20, color: Palette.teal),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.t('sol_when_title'),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(l.t('sol_when_body'),
                          style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Signs of readiness.
          _Title(l.t('sol_ready_title')),
          for (final id in readinessSigns) _CheckRow(text: l.t('sol_ready_$id')),
          const SizedBox(height: 18),

          // What to offer now — only when the age resolves to a stage.
          if (stages.isNotEmpty) ...[
            _Title(l.t('sol_stage_title')),
            for (final s in stages) _StageRow(text: l.t('sol_stage_${s.id}')),
            const SizedBox(height: 18),
          ],

          // Not yet — the safety list, set apart.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            decoration: BoxDecoration(
              color: Palette.roseDeep.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Palette.roseDeep.withValues(alpha: 0.26)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('sol_avoid_title').toUpperCase(),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Palette.roseDeep)),
                const SizedBox(height: 10),
                for (final id in avoidFoods)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.cancel_outlined, size: 19, color: Palette.roseDeep),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(l.t('sol_avoid_$id'),
                              style: const TextStyle(fontSize: 13.5, height: 1.42)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(l.t('sol_disclaimer'),
              style: const TextStyle(color: Palette.textDim, fontSize: 12, height: 1.45)),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Palette.textDim)),
      );
}

class _CheckRow extends StatelessWidget {
  final String text;
  const _CheckRow({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_outline, size: 19, color: Palette.teal),
            const SizedBox(width: 11),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.42))),
          ],
        ),
      );
}

class _StageRow extends StatelessWidget {
  final String text;
  const _StageRow({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.eco_outlined, size: 19, color: Palette.violet),
            const SizedBox(width: 11),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.42))),
          ],
        ),
      );
}
