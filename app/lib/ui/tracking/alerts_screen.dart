/// Safety alerts feed — a chronological list of zone enter/exit events for the
/// family's children. Reads the AppController's in-app alert history (the same
/// events OS notifications will fire on once wired). Opened from the map's bell.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../domain/geofence_alerts.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class AlertsScreen extends StatelessWidget {
  final AppController controller;
  const AlertsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(l.t('alerts_title')),
          actions: [
            StreamBuilder<void>(
              stream: controller.changes,
              builder: (context, _) => controller.alerts.isEmpty
                  ? const SizedBox.shrink()
                  : TextButton(onPressed: controller.clearAlerts, child: Text(l.t('alerts_clear'))),
            ),
          ],
        ),
        body: StreamBuilder<void>(
          stream: controller.changes,
          builder: (context, _) {
            final alerts = controller.alerts;
            if (alerts.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none_rounded, size: 56, color: Palette.textDim.withValues(alpha: 0.6)),
                      const SizedBox(height: 12),
                      Text(l.t('alerts_empty'),
                          textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)),
                    ],
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _AlertCard(alert: alerts[i], now: DateTime.now()),
            );
          },
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final SafetyAlert alert;
  final DateTime now;
  const _AlertCard({required this.alert, required this.now});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final entered = alert.kind == AlertKind.entered;
    final color = entered ? Palette.good : Palette.amber;
    final icon = entered ? Icons.login_rounded : Icons.logout_rounded;
    final title = l.t(entered ? 'alert_entered' : 'alert_left', {'zone': alert.zoneName});
    final age = now.difference(alert.at);

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${alert.childName} · ${l.ago(age)}',
                    style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
