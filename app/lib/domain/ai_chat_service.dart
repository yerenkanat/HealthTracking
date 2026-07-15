/// AiChatService — sends user messages to the guardrailed backend assistant and
/// routes an emergency outcome straight to the Emergency Rescue screen (the server
/// can flip any chat into an emergency when the attached telemetry is critical).
///
/// Pure Dart (depends only on ApiClient + HealthMonitor). Testable with fakes.
library;

import '../data/api_client.dart';
import 'health_monitor.dart';

class AiChatService {
  final ApiClient api;
  final String userId;
  final String locale;
  final HealthMonitor monitor;

  /// Called when the assistant response is an emergency — app shows the rescue screen.
  final void Function(EmergencyChatOutcome) onEmergency;

  const AiChatService({
    required this.api,
    required this.userId,
    required this.locale,
    required this.monitor,
    required this.onEmergency,
  });

  /// Returns the outcome for the chat UI to render. Side-effect: fires onEmergency
  /// (and callers should stop rendering chat) if the server escalated.
  Future<ChatOutcome> send(String message) async {
    final outcome = await api.chat(
      userId: userId,
      locale: locale,
      message: message,
      latestTelemetry: monitor.latest?.toJson(),
    );
    if (outcome is EmergencyChatOutcome) onEmergency(outcome);
    return outcome;
  }
}
