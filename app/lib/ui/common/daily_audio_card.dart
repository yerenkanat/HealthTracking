/// Daily calendar audio — a small player card for the clip that belongs to the
/// current day of the pregnancy / child-development calendar (uploaded from the
/// admin panel, streamed from the backend's /audio route).
///
/// It probes the clip with a HEAD request first and simply renders nothing when
/// the day has no audio, so screens can drop it in unconditionally.
library;

import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../l10n/l10n.dart' show AppLocale;
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class DailyAudioCard extends StatefulWidget {
  /// 'pregnancy' or 'child'.
  final String track;

  /// Calendar day: gestational day for pregnancy, day-of-life for a child.
  final int day;

  const DailyAudioCard({super.key, required this.track, required this.day});

  @override
  State<DailyAudioCard> createState() => _DailyAudioCardState();
}

enum _St { checking, ready, hidden }

class _DailyAudioCardState extends State<DailyAudioCard> {
  static const _base = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');
  final AudioPlayer _player = AudioPlayer();
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
    // Does this day have a clip? A HEAD keeps it cheap and lets us hide cleanly.
    try {
      final r = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      if (r.statusCode != 200) {
        setState(() => _st = _St.hidden);
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _st = _St.hidden);
      return;
    }
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _subs.add(_player.onDurationChanged.listen((d) => mounted ? setState(() => _dur = d) : null));
    _subs.add(_player.onPositionChanged.listen((p) => mounted ? setState(() => _pos = p) : null));
    _subs.add(_player.onPlayerStateChanged.listen((s) => mounted ? setState(() => _playing = s == PlayerState.playing) : null));
    _subs.add(_player.onPlayerComplete.listen((_) => mounted ? setState(() { _playing = false; _pos = Duration.zero; }) : null));
    try {
      await _player.setSourceUrl(url);
      if (mounted) setState(() => _st = _St.ready);
    } catch (_) {
      if (mounted) setState(() => _st = _St.hidden);
    }
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      if (_dur > Duration.zero && _pos >= _dur) await _player.seek(Duration.zero);
      await _player.resume();
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_st == _St.hidden) return const SizedBox.shrink();
    final l = L10nScope.of(context);
    final total = _dur.inMilliseconds;
    final value = total > 0 ? (_pos.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Palette.lilac, Palette.blush], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.violet.withValues(alpha: 0.14)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _PlayButton(playing: _playing, loading: _st == _St.checking, onTap: _st == _St.ready ? _toggle : null),
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
                        ? (v) => _player.seek(Duration(milliseconds: (v * total).round()))
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
  final bool loading;
  final VoidCallback? onTap;
  const _PlayButton({required this.playing, required this.loading, required this.onTap});

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
          boxShadow: [BoxShadow(color: Palette.violet.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: loading
            ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 30),
      ),
    );
  }
}
