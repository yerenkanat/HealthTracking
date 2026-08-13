/// Screen 43 from the Профиль tab, and the badge that says it is worth opening.
///
/// The operator's answer used to be four taps away — Профиль → ⚙ → «Помощь» →
/// «Открыть переписку» — and the unread-answer count was computed on the third
/// of those screens, where nobody who had not already gone looking could see
/// it. A badge nobody sees is the same as no badge.
///
/// Driven over a stubbed transport rather than a fake screen: the count comes
/// from `/support`, and a row that draws a hard-coded number would pass a test
/// that never asked the server anything.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/home_shell.dart';
import 'package:fcs_app/ui/theme.dart';

const ru = L10n(AppLocale.ru);
final now = DateTime(2026, 8, 12, 9);

/// One ticket the desk has answered and she has not opened since.
Map<String, dynamic> answeredTicket() => {
      'tickets': [
        {
          'id': 't1',
          'subject': 'Трекер не обновляет местоположение',
          'body': 'Последняя точка со вчера.',
          'status': 'waiting',
          'createdAt': '2026-08-11T09:00:00.000Z',
          'replies': [
            {
              'id': 'r1',
              'ticketId': 't1',
              'author': 'staff',
              'body': 'Проверьте зарядку брелока, мы видим последний сигнал в 21:40.',
              'at': '2026-08-11T10:00:00.000Z',
            }
          ],
        }
      ],
      'slaHours': 4,
    };

class _Stub implements HttpTransport {
  final Map<String, dynamic> support;
  int supportCalls = 0;
  _Stub(this.support);

  @override
  Future<HttpResponse> get(String path) async {
    if (path.startsWith('/support')) {
      supportCalls++;
      return HttpResponse(200, jsonEncode(support));
    }
    return const HttpResponse(404, '');
  }

  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');
  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);
  @override
  Future<HttpResponse> post(String path, Object body) async =>
      const HttpResponse(404, '');
}

AppController signedIn(HttpTransport stub) {
  final c = AppController(now: () => now, locale: AppLocale.ru);
  c.attachRuntime(api: ApiClient(stub));
  return c;
}

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
  testWidgets('«Поддержка» is a Профиль row, two taps from the tab bar',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final stub = _Stub(answeredTicket());
    final c = signedIn(stub);
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    // Tap 1 — the Профиль tab.
    await tester.tap(find.text(ru.t('nav_profile')));
    await tester.pumpAndSettle();

    expect(find.text(ru.t('sup_title')), findsOneWidget,
        reason: 'support is still behind the gear icon');
    // Beside «Семейный доступ», not buried at the bottom of the list.
    expect(find.text(ru.t('fam_title')), findsOneWidget);

    // The badge came off the server, and says what is waiting.
    expect(find.byKey(const Key('support-entry-badge')), findsOneWidget,
        reason: 'the unread answer is announced nowhere she can see it');
    expect(
        find.text(ru.t('sup_chat_row_waiting', {'n': '1'})), findsOneWidget);
    expect(stub.supportCalls, greaterThan(0));

    // Tap 2 — the row itself lands on screen 43, with the answer on it.
    await tester.tap(find.text(ru.t('sup_title')));
    await tester.pumpAndSettle();
    expect(find.text('Трекер не обновляет местоположение'), findsWidgets);
    expect(
        find.textContaining('Проверьте зарядку брелока'), findsWidgets,
        reason: 'the row opened something other than the conversation');
  });

  testWidgets('no answer waiting draws no badge', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Same ticket, already read: an answer she has seen is not news, and a
    // badge that never goes down is one she stops reading.
    final body = answeredTicket();
    (body['tickets'] as List).first['customerReadAt'] =
        '2026-08-11T11:00:00.000Z';
    final c = signedIn(_Stub(body));
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    await tester.tap(find.text(ru.t('nav_profile')));
    await tester.pumpAndSettle();

    expect(find.text(ru.t('sup_title')), findsOneWidget);
    expect(find.byKey(const Key('support-entry-badge')), findsNothing);
    expect(find.text(ru.t('sup_chat_row_none')), findsOneWidget);
  });

  testWidgets('Настройки keeps its own way in', (tester) async {
    // Fixing a dead end must not delete the other route to the same screen:
    // «Помощь и поддержка» is the help hub — FAQ, WhatsApp, self-service — and
    // the thread is one row inside it.
    tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final c = signedIn(_Stub(answeredTicket()));
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    await tester.tap(find.text(ru.t('nav_profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(ru.t('settings_title')));
    await tester.pumpAndSettle();
    // It lives in «О приложении», below the fold — which is exactly why it
    // was not a route anybody found, and why it is not the only one now.
    await tester.dragUntilVisible(
      find.text(ru.t('set_help')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text(ru.t('set_help')), findsOneWidget);
  });
}
