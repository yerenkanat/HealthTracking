/// Screen 43 — «Поддержка · оператор».
///
/// «шапка с именем оператора → диалог → действие в чате → чипы → поле».
///
/// WHY THIS SCREEN HAD TO EXIST. The back office has been able to answer a
/// customer since frame 12 shipped: POST /admin/support/:id/reply writes into
/// support_replies and marks the ticket «ждём клиента» — waiting on a woman who
/// had no surface anywhere in the app that could show her the answer. The desk
/// was one-way. This is the other end of it.
///
/// ON THE OPERATOR'S NAME. The spec asks for it in the header and the schema
/// cannot answer: support_replies records WHICH member of staff wrote a reply,
/// and the app is deliberately never told — a customer-facing screen naming a
/// person makes that person the address for everything afterwards. So the
/// header says «Оператор Ana-Bala», which is true, rather than a first name
/// somebody invented. Recorded in docs/DESIGN_DEVIATIONS.md.
///
/// ON RED. §2.18 gives the mother's own bubble `#D6004A`, and that is the only
/// place this colour appears on the screen — the send button carries it too
/// because the spec draws it that way, and nothing else does. Red belongs to
/// SOS everywhere else in this app.
///
/// ON SHOWING EVERY THREAD. This screen used to draw exactly one — the newest
/// live ticket — while `GET /support` returns up to twenty with all their
/// replies and «Помощь» counted every answered one. The desk can open a second
/// ticket for her from the panel (POST /admin/support takes a userId), so
/// «Есть ответ поддержки · 2» led to a screen with one conversation on it and
/// the other answer was unreachable anywhere in the app: the one-way desk this
/// frame exists to close, one ticket over. All of them are drawn now, oldest
/// first, with the live one last against the input so the thread her message
/// goes into is the one under her thumb.
library;

import 'package:flutter/material.dart';

import '../../domain/support_context.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';

/// What `GET /support` answers with.
typedef SupportThreadsPayload = ({List<SupportThread> threads, int slaHours});

class SupportThreadScreen extends StatefulWidget {
  /// Her threads and the promise the desk makes.
  final Future<SupportThreadsPayload> Function() load;

  /// Open a new ticket. Returns its id. Throws when it did not save — the
  /// screen has to be able to say so.
  final Future<String> Function(String subject, String body) onCreate;

  /// Write into the live thread. Throws on failure, for the same reason.
  final Future<void> Function(String ticketId, String body) onReply;

  /// She has read this thread. Called for every conversation drawn with an
  /// unread answer in it, which is what lets the «Есть ответ поддержки» badge
  /// on «Помощь» go DOWN — nothing else ever took it down, so it stayed lit
  /// until an operator happened to close the ticket.
  ///
  /// A failure here is deliberately silent: the cost is a badge that stays on,
  /// which is the behaviour she had before, not a message that went nowhere.
  final Future<void> Function(String ticketId) onRead;

  /// «Действие в чате» — the one thing this build can do for her without an
  /// operator, offered inside the conversation. Omitted when there is none:
  /// a button that does nothing teaches her the screen is decoration.
  final ({String label, VoidCallback onTap})? action;

  const SupportThreadScreen({
    super.key,
    required this.load,
    required this.onCreate,
    required this.onReply,
    required this.onRead,
    this.action,
  });

  @override
  State<SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends State<SupportThreadScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<SupportThread> _threads = const [];
  int _slaHours = 4;
  bool _loading = true;
  bool _sending = false;

  /// Set when the LAST attempt failed. Shown verbatim on screen: a tick over a
  /// message that never left the phone is how somebody waits for an answer to
  /// a question nobody received.
  bool _loadFailed = false;
  bool _sendFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The thread a new message goes INTO — the newest one still open. Null
  /// means the next message opens a ticket instead, which is the case when
  /// there are none and when the last one was closed.
  SupportThread? get _live {
    for (final t in _threads) {
      if (t.open) return t;
    }
    return null;
  }

  /// Every conversation, in reading order: oldest first, and the live one LAST
  /// so it sits against the input her message goes into. Nothing is dropped —
  /// an answer the desk wrote into any of her tickets is on this screen.
  List<SupportThread> get _ordered {
    final live = _live;
    final rest = [
      for (final t in _threads)
        if (t.id != live?.id) t,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return [...rest, if (live != null) live];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final payload = await widget.load();
      if (!mounted) return;
      setState(() {
        _threads = payload.threads;
        _slaHours = payload.slaHours;
        _loading = false;
      });
      _toBottom();
      _markRead();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// Tell the server she has seen the answers now on her screen.
  ///
  /// Every thread is drawn, so every unread answer has just been put in front
  /// of her, and this is the only thing that takes the mint badge on «Помощь»
  /// down. Silent on failure by design — see [SupportThreadScreen.onRead].
  void _markRead() {
    for (final t in _threads) {
      if (t.unreadAnswer) widget.onRead(t.id).catchError((_) {});
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _sendFailed = false;
    });
    try {
      final live = _live;
      if (live != null) {
        await widget.onReply(live.id, text);
      } else {
        // The subject is what the operator's queue lists, so it has to read
        // like a question. Her first line is the best available one; the whole
        // message follows as the body either way.
        await widget.onCreate(_subjectFrom(text), text);
      }
      if (!mounted) return;
      // Cleared only once it is SAVED. Clearing on tap loses the message she
      // typed during the bad moment of signal that lost it.
      _input.clear();
      setState(() => _sending = false);
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendFailed = true;
      });
    }
  }

  static String _subjectFrom(String text) {
    final first = text.split('\n').first.trim();
    if (first.length <= 80) return first.isEmpty ? text.trim() : first;
    return '${first.substring(0, 79)}…';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final threads = _ordered;
    final live = _live;

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.t('sup_chat_who'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(
              l.t('sup_chat_sla', {'h': '$_slaHours'}),
              style: const TextStyle(fontSize: 12, color: Palette.textDim),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          const _Disclaimer(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadFailed
                    ? _Failed(
                        text: l.t('sup_chat_load_failed'),
                        retry: l.t('sup_chat_retry'),
                        onRetry: _load,
                      )
                    : _Dialogue(
                        scroll: _scroll,
                        threads: threads,
                        liveId: live?.id,
                        action: widget.action,
                      ),
          ),
          if (_sendFailed)
            _Banner(text: l.t('sup_chat_failed'), tone: _BannerTone.bad),
          // No live ticket but history behind her: the next message opens a new
          // one, and saying so beats her writing into what looks like a closed
          // conversation and wondering which of them the operator will read.
          if (!_loading && !_loadFailed && live == null && threads.isNotEmpty)
            _Banner(text: l.t('sup_chat_closed'), tone: _BannerTone.calm),
          if (!_loading && !_loadFailed && threads.isEmpty)
            _Banner(text: l.t('sup_chat_first_note'), tone: _BannerTone.calm),
          _Chips(onPick: (label) {
            // Prefills rather than sends: the chip is the first line of a
            // message she still gets to finish, so the operator opens a
            // conversation that has already started.
            final existing = _input.text.trim();
            _input.text = existing.isEmpty ? '$label: ' : '$label: $existing';
            _input.selection =
                TextSelection.collapsed(offset: _input.text.length);
            setState(() {});
          }),
          _InputBar(
            controller: _input,
            hint: l.t('sup_chat_hint'),
            sendLabel: l.t('sup_chat_send'),
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// «Дисклеймер сверху»: #FFF0DC / #6E4200 per §2.18.
// ---------------------------------------------------------------------------
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Ds.pastelButter,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Text(
          L10nScope.of(context).t('sup_chat_disclaimer'),
          style: const TextStyle(
              fontSize: 12.5, height: 1.4, color: Ds.amberText),
        ),
      );
}

enum _BannerTone { bad, calm }

class _Banner extends StatelessWidget {
  final String text;
  final _BannerTone tone;
  const _Banner({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    final bad = tone == _BannerTone.bad;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bad ? Ds.pastelPink : Ds.pastelButter,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.35,
          fontWeight: bad ? FontWeight.w600 : FontWeight.w400,
          color: bad ? Ds.coralText : Ds.amberText,
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  final String text;
  final String retry;
  final VoidCallback onRetry;
  const _Failed({required this.text, required this.retry, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Palette.textDim)),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(120, DsShape.minTapTarget)),
              onPressed: onRetry,
              child: Text(retry),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// «Диалог» + «действие в чате».
// ---------------------------------------------------------------------------
class _Dialogue extends StatelessWidget {
  final ScrollController scroll;

  /// EVERY one of her conversations, oldest first, live one last. Drawing only
  /// the newest is what made an answer in any other ticket unreachable.
  final List<SupportThread> threads;

  /// Which of them her next message goes into. Null when the next message
  /// opens a new ticket.
  final String? liveId;

  final ({String label, VoidCallback onTap})? action;

  const _Dialogue({
    required this.scroll,
    required this.threads,
    required this.liveId,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    if (threads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            l.t('sup_chat_empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, height: 1.5, color: Palette.textDim),
          ),
        ),
      );
    }

    // The role labels are drawn ONLY when there is more than one conversation:
    // with a single thread there is nothing to tell apart, and a screen that
    // announces «сюда уйдёт ваше сообщение» over the only thing on it is noise.
    final many = threads.length > 1;

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      children: [
        for (final (i, t) in threads.indexed) ...[
          if (i > 0) const _ThreadDivider(),
          _ThreadHeader(thread: t, live: t.id == liveId, showRole: many),
          const SizedBox(height: 10),
          for (final m in t.messages) _Bubble(message: m),
        ],
        if (action case final a?) ...[
          const SizedBox(height: 6),
          _ChatAction(label: a.label, onTap: a.onTap),
        ],
      ],
    );
  }
}

/// Where one conversation ends and the next begins. Without it two tickets read
/// as one confusing thread in which the operator answered a question twice.
class _ThreadDivider extends StatelessWidget {
  const _ThreadDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Divider(height: 1, thickness: 1, color: Ds.hairline),
      );
}

/// The subject, the day it was raised, and — when she has more than one — which
/// conversation this is.
class _ThreadHeader extends StatelessWidget {
  final SupportThread thread;
  final bool live;
  final bool showRole;

  const _ThreadHeader({
    required this.thread,
    required this.live,
    required this.showRole,
  });

  /// Numeric on purpose: a month name would have to be invented in three
  /// languages, and «11.08» is unambiguous in all of them.
  static String _day(DateTime at) =>
      '${at.day.toString().padLeft(2, '0')}.${at.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                thread.subject,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Palette.textDim),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _day(thread.createdAt),
              style: const TextStyle(fontSize: 11.5, color: Palette.textDim),
            ),
          ],
        ),
        if (showRole)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l.t(live ? 'sup_chat_thread_live' : 'sup_chat_thread_past'),
              style: const TextStyle(fontSize: 11.5, color: Palette.textDim),
            ),
          ),
      ],
    );
  }
}

/// §2.18: mother right, `#D6004A` on white text, `18 18 6 18`; the operator
/// left, white with a shadow, `18 18 18 6`.
class _Bubble extends StatelessWidget {
  final SupportMessage message;
  const _Bubble({required this.message});

  static String _time(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final mine = message.mine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * (mine ? 0.82 : 0.88),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: mine ? Ds.coral : Palette.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 6),
                bottomRight: Radius.circular(mine ? 6 : 18),
              ),
              boxShadow: mine ? null : DsShape.hardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Named on every message, not just the first: a thread read
                  // days later, three notifications deep, must not need her to
                  // count the bubbles to work out who said what.
                  mine ? l.t('sup_chat_you') : l.t('sup_chat_who'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: mine ? Colors.white70 : Palette.textDim,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message.body,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    color: mine ? Colors.white : Palette.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _time(message.at),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: mine ? Colors.white70 : Palette.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Действие в чате» — the spec's «↻ Обновить прошивку сейчас», in the form
/// this build can actually honour.
class _ChatAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ChatAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Ds.pastelMint,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('sup_chat_action'),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: Ds.mintText)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, DsShape.minTapTarget),
                foregroundColor: Ds.mintText,
                side: const BorderSide(color: Ds.mintText),
              ),
              onPressed: onTap,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Быстрые подсказки: горизонтальный ряд чипов над полем».
class _Chips extends StatelessWidget {
  final void Function(String label) onPick;
  const _Chips({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final topic in SupportTopic.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                // 48dp minimum, per docs/UI_REVIEW_CHECKLIST.md — a Material
                // chip is 32dp tall by default.
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                backgroundColor: Palette.surface,
                side: const BorderSide(color: Ds.hairline),
                label: Text(l.t(topic.l10nKey),
                    style: const TextStyle(fontSize: 13)),
                onPressed: () => onPick(l.t(topic.l10nKey)),
              ),
            ),
        ],
      ),
    );
  }
}

/// «Поле ввода: min-height 50–52px + круглая кнопка ↑ 50×50 #D6004A».
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
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 50),
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: hint,
                      filled: true,
                      fillColor: Palette.surface,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DsShape.radiusInput),
                        borderSide: const BorderSide(color: Ds.hairline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DsShape.radiusInput),
                        borderSide: const BorderSide(color: Ds.hairline),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 50,
                height: 50,
                child: Semantics(
                  button: true,
                  label: sendLabel,
                  child: Material(
                    color: Ds.coral,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: sending ? null : onSend,
                      child: Center(
                        child: sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.arrow_upward_rounded,
                                color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
