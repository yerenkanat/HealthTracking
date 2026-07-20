/// Lessons and products for wherever the family is on the timeline — a week of
/// pregnancy, or a month of the child's life.
///
/// Presentation only: which stage applies and what belongs to it are decided by
/// the pure [timeline_content] domain.
library;

import 'package:flutter/material.dart';
import '../../domain/timeline_content.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/fitted_title.dart';
import '../widgets/glass.dart';

/// Human label for a stage: "20-я неделя", "Новорождённый", "4 мес.".
String stageLabel(L10n l, TimelineStage stage) => switch (stage.kind) {
      TimelineKind.pregnancyWeek => l.t('tl_stage_week', {'n': stage.index}),
      TimelineKind.childMonth =>
        stage.index == 0 ? l.t('tl_stage_newborn') : l.t('tl_stage_month', {'n': stage.index}),
    };

class TimelineContentScreen extends StatelessWidget {
  final TimelineStage stage;
  final List<ContentItem> items;

  /// Opens a lesson video or a product page. Null while nothing is linked yet.
  final void Function(ContentItem item)? onOpen;

  const TimelineContentScreen({
    super.key,
    required this.stage,
    required this.items,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final lessons = [for (final i in items) if (i.isLesson) i];
    final products = [for (final i in items) if (i.isProduct) i];

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: FittedTitle('${l.t('tl_title')} · ${stageLabel(l, stage)}')),
        body: items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(l.t('tl_none_for_stage'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Palette.textDim, height: 1.4)),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  if (lessons.isNotEmpty) ...[
                    _SectionHeader(l.t('tl_lessons')),
                    for (final item in lessons)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ContentTile(item: item, onOpen: onOpen),
                      ),
                  ],
                  if (products.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _SectionHeader(l.t('tl_products')),
                    for (final item in products)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ContentTile(item: item, onOpen: onOpen),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
              color: Palette.textDim,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            )),
      );
}

/// One lesson or product. Shared by the screen and the dashboard card so they
/// cannot drift apart visually.
class ContentTile extends StatelessWidget {
  final ContentItem item;
  final void Function(ContentItem item)? onOpen;
  const ContentTile({super.key, required this.item, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final locale = l.locale.name;
    final lesson = item.isLesson;
    final accent = lesson ? Palette.violet : Palette.pink;
    // An item with no link yet is shown, but says so rather than offering a
    // button that goes nowhere.
    final actionable = item.hasLink && onOpen != null;
    final price = formatPrice(item);

    return Semantics(
      button: actionable,
      label: '${item.title(locale)}. ${lesson ? l.t('tl_lessons') : l.t('tl_products')}'
          '${price.isEmpty ? '' : ', $price'}',
      child: GlassCard(
        onTap: actionable ? () => onOpen!(item) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                lesson ? Icons.play_circle_fill_rounded : Icons.shopping_bag_rounded,
                color: accent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title(locale),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: Palette.text)),
                  const SizedBox(height: 3),
                  Text(item.summary(locale),
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 12.5, height: 1.35)),
                  const SizedBox(height: 8),
                  Row(children: [
                    if (lesson && item.durationMin != null)
                      _Chip(l.t('tl_minutes', {'n': item.durationMin}), Palette.violetText)
                    else if (price.isNotEmpty)
                      _Chip(price, Palette.pinkText),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        actionable
                            ? (lesson ? l.t('tl_watch') : l.t('tl_buy'))
                            : l.t('tl_soon'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: actionable ? accent : Palette.textDim,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}
