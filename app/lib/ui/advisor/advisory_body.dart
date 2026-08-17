/// The body of an advisory card, in the shape the design spec asks for.
///
/// `ADV_BP_ELEVATED_b` is eleven lines of solid body text on the screen the app
/// opens on. docs/CLAUDE-app-design.md ЧАСТЬ 4 rule 6 says how to divide it:
///
///   «Красные флаги отдельным блоком, не под "читать дальше". 103 внизу.»
///
/// So the card is three things stacked, and the middle of the approved body is
/// the only part that moves:
///
///   1. the lead — the first sentences, as ordinary body text;
///   2. the red-flag block — the LAST sentences, in their own amber-tinted box,
///      because they are what a woman must be able to see without tapping, and
///      «103 внизу» makes them last on the card;
///   3. «Подробнее», when anything was held back.
///
/// Amber, not red: rule 5 of the same list — «Красный только SOS. Остальное
/// тревожное — янтарное». A red-flag block drawn in the SOS colour would make
/// every elevated blood pressure look like an emergency.
///
/// No copy lives here and none is composed here. Which sentences go where is
/// [AdvisoryLayout], a count per key; with no layout declared this widget
/// renders the whole body as one paragraph, exactly as the screen did before.
library;

import 'package:flutter/material.dart';

import '../../domain/advisory_layout.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';
import 'advisory_detail_screen.dart';

class AdvisoryBody extends StatelessWidget {
  /// The advisory code, e.g. `ADV_BP_ELEVATED`. The body is `${code}_b`, and
  /// the detail screen re-reads both from the catalogue rather than being
  /// handed strings — one lookup path, so the card and the screen can never
  /// disagree about what the reviewed text is.
  final String code;

  /// Type size for the lead paragraph. The dashboard banner and the advisor
  /// card size their body text differently and both are approved as they are.
  final double fontSize;

  const AdvisoryBody({super.key, required this.code, this.fontSize = 13.5});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final layout = advisoryLayouts['${code}_b'];
    final parts = advisoryBodyParts(l.t('${code}_b'), layout);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(parts.lead,
            style: TextStyle(
                color: Palette.textDim, fontSize: fontSize, height: 1.35)),
        if (parts.flags.isNotEmpty) ...[
          const SizedBox(height: 10),
          RedFlagBlock(text: parts.flags),
        ],
        if (parts.hasMore) ...[
          const SizedBox(height: 6),
          // A real control with a real tap target, not a coloured word: this is
          // the only route to the rest of a reviewed medical string.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AdvisoryDetailScreen(code: code),
              )),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, DsShape.minTapTarget),
                foregroundColor: Ds.coralText,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // «Подробнее» / «Толығырақ» / «More» — the app's existing word
                // for this, reused rather than translated a second time.
                Text(l.t('gest_details'),
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ]),
            ),
          ),
        ],
      ],
    );
  }
}

/// The red flags and «звоните 103», as their own block.
///
/// Visually distinct from the body text and NEVER behind a "read more" —
/// that is the whole of rule 6. Amber (rule 5), with `Ds.amberText` for the
/// words themselves: the amber FILL measures 2.51:1 at this size and a warning
/// nobody can read is not one.
class RedFlagBlock extends StatelessWidget {
  final String text;
  const RedFlagBlock({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.priority_high_rounded, size: 17, color: Ds.amberText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: Ds.amberText,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
