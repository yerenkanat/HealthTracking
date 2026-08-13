/// Opening screen 43 — «Поддержка · оператор».
///
/// Lifted out of `settings_screen.dart` when a SECOND caller appeared: a tapped
/// «Поддержка ответила» notification. The backend has been setting
/// `data.screen = 'SupportThread'` on that push since frame 43 shipped, and
/// until now the only way into the thread was three taps down Настройки — so
/// the operator's answer arrived on the lock screen and tapping it opened the
/// dashboard.
///
/// Everything the screen needs is a function it can call, so the screen itself
/// still has no idea there is a network; this file is only the wiring.
library;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/support_context.dart';
import '../../l10n/l10n_scope.dart';
import 'support_thread_screen.dart';

/// Tickets the desk has answered and she has NOT read — the badge figure.
///
/// Zero when the call failed or there is no server, which draws no badge:
/// claiming an answer is waiting when we could not ask is worse than a quiet
/// row. Unread, not merely answered — «status = waiting» could only ever go up,
/// so the badge stayed lit for weeks and stopped being read.
///
/// One copy, because there are now two rows carrying it: Профиль (screen 39's
/// neighbour) and Настройки → Помощь. Two copies of this arithmetic is how one
/// of them keeps counting closed tickets after the other is fixed.
Future<int> unreadSupportAnswers(AppController c) async {
  final api = c.api;
  if (api == null) return 0;
  try {
    return SupportThread.parseAll(await api.supportThreads())
        .where((t) => t.unreadAnswer)
        .length;
  } catch (_) {
    // Offline, or a server older than this build. The row still opens — the
    // thread screen says so itself if it cannot load.
    return 0;
  }
}

/// Push screen 43. A no-op without an API client — the whole screen is a
/// conversation with the server, and there is nothing to show offline that is
/// not a lie.
///
/// Awaits the route, so a caller that needs to refresh a badge afterwards
/// (Настройки does) can simply await this.
Future<void> openSupportThread(BuildContext context, AppController c) async {
  final api = c.api;
  if (api == null) return;
  final child = c.selectedChild;
  final ctx = SupportContext(
    appVersion: AppController.appVersion,
    phone: c.profile.hasPhone
        ? '${c.profile.dialCode} ${c.profile.phoneNumber}'
        : null,
    deviceId: (child?.tagId ?? '').isEmpty ? null : child!.tagId,
    offline: c.isOffline,
  );
  final messenger = ScaffoldMessenger.of(context);
  final l = L10nScope.of(context);
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => SupportThreadScreen(
      load: () async {
        final body = await api.supportThreads();
        return (
          threads: SupportThread.parseAll(body),
          slaHours: (body['slaHours'] as num?)?.toInt() ?? 4,
        );
      },
      onCreate: (subject, body) => api.createSupportTicket(
        subject: subject,
        body: body,
        // What the app can say about itself, so the operator does not spend
        // three messages asking «какая у вас версия».
        appContext: ctx.message('').split('— — —').last.trim(),
      ),
      onReply: api.replyToSupportTicket,
      // What takes the badge down. The screen calls it for every answer it has
      // just put in front of her; a failure is swallowed there, because the
      // cost is a badge that stays lit and not a lost message.
      onRead: api.markSupportThreadRead,
      // «Действие в чате» — only when there is a tracker to refresh.
      action: child != null
          ? (
              label: l.t('sup_act_refresh'),
              onTap: () async {
                final ok = await c.refreshChildLocation();
                messenger.showSnackBar(SnackBar(
                  content: Text(l.t(ok ? 'sup_act_refresh' : 'off_refresh_failed')),
                  behavior: SnackBarBehavior.floating,
                ));
              },
            )
          : null,
    ),
  ));
}
