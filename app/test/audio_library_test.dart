/// «Все записи» — the catalogue behind screen 44's row.
///
/// Two things are being protected here. The first is the count: the server
/// returns Russian AND Kazakh in one list, so anything that counts the raw list
/// prints «Все записи · 64» to a woman who can listen to thirty-two of them.
/// The second is the failure shape: a refresh that could not reach the server
/// must leave the cached list standing and must never become an empty list,
/// because an empty list is a real answer meaning «записей нет».
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/audio_library_repository.dart';
import 'package:fcs_app/domain/audio_session.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/content/audio_library_screen.dart';
import 'package:fcs_app/ui/content/audio_player_screen.dart';
import 'package:fcs_app/ui/theme.dart';

const l = L10n(AppLocale.ru);

String payload(List<Map<String, dynamic>> audio) =>
    jsonEncode({'track': 'pregnancy', 'count': audio.length, 'audio': audio});

Map<String, dynamic> row(int day, String locale, {String? title}) => {
      'day': day,
      'locale': locale,
      'title': title,
      'size': 51200,
      'url': '/audio/pregnancy/$day/$locale',
    };

class MemCache implements AudioLibraryCache {
  final Map<String, String> store = {};
  int writes = 0;
  @override
  Future<String?> read(String track) async => store[track];
  @override
  Future<void> write(String track, String json) async {
    store[track] = json;
    writes++;
  }
}

class FakeFetcher implements AudioLibraryFetcher {
  final String? body;
  final Object? error;
  int calls = 0;
  FakeFetcher.ok(this.body) : error = null;
  FakeFetcher.fails(this.error) : body = null;
  @override
  Future<String> fetch(String track) async {
    calls++;
    if (error != null) throw error!;
    return body!;
  }
}

/// A session with no platform behind it, so the library can be driven.
class FakeSession implements AudioSession {
  bool disposed = false;
  @override
  Stream<Duration> get onPosition => const Stream.empty();
  @override
  Stream<Duration> get onDuration => const Stream.empty();
  @override
  Stream<bool> get onPlaying => const Stream.empty();
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration to) async {}
  @override
  Future<void> dispose() async => disposed = true;
}

Future<void> pumpLibrary(
  WidgetTester tester, {
  required List<AudioClip> clips,
  int? todayDay,
  required ClipSessionLoader load,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // L10nScope ABOVE MaterialApp: a scope under `home:` does not reach a PUSHED
  // route, and the player this screen opens would fall back to English.
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: AudioLibraryScreen(clips: clips, todayDay: todayDay, loadClip: load),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('parsing the catalogue', () {
    test('keeps both locales but hands each reader only hers', () {
      final lib = parseAudioLibrary(payload([
        row(30, 'ru'), row(7, 'kk'), row(7, 'ru'), row(30, 'kk'),
      ]))!;
      expect(lib.clips.length, 4);
      // The trap: counting the list itself doubles «Все записи».
      expect(lib.forLocale('ru').length, 2);
      expect(lib.forLocale('kk').length, 2);
      expect(lib.forLocale('ru').map((c) => c.day), [7, 30]); // by day
      expect(lib.forLocale('en'), isEmpty);
    });

    test('drops a row that cannot be played rather than listing a dead day', () {
      final lib = parseAudioLibrary(payload([
        row(1, 'ru'),
        {'locale': 'ru', 'url': '/audio/pregnancy/2/ru'}, // no day
        {'day': 3, 'locale': 'ru', 'url': ''}, // nowhere to stream from
      ]))!;
      expect(lib.clips.map((c) => c.day), [1]);
    });

    test('an empty title is null, so the screen can say «без названия» itself', () {
      final lib = parseAudioLibrary(payload([row(1, 'ru', title: '  '), row(2, 'ru', title: ' Неделя 20 ')]))!;
      expect(lib.forLocale('ru')[0].title, isNull);
      expect(lib.forLocale('ru')[1].title, 'Неделя 20');
    });

    test('rubbish is null, never an empty library', () {
      // The difference between "could not read it" and "there is nothing" is
      // the difference between hiding the row and printing «Все записи · 0».
      expect(parseAudioLibrary('not json'), isNull);
      expect(parseAudioLibrary('[]'), isNull);
      expect(parseAudioLibrary(jsonEncode({'track': 'pregnancy'})), isNull);
      expect(parseAudioLibrary(jsonEncode({'track': 'pregnancy', 'audio': []}))!.clips, isEmpty);
    });

    test('the server count is ignored — the rows are the truth', () {
      final lib = parseAudioLibrary(jsonEncode({
        'track': 'pregnancy', 'count': 64, 'audio': [row(1, 'ru')],
      }))!;
      expect(lib.forLocale('ru').length, 1);
    });
  });

  group('the two layers', () {
    test('a failed refresh returns null so the caller keeps what it had', () async {
      final cache = MemCache();
      cache.store['pregnancy'] = payload([row(1, 'ru'), row(2, 'ru')]);
      final cached = await primeAudioLibraryFromCache('pregnancy', cache);
      expect(cached!.forLocale('ru').length, 2);

      final fresh = await refreshAudioLibraryFromApi(
        track: 'pregnancy',
        fetcher: FakeFetcher.fails(Exception('no signal')),
        cache: cache,
      );
      expect(fresh, isNull);
      // And the cache was not overwritten with the failure.
      expect(cache.store['pregnancy'], payload([row(1, 'ru'), row(2, 'ru')]));
    });

    test('a good refresh caches the exact bytes it received', () async {
      final cache = MemCache();
      final raw = payload([row(1, 'ru'), row(1, 'kk')]);
      final lib = await refreshAudioLibraryFromApi(
        track: 'pregnancy', fetcher: FakeFetcher.ok(raw), cache: cache);
      expect(lib!.clips.length, 2);
      await Future<void>.delayed(Duration.zero); // the write is unawaited
      // Byte-for-byte, so a field this build does not understand survives.
      expect(cache.store['pregnancy'], raw);
    });

    test('an empty catalogue is a real answer, not a failure', () async {
      final lib = await refreshAudioLibraryFromApi(
        track: 'child', fetcher: FakeFetcher.ok(payload([])));
      expect(lib, isNotNull);
      expect(lib!.forLocale('ru').length, 0);
    });

    test('no cache at all is an ordinary first launch, not an error', () async {
      expect(await primeAudioLibraryFromCache('pregnancy', MemCache()), isNull);
    });
  });

  group('the library screen', () {
    final clips = parseAudioLibrary(payload([
      row(1, 'ru', title: 'Первый день'),
      row(12, 'ru'),
      row(40, 'ru', title: 'Сороковой'),
    ]))!.forLocale('ru');

    testWidgets('lists every day of her track, by day number', (tester) async {
      await pumpLibrary(tester, clips: clips, todayDay: 12, load: (_) async => FakeSession());
      expect(find.text(l.t('aud_lib_day', {'n': 1})), findsOneWidget);
      expect(find.text(l.t('aud_lib_day', {'n': 12})), findsOneWidget);
      expect(find.text(l.t('aud_lib_day', {'n': 40})), findsOneWidget);
      expect(find.text('Первый день'), findsOneWidget);
      // A day with no title says so rather than showing a blank line.
      expect(find.text(l.t('aud_lib_untitled')), findsOneWidget);
      // The count above the list is derived from the rows below it.
      expect(find.text(l.t('aud_lib_lang_note', {'n': 3})), findsOneWidget);
      // Each row says how big the download is — tapping one pulls the bytes.
      expect(find.text(l.t('aud_lib_size', {'n': 50})), findsNWidgets(3));
    });

    testWidgets('plays a day that is not today', (tester) async {
      // The whole point of the screen: before it existed, day 40 was
      // unreachable for everybody whose calendar said day 12.
      AudioClip? asked;
      await pumpLibrary(tester, clips: clips, todayDay: 12, load: (c) async {
        asked = c;
        return FakeSession();
      });
      await tester.tap(find.text(l.t('aud_lib_day', {'n': 40})));
      await tester.pumpAndSettle();
      expect(asked!.day, 40);
      expect(asked!.url, '/audio/pregnancy/40/ru');
      // …and it opened the player, titled with that clip.
      expect(find.byType(AudioPlayerScreen), findsOneWidget);
      expect(find.text('Сороковой'), findsOneWidget);
    });

    testWidgets('a clip that will not load says so instead of opening nothing',
        (tester) async {
      await pumpLibrary(tester, clips: clips, load: (_) async => null);
      await tester.tap(find.text(l.t('aud_lib_day', {'n': 1})));
      await tester.pumpAndSettle();
      expect(find.byType(AudioPlayerScreen), findsNothing);
      expect(find.text(l.t('aud_lib_failed')), findsOneWidget);
    });

    testWidgets('an untitled day is still titled in the player, by its number',
        (tester) async {
      await pumpLibrary(tester, clips: clips, load: (_) async => FakeSession());
      await tester.tap(find.text(l.t('aud_lib_day', {'n': 12})));
      await tester.pumpAndSettle();
      expect(find.byType(AudioPlayerScreen), findsOneWidget);
      // «День 12» appears as the player's title.
      expect(find.text(l.t('aud_lib_day', {'n': 12})), findsWidgets);
    });

    testWidgets('an empty catalogue is an empty state, never a zero row',
        (tester) async {
      await pumpLibrary(tester, clips: const [], load: (_) async => FakeSession());
      expect(find.text(l.t('aud_lib_empty')), findsOneWidget);
      expect(find.text(l.t('aud_lib_empty_hint')), findsOneWidget);
      expect(find.textContaining('· 0'), findsNothing);
    });

    testWidgets('prints day numbers and no dates', (tester) async {
      // The catalogue is keyed by gestational day; the app knows her due date
      // but the list is shared, and a date here would be an invention.
      await pumpLibrary(tester, clips: clips, load: (_) async => FakeSession());
      for (final w in tester.widgetList<Text>(find.byType(Text))) {
        final s = w.data ?? '';
        expect(RegExp(r'\d{1,2}[./]\d{1,2}').hasMatch(s), isFalse, reason: s);
      }
    });
  });
}
