/// Health Advisor screen — the app's "AI advisor". It reasons over the mother's
/// smart-band data (via HealthAdvisor) and shows a few plain, safe, data-grounded
/// advisory cards. NOT a chatbot. High-tech dark glass styling.
library;

import 'package:flutter/material.dart';
import '../../domain/health_advisor.dart';
import '../../domain/health_series.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class AdvisorScreen extends StatelessWidget {
  final List<HealthSample> samples;
  const AdvisorScreen({super.key, required this.samples});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final advisories = generateAdvisories(samples);

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('adv_title'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Row(children: [
              const Icon(Icons.auto_awesome, size: 16, color: Palette.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l.t('adv_intro'),
                    style: const TextStyle(color: Palette.textDim, fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 16),
            for (final a in advisories) ...[
              _AdvisoryCard(advisory: a),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 4),
            Center(
              child: Text(l.t('chat_disclaimer'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Palette.textDim, fontSize: 11.5)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvisoryCard extends StatelessWidget {
  final Advisory advisory;
  const _AdvisoryCard({required this.advisory});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final (color, icon) = switch (advisory.tone) {
      AdviceTone.positive => (Palette.good, Icons.check_circle_outline),
      AdviceTone.watch => (Palette.watch, Icons.info_outline),
      AdviceTone.info => (Palette.blue, Icons.hourglass_empty),
    };

    return GlassCard(
      glow: advisory.tone == AdviceTone.watch ? color : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(l.t(advisory.code),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.text)),
                    ),
                    if (advisory.value != null)
                      Text(
                        _fmtValue(advisory),
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(l.t('${advisory.code}_b'),
                    style: const TextStyle(color: Palette.textDim, fontSize: 13.5, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtValue(Advisory a) {
    final v = a.value!;
    return switch (a.metric) {
      'temp' => '${v.toStringAsFixed(1)}°',
      'spo2' => '${v.round()}%',
      'systolic' => '${v.round()}',
      _ => '${v.round()}',
    };
  }
}
