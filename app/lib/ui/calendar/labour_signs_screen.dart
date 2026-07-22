/// Signs of labour — what tells you it's near, and when to go in.
///
/// The reference companion to the contraction timer. Two halves like the other
/// guides: the calm "labour may be starting" list, and the "go in or call" list
/// set apart in its own frame, pointing outward to the maternity unit.
library;

import 'package:flutter/material.dart';

import '../../domain/labour_signs.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class LabourSignsScreen extends StatelessWidget {
  const LabourSignsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('lab_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(l.t('lab_intro'),
              style: const TextStyle(fontSize: 13.5, height: 1.5, color: Palette.text)),
          const SizedBox(height: 18),

          // Labour may be starting.
          _Title(l.t('lab_signs_title')),
          for (final id in labourSigns) _SignRow(text: l.t('lab_sign_$id')),
          const SizedBox(height: 18),

          // When to go in — set apart.
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
                    const Icon(Icons.local_hospital_outlined, size: 19, color: Palette.roseDeep),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l.t('lab_go_title'),
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Palette.roseDeep)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(l.t('lab_go_intro'),
                    style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4)),
                const SizedBox(height: 10),
                for (final id in labourGoIn)
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
                          child: Text(l.t('lab_go_$id'),
                              style: const TextStyle(fontSize: 13.5, height: 1.4)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(l.t('lab_disclaimer'),
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

class _SignRow extends StatelessWidget {
  final String text;
  const _SignRow({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.pregnant_woman_rounded, size: 19, color: Palette.violet),
            const SizedBox(width: 11),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.42))),
          ],
        ),
      );
}
