/// WaterCard — the day's hydration at a glance: a progress ring (glasses vs goal),
/// a big "add a glass" button, an undo when there's something to undo, and a
/// tappable goal that opens a small target picker. Pure presentation over the
/// verified [hydration] helpers; the controller owns the count + goal.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../domain/hydration.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class WaterCard extends StatelessWidget {
  final int count;
  final int goal;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final ValueChanged<int> onSetGoal;
  final VoidCallback? onOpenHistory;
  const WaterCard({
    super.key,
    required this.count,
    required this.goal,
    required this.onAdd,
    required this.onRemove,
    required this.onSetGoal,
    this.onOpenHistory,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final fraction = hydrationFraction(count, goal);
    final met = hydrationGoalMet(count, goal);
    final accent = met ? Palette.good : Palette.blue;

    return Semantics(
      label: '${l.t('water_title')}: $count / $goal',
      child: GlassCard(
        glow: accent,
        child: Row(
          children: [
            InkWell(
              onTap: onOpenHistory,
              customBorder: const CircleBorder(),
              child: MetricRing(
                fraction: fraction,
                gradient: met
                    ? const LinearGradient(colors: [Palette.good, Palette.teal])
                    : const LinearGradient(colors: [Palette.blue, Palette.teal]),
                size: 66,
                stroke: 7,
                center: Icon(met ? Icons.check_rounded : Icons.water_drop_rounded, color: accent, size: 24),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.t('water_title'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.text)),
                  const SizedBox(height: 2),
                  InkWell(
                    onTap: () => _openGoalSheet(context, l),
                    borderRadius: BorderRadius.circular(6),
                    // 48dp minimum: this opens the goal sheet, so it needs a
                    // real tap target despite reading as a subtitle.
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        met ? l.t('water_goal_met') : l.t('water_progress', {'n': count, 'goal': goal}),
                        style: const TextStyle(color: Palette.textDim, fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (count > 0)
              IconButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onRemove();
                },
                icon: const Icon(Icons.remove_circle_outline_rounded, color: Palette.textDim),
                tooltip: l.t('water_remove'),
              ),
            _AddGlassButton(onAdd: onAdd),
          ],
        ),
      ),
    );
  }

  void _openGoalSheet(BuildContext context, L10n l) {
    var goalV = goal.toDouble();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('water_goal_title'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.text)),
              const SizedBox(height: 6),
              Text(l.t('water_goal_hint'), style: const TextStyle(color: Palette.textDim, fontSize: 13)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Slider(
                    value: goalV,
                    min: minWaterGoal.toDouble(),
                    max: maxWaterGoal.toDouble(),
                    divisions: maxWaterGoal - minWaterGoal,
                    label: '${goalV.round()}',
                    activeColor: Palette.blue,
                    onChanged: (v) => setSheet(() => goalV = v),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text('${goalV.round()}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontWeight: FontWeight.w700, color: Palette.blue)),
                ),
              ]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    onSetGoal(goalV.round());
                    Navigator.of(sheetCtx).pop();
                  },
                  style: FilledButton.styleFrom(backgroundColor: Palette.blue),
                  child: Text(l.t('act_save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddGlassButton extends StatelessWidget {
  final VoidCallback onAdd;
  const _AddGlassButton({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Semantics(
      button: true,
      label: l.t('water_add'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            onAdd();
          },
          customBorder: const CircleBorder(),
          child: Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Palette.blue, Palette.teal]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
