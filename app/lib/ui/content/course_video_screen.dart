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
/// Falls back to opening externally when the player cannot start — an old
/// webview, a device without one, a network that dies mid-load. The lesson
/// staying reachable matters more than where it plays.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../domain/course_lesson.dart';
import '../../domain/youtube.dart';
import '../../l10n/l10n_scope.dart';
import '../ds_widgets.dart';
import '../theme.dart';

class CourseVideoScreen extends StatefulWidget {
  final CourseLesson lesson;

  /// Injected so a widget test can assert what would be opened without a
  /// platform channel.
  final Future<bool> Function(Uri url)? launch;

  /// Skips building a real player, for tests that only care about the page
  /// around it. Production leaves it false.
  final bool debugWithoutPlayer;

  const CourseVideoScreen({
    super.key,
    required this.lesson,
    this.launch,
    this.debugWithoutPlayer = false,
  });

  @override
  State<CourseVideoScreen> createState() => _CourseVideoScreenState();
}

class _CourseVideoScreenState extends State<CourseVideoScreen> {
  YoutubePlayerController? _controller;

  /// Null while it is fine. Set when the player cannot run, which turns the
  /// screen into the "watch on YouTube" fallback rather than a black box.
  String? _failed;

  String? get _videoId => youtubeVideoId(widget.lesson.youtubeUrl);

  @override
  void initState() {
    super.initState();
    final id = _videoId;
    if (id == null || widget.debugWithoutPlayer) return;
    try {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: id,
        // Not autoplay: she may be next to a sleeping baby, which is most of
        // the audience for this course most of the time.
        autoPlay: false,
        params: const YoutubePlayerParams(
          showFullscreenButton: true,
          // Their branding stays. That is the deal.
          showControls: true,
          strictRelatedVideos: true,
        ),
      );
    } catch (e) {
      _failed = '$e';
    }
  }

  @override
  void dispose() {
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
