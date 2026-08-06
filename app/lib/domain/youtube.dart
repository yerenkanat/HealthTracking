/// The video id inside a YouTube link, or null.
///
/// Deliberately the same rules as the backend's src/youtube.ts and the admin
/// panel's ytId(): a lesson link is validated on the server, previewed in the
/// panel and played here, and three different opinions about what counts as a
/// valid link is three places for a lesson to disappear.
///
/// PURE Dart, so the parsing is testable without a player or a network.
library;

/// YouTube ids are 11 characters of URL-safe base64.
final _id = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// Paths that carry the id as their first segment.
const _pathPrefixes = {'embed', 'shorts', 'live', 'v'};

const _hosts = {'youtube.com', 'm.youtube.com', 'music.youtube.com'};

String? youtubeVideoId(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return null;

  final url = Uri.tryParse(raw);
  if (url == null) return null;
  if (url.scheme != 'http' && url.scheme != 'https') return null;

  final host = url.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();

  // youtu.be/ID — the share-sheet form, and the one most often pasted.
  if (host == 'youtu.be') {
    return segments.isNotEmpty && _id.hasMatch(segments.first) ? segments.first : null;
  }
  if (!_hosts.contains(host)) return null;

  // /watch?v=ID
  final v = url.queryParameters['v'];
  if (v != null && _id.hasMatch(v)) return v;

  // /embed/ID, /shorts/ID, /live/ID, /v/ID
  if (segments.length >= 2 && _pathPrefixes.contains(segments.first.toLowerCase())) {
    return _id.hasMatch(segments[1]) ? segments[1] : null;
  }
  return null;
}
