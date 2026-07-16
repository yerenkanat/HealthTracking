/// Child Safety tips — the child-safety counterpart to the Health Advisor.
/// Shows a few plain, age-appropriate, status-aware safety tips for the selected
/// child. Opened from the map's shield action. Pure presentation over the
/// verified child_safety_advisor logic.
library;

import 'package:flutter/material.dart';
import '../../domain/child_safety_advisor.dart';
import '../../domain/child_tracker_state.dart' show Freshness;
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class ChildSafetyScreen extends StatelessWidget {
  final String childName;
  final int? ageMonths;
  final String? currentZone;
  final Freshness freshness;
  final bool hasLocation;

  const ChildSafetyScreen({
    super.key,
    required this.childName,
    this.ageMonths,
    this.currentZone,
    this.freshness = Freshness.stale,
    this.hasLocation = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final tips = generateChildTips(
      ageMonths: ageMonths,
      currentZone: currentZone,
      freshness: freshness,
      hasLocation: hasLocation,
    );

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('safety_title'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Row(children: [
              const Icon(Icons.shield_outlined, size: 16, color: Palette.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l.t('safety_intro', {'name': childName}),
                    style: const TextStyle(color: Palette.textDim, fontSize: 13)),
              ),
            ]),
            if (ageMonths != null) ...[
              const SizedBox(height: 4),
              Text(l.t('safety_age', {'age': l.childAge(ageMonths!)}),
                  style: const TextStyle(color: Palette.textDim, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            for (final t in tips) ...[
              _TipCard(tip: t, childName: childName, zone: currentZone),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final SafetyTip tip;
  final String childName;
  final String? zone;
  const _TipCard({required this.tip, required this.childName, this.zone});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final (color, icon) = switch (tip.tone) {
      TipTone.positive => (Palette.good, Icons.check_circle_outline),
      TipTone.watch => (Palette.amber, Icons.info_outline),
      TipTone.info => (Palette.teal, Icons.lightbulb_outline),
    };
    final params = {'name': childName, 'zone': zone ?? ''};

    return GlassCard(
      glow: tip.tone == TipTone.watch ? color : null,
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
                Text(l.t(tip.code, params),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.text)),
                const SizedBox(height: 5),
                Text(l.t('${tip.code}_b', params),
                    style: const TextStyle(color: Palette.textDim, fontSize: 13.5, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
