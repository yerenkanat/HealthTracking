/// ChatController — state for the AI assistant conversation. Pure Dart (dart:async
/// Streams), so message handling + outcome routing are unit-testable with a fake
/// service. Owned by the AI Engineer + Mobile Architect.
///
/// Outcome routing (the safety-relevant part):
///   • ChatReply       → append the assistant's grounded answer.
///   • BlockedChatOutcome → append the safe fallback message (injection / unsafe /
///                          LLM-down). The user still gets a helpful, safe reply.
///   • EmergencyChatOutcome → AiChatService has ALREADY fired the app-level
///                          onEmergency (→ Emergency Rescue screen). We add a short
///                          assistant note so the transcript reflects what happened.
library;

import 'dart:async';

import '../data/api_client.dart';
import 'ai_chat_service.dart';

enum ChatRole { user, assistant }

class ChatMessage {
  final ChatRole role;
  final String text;
  final bool isBlocked;
  final bool isEmergency;
  const ChatMessage(this.role, this.text, {this.isBlocked = false, this.isEmergency = false});
}

class ChatController {
  final AiChatService service;

  /// Localized fallback for a transport/exception failure (injected so the
  /// controller stays language-agnostic and testable).
  final String Function() networkErrorText;

  /// Short assistant note appended to the transcript when an emergency is raised.
  final String Function() emergencyNoteText;

  final List<ChatMessage> _messages = [];
  final _changes = StreamController<void>.broadcast();
  bool _sending = false;

  ChatController({
    required this.service,
    required this.networkErrorText,
    required this.emergencyNoteText,
  });

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get sending => _sending;
  Stream<void> get changes => _changes.stream;

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;

    _messages.add(ChatMessage(ChatRole.user, trimmed));
    _sending = true;
    _notify();

    try {
      final outcome = await service.send(trimmed);
      switch (outcome) {
        case ChatReply r:
          _messages.add(ChatMessage(ChatRole.assistant, r.message));
        case BlockedChatOutcome b:
          _messages.add(ChatMessage(ChatRole.assistant, b.message, isBlocked: true));
        case EmergencyChatOutcome e:
          // onEmergency already fired inside AiChatService.send.
          _messages.add(ChatMessage(ChatRole.assistant, e.message, isEmergency: true));
      }
    } catch (_) {
      _messages.add(ChatMessage(ChatRole.assistant, networkErrorText(), isBlocked: true));
    } finally {
      _sending = false;
      _notify();
    }
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
