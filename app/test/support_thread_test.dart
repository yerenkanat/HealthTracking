/// Screen 43 — «Поддержка · оператор».
///
/// The defect this screen closes: the back office could ANSWER a customer and
/// she had nowhere to read it. So the tests that matter are the ways this
/// screen could be worse than nothing — showing a message as sent when it
/// never left the phone, hiding an answer that has arrived, or writing into a
/// ticket that is closed and telling her nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/support_context.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/design_system.dart';
import 'package:fcs_app/ui/settings/help_support_screen.dart';
import 'package:fcs_app/ui/settings/support_thread_screen.dart';
import 'package:fcs_app/ui/theme.dart';

const l = L10n(AppLocale.ru);

Map<String, dynamic> ticketJson({
  String id = 't1',
  String subject = 'Не приходит код',
  String body = 'Жду 10 минут.',
  String status = 'new',
  String createdAt = '2026-08-11T09:00:00.000Z',
  String? readAt,
  List<Map<String, dynamic>> replies = const [],
}) =>
    {
      'id': id,
      'subject': subject,
      'body': body,
      'status': status,
      'createdAt': createdAt,
      if (readAt != null) 'customerReadAt': readAt,
      'replies': replies,
    };

Map<String, dynamic> staffReply(String body,
        {String at = '2026-08-11T10:00:00.000Z'}) =>
    {'id': 'r1', 'ticketId': 't1', 'author': 'staff', 'body': body, 'at': at};

// ---------------------------------------------------------------------------

class _Recorder {
  final created = <({String subject, String body})>[];
  final replied = <({String id, String body})>[];

  /// Which threads the screen told the server she had read. This is the only
  /// thing that takes the «Есть ответ поддержки» badge down.
  final read = <String>[];
  bool failRead = false;
  bool failSend = false;
  bool failLoad = false;
  List<SupportThread> threads;

  _Recorder({this.threads = const []});

  Future<void> markRead(String id) async {
    if (failRead) throw Exception('offline');
    read.add(id);
  }

  Future<SupportThreadsPayload> load() async {
    if (failLoad) throw Exception('offline');
    return (threads: threads, slaHours: 4);
  }

  Future<String> create(String subject, String body) async {
    if (failSend) throw Exception('offline');
    created.add((subject: subject, body: body));
    return 'new-id';
  }

  Future<void> reply(String id, String body) async {
    if (failSend) throw Exception('offline');
    replied.add((id: id, body: body));
  }
}

Future<_Recorder> pump(
  WidgetTester tester, {
  List<Map<String, dynamic>> tickets = const [],
  bool failSend = false,
  bool failLoad = false,
  bool failRead = false,
  ({String label, VoidCallback onTap})? action,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final rec = _Recorder(
    threads: SupportThread.parseAll({'tickets': tickets}),
  )
    ..failSend = failSend
    ..failLoad = failLoad
    ..failRead = failRead;

  // L10nScope ABOVE MaterialApp. Below it, a route PUSHED from this screen
  // falls back to English and every assertion below reads as a broken screen.
  await tester.pumpWidget(L10nScope(
    l10n: l,
    child: MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: SupportThreadScreen(
        load: rec.load,
        onCreate: rec.create,
        onReply: rec.reply,
        onRead: rec.markRead,
        action: action,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return rec;
}

/// The mother's own bubble — the only `#D6004A` on the screen.
Container? myBubble(WidgetTester tester) {
  for (final c in tester.widgetList<Container>(find.byType(Container))) {
    final d = c.decoration;
    if (d is BoxDecoration && d.color == Ds.coral && d.borderRadius != null) {
      return c;
    }
  }
  return null;
}

void main() {
  group('reading the thread', () {
    test('her opening message IS the ticket body, not a separate field', () {
      final t = SupportThread.parse(ticketJson())!;
      expect(t.messages.first.author, SupportAuthor.customer);
      expect(t.messages.first.body, 'Жду 10 минут.');
    });

    test('falls back to the subject when the body is empty', () {
      // An operator taking a phone call types a subject and no body. An empty
      // bubble is worse than repeating the line she can already see.
      final t = SupportThread.parse(ticketJson(body: ''))!;
      expect(t.messages.first.body, 'Не приходит код');
    });

    test('puts the replies in the order they were said', () {
      final t = SupportThread.parse(ticketJson(replies: [
        staffReply('Второе', at: '2026-08-11T12:00:00.000Z'),
        staffReply('Первое', at: '2026-08-11T11:00:00.000Z'),
      ]))!;
      expect(t.messages.map((m) => m.body).toList(),
          ['Жду 10 минут.', 'Первое', 'Второе']);
    });

    test('a status this build does not know is not a crash', () {
      // A server that learns a fifth status must not blank her conversation.
      expect(SupportThread.parse(ticketJson(status: 'escalated'))!.status,
          SupportStatus.isNew);
    });

    test('drops a ticket it cannot make sense of rather than the whole list', () {
      final list = SupportThread.parseAll({
        'tickets': [ticketJson(), {'nonsense': true}, 'string'],
      });
      expect(list, hasLength(1));
    });

    test('an answer she has not opened is what the badge counts', () {
      final unread = SupportThread.parse(ticketJson(
          status: 'waiting', replies: [staffReply('Ответ.')]))!;
      expect(unread.unreadAnswer, isTrue);

      // Read AFTER the answer: nothing new. This is the case that used to be
      // impossible — the badge could only ever go up.
      final read = SupportThread.parse(ticketJson(
          status: 'waiting',
          readAt: '2026-08-11T11:00:00.000Z',
          replies: [staffReply('Ответ.', at: '2026-08-11T10:00:00.000Z')]))!;
      expect(read.unreadAnswer, isFalse);

      // And the next answer lights it again — the reason this is an instant
      // and not a flag.
      final answeredAgain = SupportThread.parse(ticketJson(
          status: 'waiting',
          readAt: '2026-08-11T11:00:00.000Z',
          replies: [
            staffReply('Ответ.', at: '2026-08-11T10:00:00.000Z'),
            staffReply('И ещё.', at: '2026-08-11T12:00:00.000Z'),
          ]))!;
      expect(answeredAgain.unreadAnswer, isTrue);
    });

    test('a server that never heard of read receipts still lights the badge',
        () {
      // No customerReadAt on the wire (an older build of the API) reads as
      // «never opened», which is exactly the behaviour she had before.
      final t = SupportThread.parse(
          ticketJson(status: 'waiting', replies: [staffReply('Ответ.')]))!;
      expect(t.readAt, isNull);
      expect(t.unreadAnswer, isTrue);
    });

    test('«ждём клиента» is the state that means there is something to read', () {
      expect(SupportThread.parse(ticketJson(status: 'waiting'))!.answerWaiting,
          isTrue);
      expect(SupportThread.parse(ticketJson(status: 'open'))!.answerWaiting,
          isFalse);
      expect(SupportThread.parse(ticketJson(status: 'closed'))!.open, isFalse);
    });
  });

  group('the dialogue', () {
    testWidgets('shows what she wrote AND what the operator answered',
        (tester) async {
      await pump(tester, tickets: [
        ticketJson(status: 'waiting', replies: [staffReply('Код отправлен заново.')]),
      ]);
      expect(find.text('Жду 10 минут.'), findsOneWidget);
      // The whole point of the screen: an answer that used to exist only in the
      // panel is now readable by the person it was written for.
      expect(find.text('Код отправлен заново.'), findsOneWidget);
    });

    testWidgets('draws her bubble in #D6004A with white text', (tester) async {
      await pump(tester, tickets: [ticketJson()]);
      final bubble = myBubble(tester);
      expect(bubble, isNotNull, reason: 'the mother\'s bubble is #D6004A');
      final radius = (bubble!.decoration as BoxDecoration).borderRadius
          as BorderRadius;
      // §2.18: `border-radius:18 18 6 18`.
      expect(radius.topLeft.x, 18);
      expect(radius.bottomRight.x, 6);

      final text = tester.widget<Text>(find.text('Жду 10 минут.'));
      // White on #D6004A. Any darker text on this colour fails contrast, and
      // this is the one surface in the app allowed to carry it.
      expect(text.style?.color, Colors.white);
    });

    testWidgets('names who said each line', (tester) async {
      await pump(tester, tickets: [
        ticketJson(replies: [staffReply('Проверяю.')]),
      ]);
      expect(find.text(l.t('sup_chat_you')), findsOneWidget);
      // Once in the header, once over the reply.
      expect(find.text(l.t('sup_chat_who')), findsNWidgets(2));
    });

    testWidgets('says support is not the ambulance', (tester) async {
      await pump(tester);
      expect(find.textContaining('103'), findsOneWidget);
    });

    testWidgets('an empty desk invites her to write rather than looking broken',
        (tester) async {
      await pump(tester);
      expect(find.text(l.t('sup_chat_empty')), findsOneWidget);
      expect(find.text(l.t('sup_chat_first_note')), findsOneWidget);
    });

    testWidgets('SAYS the conversation did not load', (tester) async {
      await pump(tester, failLoad: true);
      expect(find.text(l.t('sup_chat_load_failed')), findsOneWidget);
      expect(find.text(l.t('sup_chat_retry')), findsOneWidget);
    });
  });

  group('every conversation, not just the newest', () {
    // The desk can open a SECOND ticket for her from the panel (POST
    // /admin/support takes a userId) and answer both. This screen used to draw
    // one of them, so «Есть ответ поддержки · 2» led to a screen showing one
    // conversation and the other answer was unreachable anywhere in the app.
    final two = [
      ticketJson(
        id: 'new', subject: 'Где мой заказ', body: 'Оплатила вчера.',
        status: 'waiting', createdAt: '2026-08-11T09:00:00.000Z',
        replies: [staffReply('Заказ придёт завтра.',
            at: '2026-08-11T10:00:00.000Z')],
      ),
      ticketJson(
        id: 'old', subject: 'Браслет не включается', body: 'Не горит лампочка.',
        status: 'waiting', createdAt: '2026-08-09T09:00:00.000Z',
        replies: [staffReply('Зарядите два часа.',
            at: '2026-08-09T10:00:00.000Z')],
      ),
    ];

    testWidgets('draws the answer in EVERY ticket, and both subjects',
        (tester) async {
      await pump(tester, tickets: two);
      expect(find.text('Заказ придёт завтра.'), findsOneWidget);
      expect(find.text('Зарядите два часа.'), findsOneWidget);
      expect(find.text('Где мой заказ'), findsOneWidget);
      expect(find.text('Браслет не включается'), findsOneWidget);
    });

    testWidgets('puts the live one LAST, against the input', (tester) async {
      await pump(tester, tickets: two);
      // Oldest first, live last: the thread her message goes into is the one
      // under her thumb.
      expect(tester.getTopLeft(find.text('Браслет не включается')).dy,
          lessThan(tester.getTopLeft(find.text('Где мой заказ')).dy));
      expect(find.text(l.t('sup_chat_thread_live')), findsOneWidget);
      expect(find.text(l.t('sup_chat_thread_past')), findsOneWidget);
    });

    testWidgets('says nothing about roles when there is only one thread',
        (tester) async {
      await pump(tester, tickets: [ticketJson()]);
      expect(find.text(l.t('sup_chat_thread_live')), findsNothing);
      expect(find.text(l.t('sup_chat_thread_past')), findsNothing);
    });

    testWidgets('writes into the newest OPEN one', (tester) async {
      final rec = await pump(tester, tickets: two);
      await tester.enterText(find.byType(TextField), 'Уточните время.');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(rec.replied, [(id: 'new', body: 'Уточните время.')]);
    });

    testWidgets('a closed newest ticket still shows the OPEN older one',
        (tester) async {
      // The live thread is the newest one still open, whatever the order.
      final rec = await pump(tester, tickets: [
        ticketJson(id: 'new', subject: 'Закрытое', status: 'closed',
            createdAt: '2026-08-11T09:00:00.000Z'),
        ticketJson(id: 'old', subject: 'Открытое', status: 'open',
            createdAt: '2026-08-09T09:00:00.000Z'),
      ]);
      expect(find.text('Закрытое'), findsOneWidget);
      expect(find.text('Открытое'), findsOneWidget);
      expect(find.text(l.t('sup_chat_closed')), findsNothing);

      await tester.enterText(find.byType(TextField), 'Ещё вопрос.');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(rec.replied, [(id: 'old', body: 'Ещё вопрос.')]);
    });
  });

  group('the badge goes down', () {
    testWidgets('tells the server she read every unread answer', (tester) async {
      final rec = await pump(tester, tickets: [
        ticketJson(id: 'a', status: 'waiting',
            replies: [staffReply('Первый ответ.')]),
        ticketJson(id: 'b', subject: 'Второе', status: 'waiting',
            createdAt: '2026-08-09T09:00:00.000Z',
            replies: [staffReply('Второй ответ.',
                at: '2026-08-09T10:00:00.000Z')]),
      ]);
      expect(rec.read, containsAll(['a', 'b']));
    });

    testWidgets('says nothing about a thread with nothing new in it',
        (tester) async {
      // Already read, and a ticket nobody has answered. Marking those would be
      // two writes a minute for a screen she reopens out of habit.
      final rec = await pump(tester, tickets: [
        ticketJson(id: 'seen', status: 'waiting',
            readAt: '2026-08-11T11:00:00.000Z',
            replies: [staffReply('Ответ.', at: '2026-08-11T10:00:00.000Z')]),
        ticketJson(id: 'unanswered', status: 'open'),
      ]);
      expect(rec.read, isEmpty);
    });

    testWidgets('a failed mark-read does not shout at her', (tester) async {
      // The cost is a badge that stays lit — the old behaviour — not a message
      // that went nowhere, and «не отправилось» over a read receipt she never
      // asked for is noise.
      await pump(tester, tickets: [
        ticketJson(status: 'waiting', replies: [staffReply('Ответ.')]),
      ], failRead: true);
      expect(find.text(l.t('sup_chat_failed')), findsNothing);
      expect(find.text('Ответ.'), findsOneWidget);
    });
  });

  group('writing', () {
    testWidgets('adds to the live ticket instead of opening a second one',
        (tester) async {
      final rec = await pump(tester, tickets: [
        ticketJson(status: 'waiting', replies: [staffReply('Проверяю.')]),
      ]);
      await tester.enterText(find.byType(TextField), 'Кода всё ещё нет.');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(rec.replied, [(id: 't1', body: 'Кода всё ещё нет.')]);
      expect(rec.created, isEmpty);
    });

    testWidgets('opens a ticket when there is none, with her line as the subject',
        (tester) async {
      final rec = await pump(tester);
      await tester.enterText(find.byType(TextField), 'Браслет не подключается');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(rec.created, hasLength(1));
      expect(rec.created.first.subject, 'Браслет не подключается');
      expect(rec.created.first.body, 'Браслет не подключается');
    });

    testWidgets('a CLOSED ticket starts a new one and says so', (tester) async {
      final rec = await pump(tester, tickets: [ticketJson(status: 'closed')]);
      expect(find.text(l.t('sup_chat_closed')), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Проблема вернулась.');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(rec.created, hasLength(1));
      expect(rec.replied, isEmpty);
    });

    testWidgets('a failed send SAYS SO and keeps what she typed',
        (tester) async {
      // A tick over a message that never left the phone is how somebody waits
      // for an answer to a question nobody received.
      await pump(tester, failSend: true);
      await tester.enterText(find.byType(TextField), 'Помогите, пожалуйста.');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(find.text(l.t('sup_chat_failed')), findsOneWidget);
      expect(find.text('Помогите, пожалуйста.'), findsOneWidget);
    });

    testWidgets('refuses to send an empty message', (tester) async {
      final rec = await pump(tester);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(rec.created, isEmpty);
    });

    testWidgets('a chip starts the message rather than sending one',
        (tester) async {
      final rec = await pump(tester);
      await tester.tap(find.text(l.t('sup_topic_tracker')));
      await tester.pumpAndSettle();
      expect(rec.created, isEmpty);
      expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          startsWith(l.t('sup_topic_tracker')));
    });
  });

  group('«действие в чате»', () {
    testWidgets('is absent when this build cannot perform one', (tester) async {
      await pump(tester, tickets: [ticketJson()]);
      expect(find.text(l.t('sup_chat_action')), findsNothing);
    });

    testWidgets('runs the action it offers', (tester) async {
      var ran = 0;
      await pump(tester,
          tickets: [ticketJson()],
          action: (label: 'Обновить положение', onTap: () => ran++));
      await tester.tap(find.text('Обновить положение'));
      await tester.pumpAndSettle();
      expect(ran, 1);
    });
  });

  group('the way in, on «Помощь»', () {
    Future<void> pumpHelp(WidgetTester tester,
        {VoidCallback? onOpen, int answered = 0}) async {
      tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(L10nScope(
        l10n: l,
        child: MaterialApp(
          theme: FcsTheme.light(AppLocale.ru),
          home: HelpSupportScreen(
            onWrite: (_) {},
            onOpenThread: onOpen,
            answeredCount: answered,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('sits ABOVE the WhatsApp row', (tester) async {
      // The only channel where the answer comes back into the app, and the only
      // one that works when she has no WhatsApp.
      await pumpHelp(tester, onOpen: () {});
      final chat = tester.getTopLeft(find.text(l.t('sup_chat_title'))).dy;
      final whatsapp = tester.getTopLeft(find.text(l.t('sup_write'))).dy;
      expect(chat, lessThan(whatsapp));
    });

    testWidgets('counts the answers waiting for her', (tester) async {
      await pumpHelp(tester, onOpen: () {}, answered: 2);
      expect(find.text(l.t('sup_chat_row_waiting', {'n': '2'})), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('draws no badge when nothing is waiting', (tester) async {
      await pumpHelp(tester, onOpen: () {});
      expect(find.text(l.t('sup_chat_row_none')), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('is not drawn at all when the build cannot reach the server',
        (tester) async {
      // A row that opens a screen which can only fail is worse than no row.
      await pumpHelp(tester);
      expect(find.text(l.t('sup_chat_title')), findsNothing);
    });

    testWidgets('opens the thread', (tester) async {
      var opened = 0;
      await pumpHelp(tester, onOpen: () => opened++);
      await tester.tap(find.text(l.t('sup_chat_title')));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });
}
