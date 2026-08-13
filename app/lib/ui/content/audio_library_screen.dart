/// «Все записи» — every uploaded clip of one calendar track, in her language.
///
/// The destination of screen 44's «Все записи · N» row. Before this screen
/// existed an operator could upload sixty recordings and every mother could
/// reach exactly one — today's — because [DailyAudioCard] only ever asks for
/// the current day.
///
/// DAY NUMBERS, NOT DATES. The catalogue is keyed by gestational day (or day of
/// life); the server holds no due date, so turning day 140 into «14 августа»
/// would be an invention. The card that opened this screen knows which day is
/// hers, so that one row is marked «сегодня» and nothing else claims a date.
///
/// OWNERSHIP OF THE PLAYER. [DailyAudioCard] owns the only long-lived
/// `AudioPlayer` in the app and disposes it; if this screen borrowed it, playing
/// day 12 here would silence today's clip and backing out would leave her with
/// nothing playing. So every tap builds a FRESH player, handed to the pushed
/// [AudioPlayerScreen] with `ownsPlayer: true` — that screen disposes its
/// session on the way out, so a clip stops when she closes it and today's card
/// is untouched. The loader is injected so `flutter test`, where `audioplayers`
/// has no platform implementation, can drive the list.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../data/audio_library_repository.dart';
import '../../data/audio_player_session.dart';
import '../../domain/audio_session.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';
import 'audio_player_screen.dart';

/// Turns a clip into a ready-to-play session, or null if it could not be
/// fetched. Injected so the screen is drivable without a media plugin.
typedef ClipSessionLoader = Future<AudioSession?> Function(AudioClip clip);

/// The real loader: download the clip (they are small) and play it from bytes.
///
/// A `BytesSource` rather than a URL for the same reason [DailyAudioCard] uses
/// one — Android's MediaPlayer is unreliable with a URL that has no file
/// extension — and the GET doubles as the "does this still exist" check, so a
/// clip deleted since the list was cached fails honestly instead of playing
/// silence.
Future<AudioSession?> downloadClipSession(AudioClip clip) async {
  final http.Response res;
  try {
    res = await http.get(Uri.parse(audioClipUrl(clip))).timeout(const Duration(seconds: 20));
  } catch (_) {
    return null;
  }
  if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
  final player = AudioPlayer();
  try {
    // The same promise screen 44 prints: «Экран погаснет — запись не
    // остановится». stayAwake has to be set on THIS player too — the card's
    // configuration does not travel to a player it never created.
    await player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: true,
        contentType: AndroidContentType.speech,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gain,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.mixWithOthers},
      ),
    ));
    await player.setSource(BytesSource(res.bodyBytes, mimeType: res.headers['content-type']));
  } catch (_) {
    await player.dispose();
    return null;
  }
  // ownsPlayer: this player was created for this clip and nothing else holds
  // it, so closing the player screen must release it.
  return AudioPlayerSession(player, ownsPlayer: true);
}

class AudioLibraryScreen extends StatefulWidget {
  /// Already narrowed to ONE locale and ordered by day —
  /// [AudioLibrary.forLocale] does both. Handing the raw list in would double
  /// every entry, because the server returns Russian and Kazakh together.
  final List<AudioClip> clips;

  /// The day the calendar card is showing, so one row can be marked as hers
  /// today. Null when the caller has no day.
  final int? todayDay;

  final ClipSessionLoader loadClip;

  const AudioLibraryScreen({
    super.key,
    required this.clips,
    this.todayDay,
    this.loadClip = downloadClipSession,
  });

  @override
  State<AudioLibraryScreen> createState() => _AudioLibraryScreenState();
}

class _AudioLibraryScreenState extends State<AudioLibraryScreen> {
  /// The day currently being fetched, so its row shows a spinner and a second
  /// tap cannot start a second download.
  int? _opening;

  Future<void> _open(AudioClip clip) async {
    if (_opening != null) return;
    setState(() => _opening = clip.day);
    final session = await widget.loadClip(clip);
    if (!mounted) {
      // Nothing is listening any more, but a player was created — release it
      // rather than leaking an audio focus nobody can stop.
      unawaited(session?.dispose());
      return;
    }
    setState(() => _opening = null);
    final l = L10nScope.of(context);
    if (session == null) {
      // Report the RESULT, not the attempt. A tap that opens nothing and says
      // nothing is indistinguishable from a dead row.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('aud_lib_failed'))),
      );
      return;
    }
    final title = clip.title ?? l.t('aud_lib_day', {'n': clip.day});
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AudioPlayerScreen(title: title, session: session),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final clips = widget.clips;

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(l.t('aud_lib_title')),
      ),
      body: SafeArea(
        child: clips.isEmpty
            ? _Empty(title: l.t('aud_lib_empty'), hint: l.t('aud_lib_empty_hint'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: clips.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    // The count is derived from the rows below it, so the
                    // number and the list can never disagree.
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        l.t('aud_lib_lang_note', {'n': clips.length}),
                        style: const TextStyle(fontSize: 13, color: Palette.textDim),
                      ),
                    );
                  }
                  final clip = clips[i - 1];
                  return _ClipRow(
                    day: l.t('aud_lib_day', {'n': clip.day}),
                    title: clip.title ?? l.t('aud_lib_untitled'),
                    // Only when the server actually reported one — a «0 КБ»
                    // badge would be a claim about a clip nobody measured.
                    size: clip.size > 0 ? l.t('aud_lib_size', {'n': (clip.size / 1024).round()}) : null,
                    hasTitle: clip.title != null,
                    isToday: widget.todayDay == clip.day,
                    busy: _opening == clip.day,
                    // While one is opening every other row is inert, and says
                    // so by dimming, rather than silently swallowing taps.
                    onTap: _opening == null ? () => _open(clip) : null,
                  );
                },
              ),
      ),
    );
  }
}

class _ClipRow extends StatelessWidget {
  final String day;
  final String title;
  final String? size;
  final bool hasTitle;
  final bool isToday;
  final bool busy;
  final VoidCallback? onTap;

  const _ClipRow({
    required this.day,
    required this.title,
    required this.size,
    required this.hasTitle,
    required this.isToday,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Semantics(
      button: true,
      label: '$day · $title',
      child: InkWell(
        borderRadius: BorderRadius.circular(DsShape.radiusTile),
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null && !busy ? 0.5 : 1,
          child: Container(
            constraints: const BoxConstraints(minHeight: DsShape.minTapTarget),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isToday ? Ds.pastelLilac : Palette.surface,
              borderRadius: BorderRadius.circular(DsShape.radiusTile),
              border: Border.all(color: Ds.hairline, width: DsShape.borderWidth),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(7),
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.play_circle_fill_rounded, size: 34, color: Ds.coralCta),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Text(
                          day,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Palette.text),
                        ),
                        if (size != null) ...[
                          const SizedBox(width: 8),
                          Text(size!,
                              style: const TextStyle(
                                  fontFamily: 'JetBrainsMono', fontSize: 11, color: Palette.textDim, fontWeight: FontWeight.w600)),
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          fontStyle: hasTitle ? FontStyle.normal : FontStyle.italic,
                          color: Palette.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(l.t('aud_lib_loading'),
                        style: const TextStyle(fontSize: 12, color: Palette.textDim)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String title;
  final String hint;
  const _Empty({required this.title, required this.hint});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.graphic_eq_rounded, size: 40, color: Palette.textDim),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.text)),
              const SizedBox(height: 6),
              Text(hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.4, color: Palette.textDim)),
            ],
          ),
        ),
      );
}
