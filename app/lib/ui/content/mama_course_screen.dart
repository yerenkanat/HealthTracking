/// The Ма!Ма! course.
///
/// Three screens in one, and the difference matters commercially:
///
///   * NOT entitled — this is an offer, not an error. It says what the course
///     is and that the комплект includes it. A locked door with a sign sells
///     the bundle; a locked door with no sign looks broken and costs a sale.
///   * Entitled — the lessons, in order, each playing inside the app.
///   * Could not check — neither of the above. The server did not answer, so
///     the screen says that and offers a retry. It used to draw the offer
///     here, which told a paying customer to buy what she owns as soon as her
///     signal dropped.
///
/// The gate is the SERVER's answer, not a flag this screen decides. It asks
/// GET /course/lessons and draws what comes back.
///
/// The lesson opens in [CourseVideoScreen], which embeds YouTube's own IFrame
/// player with their branding intact — the rule their terms set. It used to
/// launch the YouTube app, which satisfied the same rule and lost the customer.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/course_lesson.dart';
import '../../domain/course_prices.dart';
import '../../domain/my_order.dart' show formatTenge;
import '../../domain/shop_catalogue.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../ds_widgets.dart';
import 'course_video_screen.dart';
import '../theme.dart';

class MamaCourseScreen extends StatelessWidget {
  /// Null while loading; [CourseAccess.unknown] when the request failed, which
  /// draws neither the offer nor the lessons — the course being unreachable and
  /// the course not being bought are different facts, and only one of them is
  /// safe to act on.
  final CourseAccess? access;
  final Future<void> Function()? onRetry;

  /// Injected so the test can assert what would be opened without launching a
  /// browser.
  final Future<bool> Function(Uri url)? launch;

  /// Where the player got to, on its way to the server. Null in a test or a
  /// build with no API configured, which simply does not remember.
  final void Function(LessonProgress)? onProgress;

  /// The WhatsApp number from the back office, for the offer's contact button.
  /// Empty (the default, and what a failed /shop/config gives) hides it.
  final String whatsapp;

  /// The live catalogue, so «карточка цены» quotes what the комплект actually
  /// costs today rather than what it cost when this build was compiled. Empty
  /// (the default) falls back to the constants and labels them approximate.
  final ShopCatalogue catalogue;

  const MamaCourseScreen(
      {super.key,
      required this.access,
      this.onRetry,
      this.launch,
      this.onProgress,
      this.whatsapp = '',
      this.catalogue = ShopCatalogue.empty});

  /// Open the lesson IN the app.
  ///
  /// This used to launch YouTube. The course is the entire difference between
  /// the комплект at 39 000 ₸ and two devices at 29 800, and handing it to
  /// another app put it among recommendations for everything else on the
  /// internet — she rarely came back, and the product got no credit for the
  /// thing it charges for.
  ///
  /// Still YouTube's own player, embedded, with their branding: the terms
  /// require that, and the IFrame player is that player. The external route
  /// stays as the fallback for a device that cannot run it.
  void _open(BuildContext context, CourseLesson lesson) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CourseVideoScreen(
        lesson: lesson,
        progress: access?.progress[lesson.id],
        onProgress: onProgress,
        launch: launch,
      ),
    ));
  }

  /// Play the ONE free lesson, for somebody who has not bought the course.
  ///
  /// Goes through the same player as a paid lesson. Progress is deliberately
  /// NOT reported: the server refuses progress for an account with no
  /// entitlement, and posting it anyway would put a 403 in the log on every
  /// preview — noise that would eventually hide a real one.
  void _openFree(BuildContext context, CoursePreviewLesson p) {
    final url = p.youtubeUrl;
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CourseVideoScreen(
        lesson: CourseLesson(
          id: p.id,
          titleRu: p.titleRu,
          titleKk: p.titleKk,
          youtubeUrl: url,
          summaryRu: p.summaryRu,
          summaryKk: p.summaryKk,
          sort: p.sort,
        ),
        launch: launch,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final a = access;

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(title: Text(l.t('course_title'))),
      body: a == null
          ? const Center(child: CircularProgressIndicator())
          // Before either branch, because both of them are claims about what
          // she owns and this state is the absence of one.
          : a.checkFailed
              ? _CheckFailed(onRetry: onRetry)
              : a.entitled
              ? _Lessons(access: a, onTap: (x) => _open(context, x), onRetry: onRetry)
              : _Offer(
                  whatsapp: whatsapp,
                  launch: launch,
                  preview: a.preview,
                  catalogue: catalogue,
                  onPlayFree: (p) => _openFree(context, p),
                ),
    );
  }
}

/// What everybody sees when the entitlement could not be read.
///
/// Modelled on «История зон», which draws loading / loaded / FAILED for the
/// same reason: the failure card must not be mistakable for an answer. So no
/// price card, no WhatsApp button, no lesson list — nothing on it acts as if
/// we knew, and the only thing to do is ask again.
class _CheckFailed extends StatelessWidget {
  final Future<void> Function()? onRetry;
  const _CheckFailed({this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        DsCard(
          key: const Key('course-check-failed'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 40, color: Palette.textDim),
              const SizedBox(height: 12),
              Text(l.t('course_check_failed'),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              // The sentence that keeps this apart from the offer. Without it a
              // customer reads a dead network as "you do not have this".
              Text(l.t('course_check_failed_why'),
                  style: const TextStyle(color: Palette.textDim, height: 1.45)),
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: DsShape.minTapTarget,
                  child: FilledButton(
                    key: const Key('course-check-retry'),
                    onPressed: () => onRetry!(),
                    child: Text(l.t('day_retry'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// What somebody who has not bought the комплект sees.
class _Offer extends StatelessWidget {
  /// The WhatsApp number from the back office. Empty hides the button.
  final String whatsapp;
  final Future<bool> Function(Uri url)? launch;

  /// What the course contains, from the server. Titles only, plus a video on
  /// the one free lesson.
  final List<CoursePreviewLesson> preview;

  /// Play the free lesson. Null where nothing can play it.
  final void Function(CoursePreviewLesson)? onPlayFree;

  /// The live catalogue behind «карточка цены».
  final ShopCatalogue catalogue;

  const _Offer({
    this.whatsapp = '',
    this.launch,
    this.preview = const [],
    this.catalogue = ShopCatalogue.empty,
    this.onPlayFree,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final number = whatsapp.replaceAll(RegExp(r'\D'), '');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        DsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.play_circle_outline_rounded, size: 40, color: Palette.rose),
              const SizedBox(height: 12),
              Text(l.t('course_locked_title'),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(l.t('course_locked_body'),
                  style: const TextStyle(color: Palette.textDim, height: 1.45)),

              // The way to act on it.
              //
              // This card told her to get in touch and then gave her no way to,
              // which is the whole pitch for a 39 000 ₸ product dead-ending on
              // its last line. The number is the one staff set in the back
              // office, so it is never stale and never invented here; with no
              // number configured the button is hidden rather than opening a
              // chat with nobody.
              if (number.isNotEmpty) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(
                        'https://wa.me/$number?text=${Uri.encodeComponent(l.t('course_wa_text'))}');
                    final opener = launch ??
                        (u) => launchUrl(u, mode: LaunchMode.externalApplication);
                    final ok = await opener(uri);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.t('course_open_failed'))),
                      );
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: darkenForText(Palette.rose),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
                  label: Text(l.t('course_ask_access'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),

        // Screen 34: what is actually in the course.
        //
        // «Двенадцать уроков» is a claim; the titles are evidence — she can see
        // the one about sleep and the one she needs this week. The first plays
        // free, and the server is what decides that: locked rows arrive with no
        // video at all, so this list cannot leak one however it is rendered.
        if (preview.isNotEmpty) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(l.t('crs_contents'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(l.t('crs_lessons_n', {'n': preview.length}),
                    style: const TextStyle(
                        fontSize: 13, color: Palette.textDim)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final lesson in preview)
            _PreviewRow(
              lesson: lesson,
              lang: l.locale.name,
              onPlayFree: onPlayFree,
            ),
        ],

        const SizedBox(height: 20),
        _PriceCard(number: number, launch: launch, catalogue: catalogue),
      ],
    );
  }
}

/// One row of the preview list: a title, and a lock or a play button.
class _PreviewRow extends StatelessWidget {
  final CoursePreviewLesson lesson;
  final String lang;
  final void Function(CoursePreviewLesson)? onPlayFree;

  const _PreviewRow({
    required this.lesson,
    required this.lang,
    this.onPlayFree,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final summary = lesson.summary(lang);
    // Playable only when the SERVER said free AND actually sent a video. Both,
    // because either alone would be the client deciding what is paid for.
    final playable =
        lesson.free && (lesson.youtubeUrl?.isNotEmpty ?? false) && onPlayFree != null;

    final row = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            lesson.free ? Icons.play_circle_fill_rounded : Icons.lock_rounded,
            size: 22,
            color: lesson.free ? Ds.mintText : Palette.textDim,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(lesson.title(lang),
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ),
                    if (lesson.free) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Ds.pastelMint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(l.t('crs_free_badge'),
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Ds.mintText)),
                      ),
                    ],
                  ],
                ),
                if (summary != null) ...[
                  const SizedBox(height: 3),
                  Text(summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, color: Palette.textDim)),
                ],
              ],
            ),
          ),
          if (playable)
            const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
        ],
      ),
    );

    if (!playable) return row;
    // The whole row, not a button beside the title. «Посмотреть первый урок»
    // next to a lesson name overflowed a 390 dp phone by 77 px in Russian —
    // and the row already carries a play icon, so a second affordance saying
    // the same thing was a duplicate control as well as too wide.
    return Semantics(
      button: true,
      label: '${lesson.title(lang)}. ${l.t('crs_watch_free')}',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onPlayFree!(lesson),
        child: row,
      ),
    );
  }
}

/// «карточка цены (39 000 ₸ / 128 800 ₸)» and the two ways to buy.
///
/// The comparison IS the offer: the комплект includes the whole course and
/// costs less than the two devices and the course bought separately. Stating
/// both numbers is what makes that visible, rather than asking her to work it
/// out from a price list on another page.
class _PriceCard extends StatelessWidget {
  final String number;
  final Future<bool> Function(Uri url)? launch;

  /// Where the numbers come from. The комплект's price is an operator's since
  /// frame 08a, so quoting the compile-time constant would advertise a price
  /// the shop no longer charges.
  final ShopCatalogue catalogue;

  const _PriceCard({
    required this.number,
    this.launch,
    this.catalogue = ShopCatalogue.empty,
  });

  Future<void> _write(BuildContext context, String text) async {
    final opener =
        launch ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    final ok = await opener(Uri.parse(
        'https://wa.me/$number?text=${Uri.encodeComponent(text)}'));
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10nScope.of(context).t('course_open_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final prices = coursePricesFrom(catalogue);
    final bundle = catalogue.byId(bundleProductId);
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('crs_price_title'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),

          // The комплект row goes entirely when a catalogue was read without
          // it: the set is off sale, and quoting the build's 39 000 ₸ for it
          // would advertise a product the shop will not sell. The course
          // itself is still for sale below, which is why the card stays.
          if (prices.bundleAvailable)
            _PriceRow(
              // The catalogue's own name for the set, so renaming it in the
              // back office renames it here — including into Kazakh.
              name: bundle?.name(l.localeCode) ?? l.t('crs_bundle_name'),
              detail:
                  bundle?.description(l.localeCode) ?? l.t('crs_bundle_what'),
              price: formatTenge(prices.bundleMinor),
              highlight: true,
            ),
          // «128 800 ₸» — the comparison, and ONLY while it is one. An operator
          // can price the set above its parts; a struck-through number smaller
          // than the one above it reads as a con, so the row goes rather than
          // printing a negative saving.
          if (prices.savingIsReal) ...[
            const SizedBox(height: 10),
            _PriceRow(
              name: l.t('crs_separate_name'),
              detail: '',
              price: formatTenge(prices.separatelyMinor),
              struck: true,
            ),
          ],
          const SizedBox(height: 10),
          _PriceRow(
            name: l.t('crs_course_only'),
            detail: '',
            // Deliberately still the constant: there is no course-only product
            // to read a price off. See [CoursePrices.courseOnlyMinor].
            price: formatTenge(prices.courseOnlyMinor),
          ),

          // Where these numbers came from. A price card is the last place to
          // quote a figure from memory without saying so.
          if (prices.isApproximate) ...[
            const SizedBox(height: 10),
            Text(l.t('shop_prices_approx'),
                style: const TextStyle(
                    fontSize: 12, height: 1.4, color: Palette.textDim)),
          ] else if (prices.fromCache && prices.pricedAt != null) ...[
            const SizedBox(height: 10),
            Text(
                l.t('shop_prices_cached', {
                  'date': '${prices.pricedAt!.day.toString().padLeft(2, '0')}'
                      '.${prices.pricedAt!.month.toString().padLeft(2, '0')}'
                      '.${prices.pricedAt!.year}'
                }),
                style: const TextStyle(
                    fontSize: 12, height: 1.4, color: Palette.textDim)),
          ],

          if (number.isNotEmpty) ...[
            const SizedBox(height: 18),
            // «Заказать комплект» only while there is a комплект to order. A
            // button that opens WhatsApp asking for a withdrawn set sends her
            // to a conversation that can only end in «его больше нет».
            if (prices.bundleAvailable)
              SizedBox(
                width: double.infinity,
                height: DsShape.minTapTarget,
                child: FilledButton.icon(
                  onPressed: () => _write(context, l.t('course_wa_text')),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
                  label: Text(l.t('crs_order_wa'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: DsShape.minTapTarget,
              child: TextButton(
                onPressed: () => _write(context, l.t('crs_wa_course')),
                child: Text(l.t('crs_buy_course_wa')),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(l.t('crs_already_bought'),
              style: const TextStyle(
                  fontSize: 12.5, height: 1.4, color: Palette.textDim)),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String name;
  final String detail;
  final String price;
  final bool highlight;
  final bool struck;

  const _PriceRow({
    required this.name,
    required this.detail,
    required this.price,
    this.highlight = false,
    this.struck = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: highlight ? FontWeight.w700 : FontWeight.w500)),
              if (detail.isNotEmpty)
                Text(detail,
                    style: const TextStyle(
                        fontSize: 12.5, color: Palette.textDim)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          price,
          style: TextStyle(
            fontSize: highlight ? 18 : 15,
            fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
            color: struck ? Palette.textDim : null,
            decoration: struck ? TextDecoration.lineThrough : null,
          ),
        ),
      ],
    );
  }
}

class _Lessons extends StatelessWidget {
  final CourseAccess access;
  final void Function(CourseLesson) onTap;
  final Future<void> Function()? onRetry;
  const _Lessons({required this.access, required this.onTap, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // Entitled but empty is its own state: she paid, and the lessons are not up
    // yet. Showing the offer here would tell a customer to buy what she owns.
    if (access.lessons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l.t('course_empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.textDim, height: 1.45)),
        ),
      );
    }

    final lang = l.locale.name;
    final resume = access.resume;
    final done = access.completedCount;

    return RefreshIndicator(
      onRefresh: () async => onRetry?.call(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        // One header above the lessons.
        itemCount: access.lessons.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          if (index == 0) {
            return _Header(
              done: done,
              total: access.lessons.length,
              resume: resume,
              lang: lang,
              onTap: onTap,
            );
          }
          final i = index - 1;
          final lesson = access.lessons[i];
          final summary = lesson.summary(lang);
          final p = access.progress[lesson.id];
          final fraction = p?.fraction;
          final completed = p?.completed == true;

          return DsCard(
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: CircleAvatar(
                    // A finished lesson stops being a number and becomes a tick:
                    // the whole list can be read at a glance rather than
                    // remembered.
                    backgroundColor: completed ? Palette.rose : Palette.pink,
                    child: completed
                        ? const Icon(Icons.check_rounded, size: 20, color: Colors.white)
                        : Text('${i + 1}',
                            style: const TextStyle(
                                color: Palette.rose, fontWeight: FontWeight.w700)),
                  ),
                  // Two lines each, and the summary visibly quieter than the
                  // title.
                  //
                  // Both took the default body style, so a two-line title
                  // followed straight into its summary and the pair read as one
                  // run-on paragraph — a lesson list nobody could scan. Only
                  // visible with real titles on a real screen: the fixtures
                  // were short enough to fit one line each.
                  title: Text(lesson.title(lang),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, height: 1.25)),
                  subtitle: summary == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(summary,
                              key: Key('lesson-summary-${lesson.id}'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: Palette.textDim)),
                        ),
                  trailing: Icon(
                      p == null || completed
                          ? Icons.play_circle_outline_rounded
                          : Icons.play_arrow_rounded,
                      size: 22,
                      color: completed ? Palette.textDim : Palette.rose),
                  onTap: () => onTap(lesson),
                ),
                // Only where it means something: part-watched, and the length
                // known. A bar at 0 or 100 on every row is noise.
                if (!completed && fraction != null && fraction > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        key: Key('lesson-bar-${lesson.id}'),
                        value: fraction,
                        minHeight: 4,
                        backgroundColor: Palette.pink,
                        valueColor: const AlwaysStoppedAnimation(Palette.rose),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// "You are 4 of 12 in", and the one tap that matters.
///
/// Without it a returning customer faces the same undifferentiated list she
/// left, and has to remember which lesson she was on. That is where a bought
/// course stops being watched.
class _Header extends StatelessWidget {
  final int done;
  final int total;
  final CourseLesson? resume;
  final String lang;
  final void Function(CourseLesson) onTap;
  const _Header({
    required this.done,
    required this.total,
    required this.resume,
    required this.lang,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final r = resume;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.t('course_progress_of')
                      .replaceFirst('{done}', '$done')
                      .replaceFirst('{total}', '$total'),
                  key: const Key('course-progress-line'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: Palette.textDim),
                ),
              ),
              if (done == total && total > 0)
                const Icon(Icons.emoji_events_rounded, size: 18, color: Palette.rose),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              backgroundColor: Palette.pink,
              valueColor: const AlwaysStoppedAnimation(Palette.rose),
            ),
          ),
          if (r != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('course-continue'),
              onPressed: () => onTap(r),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              // "Continue" when she is mid-lesson, "start" when she is not:
              // offering to continue something never opened reads as a bug.
              label: Text('${l.t(done == 0 ? 'course_start' : 'course_continue')} · '
                  '${r.title(lang)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              style: FilledButton.styleFrom(
                backgroundColor: darkenForText(Palette.rose),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
