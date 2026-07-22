/// The pregnancy "when to call your doctor" warning list, and a screen that
/// shows it on its own.
///
/// Safety content should never be more than a tap away. The same card appears
/// inside the week-detail screen (in context, under "how you may feel") and
/// behind a permanent app-bar action on the main calendar, so a woman worried
/// about a symptom at 2am reaches it immediately rather than hunting for it.
///
/// The content has a single source — [pregnancyWarnings] and its `preg_warn_*`
/// strings — so the two places can never drift apart.
library;

import 'package:flutter/material.dart';

import '../../domain/pregnancy_guide.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

/// The warning list in its own warm frame, set apart so surrounding reassurance
/// never softens it. Always shows every sign, whatever the week.
class PregnancyWarningsCard extends StatelessWidget {
  const PregnancyWarningsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Palette.roseDeep.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.roseDeep.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 19, color: Palette.roseDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.t('preg_warn_title'),
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Palette.roseDeep)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(l.t('preg_warn_intro'),
              style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 10),
          for (final id in pregnancyWarnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: Palette.roseDeep, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l.t('preg_warn_$id'),
                        style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The focused screen behind the calendar's "when to call" action.
class PregnancyWarningsScreen extends StatelessWidget {
  const PregnancyWarningsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('preg_warn_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: const [PregnancyWarningsCard()],
      ),
    );
  }
}
