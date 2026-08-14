/// The guide itself — the screen a guide never had.
///
/// WHY THIS EXISTS
///
/// A published guide was a heading, a one-line summary and an external `url`.
/// Tapping one threw a woman into a browser, out of the app, onto somebody
/// else's page; with the url empty it was not tappable at all and the card
/// said «Скоро». 364 items were downloaded to every phone and not one of them
/// held a sentence she could read here. The back office had no box to write
/// one in, and the app had no screen to show it on.
///
/// Admin frame 16a writes it. This reads it.
///
/// THE ORDER IS THE POINT
///
/// docs/CLAUDE-app-design.md §4.6: red flags go in their OWN block, never
/// behind «читать дальше». So «Красный флаг» is drawn ABOVE the article, fully
/// expanded, with no tap between her and it — a woman who opens a guide about
/// bleeding at week 23 must not have to scroll past four paragraphs of context
/// to find the line that says stop reading and call. The article follows, and
/// 103 sits at the bottom, which is the same rule
/// `widgets/call_ambulance.dart` already keeps on every other screen that
/// lists signs: writing the signs down is only worth it if she knows what to
/// do next.
///
/// Amber, not the emergency red. Red belongs to SOS and to the screen that
/// appears when something IS happening; this is a reference page she may be
/// reading calmly on a Tuesday, and making the two look identical makes
/// neither mean anything.
///
/// PLAIN TEXT. [articleParagraphs] splits what the editor typed into
/// paragraphs and nothing is interpreted — no HTML, no Markdown. A content
/// field that could style the page is a content field that can break it.
library;

import 'package:flutter/material.dart';

import '../../domain/timeline_content.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../ds_widgets.dart';
import '../theme.dart';
import '../widgets/call_ambulance.dart';
import '../widgets/fitted_title.dart';
import '../widgets/glass.dart';

class ArticleScreen extends StatelessWidget {
  final ContentItem item;

  /// Open the video or the shop page this guide ALSO has, when it has one.
  ///
  /// Offered as a button at the end rather than instead of this screen. A
  /// guide with both a video and a written red-flag block used to be a choice
  /// between them; putting the source at the bottom means the text — and the
  /// red flags above it — are never the thing that gets skipped.
  ///
  /// Null leaves the button out entirely rather than drawing a dead one.
  final void Function(ContentItem item)? onOpenSource;

  /// Place the 103 call. Injected so a widget test can drive the footer
  /// without a dialler; production leaves it null and the footer dials.
  final Future<bool> Function(String tel)? onCall;

  const ArticleScreen({
    super.key,
    required this.item,
    this.onOpenSource,
    this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final locale = l.locale.name;
    final summary = item.summary(locale).trim();
    final paragraphs = articleParagraphs(item.body(locale));
    final flags = articleParagraphs(item.redFlags(locale));

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // The title lives in the bar and is NOT repeated below it: two copies
        // of the same heading on one screen is the duplicate-control defect
        // docs/UI_REVIEW_CHECKLIST.md exists to catch.
        appBar: AppBar(title: FittedTitle(item.title(locale))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            if (summary.isNotEmpty) ...[
              Text(
                summary,
                style: const TextStyle(
                  color: Palette.text,
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (flags.isNotEmpty) ...[
              _RedFlagBlock(lines: flags),
              const SizedBox(height: 18),
            ],
            for (final p in paragraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  p,
                  style: const TextStyle(
                    color: Palette.text,
                    fontSize: 14.5,
                    height: 1.6,
                  ),
                ),
              ),
            if (onOpenSource != null && item.hasSource) ...[
              const SizedBox(height: 4),
              _SourceButton(item: item, onOpen: () => onOpenSource!(item)),
            ],
            const SizedBox(height: 18),
            // Last, always. Not conditional on the guide being medical: a
            // woman reading about sleep at 3am is one tap from the number
            // either way, and a footer that appears on some guides and not
            // others is one she cannot rely on.
            CallAmbulanceFooter(onCall: onCall),
          ],
        ),
      ),
    );
  }
}

/// «Красный флаг» — above the article, never collapsed.
///
/// A plain [Column] rather than an ExpansionTile, and that is deliberate
/// rather than incidental: the design system forbids putting these behind a
/// disclosure, and the only way to guarantee that is for there to be no
/// disclosure widget in the file.
class _RedFlagBlock extends StatelessWidget {
  final List<String> lines;
  const _RedFlagBlock({required this.lines});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Semantics(
      container: true,
      label: '${l.t('art_red_flag')}. ${lines.join('. ')}',
      child: DsCard(
        color: Ds.pastelButter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 22, color: Ds.amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.t('art_red_flag'),
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Ds.amberText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 8),
                      child: SizedBox(
                        width: 5,
                        height: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Ds.amberText,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                          color: Ds.textBody,
                          fontSize: 13.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// «Смотреть» / «Купить» for a guide that also has a video or a shop page.
class _SourceButton extends StatelessWidget {
  final ContentItem item;
  final VoidCallback onOpen;
  const _SourceButton({required this.item, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final lesson = item.isLesson;
    final label = lesson ? l.t('tl_watch') : l.t('tl_buy');
    final accent = lesson ? Palette.violet : Palette.pink;
    return Semantics(
      button: true,
      label: label,
      child: DsCard(
        onTap: onOpen,
        child: Row(
          children: [
            Icon(
              lesson ? Icons.play_circle_fill_rounded : Icons.shopping_bag_rounded,
              color: accent,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: Palette.textDim),
          ],
        ),
      ),
    );
  }
}
