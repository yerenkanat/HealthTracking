/// When the app asks the server for her рассылки — and it is not «once, at
/// launch, if she happened to be signed in already».
///
/// The fetch used to have exactly one call site: `bootstrapRuntime`, behind
/// `if (controller.authSession == null) return;`. On a fresh install that
/// branch is always taken — the app launches before she has onboarded, let
/// alone signed in — so `GET /announcements` was never called in that process
/// at all. An operator could publish to «Все», the server could record the
/// delivery and fire the push, and her notification centre would stay empty
/// with the bell reading 0 until she force-quit the app. Existing signed-in
/// users had the milder version of the same bug: anything published while the
/// app was open or backgrounded waited for the next cold start.
///
/// Nothing caught it because every other app test hands the list straight to
/// `setAnnouncements`. So this file asserts the CALLS, at the three moments the
/// repo's own fetch-on-open pattern says they belong: sign-in, resume, and
/// opening the screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/content_store.dart';
import 'package:fcs_app/domain/announcement.dart';
import 'package:fcs_app/domain/phone_auth.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/home_shell.dart';
import 'package:fcs_app/ui/theme.dart';

const l = L10n(AppLocale.ru);

Announcement announcement(DateTime at, {String id = 'bc-1', String title = 'Второй скрининг'}) =>
    Announcement(
      id: id,
      at: at,
      ru: AnnouncementText(title: title, body: 'Окно 18–21 неделя — запишитесь заранее.'),
      kk: const AnnouncementText(title: 'Екінші скрининг', body: '18–21 апта.'),
    );

AuthSession session(DateTime now) => AuthSession(
      userId: 'u-1', phoneE164: '+77001112233', token: 't', signedInAt: now,
    );

void main() {
  final now = DateTime(2026, 8, 12, 15);

  /// A controller with the hook main.dart wires, counting the pulls.
  ({AppController c, List<int> pulls}) make() {
    final pulls = <int>[];
    final c = AppController(now: () => now);
    c.onRefreshAnnouncements = () async => pulls.add(1);
    return (c: c, pulls: pulls);
  }

  test('signing in pulls her mail — the launch fetch already ran and gave up', () {
    final (:c, :pulls) = make();
    // Startup, on a fresh install: no session, so main.dart's pull returns
    // without asking. Nothing has been fetched.
    c.refreshAnnouncements();
    expect(pulls, isEmpty, reason: '/announcements is user-scoped — an unauthenticated call is a 401');

    c.signIn(session(now));
    expect(pulls, hasLength(1),
        reason: 'she signed in and nothing re-fetched: her centre would stay empty until a cold start');
  });

  test('a signed-in controller re-fetches on demand; a signed-out one never does', () {
    final (:c, :pulls) = make();
    c.signIn(session(now));
    pulls.clear();

    c.refreshAnnouncements();
    c.refreshAnnouncements();
    expect(pulls, hasLength(2), reason: 'cheap to repeat — a failed refresh keeps what is on screen');

    c.signOut();
    c.refreshAnnouncements();
    expect(pulls, hasLength(2));
  });

  test('without the hook it is a no-op rather than a crash — every widget test runs this way', () {
    final c = AppController(now: () => now)..signIn(session(now));
    expect(c.refreshAnnouncements, returnsNormally);
  });

  testWidgets('coming back to the app re-fetches — a phone sits backgrounded for days', (tester) async {
    final (:c, :pulls) = make();
    c.signIn(session(now));
    pulls.clear();

    await tester.pumpWidget(
      FcsApp(controller: c, content: ContentStore(const ContentCatalog({}))),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(pulls, isEmpty, reason: 'leaving flushes the save; it does not fetch');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(pulls, hasLength(1),
        reason: 'a рассылка published while she was away must not wait for the next cold launch');
  });

  testWidgets('the bell re-fetches, and the answer lands on the OPEN screen', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final c = AppController();
    c.signIn(AuthSession(
      userId: 'u-1', phoneE164: '+77001112233', token: 't', signedInAt: DateTime.now(),
    ));
    // The pull the tap triggers, answered as the server would answer it.
    var pulls = 0;
    // A round trip the test controls, so the answer provably arrives AFTER the
    // centre is on screen — the ordinary case, and the one that used to land
    // behind the pushed route where she could not see it. A plain delay would
    // not prove it: pumpAndSettle advances the clock through the push
    // transition, and the timer would fire before the screen's first build.
    final answered = Completer<void>();
    c.onRefreshAnnouncements = () async {
      pulls++;
      await answered.future;
      c.setAnnouncements([
        announcement(DateTime.now().subtract(const Duration(minutes: 2)),
            id: 'bc-new', title: 'Приём в четверг'),
      ]);
    };

    await tester.pumpWidget(L10nScope(
      l10n: l,
      child: MaterialApp(
        theme: FcsTheme.light(AppLocale.ru),
        home: HomeShell(controller: c, catalog: const ContentCatalog({})),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l.t('nav_child')));
    await tester.pumpAndSettle();
    expect(pulls, 0);

    await tester.tap(find.byTooltip(l.t('alerts_title')).first);
    await tester.pumpAndSettle();

    expect(pulls, 1, reason: 'the centre was opened without asking the server for anything');
    // Open, and empty — she has nothing yet, and the screen never waits on the
    // network to say so.
    expect(find.text(l.t('ntf_empty')), findsOneWidget);

    // Now the server answers, with the centre already in front of her.
    answered.complete();
    await tester.pumpAndSettle();

    // Not «it will be there next time»: the screen she is looking at right now.
    expect(find.text('Приём в четверг'), findsOneWidget,
        reason: 'the fetch landed behind the pushed route instead of on it');
    expect(find.text(l.t('ntf_empty')), findsNothing);
  });
}
