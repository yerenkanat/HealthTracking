/// Screen 55's hero — «Главная без беременности и детей».
///
/// docs/CLAUDE-app-design.md: «герой цикла (градиент `#F4436B→#FF7A5C`,
/// «Овуляция сегодня», точность прогноза 82 %, 5 сегментов фаз) → … секция «Что
/// дальше» + три кнопки-маршрутизатора (Планирую / Я беременна / Есть ребёнок)».
///
/// The one gradient in the system that carries WHITE text.
///
/// Two deliberate departures from the spec's mock, both because the mock's
/// numbers are illustrative and the app's data is not:
///
///   * «точность прогноза 82 %» — this app has no percentage to show. Accuracy
///     is a four-level judgement (`PredictionConfidence`) computed from how many
///     cycles she has completed and how much they vary. Rendering «82 %» would
///     invent a precision nothing measured, on a screen women use to decide
///     whether they might be pregnant. The qualitative word is what is true.
///   * «5 сегментов фаз» — the model has four phases plus ovulation as its own
///     dated event, so the five segments are menstrual · follicular · fertile ·
///     ovulation · luteal. That reaches five honestly rather than splitting one
///     phase in half to make the count.
library;

import 'package:flutter/material.dart';

import '../../domain/cycle_insights.dart';
import '../../domain/cycle_predictions.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';

/// The five bands the hero draws, in cycle order.
enum CycleBand { menstrual, follicular, fertile, ovulation, luteal }

/// Which band today falls in.
///
/// Named cycleBandFor, not bandFor: health_series.dart already exports a
/// bandFor for vitals, and the dashboard imports both. Ovulation wins over the fertile window it sits
/// inside — it is the day the whole screen is about.
CycleBand cycleBandFor(CycleInfo info, CyclePhaseInfo? phase) {
  final ov = info.ovulation;
  if (ov != null) {
    final t = DateTime(info.today.year, info.today.month, info.today.day);
    final o = DateTime(ov.year, ov.month, ov.day);
    if (t == o) return CycleBand.ovulation;
  }
  return switch (phase?.phase) {
    CyclePhase.menstrual => CycleBand.menstrual,
    CyclePhase.follicular => CycleBand.follicular,
    CyclePhase.fertile => CycleBand.fertile,
    CyclePhase.luteal => CycleBand.luteal,
    null => CycleBand.follicular,
  };
}

class CycleHero extends StatelessWidget {
  final CycleInfo info;
  final CyclePhaseInfo? phase;
  final PredictionConfidence confidence;
  final VoidCallback? onTap;

  const CycleHero({
    super.key,
    required this.info,
    required this.phase,
    required this.confidence,
    this.onTap,
  });

  static const _confidenceKey = {
    PredictionConfidence.low: 'cyc_conf_low',
    PredictionConfidence.building: 'cyc_conf_building',
    PredictionConfidence.variable: 'cyc_conf_variable',
    PredictionConfidence.good: 'cyc_conf_good',
  };

  static const _bandKey = {
    CycleBand.menstrual: 'cyc_phase_period',
    CycleBand.follicular: 'cyc_band_follicular',
    CycleBand.fertile: 'cyc_phase_fertile',
    CycleBand.ovulation: 'cyc_phase_ovulation',
    CycleBand.luteal: 'cyc_band_luteal',
  };

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final band = cycleBandFor(info, phase);

    final hero = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4436B), Color(0xFFFF7A5C)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  info.cycleDay == null
                      ? l.t('cyc_no_data_title')
                      : l.t('cyc_day_n', {'n': info.cycleDay!}),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
              // The accuracy claim, in words. Not a percentage — see the note at
              // the top of this file.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  l.t('cyc_forecast_is', {'v': l.t(_confidenceKey[confidence]!)}),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            // «Овуляция сегодня» on the day itself; otherwise the phase she is in.
            band == CycleBand.ovulation
                ? l.t('cyc_ovulation_today')
                : l.t(_bandKey[band]!),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 21,
              letterSpacing: -0.42,
              height: 1.2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final b in CycleBand.values) ...[
                if (b != CycleBand.values.first) const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      // White at full strength for where she is, a wash for the
                      // rest — the same read as the pregnancy bar, in the
                      // colours this gradient allows.
                      color: Colors.white
                          .withValues(alpha: b == band ? 1.0 : 0.30),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return hero;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: hero,
      ),
    );
  }
}

/// «Что дальше» — the three routers under the cycle hero.
///
/// This is where the app finally asks the question the calendar could only
/// answer through a date picker: «Планирую / Я беременна / Есть ребёнок». The
/// middle one is the «Тест положительный» event the design system asks for and
/// the app had no entry point for at all.
class WhatNextRouters extends StatelessWidget {
  final VoidCallback? onPlanning;
  final VoidCallback? onPregnant;
  final VoidCallback? onHasChild;

  const WhatNextRouters({
    super.key,
    this.onPlanning,
    this.onPregnant,
    this.onHasChild,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.t('whatnext_title').toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: Ds.textSecondary)),
        const SizedBox(height: 10),
        _Router(
          icon: Icons.event_available_rounded,
          tint: Ds.pastelMint,
          iconColor: Ds.mintText,
          label: l.t('whatnext_planning'),
          onTap: onPlanning,
        ),
        _Router(
          icon: Icons.favorite_rounded,
          tint: Ds.pastelPink,
          iconColor: Ds.coralText,
          label: l.t('whatnext_pregnant'),
          onTap: onPregnant,
        ),
        _Router(
          icon: Icons.child_care_rounded,
          tint: Ds.pastelLilac,
          iconColor: Ds.coralText,
          label: l.t('whatnext_haschild'),
          onTap: onHasChild,
        ),
      ],
    );
  }
}

/// §2.5 — a list row: 40px tile, 15/600 title, chevron, ≥68dp tall.
class _Router extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;

  const _Router({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          // «Высота ≥ 68 dp вместе с падингами.»
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, size: 20, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15, color: Ds.ink)),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: Color(0xFFA8949F)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
