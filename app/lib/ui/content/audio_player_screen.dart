/// Screen 44 — «Аудио дня · плеер».
///
/// «⌄ + «Аудио дня» + ⋯ → арт 190 px → название → полоса + время → ↺15 / пауза
/// 66 px / 15↻ → карточка «экран погаснет, запись не остановится» → «Все
/// записи · 64».»
///
/// The card at the bottom is a PROMISE, and the player is configured to keep
/// it: `stayAwake` is set, so the clip goes on while the display is off. It is
/// specifically about the SCREEN and not about leaving the app — real
/// lock-screen playback with a media notification needs a foreground service,
/// and this text does not claim one.
///
/// The session is injected because `audioplayers` has no platform
/// implementation under `flutter test`, and a player whose seek arithmetic
/// nobody checks is a player that skips past the end of a clip.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/audio_session.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';

class AudioPlayerScreen extends StatefulWidget {
  final String title;
  final AudioSession session;

  /// How many recordings there are in total — «Все записи · 64». Null hides
  /// the row rather than printing «Все записи · 0», which reads as a broken
  /// catalogue rather than one that has not loaded.
  final int? totalRecordings;
  final VoidCallback? onOpenAll;

  const AudioPlayerScreen({
    super.key,
    required this.title,
    required this.session,
    this.totalRecordings,
    this.onOpenAll,
  });

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  final _subs = <StreamSubscription<dynamic>>[];
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      widget.session.onPosition.listen((p) {
        if (mounted) setState(() => _pos = p);
      }),
      widget.session.onDuration.listen((d) {
        if (mounted) setState(() => _dur = d);
      }),
      widget.session.onPlaying.listen((p) {
        if (mounted) setState(() => _playing = p);
      }),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    widget.session.dispose();
    super.dispose();
  }

  void _skip(Duration by) =>
      widget.session.seek(skipTo(_pos, _dur, by));

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final progress = audioProgress(_pos, _dur);

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l.t('aud_title')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              // «арт 190 px #6B4EE6»
              Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B4EE6),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.graphic_eq_rounded,
                    size: 64, color: Colors.white),
              ),
              const SizedBox(height: 24),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 22),
              // An empty TRACK while the length is unknown — not an
              // indeterminate bar. The animated one says "loading, wait" and
              // never stops saying it; the flat one says "nothing to show
              // yet", which is the truth. It also made pumpAndSettle spin
              // forever, so every widget test on this screen timed out.
              if (progress == null)
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Ds.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              else
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Ds.hairline,
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatAudioTime(_pos),
                      style: const TextStyle(
                          fontSize: 12.5, color: Palette.textDim)),
                  Text(
                    _dur > Duration.zero ? formatAudioTime(_dur) : '—',
                    style: const TextStyle(
                        fontSize: 12.5, color: Palette.textDim),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SkipButton(
                    // Generic, not Icons.replay_30/replay_10: Flutter ships no
                    // 15-second glyph, and an icon reading "30" beside a
                    // 15-second skip is a small lie on a control she uses
                    // dozens of times. The seconds are printed beside it.
                    icon: Icons.fast_rewind_rounded,
                    tooltip: l.t('aud_back15'),
                    onTap: () => _skip(-audioSkip),
                  ),
                  const SizedBox(width: 28),
                  // 66 dp — the one control she reaches for with a baby in the
                  // other arm.
                  SizedBox(
                    width: 66,
                    height: 66,
                    child: FilledButton(
                      onPressed: () =>
                          _playing ? widget.session.pause() : widget.session.play(),
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      child: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 34,
                        semanticLabel:
                            l.t(_playing ? 'aud_pause' : 'aud_play'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 28),
                  _SkipButton(
                    icon: Icons.fast_forward_rounded,
                    tooltip: l.t('aud_fwd15'),
                    onTap: () => _skip(audioSkip),
                  ),
                ],
              ),

              const Spacer(),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Ds.pastelLilac,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.nightlight_round,
                        size: 18, color: Ds.text),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(l.t('aud_screen_off'),
                          style: const TextStyle(
                              fontSize: 13, height: 1.4, color: Ds.text)),
                    ),
                  ],
                ),
              ),

              if (widget.totalRecordings != null &&
                  widget.onOpenAll != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: DsShape.minTapTarget,
                  child: TextButton(
                    onPressed: widget.onOpenAll,
                    child: Text(
                        l.t('aud_all', {'n': widget.totalRecordings!})),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _SkipButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 30, color: Ds.text),
                // The number the icon cannot show. 15 is not a glyph Flutter
                // ships, and guessing with the 30-second one would mislabel
                // the control.
                Text('${audioSkip.inSeconds}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Ds.textSecondary)),
              ],
            ),
          ),
        ),
      );
}
