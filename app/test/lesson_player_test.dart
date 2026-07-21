/// The lesson player.
///
/// What matters here is not that video decodes — that is the plugin's job — but
/// that the screen is OURS: no third party's chrome, a real message when a URL
/// will not load, and a lesson that cannot legally play inline never reaching
/// this screen at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/content/lesson_player_screen.dart';

/// A controller that fails to initialize, standing in for an unreachable host,
/// an expired signed URL, or no network.
class _DeadController extends VideoPlayerController {
  _DeadController() : super.networkUrl(Uri.parse('https://example.invalid/x.m3u8'));

  @override
  Future<void> initialize() async => throw Exception('unreachable');

  // super.dispose() would reach for a platform channel this fake never had.
  @override
  // ignore: must_call_super
  Future<void> dispose() async {}
}

ContentItem lesson({required String provider, required String url}) => ContentItem.fromJson({
      'id': 'l1',
      'kind': 'lesson',
      'title': {'ru': 'Урок двадцатой недели', 'en': 'Week 20 lesson'},
      'summary': {'ru': 'О', 'en': 'About'},
      'video': {'provider': provider, 'url': url},
    });

void main() {
  Widget wrap(Widget child, {AppLocale locale = AppLocale.en}) =>
      MaterialApp(home: L10nScope(l10n: L10n(locale), child: child));

  testWidgets('an unreachable video says so instead of spinning for ever',
      (tester) async {
    await tester.pumpWidget(wrap(LessonPlayerScreen(
      item: lesson(provider: 'hls', url: 'https://example.invalid/x.m3u8'),
      controllerFactory: (_) => _DeadController(),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not play'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the failure message is localized, like everything else',
      (tester) async {
    await tester.pumpWidget(wrap(
      LessonPlayerScreen(
        item: lesson(provider: 'hls', url: 'https://example.invalid/x.m3u8'),
        controllerFactory: (_) => _DeadController(),
      ),
      locale: AppLocale.ru,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось воспроизвести'), findsOneWidget);
  });

  testWidgets('a YouTube lesson never renders a player here', (tester) async {
    // It should not reach this screen at all — home_shell sends it to the
    // browser — but if a bad catalogue entry gets it here, showing a black
    // square would look like a broken app rather than a routing mistake.
    await tester.pumpWidget(wrap(LessonPlayerScreen(
      item: lesson(provider: 'youtube', url: 'https://youtu.be/abc'),
    )));
    await tester.pumpAndSettle();

    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.textContaining('Could not play'), findsOneWidget);
  });

  testWidgets('the lesson title is shown, and nothing identifies the host',
      (tester) async {
    await tester.pumpWidget(wrap(LessonPlayerScreen(
      item: lesson(provider: 'hls', url: 'https://cdn.example/lesson.m3u8'),
      controllerFactory: (_) => _DeadController(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Week 20 lesson'), findsOneWidget);
    // The whole reason this screen exists: the viewer should not be able to
    // tell, or care, where the file is stored.
    for (final leak in ['youtube', 'vimeo', 'cdn.example', 'm3u8', 'bunny', 'mux']) {
      expect(
        find.textContaining(RegExp(leak, caseSensitive: false)),
        findsNothing,
        reason: 'the player must not surface "$leak" to the viewer',
      );
    }
  });
}
