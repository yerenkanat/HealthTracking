/// The force-update gate: the controller flag flips only on a raised floor, the
/// app root shows the blocking screen when set, and the ApiClient parses the
/// policy.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/app_version.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/force_update_screen.dart';

class _FakeTransport implements HttpTransport {
  Object? getBody;
  @override
  Future<HttpResponse> get(String path) async => HttpResponse(200, jsonEncode(getBody ?? {}));
  @override
  Future<HttpResponse> post(String path, Object body) async => const HttpResponse(201, '{}');
  @override
  Future<HttpResponse> put(String path, Object body) async => const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');
}

void main() {
  group('ApiClient.getAppVersion', () {
    test('parses minBuild / latestBuild', () async {
      final t = _FakeTransport()..getBody = {'minBuild': 7, 'latestBuild': 9};
      final v = await ApiClient(t).getAppVersion();
      expect(v.minBuild, 7);
      expect(v.latestBuild, 9);
    });

    test('a missing field reads as 0 (blocks nobody)', () async {
      final t = _FakeTransport()..getBody = {};
      final v = await ApiClient(t).getAppVersion();
      expect(v.minBuild, 0);
    });
  });

  group('controller gate', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 23), locale: AppLocale.ru);

    test('an unset / low floor does not block', () {
      final c = make();
      addTearDown(c.dispose);
      c.applyMinBuild(0);
      expect(c.mustUpdate, isFalse);
      c.applyMinBuild(currentAppBuild); // equal → allowed
      expect(c.mustUpdate, isFalse);
    });

    test('a raised floor blocks', () {
      final c = make();
      addTearDown(c.dispose);
      c.applyMinBuild(currentAppBuild + 1);
      expect(c.mustUpdate, isTrue);
    });
  });

  testWidgets('the force-update screen shows the block message', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: L10nScope(l10n: L10n(AppLocale.en), child: ForceUpdateScreen()),
    ));
    expect(find.text('Time to update the app'), findsOneWidget);
  });

  testWidgets('a way forward exists without one having to be injected',
      (tester) async {
    // This asserted findsNothing, certifying the defect: the screen has no way
    // BACK into the app by design, and with no button it had no way forward
    // either — a mother was simply stuck. Nothing but the server puts her here,
    // and the server cannot demand an update that has not been published, so
    // the listing exists whenever this is on screen.
    await tester.pumpWidget(const MaterialApp(
      home: L10nScope(l10n: L10n(AppLocale.en), child: ForceUpdateScreen()),
    ));
    expect(find.text('Update'), findsOneWidget);
  });

  test('the store link is the Play listing for this applicationId', () {
    // Derived from build.gradle.kts. If the applicationId is ever changed
    // without changing this, the only button on the blocking screen goes to
    // somebody else's app.
    expect(playListingUrl, contains('id=com.fcs.fcs_app'));
  });

  testWidgets('an injected callback wins, so nothing has to leave the process',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(l10n: const L10n(AppLocale.en), child: ForceUpdateScreen(onUpdate: () => tapped = true)),
    ));
    expect(find.text('Update'), findsOneWidget);
    await tester.tap(find.text('Update'));
    expect(tapped, isTrue);
  });
}
