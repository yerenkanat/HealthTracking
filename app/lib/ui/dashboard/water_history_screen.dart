/// WaterHistoryScreen — the last 7 days of hydration: a streak header (consecutive
/// days meeting the goal) and a bar per day (green when the day met its goal).
/// Pure presentation over the verified [hydration] helpers.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../domain/hydration.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class WaterHistoryScreen extends StatelessWidget {
  final List<WaterDay> week; // oldest-first
  final int goal;
  final int streak;

  /// When supplied, each day becomes correctable — you rarely log water the
  /// moment you drink it, so yesterday's count is often wrong. The screen then
  /// re-reads from the controller so edits show immediately.
  final AppController? controller;
  final DateTime Function()? _nowFn;
  const WaterHistoryScreen({
    super.key,
    required this.week,
    required this.goal,
    required this.streak,
    this.controller,
    DateTime Function()? now,
  }) : _nowFn = now;

  DateTime _now() => (_nowFn ?? DateTime.now)();

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) return _build(context, week, goal, streak);
    return StreamBuilder<void>(
      stream: c.changes,
      builder: (ctx, _) => _build(
        ctx,
        lastNDays(c.waterLog, _now(), 7),
        c.waterGoal,
        waterStreak(c.waterLog, _now(), c.waterGoal),
      ),
    );
  }

  Widget _build(BuildContext context, List<WaterDay> week, int goal, int streak) {
    final l = L10nScope.of(context);
    final maxGlasses = [goal, for (final d in week) d.glasses].reduce((a, b) => a > b ? a : b).clamp(1, 999);
    final total = week.fold<int>(0, (s, d) => s + d.glasses);
    final metDays = week.where((d) => hydrationGoalMet(d.glasses, goal)).length;

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('water_week_title'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _StreakCard(streak: streak),
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.t('water_week_bars').toUpperCase(),
                      style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 150,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final d in week) Expanded(child: _DayBar(day: d, goal: goal, maxGlasses: maxGlasses)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _StatTile(value: '$total', label: l.t('water_week_total'))),
                const SizedBox(width: 12),
                Expanded(child: _StatTile(value: '$metDays/7', label: l.t('water_week_met'))),
              ],
            ),
            if (controller != null) ...[
              const SizedBox(height: 14),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('water_correct').toUpperCase(),
                        style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                    const SizedBox(height: 6),
                    // Newest first — the day you're most likely fixing.
                    for (final d in week.reversed)
                      _EditableDayRow(
                        day: d,
                        goal: goal,
                        onAdjust: (by) => controller!.addWater(d.day, by),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One correctable day: the date, its count, and +/- controls.
class _EditableDayRow extends StatelessWidget {
  final WaterDay day;
  final int goal;
  final ValueChanged<int> onAdjust;
  const _EditableDayRow({required this.day, required this.goal, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ml = MaterialLocalizations.of(context);
    final met = hydrationGoalMet(day.glasses, goal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(ml.formatMediumDate(day.day),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
            color: Palette.textDim,
            tooltip: l.t('water_remove'),
            // Nothing to take away from a day with no glasses logged.
            onPressed: day.glasses == 0 ? null : () => onAdjust(-1),
          ),
          SizedBox(
            width: 34,
            child: Text('${day.glasses}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: met ? Palette.good : Palette.text,
                )),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
            color: Palette.blue,
            tooltip: l.t('water_add'),
            onPressed: () => onAdjust(1),
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final int streak;
  const _StreakCard({required this.streak});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final active = streak > 0;
    final accent = active ? Palette.blue : Palette.textDim;
    return GlassCard(
      glow: active ? Palette.blue : null,
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              gradient: active ? const LinearGradient(colors: [Palette.blue, Palette.teal]) : null,
              color: active ? null : Palette.glass,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.local_fire_department_rounded, color: active ? Colors.white : Palette.textDim, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  streak == 0 ? l.t('water_streak_none') : l.t('water_streak', {'n': streak}),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: accent),
                ),
                const SizedBox(height: 2),
                Text(l.t('water_streak_sub'), style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final WaterDay day;
  final int goal;
  final int maxGlasses;
  const _DayBar({required this.day, required this.goal, required this.maxGlasses});

  @override
  Widget build(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    final met = hydrationGoalMet(day.glasses, goal);
    final frac = (day.glasses / maxGlasses).clamp(0.0, 1.0);
    final color = met ? Palette.good : Palette.blue;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('${day.glasses}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: day.glasses == 0 ? Palette.textDim : color)),
          const SizedBox(height: 4),
          Container(
            height: (100 * frac).clamp(3.0, 100.0),
            decoration: BoxDecoration(
              color: day.glasses == 0 ? Palette.border : color.withValues(alpha: met ? 1 : 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 6),
          Text(ml.narrowWeekdays[day.day.weekday % 7],
              style: const TextStyle(color: Palette.textDim, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  const _StatTile({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 24, fontWeight: FontWeight.w700, color: Palette.text)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, fontSize: 12)),
          ],
        ),
      );
}
