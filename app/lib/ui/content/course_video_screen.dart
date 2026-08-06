/// A course lesson, playing inside the app.
///
/// This is YouTube's own IFrame player, embedded — not our chrome around
/// somebody else's stream, and nothing is extracted or re-hosted. Their terms
/// require their player with its branding intact, and the IFrame player IS
/// that player; opening the YouTube app was one way to satisfy the rule and
/// this is another, without handing the customer to a different app.
///
/// Why it matters commercially: the Ма!Ма! course is the whole difference
/// between the комплект at 39 000 ₸ and two devices at 29 800. Tapping a
/// lesson used to launch YouTube, where she lands among recommendations for
/// everything else on the internet and, more often than not, does not come
/// back. A course that leaves the product is a course the product gets no
/// credit for.
///
/// It also remembers where she got to. A lesson watched in three sittings, on
/// a phone put down every time the baby wakes, is the normal case for this
/// audience — and re-finding the minute she stopped at, by dragging a scrubber,
/// is the point most people give up.
///
/// Falls back to opening externally when the player cannot start — an old
/// webview, a device without one, a network that dies mid-load. The lesson
/// staying reachable matters more than where it plays.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../domain/course_lesson.dart';
import '../../domain/youtube.dart';
import '../../l10n/l10n_scope.dart';
import '../ds_widgets.dart';
import '../theme.dart';

/// How often the position is written down while it plays.
///
/// Ten seconds: often enough that closing the app loses almost nothing, rare
/// enough that an hour of watching is six requests a minute rather than sixty.
const _reportEvery = Duration(seconds: 10);

/// Watched enough to count as watched. Not 100% — nobody sits through the
/// end card, and a lesson stuck at 99% forever is worse than one ticked a
/// little early.
const _completeAt = 0.92;

class CourseVideoScreen extends StatefulWidget {
  final CourseLesson lesson;

  /// Where she stopped last time. The player seeks here on load, which is the
  /// entire difference between resuming a lesson and starting it again.
  final LessonProgress? progress;

  /// Called as the video plays and once on the way out. The screen does not
  /// know there is a network — [CourseRoute] is what sends this on.
  final void Function(LessonProgress)? onProgress;

  /// Injected so a widget test can assert what would be opened without a
  /// platform channel.
  final Future<bool> Function(Uri url)? launch;

  /// Skips building a real player, for tests that only care about the page
  /// around it. Production leaves it false.
  final bool debugWithoutPlayer;

  const CourseVideoScreen({
    super.key,
    required this.lesson,
    this.progress,
    this.onProgress,
    this.launch,
    this.debugWithoutPlayer = false,
  });

  @override
  State<CourseVideoScreen> createState() => _CourseVideoScreenState();
}

class _CourseVideoScreenState extends State<CourseVideoScreen> {
  YoutubePlayerController? _controller;
  Timer? _ticker;

  /// The last position worth keeping. Seeded from what she had, so leaving
  /// before the player ever reports cannot overwrite it with zero.
  int _seconds = 0;
  int? _duration;
  bool _completed = false;

  /// Null while it is fine. Set when the player cannot run, which turns the
  /// screen into the "watch on YouTube" fallback rather than a black box.
  String? _failed;

  String? get _videoId => youtubeVideoId(widget.lesson.youtubeUrl);

  @override
  void initState() {
    super.initState();
    final p = widget.progress;
    _seconds = p?.positionSeconds ?? 0;
    _duration = p?.durationSeconds;
    _completed = p?.completed ?? false;

    final id = _videoId;
    if (id == null || widget.debugWithoutPlayer) return;
    try {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: id,
        // Not autoplay: she may be next to a sleeping baby, which is most of
        // the audience for this course most of the time.
        autoPlay: false,
        // Resume where she stopped. A finished lesson starts from the top —
        // reopening it means watching it again, not staring at the end card.
        startSeconds: _completed ? 0 : _seconds.toDouble(),
        params: const YoutubePlayerParams(
          showFullscreenButton: true,
          // Their branding stays. That is the deal.
          showControls: true,
          strictRelatedVideos: true,
        ),
      );
      _ticker = Timer.periodic(_reportEvery, (_) => _sample());
    } catch (e) {
      _failed = '$e';
    }
  }

  /// Reads the player and reports, if it has moved.
  ///
  /// Guarded end to end: this runs on a timer over a webview that can be gone,
  /// backgrounded or mid-navigation, and none of those are worth an error over
  /// a playing video.
  Future<void> _sample() async {
    final c = _controller;
    if (c == null) return;
    try {
      final at = (await c.currentTime).round();
      final total = (await c.duration).round();
      if (!mounted) return;
      // A player still loading reports 0. Taking it would hand the server a
      // position behind the one it already has — which it ignores, but there is
      // no reason to send it.
      if (at <= _seconds && total <= (_duration ?? 0)) return;
      _seconds = at > _seconds ? at : _seconds;
      if (total > 0) _duration = total;
      final d = _duration;
      if (!_completed && d != null && d > 0 && _seconds / d >= _completeAt) {
        _completed = true;
      }
      _report();
    } catch (_) {
      // The webview went away. Nothing to record and nothing to say.
    }
  }

  void _report() {
    widget.onProgress?.call(LessonProgress(
      lessonId: widget.lesson.id,
      positionSeconds: _seconds,
      durationSeconds: _duration,
      completed: _completed,
    ));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // One last write on the way out. Without it, closing the screen eight
    // seconds after the last tick loses those eight seconds every time — and
    // people close a lesson the moment it ends, which is exactly when the tick
    // that would mark it finished has not fired yet.
    if (_seconds > 0) _report();
    _controller?.close();
    super.dispose();
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(widget.lesson.youtubeUrl);
    if (uri == null) return;
    final opener = widget.launch ??
        (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    final ok = await opener(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10nScope.of(context).t('course_open_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final lang = l.locale.name;
    final summary = widget.lesson.summary(lang);
    final controller = _controller;

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        title: Text(widget.lesson.title(lang), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: l.t('course_open_youtube'),
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: _openExternally,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (controller != null && _failed == null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: YoutubePlayer(controller: controller, aspectRatio: 16 / 9),
            )
          else
            // No player: a link that is not a video, or a device that cannot
            // run one. Say which of those it is and keep the lesson reachable.
            DsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.play_circle_outline_rounded,
                      size: 36, color: Palette.rose),
                  const SizedBox(height: 10),
                  Text(
                    l.t(_videoId == null
                        ? 'course_bad_link'
                        : 'course_player_unavailable'),
                    style: const TextStyle(color: Palette.textDim, height: 1.45),
                  ),
                  if (_videoId != null) ...[
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _openExternally,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(l.t('course_open_youtube')),
                      style: FilledButton.styleFrom(
                        backgroundColor: darkenForText(Palette.rose),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Said out loud, because the player seeking on its own looks like a
          // bug otherwise: she left this at 12:30 and it starts there.
          if (widget.progress?.resumable == true) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.history_rounded, size: 16, color: Palette.textDim),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.t('course_resumed_at').replaceFirst(
                        '{time}', formatClock(widget.progress!.positionSeconds)),
                    style: const TextStyle(color: Palette.textDim, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],

          if (summary != null && summary.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(summary,
                style: const TextStyle(
                    color: Palette.textDim, fontSize: 14, height: 1.5)),
          ],
        ],
      ),
    );
  }
}

/// Seconds as m:ss, or h:mm:ss past an hour. Written here rather than reached
/// for from Intl because it is a duration, not a time of day, and Intl formats
/// the latter.
String formatClock(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
