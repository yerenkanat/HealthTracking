/// One advisory, whole.
///
/// What «Подробнее» opens. It renders the SAME reviewed body the card shows a
/// part of — the complete string, including the sentences that were already on
/// the card. That repetition is deliberate and was the clinical gate's ruling
/// on 2026-08-17: a screen that showed only "the rest" would be a second,
/// differently-shaped claim, and the reader would have to hold the card in her
/// head to make sense of it.
///
/// There is no second string anywhere in this feature. The card decides how
/// much of the body to show; this screen shows all of it.
library;

import 'package:flutter/material.dart';

import '../../domain/advisory_layout.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'advisory_body.dart';

class AdvisoryDetailScreen extends StatelessWidget {
  /// The advisory code, e.g. `ADV_BP_ELEVATED`. Title is `code`, body is
  /// `${code}_b` — the same two lookups the card makes.
  final String code;
  const AdvisoryDetailScreen({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final layout = advisoryLayouts['${code}_b'];
    // The whole body, with the flagged tail still in its own block. Keeping the
    // block here as well means the red flags are not demoted to a paragraph on
    // the one screen that shows everything — and «103 внизу» still holds,
    // because the tail is last.
    final parts = advisoryDetailParts(l.t('${code}_b'), layout);

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('adv_title'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(l.t(code),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    color: Palette.text)),
            const SizedBox(height: 12),
            Text(parts.lead,
                style: const TextStyle(
                    color: Palette.text, fontSize: 15, height: 1.5)),
            if (parts.flags.isNotEmpty) ...[
              const SizedBox(height: 16),
              RedFlagBlock(text: parts.flags),
            ],
            const SizedBox(height: 20),
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
