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

  /// How many messages the transcript keeps.
  ///
  /// The list grew without limit for the life of the controller, and every send
  /// rebuilds the view from it. A long conversation is not a leak that shows up
  /// in a day, which is exactly why it needs a bound rather than a promise.
  /// Generous enough that no real conversation reaches it.
  final int maxMessages;

  final List<ChatMessage> _messages = [];
  final _changes = StreamController<void>.broadcast();
  bool _sending = false;
  String? _lastFailed;

  ChatController({
    required this.service,
    required this.networkErrorText,
    required this.emergencyNoteText,
    this.maxMessages = 200,
  });

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get sending => _sending;
  Stream<void> get changes => _changes.stream;

  /// The message that failed to send, if the last attempt failed.
  ///
  /// Kept so the UI can offer to try again. Without it a question typed out
  /// during a bad moment of signal was simply gone, and she had to remember
  /// and retype it.
  String? get lastFailed => _lastFailed;

  /// Retry the message that failed. No-op when nothing did.
  Future<void> retryLast() async {
    final text = _lastFailed;
    if (text == null || _sending) return;
    // Drop the error bubble the failure left behind; the retry replaces it.
    if (_messages.isNotEmpty && _messages.last.isBlocked) _messages.removeLast();
    // And the user message it belonged to, since send() adds it again.
    if (_messages.isNotEmpty &&
        _messages.last.role == ChatRole.user &&
        _messages.last.text == text) {
      _messages.removeLast();
    }
    _lastFailed = null;
    await send(text);
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;

    _messages.add(ChatMessage(ChatRole.user, trimmed));
    _sending = true;
    _notify();

    try {
      final outcome = await service.send(trimmed);
      _lastFailed = null;
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
      // Remembered so she can try again rather than retype the question.
      _lastFailed = trimmed;
      _messages.add(ChatMessage(ChatRole.assistant, networkErrorText(), isBlocked: true));
    } finally {
      _trim();
      _sending = false;
      _notify();
    }
  }

  /// Drop the oldest messages once past [maxMessages], in whole exchanges.
  ///
  /// Removing an odd number would leave an assistant reply at the top with the
  /// question it answered gone — which reads as the assistant volunteering
  /// medical advice unprompted.
  void _trim() {
    if (_messages.length <= maxMessages) return;
    var over = _messages.length - maxMessages;
    if (over.isOdd) over++;
    _messages.removeRange(0, over.clamp(0, _messages.length));
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
