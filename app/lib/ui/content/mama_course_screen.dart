/// The Ма!Ма! course.
///
/// Two screens in one, and the difference matters commercially:
///
///   * NOT entitled — this is an offer, not an error. It says what the course
///     is and that the комплект includes it. A locked door with a sign sells
///     the bundle; a locked door with no sign looks broken and costs a sale.
///   * Entitled — the lessons, in order, each playing inside the app.
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
import '../../l10n/l10n_scope.dart';
import '../ds_widgets.dart';
import 'course_video_screen.dart';
import '../theme.dart';

class MamaCourseScreen extends StatelessWidget {
  /// Null while loading; [CourseAccess.none] when the request failed, which
  /// draws the offer rather than an error — the course being unreachable and
  /// the course not being bought look the same to someone who has not bought it.
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

  const MamaCourseScreen(
      {super.key,
      required this.access,
      this.onRetry,
      this.launch,
      this.onProgress,
      this.whatsapp = ''});

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

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final a = access;

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(title: Text(l.t('course_title'))),
      body: a == null
          ? const Center(child: CircularProgressIndicator())
          : a.entitled
              ? _Lessons(access: a, onTap: (x) => _open(context, x), onRetry: onRetry)
              : _Offer(whatsapp: whatsapp, launch: launch),
    );
  }
}

/// What somebody who has not bought the комплект sees.
class _Offer extends StatelessWidget {
  /// The WhatsApp number from the back office. Empty hides the button.
  final String whatsapp;
  final Future<bool> Function(Uri url)? launch;
  const _Offer({this.whatsapp = '', this.launch});

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
                  title: Text(lesson.title(lang),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: summary == null ? null : Text(summary),
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
