/// Dashboard entry point for timeline content: the current stage, a couple of
/// its lessons and a product, and a way through to the rest.
library;

import 'package:flutter/material.dart';
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
            _Header(title: l.t('tl_title'), subtitle: null),
            const SizedBox(height: 10),
            Text(l.t('tl_empty'),
                style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.35)),
          ],
        ),
      );
    }

    // Lead with a lesson or two, then a product — the material comes first and
    // what's for sale follows it, rather than the other way round.
    final lessons = [for (final i in items) if (i.isLesson) i];
    final products = [for (final i in items) if (i.isProduct) i];
    final preview = [
      ...lessons.take(previewCount - 1),
      ...products.take(previewCount - lessons.take(previewCount - 1).length),
    ].take(previewCount).toList();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(title: l.t('tl_title'), subtitle: stageLabel(l, s)),
          const SizedBox(height: 12),
          if (preview.isEmpty)
            Text(l.t('tl_none_for_stage'),
                style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.35))
          else
            for (final item in preview)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ContentTile(item: item, onOpen: onOpen),
              ),
          if (onSeeAll != null && items.length > preview.length)
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
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _Header({required this.title, required this.subtitle});

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
          if (subtitle != null)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Palette.violet.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Palette.violetText, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
        ],
      );
}
