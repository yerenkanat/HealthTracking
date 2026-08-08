/// Screen 54's home block — «Есть ребёнок → возраст, навыки, перцентили».
///
/// docs/CLAUDE-app-design.md: «герой месяца (`#DFF3EA→#ECE6FF`) с навыками в
/// тексте → карточка «Вес 6,1 кг» с коридором перцентилей и подписью «растёт по
/// своему коридору»».
///
/// ON «перцентили», DELIBERATELY NOT DRAWN
///
/// domain/child_growth.dart refuses WHO percentile bands, and the reason is
/// written there: they come from the WHO's published LMS tables — three
/// parameters per sex per day of age — and the honest way to have them is to
/// import that data file, not to type approximate numbers from memory into a
/// medical chart. A band 300 g off tells a mother her healthy child is
/// underweight.
///
/// The spec's own caption is «растёт по своему коридору» — growing along HER
/// corridor — which is exactly the comparison the app can stand behind: the
/// child against herself, and the change since the last visit. So the caption
/// is honoured and the band is not invented. Real percentiles are a data
/// import, not a UI task; see docs/INTEGRATION_STATUS.md.
library;

import 'package:flutter/material.dart';

import '../../domain/child_development.dart';
import '../../domain/child_growth.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';

class ChildHero extends StatelessWidget {
  final String childName;
  final int ageMonths;

  /// Her measurements so far, newest last. Empty hides the growth line rather
  /// than drawing a card with a dash in it.
  final List<GrowthPoint> growth;
  final VoidCallback? onTap;

  const ChildHero({
    super.key,
    required this.childName,
    required this.ageMonths,
    this.growth = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // «навыки в тексте» — what is expected around now, named rather than
    // charted. Two is what fits before the block stops being a hero.
    final skills = milestonesNow(ageMonths).take(2).toList();
    final weights = weightSeries(growth);
    final latest = weights.isEmpty ? null : weights.last;
    final change = weightChange(growth);

    final hero = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        // The child-development gradient — the second of the three the system
        // allows, and the only one for this stage.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDFF3EA), Color(0xFFECE6FF)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.t('childhero_age', {'name': childName, 'n': ageMonths}),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: Ds.mintText),
          ),
          const SizedBox(height: 12),
          Text(
            skills.isEmpty
                // Past the milestone table (over five) there is nothing
                // age-specific left to promise, and inventing one would be a
                // claim about a child the app has never met.
                ? l.t('childhero_growing')
                : l.t('dev_${skills.first.id}'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 21,
              letterSpacing: -0.42,
              height: 1.2,
              color: Ds.ink,
            ),
          ),
          if (skills.length > 1) ...[
            const SizedBox(height: 3),
            Text(
              l.t('dev_${skills[1].id}'),
              style: const TextStyle(fontSize: 13, color: Palette.textDim),
            ),
          ],
          if (latest?.weightKg != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.t('childhero_weight',
                              {'kg': latest!.weightKg!.toStringAsFixed(1)}),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16, color: Ds.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          // Her own corridor — «растёт по своему коридору» —
                          // which is the comparison this app can stand behind.
                          // With one measurement there is no change to report,
                          // so it says the caption alone.
                          change == null
                              ? l.t('childhero_own_corridor')
                              : l.t('childhero_gained', {
                                  'g': (change.delta * 1000).round().abs(),
                                  'd': change.days,
                                }),
                          style: const TextStyle(
                              fontSize: 12.5, height: 1.35, color: Palette.textDim),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 20, color: Color(0xFFA8949F)),
                ],
              ),
            ),
          ],
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
