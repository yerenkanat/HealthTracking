/// WeightCard — the mother's weight trend during pregnancy: the latest reading,
/// the change since the first entry, and a sparkline. "Log weight" opens a small
/// stepper sheet (one entry per day; logging again replaces today's). Pure
/// presentation over the verified [weight] domain.
library;

import 'package:flutter/material.dart';
import '../../domain/health_series.dart' show SeriesPoint, MetricBand;
import '../../domain/weight.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../dashboard/sparkline.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class WeightCard extends StatelessWidget {
  final List<WeightEntry> entries;
  final ValueChanged<double> onLog;
  final double? goalKg;
  final ValueChanged<double?> onSetGoal;
  final VoidCallback? onOpenHistory;
  const WeightCard({super.key, required this.entries, required this.onLog, this.goalKg, required this.onSetGoal, this.onOpenHistory});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final stats = computeWeightStats(entries);
    final points = <SeriesPoint>[
      for (final e in entries)
        if (e.day != null) SeriesPoint(e.day!, e.kg),
    ];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l.t('weight_title').toUpperCase(),
                  style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _openLog(context, l, stats?.latest ?? 65.0),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l.t('weight_log')),
                style: TextButton.styleFrom(foregroundColor: Palette.violet, padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
              ),
            ],
          ),
          if (stats == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l.t('weight_empty'), style: const TextStyle(color: Palette.textDim, fontSize: 13.5)),
            )
          else ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(stats.latest.toStringAsFixed(1),
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 30, fontWeight: FontWeight.w700, height: 1, color: Palette.text)),
                const SizedBox(width: 4),
                const Text('kg', style: TextStyle(color: Palette.textDim, fontSize: 13)),
                const SizedBox(width: 10),
                if (stats.count >= 2) _DeltaBadge(delta: stats.delta),
                const Spacer(),
                if (onOpenHistory != null)
                  InkWell(
                    onTap: onOpenHistory,
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.history_rounded, size: 20, color: Palette.textDim),
                    ),
                  ),
              ],
            ),
            if (points.length >= 2) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: Sparkline(points: points, band: const MetricBand(), color: Palette.violet),
              ),
            ],
            if (weeklyGainRate(entries) case final rate? when weeksSpanned(entries) >= 1) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(rate >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                    size: 15, color: Palette.textDim),
                const SizedBox(width: 6),
                Text(
                  l.t('weight_rate', {
                    'sign': rate >= 0 ? '+' : '−',
                    'kg': rate.abs().toStringAsFixed(1),
                    'weeks': weeksSpanned(entries),
                  }),
                  style: const TextStyle(color: Palette.textDim, fontSize: 12),
                ),
              ]),
            ],
            const SizedBox(height: 10),
            _TargetRow(latest: stats.latest, goalKg: goalKg, onTap: () => _openTarget(context, l, stats.latest)),
          ],
        ],
      ),
    );
  }

  void _openTarget(BuildContext context, L10n l, double latest) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => _WeightTargetSheet(
        seed: goalKg ?? (latest + 5),
        hasGoal: goalKg != null,
        onSave: (kg) {
          onSetGoal(kg);
          Navigator.of(sheetCtx).pop();
        },
        onClear: () {
          onSetGoal(null);
          Navigator.of(sheetCtx).pop();
        },
      ),
    );
  }

  void _openLog(BuildContext context, L10n l, double seed) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => _LogWeightSheet(seed: seed, onSave: (kg) {
        onLog(kg);
        Navigator.of(sheetCtx).pop();
      }),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  final double delta;
  const _DeltaBadge({required this.delta});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final up = delta >= 0;
    final color = up ? Palette.violet : Palette.blue;
    final sign = up ? '+' : '−';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(l.t('weight_delta', {'sign': sign, 'kg': delta.abs().toStringAsFixed(1)}),
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

/// A tappable target row: set a target, or show progress toward it.
class _TargetRow extends StatelessWidget {
  final double latest;
  final double? goalKg;
  final VoidCallback onTap;
  const _TargetRow({required this.latest, required this.goalKg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final Widget content;
    if (goalKg == null) {
      content = Text(l.t('weight_set_target'),
          style: const TextStyle(color: Palette.violet, fontSize: 13, fontWeight: FontWeight.w600));
    } else {
      final reached = weightTargetReached(latest, goalKg!);
      final remaining = weightRemaining(latest, goalKg!).abs();
      content = Row(children: [
        Icon(Icons.flag_rounded, size: 16, color: reached ? Palette.good : Palette.textDim),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            reached
                ? l.t('weight_target_reached')
                : l.t('weight_target_to_go', {'target': goalKg!.toStringAsFixed(1), 'kg': remaining.toStringAsFixed(1)}),
            style: TextStyle(color: reached ? Palette.good : Palette.textDim, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        const Icon(Icons.edit_outlined, size: 14, color: Palette.textDim),
      ]);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      // Keep the row a full 48dp tap target even though the text is short.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(alignment: Alignment.centerLeft, child: content),
      ),
    );
  }
}

/// Set / edit / clear the target weight.
class _WeightTargetSheet extends StatefulWidget {
  final double seed;
  final bool hasGoal;
  final ValueChanged<double> onSave;
  final VoidCallback onClear;
  const _WeightTargetSheet({required this.seed, required this.hasGoal, required this.onSave, required this.onClear});
  @override
  State<_WeightTargetSheet> createState() => _WeightTargetSheetState();
}

class _WeightTargetSheetState extends State<_WeightTargetSheet> {
  late double _kg = widget.seed.clamp(minWeightKg, maxWeightKg).toDouble();

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('weight_target_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.text)),
          const SizedBox(height: 18),
          Center(
            child: Text('${_kg.toStringAsFixed(1)} kg',
                style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 30, fontWeight: FontWeight.w700, color: Palette.text)),
          ),
          Slider(
            value: _kg,
            min: 40,
            max: 130,
            divisions: (130 - 40) * 2,
            label: _kg.toStringAsFixed(1),
            activeColor: Palette.violet,
            onChanged: (v) => setState(() => _kg = double.parse(v.toStringAsFixed(1))),
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (widget.hasGoal)
              TextButton(
                onPressed: widget.onClear,
                style: TextButton.styleFrom(foregroundColor: Palette.danger),
                child: Text(l.t('weight_target_clear')),
              ),
            const Spacer(),
            FilledButton(
              onPressed: () => widget.onSave(double.parse(_kg.toStringAsFixed(1))),
              style: FilledButton.styleFrom(backgroundColor: Palette.violet, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              child: Text(l.t('act_save'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ],
      ),
    );
  }
}

class _LogWeightSheet extends StatefulWidget {
  final double seed;
  final ValueChanged<double> onSave;
  const _LogWeightSheet({required this.seed, required this.onSave});
  @override
  State<_LogWeightSheet> createState() => _LogWeightSheetState();
}

class _LogWeightSheetState extends State<_LogWeightSheet> {
  late double _kg = widget.seed.clamp(minWeightKg, maxWeightKg).toDouble();

  void _bump(double by) => setState(() => _kg = (_kg + by).clamp(minWeightKg, maxWeightKg).toDouble());

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('weight_log_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.text)),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepBtn(icon: Icons.remove_rounded, onTap: () => _bump(-0.1)),
              const SizedBox(width: 20),
              SizedBox(
                width: 130,
                child: Text('${_kg.toStringAsFixed(1)} kg',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 30, fontWeight: FontWeight.w700, color: Palette.text)),
              ),
              const SizedBox(width: 20),
              _StepBtn(icon: Icons.add_rounded, onTap: () => _bump(0.1)),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: _kg,
            min: 40,
            max: 130,
            divisions: (130 - 40) * 2,
            label: _kg.toStringAsFixed(1),
            activeColor: Palette.violet,
            onChanged: (v) => setState(() => _kg = double.parse(v.toStringAsFixed(1))),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onSave(double.parse(_kg.toStringAsFixed(1))),
              style: FilledButton.styleFrom(backgroundColor: Palette.violet, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(l.t('act_save'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Palette.glass,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Palette.border)),
            child: Icon(icon, color: Palette.violet),
          ),
        ),
      );
}
