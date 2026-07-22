/// The home-safety (babyproofing) checklist — grows with the child, tracked and
/// remembered across restarts.
///
/// Stateless over (ageMonths, done, onToggle); the caller pushes it inside a
/// StreamBuilder on the controller's changes, so a tick persists and the
/// progress rebuilds. Tasks are grouped by the stage they become relevant, and
/// only the stages the child has reached are shown — no wall of things that do
/// not apply yet.
library;

import 'package:flutter/material.dart';

import '../../domain/home_safety.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class HomeSafetyScreen extends StatelessWidget {
  final int ageMonths;
  final Set<String> done;
  final ValueChanged<String> onToggle;
  const HomeSafetyScreen({
    super.key,
    required this.ageMonths,
    required this.done,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final count = homeSafetyDoneCount(done, ageMonths);
    final total = homeSafetyRelevantTotal(ageMonths);
    final allDone = total > 0 && count == total;

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('hs_title'))),
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
                colors: [Palette.teal.withValues(alpha: 0.12), Palette.violet.withValues(alpha: 0.05)],
              ),
              border: Border.all(color: Palette.teal.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(allDone ? Icons.verified_rounded : Icons.shield_outlined,
                      size: 20, color: allDone ? Palette.teal : Palette.violet),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(allDone ? l.t('hs_all_done') : l.t('hs_progress', {'n': count, 'total': total}),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ]),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: homeSafetyFraction(done, ageMonths),
                    minHeight: 7,
                    backgroundColor: Palette.teal.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(allDone ? Palette.teal : Palette.violet),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(l.t('hs_intro'),
              style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.45)),
          const SizedBox(height: 16),

          for (final stage in SafetyStage.values)
            if (tasksInStage(stage, ageMonths).isNotEmpty) ...[
              _StageTitle(l.t('hs_stage_${stage.name}')),
              for (final task in tasksInStage(stage, ageMonths))
                _TaskRow(
                  label: l.t('hs_${task.id}'),
                  done: done.contains(task.id),
                  onTap: () => onToggle(task.id),
                ),
              const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }
}

class _StageTitle extends StatelessWidget {
  final String text;
  const _StageTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: Palette.textDim)),
      );
}

class _TaskRow extends StatelessWidget {
  final String label;
  final bool done;
  final VoidCallback onTap;
  const _TaskRow({required this.label, required this.done, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          // A 48dp minimum so the whole row is a comfortable tap target, not
          // just the 22dp tick — the accessibility guideline the home-safety
          // checklist used to miss.
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: done ? Palette.teal : Palette.border,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: done ? Palette.textDim : Palette.text,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: Palette.textDim,
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
