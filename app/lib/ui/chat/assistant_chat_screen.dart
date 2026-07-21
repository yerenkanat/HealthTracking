/// Assistant chat screen — the guardrailed wellness companion ("Umay").
/// Renders the ChatController's message list and an input bar. A persistent
/// disclaimer keeps the "not a diagnosis" boundary visible. Blocked/emergency
/// messages get distinct styling. Strings via L10nScope.
library;

import 'package:flutter/material.dart';
import '../../domain/chat_controller.dart';
import '../../l10n/l10n_scope.dart';

class AssistantChatScreen extends StatefulWidget {
  final ChatController controller;
  const AssistantChatScreen({super.key, required this.controller});

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await widget.controller.send(text);
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final c = widget.controller;

    return Scaffold(
      appBar: AppBar(title: Text(l.t('chat_title'))),
      body: Column(
        children: [
          _Disclaimer(text: l.t('chat_disclaimer')),
          Expanded(
            child: StreamBuilder<void>(
              stream: c.changes,
              builder: (context, _) {
                if (c.messages.isEmpty) return _EmptyState();
                // One extra row for the retry, when the last send failed. A
                // question that could not be sent used to be simply gone: she
                // had to remember it and type it again, having typed it during
                // the bad moment of signal that lost it.
                final showRetry = c.lastFailed != null && !c.sending;
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: c.messages.length + (showRetry ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == c.messages.length) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          // A Material 3 TextButton is 40dp tall by default,
                          // under the 48dp minimum in the UI checklist. Caught
                          // reviewing my own change against it.
                          style: TextButton.styleFrom(
                            minimumSize: const Size(64, 48),
                            tapTargetSize: MaterialTapTargetSize.padded,
                          ),
                          onPressed: () => c.retryLast(),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(l.t('chat_retry')),
                        ),
                      );
                    }
                    return _Bubble(message: c.messages[i]);
                  },
                );
              },
            ),
          ),
          StreamBuilder<void>(
            stream: c.changes,
            builder: (context, _) => _InputBar(
              controller: _input,
              hint: l.t('chat_hint'),
              sendLabel: l.t('chat_send'),
              sending: c.sending,
              onSend: _send,
            ),
          ),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  final String text;
  const _Disclaimer({required this.text});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  const _Bubble({required this.message});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == ChatRole.user;
    final bg = message.isEmergency
        ? const Color(0xFFE5484D)
        : message.isBlocked
            ? scheme.surfaceContainerHighest
            : isUser
                ? scheme.primaryContainer
                : scheme.secondaryContainer;
    final fg = message.isEmergency ? Colors.white : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(message.text, style: TextStyle(color: fg, fontSize: 15, height: 1.3)),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String sendLabel;
  final bool sending;
  final VoidCallback onSend;
  const _InputBar({
    required this.controller,
    required this.hint,
    required this.sendLabel,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: hint,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: sendLabel,
              child: IconButton.filled(
                onPressed: sending ? null : onSend,
                icon: sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.arrow_upward),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.spa_outlined, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            Text(l.t('chat_empty_title'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(l.t('chat_empty_body'),
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
