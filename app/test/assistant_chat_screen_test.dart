/// Widget test for the assistant chat screen (run with `flutter test`).
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
