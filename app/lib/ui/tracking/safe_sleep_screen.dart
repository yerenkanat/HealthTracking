/// Safe infant sleep — the reduce-the-risk guidance, one tap from the newborn
/// log.
///
/// Two lists, visibly different: what helps (calm, affirmative) and what to
/// avoid (set apart in a warm frame). Short by design — a wall of rules is one
/// nobody reads — and led by the one-line summary a tired parent can hold.
library;

import 'package:flutter/material.dart';

import '../../domain/safe_sleep.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class SafeSleepScreen extends StatelessWidget {
  const SafeSleepScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('ss_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // The summary first — it is the whole thing in one line.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Palette.violet.withValues(alpha: 0.12), Palette.teal.withValues(alpha: 0.06)],
              ),
              border: Border.all(color: Palette.violet.withValues(alpha: 0.20)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.nightlight_round, size: 20, color: Palette.violet),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(l.t('ss_intro'),
                      style: const TextStyle(fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // What helps.
          _Title(l.t('ss_do_title')),
          for (final r in sleepDos) _RuleRow(id: r.id, follow: true),
          const SizedBox(height: 18),

          // What to avoid, set apart.
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
                Text(l.t('ss_avoid_title').toUpperCase(),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Palette.roseDeep)),
                const SizedBox(height: 10),
                for (final r in sleepAvoids) _RuleRow(id: r.id, follow: false),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(l.t('ss_disclaimer'),
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

class _RuleRow extends StatelessWidget {
  final String id;
  final bool follow;
  const _RuleRow({required this.id, required this.follow});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final colour = follow ? Palette.teal : Palette.roseDeep;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(follow ? Icons.check_circle_outline : Icons.cancel_outlined, size: 19, color: colour),
          const SizedBox(width: 11),
          Expanded(
            child: Text(l.t('ss_$id'),
                style: const TextStyle(fontSize: 13.5, height: 1.42)),
          ),
        ],
      ),
    );
  }
}
