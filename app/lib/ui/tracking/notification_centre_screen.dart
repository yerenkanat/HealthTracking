/// Screen 39 — «Центр уведомлений».
///
/// «Прочитать всё» → секция «Сегодня» → секция «Раньше» → карточка «экстренные
/// отключить нельзя» + «Настроить остальные →».
///
/// The alerts screen listed everything that had ever happened in one flat
/// column with no idea what had been seen, so the badge never went down and
/// nobody could tell the new thing from the thing they read yesterday.
///
/// The locked-emergency card is drawn from [NotificationChannel.canBeMuted],
/// not from a hard-coded sentence: if a channel ever became mutable the card
/// would stop claiming otherwise. A promise about a child's safety that lives
/// only in copy is one refactor from being false.
library;

import 'package:flutter/material.dart';
import '../../domain/geofence_alerts.dart';
import '../../domain/notification_centre.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';

class NotificationCentreScreen extends StatelessWidget {
  final List<SafetyAlert> alerts;
  final DateTime now;
  final DateTime? readUpTo;

  /// «Прочитать всё». Given the watermark to record, or null when there is
  /// nothing to read.
  final void Function(DateTime) onReadAll;

  /// «Настроить остальные →». Null hides the button rather than opening a
  /// screen that does not exist yet.
  final VoidCallback? onConfigure;

  /// The per-child statistics view — how many zone events today, how long
  /// since the last SOS. A different question from «что нового», which is why
  /// it is a separate destination and not a second copy of this list.
  final VoidCallback? onOpenStats;

  const NotificationCentreScreen({
    super.key,
    required this.alerts,
    required this.now,
    required this.onReadAll,
    this.readUpTo,
    this.onConfigure,
    this.onOpenStats,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final s = groupNotifications(alerts, now, readUpTo: readUpTo);
    final watermark = readAllWatermark(alerts);

    return Scaffold(
      backgroundColor: Ds.cream,
      appBar: AppBar(
        title: Text(l.t('ntf_title')),
        actions: [
          if (onOpenStats != null)
            IconButton(
              onPressed: onOpenStats,
              tooltip: l.t('alerts_title'),
              icon: const Icon(Icons.insights_rounded),
            ),
          // Disabled when there is nothing unread, rather than silently doing
          // nothing — a button that looks live and is not teaches distrust of
          // every other button on the screen.
          TextButton(
            onPressed: (s.unreadCount == 0 || watermark == null)
                ? null
                : () => onReadAll(watermark),
            child: Text(l.t('ntf_read_all')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          if (s.isEmpty)
            _EmptyCard(title: l.t('ntf_empty'), body: l.t('ntf_empty_why'))
          else ...[
            if (s.today.isNotEmpty) ...[
              _SectionTitle(l.t('ntf_today')),
              for (final i in s.today) _Row(item: i),
              const SizedBox(height: 18),
            ],
            if (s.earlier.isNotEmpty) ...[
              _SectionTitle(l.t('ntf_earlier')),
              for (final i in s.earlier) _Row(item: i),
              const SizedBox(height: 18),
            ],
          ],
          const SizedBox(height: 8),
          _EmergencyLockedCard(onConfigure: onConfigure),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
      );
}

class _Row extends StatelessWidget {
  final NotificationItem item;
  const _Row({required this.item});

  String _line(L10n l) {
    final a = item.alert;
    return switch (a.kind) {
      AlertKind.entered => l.t('alert_entered', {'zone': a.zoneName}),
      AlertKind.left => l.t('alert_left', {'zone': a.zoneName}),
      AlertKind.checkIn => l.t('alert_checkin'),
      AlertKind.sos => l.t('today_sos'),
      AlertKind.lowBattery => l.t('today_battery'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final a = item.alert;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The unread dot. An emergency keeps its colour whether or not it has
          // been read — «прочитано» does not make an SOS ordinary.
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(top: 5, right: 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.isEmergency
                  ? Ds.coralText
                  : item.unread
                      ? Ds.blue
                      : Colors.transparent,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _line(l),
                  style: TextStyle(
                    fontSize: 14.5,
                    color: Ds.text,
                    fontWeight:
                        item.unread ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${a.childName} · ${a.at.hour.toString().padLeft(2, '0')}:'
                  '${a.at.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 12.5, color: Ds.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «Экстренные отключить нельзя», and what she CAN configure.
class _EmergencyLockedCard extends StatelessWidget {
  final VoidCallback? onConfigure;
  const _EmergencyLockedCard({this.onConfigure});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // Read from the model. If a channel ever became mutable this card would
    // stop making the claim, rather than making it falsely.
    final locked = NotificationChannel.values.where((c) => !c.canBeMuted);
    if (locked.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Ds.pastelPink,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_rounded, size: 20, color: Ds.coralText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l.t('ntf_emergency_locked'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Ds.coralText)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(l.t('ntf_emergency_why'),
              style: const TextStyle(
                  fontSize: 13, height: 1.4, color: Ds.coralText)),
          if (onConfigure != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: DsShape.minTapTarget,
              child: OutlinedButton(
                onPressed: onConfigure,
                child: Text(l.t('ntf_configure_rest')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String title;
  final String body;
  const _EmptyCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
            const SizedBox(height: 8),
            Text(body,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.4, color: Ds.textSecondary)),
          ],
        ),
      );
}
