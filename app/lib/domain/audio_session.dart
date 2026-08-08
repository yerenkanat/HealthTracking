/// Screen 44 — «Аудио дня · плеер».
///
/// The player's contract, separated from the plugin so the screen can be driven
/// in a widget test. `audioplayers` has no platform implementation under
/// `flutter test`, and a player screen that cannot be tested is a player screen
/// whose seek arithmetic nobody checks.
library;

/// What the screen needs of a player, and nothing more.
abstract class AudioSession {
  Stream<Duration> get onPosition;
  Stream<Duration> get onDuration;
  Stream<bool> get onPlaying;

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> dispose();
}

/// «↺15 / 15↻» — where a skip lands.
///
/// Clamped at both ends, and that is the whole point of having it as a
/// function: skipping back from 0:07 must land on 0:00 rather than a negative
/// position the platform rejects silently, and skipping forward past the end
/// must land ON the end rather than restarting the clip, which is what a
/// wrapped value would do to somebody who tapped forward once too often.
Duration skipTo(Duration position, Duration total, Duration by) {
  final target = position + by;
  if (target < Duration.zero) return Duration.zero;
  // A zero total means the length is not known yet — the plugin has not
  // reported it. Refusing to clamp against an unknown is safer than clamping
  // to zero, which would make forward-skip do nothing at the start of a clip.
  if (total > Duration.zero && target > total) return total;
  return target;
}

/// «0:42» / «1:05:03». Hours only when there are hours.
String formatAudioTime(Duration d) {
  final t = d.isNegative ? Duration.zero : d;
  final h = t.inHours;
  final m = t.inMinutes.remainder(60);
  final s = t.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
  return '$m:$s';
}

/// How far through, 0..1, or null when the length is not known.
///
/// Null rather than 0: a bar sitting at the far left is a claim that she is at
/// the beginning, and at the moment a clip loads that is a guess.
double? audioProgress(Duration position, Duration total) {
  if (total <= Duration.zero) return null;
  return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
}

/// The step both skip buttons use.
const audioSkip = Duration(seconds: 15);
