/// Dashboard entry point for timeline content.
///
/// The first version was three identical cards with no hierarchy, which read
/// as a shelf rather than something worth opening. This leads with the reason
/// it matters THIS week — how far along, how big the baby is now, what is
/// coming next — and only then shows the material, with lessons and products
/// visually separated so the shop never wears the clothes of the advice.
///
/// Everything in the hook is factual. No countdowns, no invented scarcity, no
/// "127 mothers bought this": manufactured urgency aimed at pregnant women
/// around health purchases is manipulative, and it would undermine the trust
/// the triage features depend on.
library;

import 'package:flutter/material.dart';
import '../../domain/baby_size.dart';
import '../../domain/timeline_content.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'timeline_content_screen.dart';

class TimelineContentCard extends StatelessWidget {
  /// Null when neither a due date nor a child's age is known — the card then
  /// explains what to add rather than showing an empty shelf.
  final TimelineStage? stage;
  final List<ContentItem> items;
  final void Function(ContentItem item)? onOpen;
  final VoidCallback? onSeeAll;

  /// How many items the card previews before deferring to the full screen.
  static const previewCount = 3;

  const TimelineContentCard({
    super.key,
    required this.stage,
    required this.items,
    this.onOpen,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final s = stage;

    if (s == null) {
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(title: l.t('tl_title')),
            const SizedBox(height: 10),
            Text(l.t('tl_empty'),
                style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.35)),
          ],
        ),
      );
    }

    final lessons = [for (final i in items) if (i.isLesson) i];
    final products = [for (final i in items) if (i.isProduct) i];
    // Lessons first: the material is the reason to be here, and what's for sale
    // follows it rather than leading.
    final previewLessons = lessons.take(previewCount - 1).toList();
    final previewProducts = products.take(previewCount - previewLessons.length).toList();
    final previewed = previewLessons.length + previewProducts.length;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(title: l.t('tl_title'), badge: stageLabel(l, s)),
          const SizedBox(height: 12),
          StageHero(stage: s),
          if (previewed == 0) ...[
            const SizedBox(height: 12),
            Text(l.t('tl_none_for_stage'),
                style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.35)),
          ] else ...[
            if (previewLessons.isNotEmpty) ...[
              const SizedBox(height: 14),
              _MiniSection(label: l.t('tl_lessons'), count: lessons.length),
              for (final item in previewLessons)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ContentTile(item: item, onOpen: onOpen),
                ),
            ],
            if (previewProducts.isNotEmpty) ...[
              const SizedBox(height: 14),
              _MiniSection(label: l.t('tl_products'), count: products.length),
              for (final item in previewProducts)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ContentTile(item: item, onOpen: onOpen),
                ),
            ],
          ],
          if (onSeeAll != null && items.length > previewed) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 48, // full-size target
              child: TextButton(
                onPressed: onSeeAll,
                child: Text(l.t('tl_see_all'),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.violet)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The hook: where you are, how big the baby is now, and what comes next.
///
/// Split out so the full screen can show the same thing without the two
/// drifting apart.
class StageHero extends StatelessWidget {
  final TimelineStage stage;
  const StageHero({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final h = highlightFor(stage);
    final pregnancy = stage.kind == TimelineKind.pregnancyWeek;
    final size = pregnancy ? babySizeFor(stage.index) : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Palette.violet.withValues(alpha: 0.10),
            Palette.pink.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pregnancy
                      ? l.t('tl_progress_weeks', {
                          'n': stage.index,
                          'left': l.t('tl_weeks_left', {'n': h.remaining ?? 0}),
                        })
                      : l.t('tl_month_progress', {'n': stage.index}),
                  style: const TextStyle(
                      color: Palette.text, fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (h.isHalfway)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Palette.good.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(l.t('tl_halfway'),
                      style: const TextStyle(
                          color: Palette.goodText, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: h.progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Palette.glass,
              valueColor: const AlwaysStoppedAnimation(Palette.violet),
            ),
          ),
          if (size != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.child_care_rounded, size: 16, color: Palette.pinkText),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    l.t('tl_baby_size', {
                      'size': l.t(size.code),
                      'cm': size.lengthCm.toStringAsFixed(1),
                    }),
                    style: const TextStyle(
                        color: Palette.text, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniSection extends StatelessWidget {
  final String label;
  final int count;
  const _MiniSection({required this.label, required this.count});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Palette.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                )),
          ),
          Text('$count',
              style: const TextStyle(
                  color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      );
}

class _CardHeader extends StatelessWidget {
  final String title;
  final String? badge;
  const _CardHeader({required this.title, this.badge});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: Palette.violetPink,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_stories_rounded, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Palette.text, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          if (badge != null)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Palette.violet.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(badge!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Palette.violetText, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
        ],
      );
}
