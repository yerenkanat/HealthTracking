/// The production [AudioSession] — `audioplayers` behind the interface screen
/// 44 talks to.
///
/// There was none. `AudioSession` was an abstract class, `AudioPlayerScreen`
/// required one, and the only implementation in the repository was a fake in a
/// test — so the player screen could not be constructed outside `flutter test`
/// at all, and nothing pushed it. This is the missing half.
///
/// OWNERSHIP. [AudioPlayerScreen.dispose] disposes its session, which is right
/// when the screen created the player and wrong when it borrowed one.
/// [DailyAudioCard] owns the only [AudioPlayer] the app creates and keeps
/// playing after the full-screen player is closed, so by default this adapter
/// releases its own subscriptions and leaves the player alone. Pass
/// `ownsPlayer: true` only when the caller has handed over a player it will not
/// touch again.
library;

import 'package:audioplayers/audioplayers.dart';

import '../domain/audio_session.dart';

class AudioPlayerSession implements AudioSession {
  final AudioPlayer player;

  /// Whether disposing this session should also dispose [player]. False by
  /// default: closing a borrowed player is how backing out of the full screen
  /// silences the card that opened it.
  final bool ownsPlayer;

  AudioPlayerSession(this.player, {this.ownsPlayer = false});

  @override
  Stream<Duration> get onPosition => player.onPositionChanged;

  @override
  Stream<Duration> get onDuration => player.onDurationChanged;

  @override
  Stream<bool> get onPlaying =>
      player.onPlayerStateChanged.map((s) => s == PlayerState.playing);

  @override
  Future<void> play() => player.resume();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration to) => player.seek(to);

  @override
  Future<void> dispose() async {
    if (ownsPlayer) await player.dispose();
  }
}
