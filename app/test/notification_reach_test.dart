/// Can she reach her рассылки at all?
///
/// The notification centre had exactly two ways in: the bell on the child map
/// and a tapped push. Both live on «Ребёнок». A woman who is pregnant and has
/// added no child never opens that tab — and the back office publishes to
/// exactly those people (admin frame 06), marks the рассылка delivered, and
/// counts her among the recipients. She could not open it from anywhere.
///
/// So this drives it the way she would: boot the shell, stay on «Сегодня»,
/// and read what is on the screen the bell there opens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/announcement.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/home_shell.dart';
import 'package:fcs_app/ui/theme.dart';

const ru = L10n(AppLocale.ru);

/// Pregnant, onboarded, no child — the audience frame 06 publishes to.
AppController expectantMother(DateTime now) {
  final c = AppController(now: () => now, locale: AppLocale.ru)
    ..setDueDate(now.add(const Duration(days: 126)));
  c.setAnnouncements([
    Announcement(
      id: 'bc-1',
      at: now.subtract(const Duration(hours: 2)),
      ru: const AnnouncementText(
          title: 'Второй скрининг',
          body: 'Окно 18–21 неделя — запишитесь заранее.'),
      kk: const AnnouncementText(
          title: 'Екінші скрининг', body: '18–21 апта — алдын ала жазылыңыз.'),
    ),
  ]);
  return c;
}

// L10nScope wraps MaterialApp, never `home:` — under `home:` it sits below the
// Navigator and the PUSHED notification centre would fall back to English,
// silently, because L10nScope.of returns const L10n(AppLocale.en).
// The StreamBuilder is what FcsApp puts above the shell in production — it is
// how a рассылка that arrives while she has the app open lights the badge, so
// a test without it would be measuring a screen the app never shows.
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

void main() {
  final now = DateTime(2026, 8, 12, 9);

  testWidgets('a pregnant woman with no child reads her рассылка from Сегодня',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final c = expectantMother(now);
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    // She has no child, so «Ребёнок» is a tab she has no reason to open — and
    // until now it was the only tab with a bell on it.
    expect(c.children, isEmpty);
    expect(c.unreadAlertCount, 1);

    // Still on the tab the app opened on.
    expect(find.text(ru.t('nav_today')), findsOneWidget);
    final bell = find.descendant(
      of: find.byType(AppBar),
      matching: find.byTooltip(ru.t('ntf_title')),
    );
    expect(bell, findsOneWidget,
        reason: 'the screen the app opens on has no route to screen 39');

    // The badge is on it, so a рассылка announces itself rather than waiting
    // to be found.
    expect(
      find.descendant(of: bell, matching: find.text('1')),
      findsOneWidget,
      reason: 'the bell carries no unread count',
    );

    await tester.tap(bell);
    await tester.pumpAndSettle();

    // Screen 39, in Russian (a pushed route below an L10nScope at `home:`
    // would be in English here), with the message actually rendered.
    expect(find.text(ru.t('ntf_title')), findsWidgets);
    expect(find.text('Второй скрининг'), findsOneWidget);
    expect(find.text('Окно 18–21 неделя — запишитесь заранее.'), findsOneWidget);
    expect(find.text(ru.t('ntf_empty')), findsNothing);

    // And she can clear it, which is what takes the badge down.
    await tester.tap(find.text(ru.t('ntf_read_all')));
    await tester.pumpAndSettle();
    expect(c.unreadAlertCount, 0);
  });

  testWidgets('the badge falls to nothing once she has read it', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final c = expectantMother(now);
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    c.markAlertsRead(now);
    await tester.pumpAndSettle();
    final bell = find.descendant(
      of: find.byType(AppBar),
      matching: find.byTooltip(ru.t('ntf_title')),
    );
    expect(bell, findsOneWidget);
    expect(find.descendant(of: bell, matching: find.text('1')), findsNothing,
        reason: 'a badge that never goes down is one she stops reading');
  });
}
