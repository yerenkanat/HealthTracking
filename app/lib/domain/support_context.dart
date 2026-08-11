/// Screen 43 — «Поддержка».
///
/// THE CHAT NOW EXISTS, AND WHAT CHANGED
///
/// This file used to open by explaining why the spec's in-app operator chat was
/// not being built: it needed push notifications, so she learns a reply
/// arrived, and an operator inbox somebody actually watches. Both now exist —
/// frame 12 «Поддержка» is the inbox (support_tickets / support_replies), and
/// the reply route sends «Поддержка ответила» to her phone. So the thread is
/// built, and the context collected here is what it sends with her first
/// message, exactly as this comment promised it would be.
///
/// WhatsApp stays alongside it rather than being replaced. It is where support
/// already happens, it works when she has no account, and the desk answers on
/// both.
library;

/// What the app can say about itself without asking her anything.
class SupportContext {
  final String appVersion;

  /// Her number, so the operator can find the account and the order.
  final String? phone;

  /// The child's tracker, when one is paired — most support is about it.
  final String? deviceId;

  /// Whether the app currently has a connection. An operator reading «нет
  /// интернета» knows why the map was stale before she explains it.
  final bool offline;

  /// The most recent thing that went wrong, if anything did.
  final String? lastError;

  const SupportContext({
    required this.appVersion,
    this.phone,
    this.deviceId,
    this.offline = false,
    this.lastError,
  });

  /// The message body. Russian, because that is what the operator reads.
  ///
  /// Everything here is about the DEVICE and the app. Deliberately nothing
  /// about her health, her cycle or her children's names: a support message is
  /// pasted into a group chat, forwarded to a colleague and read on a shared
  /// phone, and none of those are places for a medical record.
  String message(String complaint) {
    final lines = <String>[
      complaint.trim().isEmpty ? 'Здравствуйте! Нужна помощь.' : complaint.trim(),
      '',
      '— — —',
      'Приложение: $appVersion',
    ];
    if (phone != null && phone!.isNotEmpty) lines.add('Телефон: $phone');
    if (deviceId != null && deviceId!.isNotEmpty) {
      lines.add('Устройство: $deviceId');
    }
    if (offline) lines.add('Связь: нет интернета');
    if (lastError != null && lastError!.isNotEmpty) {
      // Truncated: a stack trace in a WhatsApp message is unreadable and the
      // first line is the only part anyone acts on.
      final first = lastError!.split('\n').first;
      lines.add('Последняя ошибка: ${first.length > 140 ? '${first.substring(0, 140)}…' : first}');
    }
    return lines.join('\n');
  }
}

/// The things she can try herself, in the order they resolve most problems.
///
/// Each is a real action that exists in this build. A self-service list with a
/// dead entry teaches her that none of them work.
enum SupportAction {
  /// The tracker's position is stale — ask the server again.
  refreshLocation,

  /// The tracker is not answering — pair it again.
  repairDevice,

  /// «Где мой заказ» — the commonest question the operator gets.
  openOrder,
}

extension SupportActionKeys on SupportAction {
  String get titleKey => switch (this) {
        SupportAction.refreshLocation => 'sup_act_refresh',
        SupportAction.repairDevice => 'sup_act_repair',
        SupportAction.openOrder => 'sup_act_order',
      };

  String get bodyKey => switch (this) {
        SupportAction.refreshLocation => 'sup_act_refresh_b',
        SupportAction.repairDevice => 'sup_act_repair_b',
        SupportAction.openOrder => 'sup_act_order_b',
      };
}

// ---------------------------------------------------------------------------
// The thread — screen 43's dialogue, as the server sends it.
// ---------------------------------------------------------------------------

/// Who said it. The screen draws these two very differently and nothing else
/// is possible: `support_replies.author` is CHECKed to exactly this pair.
enum SupportAuthor { customer, staff }

/// One line of the conversation.
class SupportMessage {
  final SupportAuthor author;
  final String body;
  final DateTime at;

  const SupportMessage({
    required this.author,
    required this.body,
    required this.at,
  });

  bool get mine => author == SupportAuthor.customer;
}

/// Where a ticket stands. `waiting` means WE answered and the desk is waiting
/// on her — which is the only status the entry row counts, because it is the
/// only one that means there is something new for her to read.
enum SupportStatus { isNew, open, waiting, closed }

SupportStatus _statusOf(String? raw) => switch (raw) {
      'open' => SupportStatus.open,
      'waiting' => SupportStatus.waiting,
      'closed' => SupportStatus.closed,
      _ => SupportStatus.isNew,
    };

/// One support conversation.
class SupportThread {
  final String id;
  final String subject;
  final SupportStatus status;
  final DateTime createdAt;

  /// When she last OPENED this thread, as the server recorded it. Null means
  /// never. It is what makes the «Есть ответ поддержки» badge able to go down:
  /// an answer newer than this is unread, an answer older is not.
  final DateTime? readAt;

  /// Her opening message and every reply since, oldest first. The ticket's own
  /// body IS her first message, so it is folded in here rather than drawn
  /// separately — the screen shows a conversation, not a form and its answers.
  final List<SupportMessage> messages;

  const SupportThread({
    required this.id,
    required this.subject,
    required this.status,
    required this.createdAt,
    required this.messages,
    this.readAt,
  });

  /// The desk answered and is waiting on her: there is something to read.
  bool get answerWaiting => status == SupportStatus.waiting;

  /// When the operator last spoke here. Null when nobody has yet.
  DateTime? get lastStaffAt {
    DateTime? at;
    for (final m in messages) {
      if (m.author != SupportAuthor.staff) continue;
      if (at == null || m.at.isAfter(at)) at = m.at;
    }
    return at;
  }

  /// There is an answer here she has NOT read — the only thing worth a badge.
  ///
  /// «Ответила и ждём её» plus an answer newer than the last time she opened
  /// the thread. The status alone was the old rule and it could only ever go
  /// up: reading changed nothing, so the badge stayed lit for weeks and she
  /// stopped looking at it. A ticket an operator parked in «ждём клиента»
  /// without writing anything has nothing to read and is deliberately not
  /// counted once she has opened it.
  bool get unreadAnswer {
    if (!answerWaiting) return false;
    final read = readAt;
    if (read == null) return true;
    final answered = lastStaffAt;
    return answered != null && read.isBefore(answered);
  }

  /// Still a live conversation. A closed one is history — she can read it, and
  /// writing again starts a new ticket rather than reopening this screen's
  /// idea of what "current" means.
  bool get open => status != SupportStatus.closed;

  /// Tolerant on purpose: a field this build does not know must not lose her
  /// the whole thread. An unparseable date falls back to the ticket's own.
  static SupportThread? parse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final subject = raw['subject'];
    if (id is! String || subject is! String) return null;
    final created = DateTime.tryParse('${raw['createdAt']}')?.toLocal();
    if (created == null) return null;

    final body = '${raw['body'] ?? ''}'.trim();
    final messages = <SupportMessage>[
      // Her first message. Some tickets carry only a subject (one an operator
      // typed while she was on the phone), and an empty bubble is worse than
      // repeating the subject she can already see at the top.
      SupportMessage(
        author: SupportAuthor.customer,
        body: body.isEmpty ? subject : body,
        at: created,
      ),
      for (final r in (raw['replies'] as List? ?? const []))
        if (r is Map && r['body'] is String)
          SupportMessage(
            author: r['author'] == 'staff'
                ? SupportAuthor.staff
                : SupportAuthor.customer,
            body: r['body'] as String,
            at: DateTime.tryParse('${r['at']}')?.toLocal() ?? created,
          ),
    ]..sort((a, b) => a.at.compareTo(b.at));

    return SupportThread(
      id: id,
      subject: subject,
      status: _statusOf(raw['status'] as String?),
      createdAt: created,
      messages: messages,
      // Absent on a server older than migration 035, which reads as «never
      // opened» — the badge then behaves exactly as it did before, rather than
      // claiming she has read an answer nobody can prove she saw.
      readAt: DateTime.tryParse('${raw['customerReadAt']}')?.toLocal(),
    );
  }

  /// The whole payload of `GET /support`, newest ticket first.
  static List<SupportThread> parseAll(Map<String, dynamic> body) => [
        for (final t in (body['tickets'] as List? ?? const []))
          if (parse(t) case final thread?) thread,
      ];
}

/// The common complaints, as one-tap chips. Each becomes the first line of the
/// message so the operator opens a conversation that has already started.
enum SupportTopic { tracker, band, order, course, account }

extension SupportTopicKeys on SupportTopic {
  String get l10nKey => switch (this) {
        SupportTopic.tracker => 'sup_topic_tracker',
        SupportTopic.band => 'sup_topic_band',
        SupportTopic.order => 'sup_topic_order',
        SupportTopic.course => 'sup_topic_course',
        SupportTopic.account => 'sup_topic_account',
      };
}
