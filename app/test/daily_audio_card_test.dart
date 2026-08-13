/// «Все записи» as the CARD wires it — the app half of the audio library.
///
/// [AudioLibrary.forLocale] is covered by `audio_library_test.dart`, and
/// [AudioPlayerScreen]'s row is covered by `audio_player_test.dart`, but the
/// ONE piece of production code that joins them — [DailyAudioCard] — had no
/// test at all: the locale filter could be dropped, or `totalRecordings` and
/// `onOpenAll` set to null, and the whole suite stayed green while every mother
/// went back to reaching exactly one recording.
///
/// Driving the card means driving a real [AudioPlayer], because that is what it
/// creates and what gates the full-screen player behind `_St.ready`. Two seams
/// make that possible without a device:
///
///   * `AudioplayersPlatformInterface.instance` — a settable static the plugin
///     provides for exactly this, replaced here with a fake that answers
///     `create`/`setSourceBytes` and emits the `prepared` and `duration` events
///     the card waits for;
///   * `runWithClient` — `http.get` for the clip bytes goes through a
///     [MockClient] instead of trying to reach `localhost:8080`.
///
/// The catalogue itself needs neither: the card already injects
/// `libraryFetcher` and `libraryCache`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fcs_app/data/audio_library_repository.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/common/daily_audio_card.dart';
import 'package:fcs_app/ui/content/audio_library_screen.dart';
import 'package:fcs_app/ui/content/audio_player_screen.dart';
import 'package:fcs_app/ui/theme.dart';

// ---------------------------------------------------------------------------
// The fixture: a track published unevenly — four Russian days, two Kazakh.
// The gap between them is the whole point: counting the raw list prints six.
// ---------------------------------------------------------------------------
const ruDays = [1, 2, 3, 5];
const kkDays = [1, 2];

Map<String, dynamic> _row(int day, String locale) => {
      'day': day,
      'locale': locale,
      'title': locale == 'ru' ? 'День $day' : '$day-күн жазбасы',
      'size': 51200,
      'url': '/audio/pregnancy/$day/$locale',
    };

final catalogue = jsonEncode({
  'track': 'pregnancy',
  'count': ruDays.length + kkDays.length,
  'audio': [
    ...ruDays.map((d) => _row(d, 'ru')),
    ...kkDays.map((d) => _row(d, 'kk')),
  ],
});

class FakeFetcher implements AudioLibraryFetcher {
  final String? body;
  int calls = 0;
  FakeFetcher(this.body);
  @override
  Future<String> fetch(String track) async {
    calls++;
    if (body == null) throw Exception('no signal');
    return body!;
  }
}

class MemCache implements AudioLibraryCache {
  final Map<String, String> store;
  MemCache([Map<String, String>? seed]) : store = {...?seed};
  @override
  Future<String?> read(String track) async => store[track];
  @override
  Future<void> write(String track, String json) async => store[track] = json;
}

// ---------------------------------------------------------------------------
// A plugin that answers instead of a device. Modelled on the fake audioplayers
// ships in its own test suite; the only behaviour that matters here is that
// `setSourceBytes` reports the clip as prepared, which is what turns the card
// from invisible into a player.
// ---------------------------------------------------------------------------
class FakeAudioPlatform extends AudioplayersPlatformInterface {
  final calls = <String>[];
  final controllers = <String, StreamController<AudioEvent>>{};

  @override
  Future<void> create(String playerId) async {
    calls.add('create');
    controllers[playerId] = StreamController<AudioEvent>.broadcast();
  }

  @override
  Stream<AudioEvent> getEventStream(String playerId) => controllers[playerId]!.stream;

  @override
  Future<void> setSourceBytes(String playerId, Uint8List bytes, {String? mimeType}) async {
    calls.add('setSourceBytes');
    controllers[playerId]
      ?..add(const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true))
      ..add(const AudioEvent(eventType: AudioEventType.duration, duration: Duration(minutes: 4)));
  }

  @override
  Future<void> dispose(String playerId) async {
    calls.add('dispose');
    await controllers.remove(playerId)?.close();
  }

  @override
  Future<void> pause(String playerId) async => calls.add('pause');
  @override
  Future<void> resume(String playerId) async => calls.add('resume');
  @override
  Future<void> stop(String playerId) async => calls.add('stop');
  @override
  Future<void> release(String playerId) async => calls.add('release');
  @override
  Future<void> seek(String playerId, Duration position) async => calls.add('seek');
  @override
  Future<void> setBalance(String playerId, double balance) async {}
  @override
  Future<void> setVolume(String playerId, double volume) async {}
  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}
  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}
  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}
  @override
  Future<void> setAudioContext(String playerId, AudioContext audioContext) async =>
      calls.add('setAudioContext');
  @override
  Future<void> setSourceUrl(String playerId, String url, {bool? isLocal, String? mimeType}) async {}
  @override
  Future<int?> getDuration(String playerId) async => 240000;
  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;
  @override
  Future<void> emitLog(String playerId, String message) async {}
  @override
  Future<void> emitError(String playerId, String code, String message) async {}
}

class FakeGlobalAudioPlatform extends GlobalAudioplayersPlatformInterface {
  final _events = StreamController<GlobalAudioEvent>.broadcast();
  @override
  Future<void> init() async {}
  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}
  @override
  Future<void> emitGlobalLog(String message) async {}
  @override
  Future<void> emitGlobalError(String code, String message) async {}
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => _events.stream;
}

late FakeAudioPlatform platform;

/// The clip bytes. Non-empty, because an empty body is how the card decides the
/// day has no audio.
http.Client clipServer() => MockClient((_) async =>
    http.Response.bytes(List<int>.filled(64, 7), 200, headers: {'content-type': 'audio/mpeg'}));

Future<void> pumpCard(
  WidgetTester tester, {
  required AppLocale locale,
  required AudioLibraryFetcher fetcher,
  AudioLibraryCache? cache,
  int day = 140,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // L10nScope ABOVE MaterialApp: the full player and the library are PUSHED
  // routes, and a scope under `home:` does not reach them.
  await tester.pumpWidget(L10nScope(
    l10n: L10n(locale),
    child: MaterialApp(
      theme: FcsTheme.light(locale),
      home: Scaffold(
        body: DailyAudioCard(
          track: 'pregnancy',
          day: day,
          libraryFetcher: fetcher,
          libraryCache: cache,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Flush the card's 8-second "never spin forever" fallback so the test does not
/// end with a pending timer.
Future<void> settleFallback(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 9));
}

void main() {
  setUp(() {
    platform = FakeAudioPlatform();
    AudioplayersPlatformInterface.instance = platform;
    // A FRESH global platform per test, not one from setUpAll. `AudioPlayer`
    // caches its initialisation in a Completer, and every test body runs in its
    // own fake-async zone — a completer completed in the first test's zone never
    // delivers in the second, so every later card would sit in «checking»
    // forever. Swapping the instance makes the plugin re-initialise in the zone
    // that is actually pumping.
    GlobalAudioplayersPlatformInterface.instance = FakeGlobalAudioPlatform();
    // setSourceBytes takes a temp-file detour on iOS/macOS/linux (path_provider,
    // which has no test implementation). flutter_test already pins the target
    // platform to Android for every test, so the bytes path is the one taken —
    // and overriding it here would trip the binding's "a debug variable was
    // changed by the test" guard.
    expect(defaultTargetPlatform, TargetPlatform.android);
  });

  testWidgets('the card reaches the full player once the clip is ready', (tester) async {
    // The premise of every assertion below: without this, «Все записи» is
    // behind a screen no test can open.
    await http.runWithClient(() async {
      await pumpCard(tester, locale: AppLocale.ru, fetcher: FakeFetcher(catalogue));
      expect(find.byType(DailyAudioCard), findsOneWidget);
      expect(platform.calls, contains('setSourceBytes'));

      await tester.tap(find.text(const L10n(AppLocale.ru).t('audio_title')));
      await tester.pumpAndSettle();
      expect(find.byType(AudioPlayerScreen), findsOneWidget);
      await settleFallback(tester);
    }, clipServer);
  });

  testWidgets('a Kazakh reader is offered the Kazakh recordings, not both languages',
      (tester) async {
    // The named trap. The server returns ru AND kk in one list, so a card that
    // counted the raw list would print «Барлық жазба · 6» to a woman who can
    // listen to two of them — and open a list half in Russian.
    const kk = L10n(AppLocale.kk);
    await http.runWithClient(() async {
      await pumpCard(tester, locale: AppLocale.kk, fetcher: FakeFetcher(catalogue));
      await tester.tap(find.text(kk.t('audio_title')));
      await tester.pumpAndSettle();

      expect(find.text(kk.t('aud_all', {'n': kkDays.length})), findsOneWidget);
      expect(find.text(kk.t('aud_all', {'n': ruDays.length + kkDays.length})), findsNothing);
      await settleFallback(tester);
    }, clipServer);
  });

  testWidgets('a Russian reader gets the Russian count from the same catalogue',
      (tester) async {
    const ru = L10n(AppLocale.ru);
    await http.runWithClient(() async {
      await pumpCard(tester, locale: AppLocale.ru, fetcher: FakeFetcher(catalogue));
      await tester.tap(find.text(ru.t('audio_title')));
      await tester.pumpAndSettle();
      expect(find.text(ru.t('aud_all', {'n': ruDays.length})), findsOneWidget);
      await settleFallback(tester);
    }, clipServer);
  });

  testWidgets('the row opens her whole track, and pauses today\'s clip first',
      (tester) async {
    const kk = L10n(AppLocale.kk);
    await http.runWithClient(() async {
      await pumpCard(tester, locale: AppLocale.kk, fetcher: FakeFetcher(catalogue));
      await tester.tap(find.text(kk.t('audio_title')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kk.t('aud_all', {'n': kkDays.length})));
      await tester.pumpAndSettle();

      expect(find.byType(AudioLibraryScreen), findsOneWidget);
      // The count above the list and the rows below it agree, because both come
      // from the same filtered list.
      expect(find.text(kk.t('aud_lib_lang_note', {'n': kkDays.length})), findsOneWidget);
      for (final d in kkDays) {
        expect(find.text(kk.t('aud_lib_day', {'n': d})), findsOneWidget);
      }
      // Day 5 exists — in Russian only. It must not be in her list.
      expect(find.text(kk.t('aud_lib_day', {'n': 5})), findsNothing);
      // Two recordings at once is what happens without the pause.
      expect(platform.calls, contains('pause'));
      await settleFallback(tester);
    }, clipServer);
  });

  testWidgets('no catalogue means no row — never «Все записи · 0»', (tester) async {
    // A refresh that could not reach the server leaves the card with nothing to
    // count, and a zero would read as an empty catalogue rather than an
    // unreachable one. Today's clip still plays.
    const ru = L10n(AppLocale.ru);
    await http.runWithClient(() async {
      await pumpCard(tester, locale: AppLocale.ru, fetcher: FakeFetcher(null));
      await tester.tap(find.text(ru.t('audio_title')));
      await tester.pumpAndSettle();
      expect(find.byType(AudioPlayerScreen), findsOneWidget);
      expect(find.textContaining('Все записи'), findsNothing);
      await settleFallback(tester);
    }, clipServer);
  });

  testWidgets('a cached catalogue answers when the network cannot', (tester) async {
    // The cache-first ladder, from the card's end: last launch's list is what
    // she gets offered on a launch with no signal.
    const ru = L10n(AppLocale.ru);
    await http.runWithClient(() async {
      await pumpCard(
        tester,
        locale: AppLocale.ru,
        fetcher: FakeFetcher(null),
        cache: MemCache({'pregnancy': catalogue}),
      );
      await tester.tap(find.text(ru.t('audio_title')));
      await tester.pumpAndSettle();
      expect(find.text(ru.t('aud_all', {'n': ruDays.length})), findsOneWidget);
      await settleFallback(tester);
    }, clipServer);
  });
}
