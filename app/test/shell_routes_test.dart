/// Screens nothing pushed.
///
/// Three dead ends, all of the same shape: finished code with no caller.
///
///   1. ChildDetailScreen — the child-care hub (медкарта, прививки, рост и вес,
///      развитие, дневник новорождённого, детектор плача, прикорм,
///      безопасность дома, болезни) — had exactly ONE caller in the whole app:
///      Настройки → Дети. The «Бала» tab, which is where a mother looks for her
///      child, had no route to it at all.
///   2. Профиль's «2 детей» tile switched to the child MAP, a live-tracking
///      screen with no way through to any child's card. The tile that counts
///      her children landed on a screen that shows none of them.
///   3. The notification centre's «Настроить остальные» was hard-null with a
///      comment saying the per-channel screen «does not exist yet». It does —
///      RemindersCenterScreen, quiet hours included, reachable from Settings.
///
/// Driven through the real shell rather than by constructing the destinations,
/// because constructing them is exactly what every existing test did while the
/// app could not reach them.
///
/// L10nScope wraps MaterialApp, never `home:` — below the Navigator every
/// PUSHED route silently falls back to English and the assertions lie.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/home_shell.dart';
import 'package:fcs_app/ui/settings/reminders_center_screen.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/child_detail_screen.dart';

const l = L10n(AppLocale.ru);
final today = DateTime(2026, 8, 12);

AppController controllerWith(List<ChildProfile> children) {
  final c = AppController(now: () => today, locale: AppLocale.ru);
  for (final ch in children) {
    c.addChild(ch);
  }
  return c;
}

Future<void> pumpShell(WidgetTester tester, AppController c) async {
  tester.view.physicalSize = const Size(390 * 3, 1000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: HomeShell(controller: c, catalog: const ContentCatalog({})),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the child card is reachable from the «Бала» tab, without Settings',
      (tester) async {
    final c = controllerWith([
      ChildProfile(id: 'c1', name: 'Сұлтан', dateOfBirth: DateTime(2024, 3, 2)),
    ]);
    addTearDown(c.dispose);
    await pumpShell(tester, c);

    await tester.tap(find.text(l.t('nav_child')));
    await tester.pumpAndSettle();

    // The entry point is on the tab itself — not behind Настройки, and not
    // behind a long-press or a gesture nobody discovers.
    expect(find.byTooltip(l.t('tr_child_card')), findsOneWidget,
        reason: 'the child tab still has no route to the child card');
    await tester.tap(find.byTooltip(l.t('tr_child_card')));
    await tester.pumpAndSettle();

    expect(find.byType(ChildDetailScreen), findsOneWidget);
    // …and it is the card of the child the map has selected, in Russian —
    // proof the scope is above the Navigator, not at `home:`.
    expect(find.text('Сұлтан'), findsWidgets);
    expect(find.text(l.t('vac_title')), findsOneWidget,
        reason: 'the hub under the card should have come with it');
  });

  testWidgets('no child, no icon — it does not open an empty card',
      (tester) async {
    final c = controllerWith([]);
    addTearDown(c.dispose);
    await pumpShell(tester, c);

    await tester.tap(find.text(l.t('nav_child')));
    await tester.pumpAndSettle();
    expect(find.byTooltip(l.t('tr_child_card')), findsNothing);
  });

  testWidgets("Профиль's children tile opens the child, not the map",
      (tester) async {
    final c = controllerWith([
      ChildProfile(id: 'c1', name: 'Сұлтан', dateOfBirth: DateTime(2024, 3, 2)),
    ]);
    addTearDown(c.dispose);
    await pumpShell(tester, c);

    await tester.tap(find.text(l.t('nav_profile')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l.t('prof_children_count')));
    await tester.pumpAndSettle();

    expect(find.byType(ChildDetailScreen), findsOneWidget,
        reason: 'the tile still lands on the tracking map');
  });

  testWidgets('with two children it asks which one rather than guessing',
      (tester) async {
    final c = controllerWith([
      ChildProfile(id: 'c1', name: 'Сұлтан', dateOfBirth: DateTime(2024, 3, 2)),
      ChildProfile(id: 'c2', name: 'Аяжан', dateOfBirth: DateTime(2019, 5, 9)),
    ]);
    addTearDown(c.dispose);
    await pumpShell(tester, c);

    await tester.tap(find.text(l.t('nav_profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.t('prof_children_count')));
    await tester.pumpAndSettle();

    // The picker, not the first child's medical record.
    expect(find.text(l.t('tr_pick_child')), findsOneWidget);
    expect(find.byType(ChildDetailScreen), findsNothing);

    await tester.tap(find.text('Аяжан'));
    await tester.pumpAndSettle();
    expect(find.byType(ChildDetailScreen), findsOneWidget);
    // The one she picked — not whoever the map happened to have selected.
    expect(find.text('Аяжан'), findsWidgets);
  });

  testWidgets('«Настроить остальные» opens the reminders centre',
      (tester) async {
    final c = controllerWith([
      ChildProfile(id: 'c1', name: 'Сұлтан', dateOfBirth: DateTime(2024, 3, 2)),
    ]);
    addTearDown(c.dispose);
    await pumpShell(tester, c);

    await tester.tap(find.text(l.t('nav_child')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l.t('alerts_title')).first);
    await tester.pumpAndSettle();

    expect(find.text(l.t('ntf_configure_rest')), findsOneWidget,
        reason: 'the button was hidden by a hard null');
    await tester.tap(find.text(l.t('ntf_configure_rest')));
    await tester.pumpAndSettle();

    expect(find.byType(RemindersCenterScreen), findsOneWidget);
    // The screen it lands on really is the one with the switches on it —
    // including quiet hours, which is what «остальные» means here.
    expect(find.text(l.t('rem_title')), findsWidgets);
    expect(find.text(l.t('notif_quiet')), findsOneWidget);
  });
}
