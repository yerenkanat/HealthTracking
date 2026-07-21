/// Widget test for the assistant chat screen (run with `flutter test`).
library;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/ai_chat_service.dart';
import 'package:fcs_app/domain/chat_controller.dart';
import 'package:fcs_app/domain/health_monitor.dart';
import 'package:fcs_app/ui/chat/assistant_chat_screen.dart';

class _FakeTransport implements HttpTransport {
  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);

  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, "");

  @override
  Future<HttpResponse> post(String path, Object body) async =>
      HttpResponse(200, jsonEncode({'kind': 'chat', 'message': 'Rest and hydrate.', 'grounded': true}));
  @override
  Future<HttpResponse> get(String path) async => const HttpResponse(404, '');
}

ChatController buildController() {
  final monitor = HealthMonitor(deviceId: 'd', enqueue: (_, {required urgent}) {}, onEmergency: (_, __) {});
  final service = AiChatService(
    api: ApiClient(_FakeTransport()),
    userId: 'u',
    locale: 'en',
    monitor: monitor,
    onEmergency: (_) {},
  );
  return ChatController(
    service: service,
    networkErrorText: () => 'network error',
    emergencyNoteText: () => 'opening emergency',
  );
}

void main() {
  testWidgets('a question that failed to send can be sent again', (tester) async {
    // The question used to be gone: an error bubble appeared under it and the
    // only way forward was to remember it and type it again — having typed it
    // during the bad moment of signal that lost it.
    final transport = _FlakyTransport();
    final monitor =
        HealthMonitor(deviceId: 'd', enqueue: (_, {required urgent}) {}, onEmergency: (_, __) {});
    final c = ChatController(
      service: AiChatService(
        api: ApiClient(transport),
        userId: 'u',
        locale: 'en',
        monitor: monitor,
        onEmergency: (_) {},
      ),
      networkErrorText: () => 'network error',
      emergencyNoteText: () => 'opening emergency',
    );
    addTearDown(c.dispose);

    await tester.pumpWidget(MaterialApp(home: AssistantChatScreen(controller: c)));
    await tester.enterText(find.byType(TextField), 'is 150/95 dangerous?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(find.text('network error'), findsOneWidget);
    expect(find.text('Send again'), findsOneWidget);

    transport.ok = true;
    await tester.tap(find.text('Send again'));
    await tester.pumpAndSettle();

    expect(find.text('Rest and hydrate.'), findsOneWidget);
    expect(find.text('network error'), findsNothing);
    expect(find.text('Send again'), findsNothing);
    // And the question is still there exactly once.
    expect(find.text('is 150/95 dangerous?'), findsOneWidget);
  });

  testWidgets('shows empty state, disclaimer, then exchanges a message', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AssistantChatScreen(controller: buildController())));

    // Empty state + persistent disclaimer.
    expect(find.text('How can I help?'), findsOneWidget);
    expect(find.text('General guidance, not a medical diagnosis.'), findsOneWidget);

    // Type and send.
    await tester.enterText(find.byType(TextField), 'any tips for nausea?');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(find.text('any tips for nausea?'), findsOneWidget); // user bubble
    expect(find.text('Rest and hydrate.'), findsOneWidget); // assistant reply
    expect(find.text('How can I help?'), findsNothing); // empty state gone
  });
}

/// A transport that fails until [ok] is set — for the retry path.
class _FlakyTransport implements HttpTransport {
  bool ok = false;
  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);
  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');
  @override
  Future<HttpResponse> post(String path, Object body) async {
    if (!ok) throw Exception('offline');
    return HttpResponse(200, jsonEncode({'kind': 'chat', 'message': 'Rest and hydrate.', 'grounded': true}));
  }
  @override
  Future<HttpResponse> get(String path) async => const HttpResponse(404, '');
}
