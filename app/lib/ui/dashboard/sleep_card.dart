/// Sleep card + shared sleep-stage visuals for the dashboard. Shows last night's
/// total sleep, a quality pill, a proportional stage bar (deep / REM / light /
/// awake), and the deep-sleep figure. Tapping opens the sleep detail screen.
library;

import 'package:flutter/material.dart';
import '../../domain/sleep.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'sleep_detail_screen.dart';

// Stage palette — cool indigo→blue tones so sleep reads distinctly from the
// warm health metrics. Awake is a soft neutral, not alarming.
const sleepDeep = Color(0xFF4B3FBE);
const sleepRem = Color(0xFF7C6CF0);
const sleepLight = Color(0xFF6FA8FF);
const sleepAwake = Color(0xFFCBD0E0);

Color sleepAccentFor(SleepQuality q) => switch (q) {
      SleepQuality.good => Palette.good,
      SleepQuality.fair => Palette.blue,
      SleepQuality.poor => Palette.amber,
    };

class SleepCard extends StatelessWidget {
  final List<SleepSummary> nights;
  const SleepCard({super.key, required this.nights});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final last = latestNight(nights);
    if (last == null) return const SizedBox.shrink();
    final accent = sleepAccentFor(last.quality);

    return Semantics(
      label: '${l.t('metric_sleep')}: ${l.duration(last.asleepMin)}, ${l.sleepQuality(last.quality)}',
      child: GlassCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SleepDetailScreen(nights: nights)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [sleepDeep, sleepRem]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bedtime_rounded, size: 17, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.t('metric_sleep'),
                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                TonePill(l.sleepQuality(last.quality), accent),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(l.duration(last.asleepMin),
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono', fontSize: 30, fontWeight: FontWeight.w700, height: 1, color: Palette.text,
                    )),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(l.t('sleep_last_night'), style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SleepStageBar(summary: last, height: 12),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16, runSpacing: 6,
              children: [
                _Legend(color: sleepDeep, label: l.t('sleep_deep'), value: l.duration(last.deepMin)),
                _Legend(color: sleepRem, label: l.t('sleep_rem'), value: l.duration(last.remMin)),
                _Legend(color: sleepLight, label: l.t('sleep_light'), value: l.duration(last.lightMin)),
                _Legend(color: sleepAwake, label: l.t('sleep_awake'), value: l.duration(last.awakeMin)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A single proportional horizontal bar of sleep stages.
class SleepStageBar extends StatelessWidget {
  final SleepSummary summary;
  final double height;
  const SleepStageBar({super.key, required this.summary, this.height = 12});

  @override
  Widget build(BuildContext context) {
    final total = summary.inBedMin;
    final segments = <(int, Color)>[
      (summary.deepMin, sleepDeep),
      (summary.remMin, sleepRem),
      (summary.lightMin, sleepLight),
      (summary.awakeMin, sleepAwake),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: total == 0
            ? const ColoredBox(color: sleepAwake)
            : Row(
                children: [
                  for (final (mins, color) in segments)
                    if (mins > 0)
                      Expanded(flex: mins, child: ColoredBox(color: color)),
                ],
              ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _Legend({required this.color, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text('$label ', style: const TextStyle(color: Palette.textDim, fontSize: 12)),
      Text(value, style: const TextStyle(color: Palette.text, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}
