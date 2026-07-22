/// "When your child is unwell" — comfort measures and the red flags that mean
/// call now.
///
/// Two halves, like the pregnancy and postpartum guides: calm "what helps" up
/// top, the warning list set apart below so the reassurance never softens it.
/// For a baby under three months a fever banner leads, because at that age the
/// age alone changes what a parent should do.
library;

import 'package:flutter/material.dart';

import '../../domain/child_illness.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class ChildIllnessScreen extends StatelessWidget {
  final int ageMonths;
  const ChildIllnessScreen({super.key, required this.ageMonths});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final young = feverIsUrgentForAge(ageMonths);

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('ill_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(l.t('ill_intro'),
              style: const TextStyle(fontSize: 13.5, height: 1.5, color: Palette.text)),
          const SizedBox(height: 18),

          // The one thing age alone decides.
          if (young) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Palette.roseDeep.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Palette.roseDeep.withValues(alpha: 0.32)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.priority_high_rounded, size: 19, color: Palette.roseDeep),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.t('ill_young_title'),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Palette.roseDeep)),
                        const SizedBox(height: 3),
                        Text(l.t('ill_young_body'),
                            style: const TextStyle(fontSize: 13, height: 1.45)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // What helps at home.
          _Title(l.t('ill_care_title')),
          for (final id in illnessCare) _CareRow(text: l.t('ill_care_$id')),
          const SizedBox(height: 18),

          // When to get help — set apart.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            decoration: BoxDecoration(
              color: Palette.roseDeep.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Palette.roseDeep.withValues(alpha: 0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 19, color: Palette.roseDeep),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l.t('ill_warn_title'),
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Palette.roseDeep)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(l.t('ill_warn_intro'),
                    style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4)),
                const SizedBox(height: 10),
                for (final id in illnessWarnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(color: Palette.roseDeep, shape: BoxShape.circle),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(l.t('ill_warn_$id'),
                              style: const TextStyle(fontSize: 13.5, height: 1.4)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(l.t('ill_disclaimer'),
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

class _CareRow extends StatelessWidget {
  final String text;
  const _CareRow({required this.text});
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
