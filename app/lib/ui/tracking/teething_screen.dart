/// Teething — the timeline, the signs, what helps, and what teething is NOT.
///
/// The tooth group most likely erupting around the child's age is highlighted,
/// so the timeline reads as "where you are" rather than an abstract table. The
/// "this isn't teething" block is set apart because it corrects a real, harmful
/// misconception — a high fever blamed on teeth while an illness is missed.
library;

import 'package:flutter/material.dart';

import '../../domain/teething.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class TeethingScreen extends StatelessWidget {
  final int ageMonths;
  const TeethingScreen({super.key, required this.ageMonths});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final current = toothGroupForAge(ageMonths);

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('teeth_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(l.t('teeth_intro'),
              style: const TextStyle(fontSize: 13.5, height: 1.5, color: Palette.text)),
          const SizedBox(height: 18),

          // The timeline, with the current group lit.
          _Title(l.t('teeth_timeline_title')),
          for (final g in teethingTimeline)
            _ToothRow(
              name: l.t('teeth_${g.id}'),
              range: l.t('teeth_age_range', {'from': g.fromMonth, 'to': g.toMonth}),
              current: current?.id == g.id,
            ),
          const SizedBox(height: 18),

          // Signs.
          _Title(l.t('teeth_signs_title')),
          for (final id in teethingSigns) _Bullet(text: l.t('teeth_sign_$id'), colour: Palette.violet),
          const SizedBox(height: 18),

          // What helps.
          _Title(l.t('teeth_soothe_title')),
          for (final id in teethingSoothe) _CheckRow(text: l.t('teeth_soothe_$id')),
          const SizedBox(height: 18),

          // Not teething — set apart.
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
                Row(children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: Palette.roseDeep),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l.t('teeth_not_title'),
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Palette.roseDeep)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(l.t('teeth_not_intro'),
                    style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4)),
                const SizedBox(height: 10),
                for (final id in teethingNot)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 6, height: 6,
                            decoration: const BoxDecoration(color: Palette.roseDeep, shape: BoxShape.circle),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(l.t('teeth_not_$id'), style: const TextStyle(fontSize: 13.5, height: 1.4))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(l.t('teeth_disclaimer'),
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

class _ToothRow extends StatelessWidget {
  final String name;
  final String range;
  final bool current;
  const _ToothRow({required this.name, required this.range, required this.current});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: current ? Palette.violet.withValues(alpha: 0.10) : Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: current ? Palette.violet.withValues(alpha: 0.4) : Palette.border),
      ),
      child: Row(
        children: [
          Icon(current ? Icons.brightness_1 : Icons.brightness_1_outlined,
              size: 10, color: current ? Palette.violet : Palette.border),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                style: TextStyle(fontSize: 13.5, fontWeight: current ? FontWeight.w700 : FontWeight.w600)),
          ),
          Text(range,
              style: const TextStyle(
                  fontFamily: 'JetBrainsMono', fontSize: 12.5, fontWeight: FontWeight.w700, color: Palette.textDim)),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  final Color colour;
  const _Bullet({required this.text, required this.colour});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 11, left: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(width: 6, height: 6, decoration: BoxDecoration(color: colour, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 11),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.42))),
          ],
        ),
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
