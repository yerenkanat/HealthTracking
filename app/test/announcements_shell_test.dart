/// The join: back office → phone → the screen she actually opens.
///
/// Everything else about рассылки can be right — the route, the ledger, the
/// repository, the parser, the notification centre itself — and the feature
/// still reach nobody, because the ONE line that hands the messages to the
/// screen was never written. That is this repository's dominant defect and it
/// is invisible to every unit test: each layer passes on its own.
///
/// So this drives it the way a person does. Boot the shell, walk to the child
/// tab, press the bell, and read what is on the screen that opens.
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

const l = L10n(AppLocale.ru);

Announcement announcement(DateTime at) => Announcement(
      id: 'bc-1',
      at: at,
      ru: const AnnouncementText(
          title: 'Второй скрининг', body: 'Окно 18–21 неделя — запишитесь заранее.'),
      kk: const AnnouncementText(title: 'Екінші скрининг', body: '18–21 апта.'),
    );

void main() {
  testWidgets('a delivered рассылка is on the screen the bell opens', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final c = AppController();
    // What main.dart does after priming the cache before first paint.
    c.setAnnouncements([announcement(DateTime.now().subtract(const Duration(hours: 1)))]);

    await tester.pumpWidget(L10nScope(
      l10n: l,
      child: MaterialApp(
        theme: FcsTheme.light(AppLocale.ru),
        home: HomeShell(controller: c, catalog: const ContentCatalog({})),
      ),
    ));
    await tester.pumpAndSettle();

    // Screen 20 — the child tab, where the bell lives.
    await tester.tap(find.text(l.t('nav_child')));
    await tester.pumpAndSettle();

    // The badge counts it before she has read anything.
    expect(c.unreadAlertCount, 1);

    await tester.tap(find.byTooltip(l.t('alerts_title')).first);
    await tester.pumpAndSettle();

    // Screen 39, with the message actually on it — not an empty centre over a
    // controller that is holding one.
    expect(find.text(l.t('ntf_title')), findsOneWidget);
    expect(find.text('Второй скрининг'), findsOneWidget,
        reason: 'the centre was opened without the рассылки it was given');
    expect(find.text('Окно 18–21 неделя — запишитесь заранее.'), findsOneWidget);
    expect(find.text(l.t('ntf_empty')), findsNothing);

    // ...and «Прочитать всё» reaches this one, rather than being dead because
    // the screen only knows about the (empty) alert feed.
    final btn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, l.t('ntf_read_all')));
    expect(btn.onPressed, isNotNull);
    await tester.tap(find.text(l.t('ntf_read_all')));
    await tester.pumpAndSettle();
    expect(c.unreadAlertCount, 0);
  });
}
