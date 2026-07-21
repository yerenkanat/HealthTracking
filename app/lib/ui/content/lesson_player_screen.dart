/// The lesson player.
///
/// Deliberately ours: our controls, our colours, no third party's chrome. That
/// is the whole reason [VideoSource] carries a provider — an HLS or MP4 URL
/// from any store, from a bucket with a free tier to a white-label CDN, plays
/// here. YouTube never reaches this screen; it opens externally, because their
/// terms require their player with its branding intact.
///
/// Nothing here assumes a particular host. The URL is the contract.
library;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../domain/timeline_content.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class LessonPlayerScreen extends StatefulWidget {
  final ContentItem item;

  /// Injected so widget tests can drive the UI without a platform channel.
  /// Production leaves it null and the real controller is built from the URL.
  final VideoPlayerController Function(VideoSource)? controllerFactory;

  const LessonPlayerScreen({super.key, required this.item, this.controllerFactory});

  @override
  State<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends State<LessonPlayerScreen> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _showChrome = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final source = widget.item.video;
    // A lesson that cannot play inline should never have reached this screen,
    // but a bad catalogue entry must show a message rather than a black square.
    if (source == null || !source.playsInline) {
      setState(() => _failed = true);
      return;
    }
    final controller = widget.controllerFactory?.call(source) ??
        VideoPlayerController.networkUrl(Uri.parse(source.url));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.play();
    } catch (_) {
      // Offline, an expired signed URL, a host that moved. Say so; a spinner
      // that never resolves is the worst of the options.
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final title = widget.item.title(l.locale.name);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(child: _body(l)),
    );
  }

  Widget _body(dynamic l) {
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, size: 40, color: Colors.white70),
            const SizedBox(height: 14),
            Text(
              l.t('lesson_play_failed'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
        ),
      );
    }

    final c = _controller;
    if (c == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }

    return GestureDetector(
      onTap: () => setState(() => _showChrome = !_showChrome),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
          if (_showChrome) ...[
            // Our controls. Nothing here identifies where the file is stored,
            // which is the point.
            Semantics(
              button: true,
              label: l.t(c.value.isPlaying ? 'lesson_pause' : 'lesson_play'),
              child: IconButton(
                iconSize: 64,
                icon: Icon(
                  c.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: Colors.white,
                ),
                onPressed: _togglePlay,
              ),
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Palette.violet,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white10,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
