/// Sleep detail — a per-night stacked-stage bar chart plus aggregate stats.
/// Opened by tapping the dashboard Sleep card.
library;

import 'package:flutter/material.dart';
import '../../domain/sleep.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'sleep_card.dart';

class SleepDetailScreen extends StatelessWidget {
  final List<SleepSummary> nights;

  /// Opens the hand-entry sheet. Null when logging isn't offered at all.
  final VoidCallback? onLog;
  const SleepDetailScreen({super.key, required this.nights, this.onLog});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ordered = sortedByNight(nights);
    final stats = sleepStats(nights);
    final consistency = sleepConsistency(nights);

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(l.t('sleep_title')),
          actions: [
            if (onLog != null)
              IconButton(
                onPressed: onLog,
                icon: const Icon(Icons.add_rounded),
                tooltip: l.t('sleep_log_title'),
              ),
          ],
        ),
        body: ordered.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(l.t('sleep_empty'),
                      textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  if (stats != null) _StatsHeader(stats: stats),
                  if (consistency.level != SleepConsistency.insufficient) ...[
                    const SizedBox(height: 14),
                    _ConsistencyCard(insight: consistency),
                  ],
                  const SizedBox(height: 16),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.t('sleep_recent_nights').toUpperCase(),
                            style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                        const SizedBox(height: 14),
                        _NightBars(nights: ordered),
                        const SizedBox(height: 16),
                        Wrap(spacing: 16, runSpacing: 6, children: [
                          _Legend(color: sleepDeep, label: l.t('sleep_deep')),
                          _Legend(color: sleepRem, label: l.t('sleep_rem')),
                          _Legend(color: sleepLight, label: l.t('sleep_light')),
                          _Legend(color: sleepAwake, label: l.t('sleep_awake')),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "Your sleep is consistent / varies / is irregular" from night-to-night
/// duration spread — coloured by level.
class _ConsistencyCard extends StatelessWidget {
  final SleepConsistencyInsight insight;
  const _ConsistencyCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final (accent, icon, headline) = switch (insight.level) {
      SleepConsistency.consistent => (Palette.good, Icons.check_circle_rounded, l.t('sleep_cons_good')),
      SleepConsistency.variable => (Palette.amber, Icons.timeline_rounded, l.t('sleep_cons_variable')),
      SleepConsistency.irregular => (Palette.roseDeep, Icons.show_chart_rounded, l.t('sleep_cons_irregular')),
      SleepConsistency.insufficient => (Palette.textDim, Icons.hourglass_empty_rounded, ''),
    };
    return GlassCard(
      glow: accent,
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: accent)),
                const SizedBox(height: 2),
                Text(l.t('sleep_cons_sub', {'spread': l.duration(insight.spreadMin)}),
                    style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  final SleepStats stats;
  const _StatsHeader({required this.stats});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [sleepDeep.withValues(alpha: 0.10), sleepRem.withValues(alpha: 0.04)],
        ),
        border: Border.all(color: sleepRem.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Expanded(child: _Stat(value: l.duration(stats.avgAsleepMin), label: l.t('sleep_avg', {'n': stats.nights}))),
          Container(width: 1, height: 40, color: Palette.border),
          Expanded(child: _Stat(value: '${(stats.avgDeepFraction * 100).round()}%', label: l.t('sleep_deep'))),
          Container(width: 1, height: 40, color: Palette.border),
          Expanded(child: _Stat(value: l.duration(stats.bestAsleepMin), label: l.t('stat_max'))),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 19, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, fontSize: 11.5)),
      ],
    );
  }
}

/// Vertical stacked bars, one per night, scaled to the longest in-bed time.
class _NightBars extends StatelessWidget {
  final List<SleepSummary> nights;
  const _NightBars({required this.nights});

  @override
  Widget build(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    const chartH = 150.0;
    var maxInBed = 1;
    for (final n in nights) {
      if (n.inBedMin > maxInBed) maxInBed = n.inBedMin;
    }

    double h(int mins) => (mins / maxInBed) * chartH;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final n in nights)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: chartH,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Top → bottom: awake, rem, light, deep (deep at the base).
                      _seg(h(n.awakeMin), sleepAwake, top: true),
                      _seg(h(n.remMin), sleepRem),
                      _seg(h(n.lightMin), sleepLight),
                      _seg(h(n.deepMin), sleepDeep, bottom: true),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(ml.narrowWeekdays[n.night.weekday % 7],
                    style: const TextStyle(color: Palette.textDim, fontSize: 11)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _seg(double height, Color color, {bool top = false, bool bottom = false}) {
    if (height <= 0) return const SizedBox.shrink();
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.vertical(
          top: top ? const Radius.circular(3) : Radius.zero,
          bottom: bottom ? const Radius.circular(3) : Radius.zero,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Palette.textDim, fontSize: 12)),
    ]);
  }
}
