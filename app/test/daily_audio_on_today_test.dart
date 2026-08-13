/// «Аудио дня» on the screen the app opens on — spec screens 04 and 55.
///
/// An operator uploads a clip for today from the back office. It reached the
/// pregnancy calendar and the child-development screen, and neither of those is
/// «Сегодня» — so the one recording made for today was on no screen anybody
/// opens first.
///
/// The card itself cannot be driven here: it plays through the audioplayers
/// plugin, which has no implementation in a widget test, and it renders nothing
/// until a clip is confirmed. What IS testable, and what was actually broken,
/// is whether Сегодня mounts it at all — for the right track, the right day,
/// and above the shelf where the spec puts it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/baby_development_content.dart' show childAgeDays;
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/common/daily_audio_card.dart';
import 'package:fcs_app/ui/content/timeline_content_card.dart';
import 'package:fcs_app/ui/home_shell.dart';
import 'package:fcs_app/ui/theme.dart';

const ru = L10n(AppLocale.ru);
final now = DateTime(2026, 8, 12, 9);

Widget wrap(AppController c) => StreamBuilder<void>(
      stream: c.changes,
      builder: (_, __) => L10nScope(
        l10n: ru,
        child: MaterialApp(
          theme: FcsTheme.light(AppLocale.ru),
          home: HomeShell(controller: c, catalog: const ContentCatalog({})),
        ),
      ),
    );

Future<void> pump(WidgetTester tester, AppController c) async {
  tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(c));
  await tester.pumpAndSettle();
}

/// Where each card sits in the Today list, by index. -1 when it is absent.
({int audio, int shelf}) order(WidgetTester tester) {
  final list = tester.widget<ListView>(find.byType(ListView).first);
  final children =
      (list.childrenDelegate as SliverChildListDelegate).children;
  return (
    audio: children.indexWhere((w) => w is DailyAudioCard),
    shelf: children.indexWhere((w) => w is TimelineContentCard),
  );
}

void main() {
  testWidgets('a pregnant woman gets today\'s clip on Сегодня, above the shelf',
      (tester) async {
    final c = AppController(now: () => now, locale: AppLocale.ru)
      // 22 weeks + 0 days = day 154 of the pregnancy.
      ..setDueDate(now.add(const Duration(days: 126)));
    addTearDown(c.dispose);
    await pump(tester, c);

    final card = tester.widget<DailyAudioCard>(find.byType(DailyAudioCard));
    expect(card.track, 'pregnancy');
    expect(card.day, c.gestation!.totalDays,
        reason: 'the clip must be keyed on the day her calendar is on');

    final idx = order(tester);
    expect(idx.audio, isNonNegative);
    expect(idx.audio, lessThan(idx.shelf),
        reason: 'screens 04 and 55 put the audio above the timeline shelf');
  });

  testWidgets('a mother gets the child track, keyed on days of life',
      (tester) async {
    // Off the wall clock, because the shell dates this card the way it dates
    // everything else on Сегодня — from DateTime.now().
    final dob = DateTime.now().subtract(const Duration(days: 40));
    final c = AppController(now: () => now, locale: AppLocale.ru)
      ..addChild(ChildProfile(id: 'c1', name: 'Сұлтан', dateOfBirth: dob));
    addTearDown(c.dispose);
    await pump(tester, c);

    final card = tester.widget<DailyAudioCard>(find.byType(DailyAudioCard));
    expect(card.track, 'child');
    expect(card.day, childAgeDays(dob, DateTime.now()),
        reason: 'the clip must be keyed on this baby\'s day of life');
    expect(card.day, inInclusiveRange(40, 41));
  });

  testWidgets('and nothing is fetched when there is no calendar to key on',
      (tester) async {
    // No due date and no child: /audio/child/0 is not a day, and a card that
    // asks for one is a request that can only 404.
    final c = AppController(now: () => now, locale: AppLocale.ru);
    addTearDown(c.dispose);
    await pump(tester, c);
    expect(find.byType(DailyAudioCard), findsNothing);
  });
}
