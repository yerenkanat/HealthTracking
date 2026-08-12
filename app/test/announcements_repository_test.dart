/// Admin frame 06 → screen 39, the app half: a рассылка written in the back
/// office reaches the phone, and SURVIVES a launch with no signal.
///
/// The two failures this guards against are opposite and both cheap to ship:
///
///   * the message never arrives, because nothing calls the route — the defect
///     this repository has the most of;
///   * the message arrives once and then vanishes, because a failed refresh
///     overwrote the cached copy with nothing. She reads half a sentence on the
///     bus, comes back to it in the evening and it is gone.
///
/// So `null` from the refresh means «could not ask» and an empty list means
/// «ей ничего не присылали», and the two are never allowed to collapse.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/announcements_repository.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/announcement.dart';

String payload(List<Map<String, Object?>> items) =>
    jsonEncode({'announcements': items});

Map<String, Object?> row(
  String id,
  String at, {
  String titleRu = 'Второй скрининг',
  String bodyRu = 'Окно 18–21 неделя.',
  String titleKk = 'Екінші скрининг',
  String bodyKk = '18–21 апта.',
}) =>
    {
      'id': id,
      'at': at,
      'ru': {'title': titleRu, 'body': bodyRu},
      'kk': {'title': titleKk, 'body': bodyKk},
    };

class _Transport implements HttpTransport {
  _Transport({this.reply, this.status = 200, this.throws = false});

  final String? reply;
  final int status;
  final bool throws;
  final List<String> calls = [];

  @override
  Future<HttpResponse> get(String path) async {
    calls.add(path);
    if (throws) throw Exception('no network');
    return HttpResponse(status, reply ?? '{}');
  }

  @override
  Future<HttpResponse> post(String path, Object body) async => const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);
  @override
  Future<HttpResponse> delete(String path) => get(path);
}

class _MemoryCache implements AnnouncementsCache {
  String? stored;
  int clears = 0;
  @override
  Future<String?> read() async => stored;
  @override
  Future<void> write(String json) async => stored = json;
  @override
  Future<void> clear() async {
    clears++;
    stored = null;
  }
}

void main() {
  group('parsing what the server sends', () {
    test('reads both languages and orders newest first', () {
      final items = parseAnnouncements(jsonDecode(payload([
        row('bc-old', '2026-08-01T09:00:00Z'),
        row('bc-new', '2026-08-06T09:00:00Z', titleRu: 'Витамин D'),
      ])) as Map<String, dynamic>);
      expect(items.map((a) => a.id), ['bc-new', 'bc-old']);
      expect(items.first.ru.title, 'Витамин D');
      expect(items.last.kk.title, 'Екінші скрининг');
    });

    test('a malformed row costs that row, not the notification centre', () {
      // This screen is also where a child's SOS lands. One bad marketing row
      // must never be able to empty it.
      final items = parseAnnouncements(jsonDecode(jsonEncode({
        'announcements': [
          {'id': 'broken', 'at': 'not-a-date'},
          row('bc-1', '2026-08-06T09:00:00Z'),
          'a string where an object should be',
        ],
      })) as Map<String, dynamic>);
      expect(items.map((a) => a.id), ['bc-1']);
    });

    test('drops a row with no text in either language', () {
      final items = parseAnnouncements(jsonDecode(payload([
        row('empty', '2026-08-06T09:00:00Z',
            titleRu: '', bodyRu: '', titleKk: '', bodyKk: ''),
      ])) as Map<String, dynamic>);
      expect(items, isEmpty);
    });

    test('the same message twice is one row', () {
      // Two delivery rows for one person would otherwise read as two messages.
      final items = parseAnnouncements(jsonDecode(payload([
        row('bc-1', '2026-08-06T09:00:00Z'),
        row('bc-1', '2026-08-05T09:00:00Z'),
      ])) as Map<String, dynamic>);
      expect(items, hasLength(1));
    });

    test('kk falls back to ru only when the Kazakh half is genuinely empty', () {
      final [both, ruOnly] = parseAnnouncements(jsonDecode(payload([
        row('bc-1', '2026-08-06T09:00:00Z'),
        row('bc-0', '2026-08-05T09:00:00Z', titleKk: '', bodyKk: ''),
      ])) as Map<String, dynamic>);
      expect(both.textFor('kk').title, 'Екінші скрининг');
      expect(ruOnly.textFor('kk').title, 'Второй скрининг');
      // en → ru, like the pregnancy calendar.
      expect(both.textFor('en').title, 'Второй скрининг');
    });
  });

  group('the refresh', () {
    test('asks the user-scoped route and returns what it got', () async {
      final t = _Transport(reply: payload([row('bc-1', '2026-08-06T09:00:00Z')]));
      final items = await refreshAnnouncementsFromApi(api: ApiClient(t));
      expect(items, hasLength(1));
      expect(t.calls.single, startsWith('/announcements'));
    });

    test('caches the EXACT bytes, so a field this build ignores survives', () async {
      final raw = jsonEncode({
        'announcements': [
          {...row('bc-1', '2026-08-06T09:00:00Z'), 'cta': 'https://example.kz'},
        ],
      });
      final cache = _MemoryCache();
      await refreshAnnouncementsFromApi(api: ApiClient(_Transport(reply: raw)), cache: cache);
      // Flushed without blocking the caller.
      await Future<void>.delayed(Duration.zero);
      expect(cache.stored, raw);
      expect(cache.stored, contains('cta'));
    });

    test('an unreachable server returns null and leaves the cache alone', () async {
      final cache = _MemoryCache()
        ..stored = payload([row('bc-1', '2026-08-06T09:00:00Z')]);
      final items = await refreshAnnouncementsFromApi(
          api: ApiClient(_Transport(throws: true)), cache: cache);
      expect(items, isNull, reason: 'a failure must be reported as a failure');
      expect(cache.stored, isNotNull, reason: 'a failed request erased her mail');
    });

    test('a 503 — migration 037 not applied — is a failure, not «пусто»', () async {
      // The route answers 503 precisely so the notification centre keeps its
      // safety alerts. Reading that as an empty inbox would wipe the cache.
      final cache = _MemoryCache()
        ..stored = payload([row('bc-1', '2026-08-06T09:00:00Z')]);
      final items = await refreshAnnouncementsFromApi(
          api: ApiClient(_Transport(status: 503, reply: '{"error":"announcements_unavailable"}')),
          cache: cache);
      expect(items, isNull);
      expect(cache.stored, isNotNull);
    });

    test('an honestly empty inbox IS an empty list, not null', () async {
      final items = await refreshAnnouncementsFromApi(
          api: ApiClient(_Transport(reply: payload([]))));
      expect(items, isNotNull);
      expect(items, isEmpty);
    });
  });

  group('the offline launch', () {
    test('renders the cached copy with no network at all', () async {
      final cache = _MemoryCache()
        ..stored = payload([row('bc-1', '2026-08-06T09:00:00Z', titleRu: 'Витамин D')]);
      final items = await primeAnnouncementsFromCache(cache);
      expect(items, hasLength(1));
      expect(items.single.ru.title, 'Витамин D');
    });

    test('a first launch is empty, not an error', () async {
      expect(await primeAnnouncementsFromCache(_MemoryCache()), isEmpty);
    });

    test('an unreadable cache is empty, not a crash on the way to first paint',
        () async {
      final cache = _MemoryCache()..stored = 'not json at all';
      expect(await primeAnnouncementsFromCache(cache), isEmpty);
    });

    test('signing out takes the copy with it', () async {
      final cache = _MemoryCache()
        ..stored = payload([row('bc-1', '2026-08-06T09:00:00Z')]);
      await clearAnnouncementsCache(cache);
      expect(cache.clears, 1);
      expect(await primeAnnouncementsFromCache(cache), isEmpty);
    });
  });
}
