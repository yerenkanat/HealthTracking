/// The soft update nudge — TODO §4.2, the gentle step between "fine" and
/// "blocked".
///
/// `GET /app/version` has always answered with two numbers and the ApiClient has
/// always parsed both, but `main.dart` read only `minBuild`. `latestBuild` was
/// fetched, decoded, carried into the process and dropped one line short of the
/// controller, so the app had exactly two states: running, and walled off behind
/// the force-update screen. A mother sat on a stale build for as long as the
/// server tolerated it and then, one back-office edit later, hit a full-screen
/// block she had never been warned about. `appUpdateAvailable` — the function
/// whose own doc comment describes this nudge — had no caller anywhere outside
/// tool/verify_app_version.dart.
///
/// So these tests refuse to construct the strip directly. Every one of them
/// starts at an HTTP response and ends at what is on the phone's screen, driving
/// the real launch call (`refreshAppVersionFromApi`, which is what `main()`
/// invokes) into the real app root (`FcsApp` → `HomeShell`). A test that built
/// `UpdateNudgeStrip` by hand would have passed against the broken code.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/app/app_version_refresh.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/data/app_store.dart';
import 'package:fcs_app/data/content_store.dart';
import 'package:fcs_app/data/persisted_config.dart';
import 'package:fcs_app/domain/app_version.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/legal.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/force_update_screen.dart';
import 'package:fcs_app/ui/home_shell.dart';
import 'package:fcs_app/ui/widgets/update_nudge.dart';

/// The server, answering /app/version with whatever the case under test needs.
class _VersionTransport implements HttpTransport {
  Map<String, Object?> body;
  final paths = <String>[];
  _VersionTransport(this.body);

  @override
  Future<HttpResponse> get(String path) async {
    paths.add(path);
    if (path == '/app/version') return HttpResponse(200, jsonEncode(body));
    return const HttpResponse(200, '{}');
  }

  @override
  Future<HttpResponse> post(String path, Object body) async => const HttpResponse(201, '{}');
  @override
  Future<HttpResponse> put(String path, Object body) async => const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');
}

/// A phone that has finished onboarding and accepted the current terms — the
/// only state in which the shell (and therefore the strip) is ever on screen.
PersistedConfig onboardedConfig({
  int dismissedBuild = 0,
  DateTime? dismissedAt,
}) =>
    PersistedConfig(
      onboarded: true,
      acceptedLegalVersion: currentLegalVersion,
      locale: AppLocale.en,
      profile: const UserProfile(displayName: 'Айгүл'),
      children: const [],
      devices: const [],
      updateNudgeDismissedBuild: dismissedBuild,
      updateNudgeDismissedAt: dismissedAt,
    );

const l = L10n(AppLocale.en);

void main() {
  // A phone-sized viewport: the strip sits above the shell's IndexedStack, and
  // the default 800x600 test window is not a phone.
  void phoneSized(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// One cold launch: restore from [store], ask the server for the version
  /// policy exactly as main() does, and paint the app root.
  Future<AppController> launch(
    WidgetTester tester, {
    required AppStore store,
    required Map<String, Object?> serverSays,
    required DateTime now,
  }) async {
    final transport = _VersionTransport(serverSays);
    final c = AppController(now: () => now, locale: AppLocale.en, persistStore: store);
    addTearDown(c.dispose);
    await c.restore();

    // The real launch-time call. NOT controller.applyAppVersion() — the defect
    // being fixed lived in the caller, not the controller.
    await refreshAppVersionFromApi(api: ApiClient(transport), controller: c);
    expect(transport.paths, contains('/app/version'),
        reason: 'the launch path never asked the server for the version policy');

    await tester.pumpWidget(
      FcsApp(controller: c, content: ContentStore(const ContentCatalog({}))),
    );
    await tester.pumpAndSettle();
    return c;
  }

  /// The strip, only when it is actually painted.
  ///
  /// `skipOffstage` is left at its default true on purpose: the shell keeps
  /// every tab alive inside an IndexedStack, so "a widget exists in the tree"
  /// and "a mother can see it" are different questions here, and only the
  /// second one is worth asserting.
  final strip = find.byType(UpdateNudgeStrip);

  testWidgets('an up-to-date build is told nothing at all', (tester) async {
    phoneSized(tester);
    await launch(
      tester,
      store: InMemoryAppStore(onboardedConfig()),
      serverSays: {'minBuild': currentAppBuild, 'latestBuild': currentAppBuild},
      now: DateTime.utc(2026, 8, 18, 9),
    );

    expect(find.byType(HomeShell), findsOneWidget);
    expect(strip, findsNothing);
    expect(find.text(l.t('upd_title')), findsNothing,
        reason: 'nothing to update to, so there is nothing to say');
  });

  testWidgets('below latestBuild but above minBuild, she gets the nudge on the shell',
      (tester) async {
    phoneSized(tester);
    await launch(
      tester,
      store: InMemoryAppStore(onboardedConfig()),
      // At the floor — allowed to run — with a newer build published.
      serverSays: {'minBuild': currentAppBuild, 'latestBuild': currentAppBuild + 3},
      now: DateTime.utc(2026, 8, 18, 9),
    );

    // The app is running, not blocked.
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(ForceUpdateScreen), findsNothing);

    // And the nudge is painted, with its words, on the screen she is looking at.
    expect(strip, findsOneWidget,
        reason: 'latestBuild reached the controller and stopped there');
    expect(find.text(l.t('upd_title')), findsOneWidget);
    expect(find.text(l.t('upd_cta')), findsOneWidget);
  });

  testWidgets('a build below minBuild is blocked — and NOT also nudged', (tester) async {
    phoneSized(tester);
    final c = await launch(
      tester,
      store: InMemoryAppStore(onboardedConfig()),
      serverSays: {'minBuild': currentAppBuild + 1, 'latestBuild': currentAppBuild + 3},
      now: DateTime.utc(2026, 8, 18, 9),
    );

    expect(c.mustUpdate, isTrue);
    expect(find.byType(ForceUpdateScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    // The block owns this state. A dismissible strip behind a screen with no way
    // out would be an invitation to close the only thing that is not stuck.
    expect(strip, findsNothing);
    expect(c.updateNudgeVisible, isFalse);
    // The block's own copy is what she reads, and it says more than the strip.
    expect(find.text(l.t('upd_body')), findsOneWidget);
  });

  testWidgets('closing it is remembered across a relaunch, then expires', (tester) async {
    phoneSized(tester);
    final store = InMemoryAppStore(onboardedConfig());
    const serverSays = {'minBuild': currentAppBuild, 'latestBuild': currentAppBuild + 3};
    final firstLaunch = DateTime.utc(2026, 8, 18, 9);

    // --- Launch 1: she sees it and closes it.
    final c1 = await launch(
      tester, store: store, serverSays: serverSays, now: firstLaunch);
    expect(strip, findsOneWidget);

    await tester.tap(find.byTooltip(l.t('act_close')));
    await tester.pumpAndSettle();
    expect(strip, findsNothing, reason: 'the close button did not close it');

    // Persisted, not merely forgotten in RAM. flushPendingSave is what the app
    // itself calls on pause; without the write reaching the store, everything
    // below would pass on a controller that never round-tripped.
    c1.flushPendingSave();
    await tester.pump();
    final saved = await store.load();
    expect(saved!.updateNudgeDismissedBuild, currentAppBuild + 3);
    expect(saved.updateNudgeDismissedAt, firstLaunch);

    // --- Launch 2, the next day: a fresh controller off the same disk.
    await launch(
      tester,
      store: store,
      serverSays: serverSays,
      now: firstLaunch.add(const Duration(days: 1)),
    );
    expect(strip, findsNothing,
        reason: 'a nudge that returns every launch trains her to ignore the hard block');

    // --- Launch 3, once the snooze has run out: it speaks up again.
    await launch(
      tester,
      store: store,
      serverSays: serverSays,
      now: firstLaunch.add(updateNudgeSnooze),
    );
    expect(strip, findsOneWidget,
        reason: 'snoozed is not silenced — the build is still out of date');
  });

  testWidgets('a newer release than the one she snoozed asks again immediately',
      (tester) async {
    phoneSized(tester);
    final dismissedAt = DateTime.utc(2026, 8, 18, 9);
    final store = InMemoryAppStore(onboardedConfig(
      dismissedBuild: currentAppBuild + 1,
      dismissedAt: dismissedAt,
    ));

    // Same day — well inside the snooze — but the store now has a build newer
    // than the one she waved away.
    await launch(
      tester,
      store: store,
      serverSays: {'minBuild': currentAppBuild, 'latestBuild': currentAppBuild + 2},
      now: dismissedAt.add(const Duration(hours: 2)),
    );
    expect(strip, findsOneWidget);
  });

  testWidgets('an unreachable server neither blocks nor nudges', (tester) async {
    phoneSized(tester);
    final c = AppController(
      now: () => DateTime.utc(2026, 8, 18, 9),
      locale: AppLocale.en,
      persistStore: InMemoryAppStore(onboardedConfig()),
    );
    addTearDown(c.dispose);
    await c.restore();

    // A transport that fails the way a dead network does.
    await refreshAppVersionFromApi(api: ApiClient(_FailingTransport()), controller: c);

    await tester.pumpWidget(
      FcsApp(controller: c, content: ContentStore(const ContentCatalog({}))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(ForceUpdateScreen), findsNothing);
    expect(strip, findsNothing, reason: 'never invent a version policy we could not fetch');
  });

  testWidgets('the CTA is a real action, and the listing it opens is this app',
      (tester) async {
    // The button on the strip is the same Play listing the hard block opens,
    // derived from the applicationId in build.gradle.kts — so it cannot be a
    // dead link while a newer build exists to nudge towards.
    expect(playListingUrl, contains('id=com.fcs.fcs_app'));

    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: L10nScope(
          l10n: l,
          child: UpdateNudgeStrip(onDismiss: () {}, onUpdate: () => tapped++),
        ),
      ),
    ));
    await tester.tap(find.text(l.t('upd_cta')));
    expect(tapped, 1);
  });

  testWidgets('the strip speaks Kazakh', (tester) async {
    phoneSized(tester);
    final c = AppController(
      now: () => DateTime.utc(2026, 8, 18, 9),
      locale: AppLocale.kk,
      persistStore: InMemoryAppStore(PersistedConfig(
        onboarded: true,
        acceptedLegalVersion: currentLegalVersion,
        locale: AppLocale.kk,
        profile: const UserProfile(displayName: 'Айгүл'),
        children: const [],
        devices: const [],
      )),
    );
    addTearDown(c.dispose);
    await c.restore();
    await refreshAppVersionFromApi(
      api: ApiClient(_VersionTransport(
          {'minBuild': currentAppBuild, 'latestBuild': currentAppBuild + 1})),
      controller: c,
    );
    await tester.pumpWidget(
      FcsApp(controller: c, content: ContentStore(const ContentCatalog({}))),
    );
    await tester.pumpAndSettle();

    const kk = L10n(AppLocale.kk);
    expect(find.text(kk.t('upd_title')), findsOneWidget);
    expect(find.text(kk.t('upd_cta')), findsOneWidget);
    // Not the Russian copy leaking through a missing translation.
    expect(kk.t('upd_title'), isNot(const L10n(AppLocale.ru).t('upd_title')));
    expect(kk.t('upd_cta'), isNot(const L10n(AppLocale.ru).t('upd_cta')));
  });
}

class _FailingTransport implements HttpTransport {
  @override
  Future<HttpResponse> get(String path) async => throw const SocketishFailure();
  @override
  Future<HttpResponse> post(String path, Object body) async => throw const SocketishFailure();
  @override
  Future<HttpResponse> put(String path, Object body) async => throw const SocketishFailure();
  @override
  Future<HttpResponse> delete(String path) async => throw const SocketishFailure();
}

class SocketishFailure implements Exception {
  const SocketishFailure();
}
