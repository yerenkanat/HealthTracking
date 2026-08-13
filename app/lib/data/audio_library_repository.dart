/// Where «Все записи» gets its list — the app end of `GET /audio/:track`.
///
/// TWO layers, and the order is the point:
///
///   1. the last server response, cached in prefs, read first;
///   2. `GET /audio/:track`, fetched after that.
///
/// There is no bundled asset layer, unlike the pregnancy calendar or the
/// emergency scenarios. Nothing about a clip an operator uploaded last Tuesday
/// can be shipped in a build, and — unlike text — the audio itself is not in the
/// APK either, so a fabricated baseline would be a list of days that cannot
/// play. What replaces the asset layer is the rule that a failed refresh KEEPS
/// what is already on screen, and that nothing at all is shown as an empty
/// state rather than as a number.
///
/// That rule is why [refreshAudioLibraryFromApi] returns null on failure
/// instead of an empty library: null means "could not ask", an empty list means
/// "asked, and this track has no clips". Collapsing them would print «Все
/// записи · 0» over a catalogue of sixty recordings the phone simply could not
/// reach this second — which is exactly the case [AudioPlayerScreen] hides the
/// row for.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One uploaded clip: a day of the calendar, in one language.
class AudioClip {
  /// Gestational day (pregnancy) or day of life (child). NOT a date — the
  /// catalogue has no calendar in it, and printing one would be an invention.
  final int day;

  /// 'ru' or 'kk'.
  final String locale;
  final String? title;

  /// Bytes, for a "this is a big one" warning on a slow connection.
  final int size;

  /// Server-relative path of the stream, e.g. `/audio/pregnancy/140/ru`.
  final String url;

  const AudioClip({
    required this.day,
    required this.locale,
    required this.title,
    required this.size,
    required this.url,
  });
}

/// The catalogue of one track, in every language it was uploaded in.
class AudioLibrary {
  final String track;

  /// Every clip the server knows about — BOTH locales. Ordered by day.
  final List<AudioClip> clips;

  const AudioLibrary({required this.track, required this.clips});

  /// The clips somebody reading [locale] can actually listen to, by day.
  ///
  /// The ONE way anything is allowed to count this catalogue. The server
  /// returns Russian AND Kazakh in one list, so counting [clips] itself makes
  /// «Все записи · 64» out of thirty-two recordings she can understand — and
  /// the list the row opens would then be half in a language she does not
  /// read.
  List<AudioClip> forLocale(String locale) =>
      [for (final c in clips) if (c.locale == locale) c]..sort((a, b) => a.day.compareTo(b.day));
}

/// Prefs key for a track's last good `/audio/:track` response.
String audioLibraryCacheKey(String track) => 'audio_library_json_$track';

/// Somewhere to keep the last good response. An interface rather than a direct
/// dependency on shared_preferences, so the layering is testable in plain Dart.
abstract class AudioLibraryCache {
  Future<String?> read(String track);
  Future<void> write(String track, String json);
}

/// [AudioLibraryCache] over shared_preferences — the store the rest of the
/// app's durable state uses.
class PrefsAudioLibraryCache implements AudioLibraryCache {
  const PrefsAudioLibraryCache();

  @override
  Future<String?> read(String track) async =>
      (await SharedPreferences.getInstance()).getString(audioLibraryCacheKey(track));

  @override
  Future<void> write(String track, String json) async =>
      (await SharedPreferences.getInstance()).setString(audioLibraryCacheKey(track), json);
}

/// Who asks the server. An interface because the only widget that needs the
/// catalogue — [DailyAudioCard] — reaches the network with plain `http` and the
/// same `API_BASE` the clip bytes come from, and has no `ApiClient` to hand.
abstract class AudioLibraryFetcher {
  /// The raw response body, or throws.
  Future<String> fetch(String track);
}

/// The real one: `GET $API_BASE/audio/:track`.
class HttpAudioLibraryFetcher implements AudioLibraryFetcher {
  static const base = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');
  const HttpAudioLibraryFetcher();

  @override
  Future<String> fetch(String track) async {
    final res = await http.get(Uri.parse('$base/audio/$track'));
    if (res.statusCode != 200) {
      throw http.ClientException('audio library: HTTP ${res.statusCode}');
    }
    return res.body;
  }
}

/// Where a clip's bytes come from — `$API_BASE` + the server-relative [url].
String audioClipUrl(AudioClip clip) => '${HttpAudioLibraryFetcher.base}${clip.url}';

/// What this phone last received, from disk.
///
/// Read BEFORE the network refresh, so a launch with no signal still offers the
/// recordings she already knows about. Null when there is no usable cache — an
/// ordinary first launch, and the caller shows nothing rather than a zero.
Future<AudioLibrary?> primeAudioLibraryFromCache(String track, AudioLibraryCache cache) async {
  try {
    final raw = await cache.read(track);
    if (raw == null) return null;
    return parseAudioLibrary(raw);
  } catch (e) {
    debugPrint('audio library: cached copy unusable — $e');
    return null;
  }
}

/// Fetch `/audio/:track` and cache the exact bytes.
///
/// Returns null when the server could not be reached OR answered something
/// unusable, so the caller keeps whatever it already had. An EMPTY library is a
/// real answer — «на этом календаре пока нет записей» — and is returned as
/// such.
Future<AudioLibrary?> refreshAudioLibraryFromApi({
  required String track,
  required AudioLibraryFetcher fetcher,
  AudioLibraryCache? cache,
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    final raw = await fetcher.fetch(track).timeout(timeout);
    final lib = parseAudioLibrary(raw);
    if (lib == null) return null;
    // The exact bytes, not a re-encode, so a field this build does not
    // understand still survives to the next launch.
    unawaited(cache?.write(track, raw));
    return lib;
  } catch (e) {
    debugPrint('audio library: refresh failed, keeping what we have — $e');
    return null;
  }
}

/// Parse `{track, count, audio:[…]}`. Null when the payload is not that.
///
/// `count` from the server is deliberately ignored: the list is the truth, and
/// a client that printed a count it did not derive from the rows it can play
/// would be back to inventing a number.
AudioLibrary? parseAudioLibrary(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final track = decoded['track'];
    final audio = decoded['audio'];
    if (track is! String || audio is! List) return null;
    final clips = <AudioClip>[];
    for (final entry in audio) {
      if (entry is! Map) continue;
      final day = entry['day'];
      final locale = entry['locale'];
      final url = entry['url'];
      // A row with no day or no stream is not playable; skipping it is better
      // than a list item that does nothing when tapped.
      if (day is! num || locale is! String || url is! String || url.isEmpty) continue;
      final title = entry['title'];
      clips.add(AudioClip(
        day: day.toInt(),
        locale: locale,
        title: title is String && title.trim().isNotEmpty ? title.trim() : null,
        size: entry['size'] is num ? (entry['size'] as num).toInt() : 0,
        url: url,
      ));
    }
    clips.sort((a, b) => a.day.compareTo(b.day));
    return AudioLibrary(track: track, clips: clips);
  } catch (e) {
    debugPrint('audio library: could not parse a payload — $e');
    return null;
  }
}
