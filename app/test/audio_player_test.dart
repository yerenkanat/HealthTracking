/// Screen 44 — «Аудио дня · плеер».
///
/// The arithmetic is the point. A skip that goes negative is silently rejected
/// by the platform and looks like a dead button; a skip past the end wraps to
/// the start, which is what somebody who tapped forward once too often
/// experiences as the clip restarting.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/audio_session.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/content/audio_player_screen.dart';
import 'package:fcs_app/ui/theme.dart';

const l = L10n(AppLocale.ru);

/// A session with no platform behind it, so the screen can be driven.
class FakeSession implements AudioSession {
  final position = StreamController<Duration>.broadcast();
  final duration = StreamController<Duration>.broadcast();
  final playing = StreamController<bool>.broadcast();

  final seeks = <Duration>[];
  int plays = 0;
  int pauses = 0;
  bool disposed = false;

  @override
  Stream<Duration> get onPosition => position.stream;
  @override
  Stream<Duration> get onDuration => duration.stream;
  @override
  Stream<bool> get onPlaying => playing.stream;

  @override
  Future<void> play() async => plays++;
  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> seek(Duration to) async => seeks.add(to);
  @override
  Future<void> dispose() async => disposed = true;
}

Future<FakeSession> pump(
  WidgetTester tester, {
  int? total,
  VoidCallback? onOpenAll,
}) async {
  final s = FakeSession();
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: AudioPlayerScreen(
        title: 'Неделя 20 · О малыше',
        session: s,
        totalRecordings: total,
        onOpenAll: onOpenAll,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return s;
}

void main() {
  group('skipping', () {
    test('back from the very start lands on zero, not below it', () {
      // A negative seek is rejected by the platform without saying so, which
      // reads as a dead button.
      expect(skipTo(const Duration(seconds: 7), const Duration(minutes: 3),
          -audioSkip), Duration.zero);
    });

    test('forward past the end lands ON the end, not back at the start', () {
      // Wrapping is what somebody who tapped forward once too often
      // experiences as the clip restarting.
      expect(
        skipTo(const Duration(seconds: 170), const Duration(seconds: 180),
            audioSkip),
        const Duration(seconds: 180),
      );
    });

    test('ordinary skips are exactly fifteen seconds', () {
      expect(skipTo(const Duration(minutes: 1), const Duration(minutes: 5),
          audioSkip), const Duration(seconds: 75));
      expect(skipTo(const Duration(minutes: 1), const Duration(minutes: 5),
          -audioSkip), const Duration(seconds: 45));
    });

    test('an unknown length does not clamp forward to zero', () {
      // Before the plugin reports a duration, clamping against it would make
      // forward-skip do nothing at the start of every clip.
      expect(skipTo(const Duration(seconds: 5), Duration.zero, audioSkip),
          const Duration(seconds: 20));
    });
  });

  group('formatting', () {
    test('minutes and seconds, hours only when there are hours', () {
      expect(formatAudioTime(const Duration(seconds: 42)), '0:42');
      expect(formatAudioTime(const Duration(minutes: 3, seconds: 5)), '3:05');
      expect(formatAudioTime(const Duration(hours: 1, minutes: 5, seconds: 3)),
          '1:05:03');
    });

    test('never shows a negative time', () {
      expect(formatAudioTime(const Duration(seconds: -5)), '0:00');
    });
  });

  group('the progress bar', () {
    test('is null while the length is unknown', () {
      // A bar at the far left claims she is at the beginning; at load time
      // that is a guess.
      expect(audioProgress(Duration.zero, Duration.zero), isNull);
    });

    test('is a fraction once it is known, clamped', () {
      expect(audioProgress(const Duration(seconds: 30),
          const Duration(minutes: 1)), 0.5);
      expect(audioProgress(const Duration(minutes: 5),
          const Duration(minutes: 1)), 1.0);
    });
  });

  testWidgets('play and pause reach the session', (tester) async {
    final s = await pump(tester);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    expect(s.plays, 1);

    s.playing.add(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pumpAndSettle();
    expect(s.pauses, 1);
  });

  testWidgets('the skip buttons seek by fifteen from the live position',
      (tester) async {
    final s = await pump(tester);
    s.duration.add(const Duration(minutes: 3));
    s.position.add(const Duration(seconds: 40));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.fast_forward_rounded));
    await tester.pumpAndSettle();
    expect(s.seeks.last, const Duration(seconds: 55));

    await tester.tap(find.byIcon(Icons.fast_rewind_rounded));
    await tester.pumpAndSettle();
    expect(s.seeks.last, const Duration(seconds: 25));
  });

  testWidgets('the skip buttons say how many seconds, since the icon cannot',
      (tester) async {
    // Flutter ships no 15-second glyph, and using the 30-second one would
    // mislabel a control she uses dozens of times.
    await pump(tester);
    expect(find.text('15'), findsNWidgets(2));
  });

  testWidgets('shows the elapsed time, and a dash until the length is known',
      (tester) async {
    final s = await pump(tester);
    expect(find.text('—'), findsOneWidget);

    s.duration.add(const Duration(minutes: 4, seconds: 12));
    s.position.add(const Duration(seconds: 65));
    await tester.pumpAndSettle();
    expect(find.text('4:12'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
  });

  testWidgets('promises that the screen going dark does not stop it',
      (tester) async {
    await pump(tester);
    expect(find.text(l.t('aud_screen_off')), findsOneWidget);
  });

  testWidgets('«Все записи» appears only with a real count and a destination',
      (tester) async {
    // «Все записи · 0» reads as a broken catalogue rather than one that has
    // not loaded.
    await pump(tester);
    expect(find.textContaining('Все записи'), findsNothing);

    await pump(tester, total: 64, onOpenAll: () {});
    expect(find.text(l.t('aud_all', {'n': 64})), findsOneWidget);
  });

  testWidgets('releases the session when the screen closes', (tester) async {
    final s = await pump(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(s.disposed, isTrue);
  });
}
