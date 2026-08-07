/// The hero block that opens the home screen — §2.4 of the design system.
///
/// «Главная зависит от этапа.» Screen 53 leads with the pregnancy week and how
/// big the baby is; the band readings come far below, because they are not what
/// she opened the app for.
///
/// Built to the spec's literal values: gradient `#FFE4EA → #FFF0DC` at 135°,
/// radius 26, padding 18, caption 13/600 in `#B8003F`, a white pill on the
/// right, title 21/700 with -.02em tracking, and the trimester progress as
/// segments — filled `#D6004A`, remaining the same colour at 25%.
///
/// Three segments, one per trimester. The spec's own snippet shows two `div`s
/// under a comment saying five; three is what «прогресс триместров» means and
/// what a reader can map to something real. Noted rather than guessed silently.
library;

import 'package:flutter/material.dart';

import '../../domain/baby_size.dart';
import '../../domain/cycle_log.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';

class PregnancyHero extends StatelessWidget {
  final GestationInfo gestation;

  /// Opens the week in the calendar. Null leaves the hero inert rather than
  /// drawing a chevron that does nothing.
  final VoidCallback? onTap;

  const PregnancyHero({super.key, required this.gestation, this.onTap});

  /// 1, 2 or 3 — which trimester [week] falls in, by the usual 13/27 cut.
  static int trimesterOf(int week) => week <= 13 ? 1 : (week <= 27 ? 2 : 3);

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final week = gestation.week;
    final trimester = trimesterOf(week);
    final size = babySizeFor(week);

    final hero = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        // One of the three gradients the system allows, and the only one for
        // pregnancy.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE4EA), Color(0xFFFFF0DC)],
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
                  l.t('hero_week_trimester', {'w': week, 't': trimester}),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: Ds.coralText),
                ),
              ),
              // The white pill. Only drawn while there is time left to count —
              // «осталось -3 недели» past the due date is not a fact.
              if (gestation.daysUntilDue > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l.t('hero_weeks_left', {'n': (gestation.daysUntilDue / 7).ceil()}),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF8A5300)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            // Before week 4 there is no honest comparison, so the hero says the
            // week rather than inventing a fruit.
            size == null ? l.t('hero_early') : l.t(size.code),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 21,
              letterSpacing: -0.42, // -.02em at 21px
              height: 1.2,
              color: Ds.ink,
            ),
          ),
          if (size != null) ...[
            const SizedBox(height: 3),
            Text(
              l.t('hero_length', {'cm': size.lengthCm.toStringAsFixed(1)}),
              style: const TextStyle(fontSize: 13, color: Color(0xFF6E4200)),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 1; i <= 3; i++) ...[
                if (i > 1) const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: i <= trimester
                          ? Ds.coral
                          : Ds.coral.withValues(alpha: 0.25),
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

/// The row of three quick actions under the hero — §2.7.
///
/// «Три быстрых действия (Шевеления / Самочувствие / Вес)». Each is a white
/// card with a 36px tinted tile, a 13/600 label and an 11px value line — the
/// value is what makes it worth a tap rather than a menu item.
class QuickAction {
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String label;

  /// Today's figure, or null when there is nothing to report yet.
  final String? value;
  final VoidCallback? onTap;

  const QuickAction({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.label,
    this.value,
    this.onTap,
  });
}

class QuickActionRow extends StatelessWidget {
  final List<QuickAction> actions;
  const QuickActionRow({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight, not CrossAxisAlignment.stretch: this row lives in a
    // ListView, so its height is unbounded and `stretch` asks the cards to fill
    // infinity. IntrinsicHeight measures the tallest card — the Kazakh label
    // that wraps to two lines — and matches the others to it, which is the
    // effect `stretch` was reaching for.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _QuickActionCard(action: actions[i])),
          ],
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final QuickAction action;
  const _QuickActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F3C1E2D), // rgba(60,30,45,.06)
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: action.tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(action.icon, size: 18, color: action.iconColor),
          ),
          const SizedBox(height: 7),
          Text(action.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: Ds.ink)),
          if (action.value != null) ...[
            const SizedBox(height: 1),
            Text(action.value!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Palette.textDim)),
          ],
        ],
      ),
    );

    if (action.onTap == null) return body;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: action.onTap,
        // 48dp is the tap-target floor even though the card draws smaller at
        // small text scales.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DsShape.minTapTarget),
          child: body,
        ),
      ),
    );
  }
}
