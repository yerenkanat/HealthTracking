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

class AlertsScreen extends StatefulWidget {
  final AppController controller;
  final DateTime Function()? _nowFn;
  const AlertsScreen({super.key, required this.controller, DateTime Function()? now}) : _nowFn = now;
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  AlertFilter _filter = AlertFilter.all;
  String? _child; // null = all children

  DateTime _now() => (widget._nowFn ?? DateTime.now)();

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final controller = widget.controller;
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
            final all = controller.alerts;
            if (all.isEmpty) {
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
            // A selected child that no longer appears falls back to all children.
            final children = childNamesInAlerts(all);
            if (_child != null && !children.contains(_child)) _child = null;
            final byChild = filterAlertsByChild(all, _child);
            // A filter no longer present (e.g. after clearing) falls back to All.
            final present = presentAlertFilters(byChild);
            if (_filter != AlertFilter.all && !present.contains(_filter)) _filter = AlertFilter.all;
            final alerts = filterAlerts(byChild, _filter);
            // Today's activity summary (respects the child filter).
            final todayCounts = alertKindCounts(alertsOnDay(byChild, _now()));
            return Column(
              children: [
                if (todayCounts.isNotEmpty) _TodaySummary(counts: todayCounts),
                if (children.length > 1)
                  _ChildChips(children: children, selected: _child, onSelect: (c) => setState(() => _child = c)),
                if (present.length > 1) _FilterChips(present: present, selected: _filter, onSelect: (f) => setState(() => _filter = f)),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: alerts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _AlertCard(alert: alerts[i], now: _now()),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A horizontal row of filter chips: All + the categories that have alerts.
class _FilterChips extends StatelessWidget {
  final Set<AlertFilter> present;
  final AlertFilter selected;
  final ValueChanged<AlertFilter> onSelect;
  const _FilterChips({required this.present, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    String label(AlertFilter f) => switch (f) {
          AlertFilter.all => l.t('alerts_filter_all'),
          AlertFilter.zones => l.t('alerts_filter_zones'),
          AlertFilter.sos => l.t('alerts_filter_sos'),
          AlertFilter.checkIns => l.t('alerts_filter_checkins'),
          AlertFilter.battery => l.t('alerts_filter_battery'),
        };
    final chips = [AlertFilter.all, ...present];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = chips[i];
          final sel = f == selected;
          return ChoiceChip(
            label: Text(label(f)),
            selected: sel,
            onSelected: (_) => onSelect(f),
            showCheckmark: false,
            selectedColor: Palette.violet.withValues(alpha: 0.16),
            side: BorderSide(color: sel ? Palette.violet.withValues(alpha: 0.5) : Palette.border),
            labelStyle: TextStyle(color: sel ? Palette.violet : Palette.textDim, fontWeight: FontWeight.w600, fontSize: 13),
            backgroundColor: Palette.surface,
          );
        },
      ),
    );
  }
}

/// A compact "Today" strip summarizing how many of each alert kind fired today —
/// a quick pulse of the day's activity above the feed.
class _TodaySummary extends StatelessWidget {
  final Map<AlertKind, int> counts;
  const _TodaySummary({required this.counts});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // Fixed order; zone enter+left are merged into one "zone events" figure.
    final zone = (counts[AlertKind.entered] ?? 0) + (counts[AlertKind.left] ?? 0);
    final items = <(IconData, Color, int, String)>[
      if (zone > 0) (Icons.swap_horiz_rounded, Palette.good, zone, l.t('today_zone_events')),
      if ((counts[AlertKind.checkIn] ?? 0) > 0) (Icons.how_to_reg_rounded, Palette.blue, counts[AlertKind.checkIn]!, l.t('today_checkins')),
      if ((counts[AlertKind.sos] ?? 0) > 0) (Icons.sos_rounded, Palette.danger, counts[AlertKind.sos]!, l.t('today_sos')),
      if ((counts[AlertKind.lowBattery] ?? 0) > 0) (Icons.battery_alert_rounded, Palette.amber, counts[AlertKind.lowBattery]!, l.t('today_battery')),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Palette.violet.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('today_title').toUpperCase(),
              style: const TextStyle(color: Palette.textDim, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16, runSpacing: 8,
            children: [
              for (final (icon, color, n, label) in items)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 5),
                  Text('$n', style: TextStyle(fontFamily: 'JetBrainsMono', fontWeight: FontWeight.w700, color: color, fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(label, style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                ]),
            ],
          ),
        ],
      ),
    );
  }
}

/// A horizontal row of per-child chips: All children + one chip per child that
/// has alerts. Shown only when the feed spans more than one child.
class _ChildChips extends StatelessWidget {
  final List<String> children;
  final String? selected; // null = all
  final ValueChanged<String?> onSelect;
  const _ChildChips({required this.children, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // null sentinel = "All children"; then one entry per child name.
    final items = <String?>[null, ...children];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = items[i];
          final sel = c == selected;
          return ChoiceChip(
            avatar: c == null ? null : Icon(Icons.person_rounded, size: 16, color: sel ? Palette.pink : Palette.textDim),
            label: Text(c ?? l.t('alerts_child_all')),
            selected: sel,
            onSelected: (_) => onSelect(c),
            showCheckmark: false,
            selectedColor: Palette.pink.withValues(alpha: 0.16),
            side: BorderSide(color: sel ? Palette.pink.withValues(alpha: 0.5) : Palette.border),
            labelStyle: TextStyle(color: sel ? Palette.pink : Palette.textDim, fontWeight: FontWeight.w600, fontSize: 13),
            backgroundColor: Palette.surface,
          );
        },
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
    final (color, icon, title) = switch (alert.kind) {
      AlertKind.entered => (Palette.good, Icons.login_rounded, l.t('alert_entered', {'zone': alert.zoneName})),
      AlertKind.left => (Palette.amber, Icons.logout_rounded, l.t('alert_left', {'zone': alert.zoneName})),
      AlertKind.checkIn => (Palette.blue, Icons.how_to_reg_rounded, l.t('alert_checkin')),
      AlertKind.sos => (Palette.danger, Icons.sos_rounded, l.t('alert_sos')),
      AlertKind.lowBattery => (Palette.amber, Icons.battery_alert_rounded, l.t('alert_low_battery', {'pct': alert.zoneName})),
    };
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
