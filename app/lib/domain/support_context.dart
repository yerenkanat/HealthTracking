/// Screen 43 — «Поддержка».
///
/// WHAT THIS IS NOT, AND WHY
///
/// The spec draws an in-app operator chat: a named operator, a dialogue, quick
/// chips and an action button. That needs two things this product does not have
/// today — push notifications, so she learns a reply arrived, and an operator
/// inbox somebody actually watches. Shipping the chat without them creates a
/// channel where messages go unanswered while looking like one where they are
/// read, which is worse than not offering it: she would wait instead of calling.
///
/// So support routes to WhatsApp, which is where it already happens — the shop,
/// the course and the order screen all send people there — and this file makes
/// that route WORTH taking by collecting what the operator would otherwise have
/// to ask for. Three round trips of «какая у вас версия?» is most of the delay
/// in a support conversation.
///
/// When push and an inbox exist, the chat replaces this and the context
/// collection is what it will send as its first message.
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
