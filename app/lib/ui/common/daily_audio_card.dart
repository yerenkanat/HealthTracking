/// Daily calendar audio — a small player card for the clip that belongs to the
/// current day of the pregnancy / child-development calendar (uploaded from the
/// admin panel, streamed from the backend's /audio route).
///
/// It fetches the clip and renders only once playback is confirmed ready —
/// nothing while checking or when the day has no audio — so screens can drop it
/// in unconditionally.
library;

import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../l10n/l10n.dart' show AppLocale;
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';

class DailyAudioCard extends StatefulWidget {
  /// 'pregnancy' or 'child'.
  final String track;

  /// Calendar day: gestational day for pregnancy, day-of-life for a child.
  final int day;

  /// Spacing applied only when the card is actually shown — so a day with no
  /// clip (the card renders nothing) adds no stray gap to the surrounding list.
  final EdgeInsetsGeometry margin;

  const DailyAudioCard({super.key, required this.track, required this.day, this.margin = EdgeInsets.zero});

  @override
  State<DailyAudioCard> createState() => _DailyAudioCardState();
}

enum _St { checking, ready, hidden }

class _DailyAudioCardState extends State<DailyAudioCard> {
  static const _base = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');
  // Created lazily, only once the fetch confirms a real clip. Days without audio
  // (the common case) never spin up a media player — and neither do widget tests,
  // where the audioplayers plugin has no platform implementation.
  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  _St _st = _St.checking;
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  String? _loadedUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = L10nScope.of(context).locale;
    final url = '$_base/audio/${widget.track}/${widget.day}/${loc == AppLocale.kk ? 'kk' : 'ru'}';
    if (url != _loadedUrl) {
      _loadedUrl = url;
      _load(url);
    }
  }

  Future<void> _load(String url) async {
    setState(() => _st = _St.checking);
    // Download the clip (they're small) and play it from bytes. Android's
    // MediaPlayer is flaky with a URL source that has no file extension; a
    // BytesSource writes a temp file it plays reliably — and the GET doubles as
    // the existence check, so an absent day cleanly hides.
    http.Response resp;
    try {
      resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    } catch (_) {
      if (mounted) setState(() => _st = _St.hidden);
      return;
    }
    if (!mounted) return;
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
      setState(() => _st = _St.hidden);
      return;
    }
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final player = _player ??= AudioPlayer();
    _subs.add(player.onDurationChanged.listen((d) {
      if (mounted) setState(() { _dur = d; _st = _St.ready; }); // a duration means it's playable
    }));
    _subs.add(player.onPositionChanged.listen((p) => mounted ? setState(() => _pos = p) : null));
    _subs.add(player.onPlayerStateChanged.listen((s) => mounted ? setState(() => _playing = s == PlayerState.playing) : null));
    _subs.add(player.onPlayerComplete.listen((_) => mounted ? setState(() { _playing = false; _pos = Duration.zero; }) : null));
    // Confirm readiness via the future OR a duration event. On any failure — or
    // if it never becomes ready — hide, never spin forever.
    player.setSource(BytesSource(resp.bodyBytes, mimeType: resp.headers['content-type'])).then((_) {
      if (mounted && _st == _St.checking) setState(() => _st = _St.ready);
    }).catchError((_) {
      if (mounted && _st != _St.ready) setState(() => _st = _St.hidden);
    });
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _st == _St.checking) setState(() => _st = _St.hidden);
    });
  }

  Future<void> _toggle() async {
    final player = _player;
    if (player == null) return;
    if (_playing) {
      await player.pause();
    } else {
      if (_dur > Duration.zero && _pos >= _dur) await player.seek(Duration.zero);
      await player.resume();
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Stay invisible until a clip is confirmed. Most calendar days have none, so
    // a loading card that flashes then vanishes would be worse than the card
    // simply appearing once it's ready.
    if (_st != _St.ready) return const SizedBox.shrink();
    final l = L10nScope.of(context);
    final total = _dur.inMilliseconds;
    final value = total > 0 ? (_pos.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Palette.lilac, Palette.blush], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.violet.withValues(alpha: 0.14)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _PlayButton(playing: _playing, onTap: _toggle),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Icon(Icons.auto_awesome_rounded, size: 15, color: Palette.violet),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(l.t('audio_title'),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Palette.text)),
                  ),
                  Text('${_fmt(_pos)} / ${_fmt(_dur)}',
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12, color: Palette.textDim, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 2),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    activeTrackColor: Palette.violet,
                    inactiveTrackColor: Palette.violet.withValues(alpha: 0.16),
                    thumbColor: Palette.violet,
                    overlayColor: Palette.violet.withValues(alpha: 0.12),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
                  ),
                  child: Slider(
                    value: value,
                    onChanged: _st == _St.ready && total > 0
                        ? (v) => _player?.seek(Duration(milliseconds: (v * total).round()))
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool playing;
  final VoidCallback? onTap;
  const _PlayButton({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          gradient: Palette.violetPink,
          shape: BoxShape.circle,
          boxShadow: DsShape.hardShadow,
        ),
        child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 30),
      ),
    );
  }
}
