/// ChildDetailScreen — everything about one child in one place: age, tracker
/// battery, last check-in, last activity, their zones and how often each is
/// visited, and their alert history.
///
/// Deliberately read-only. The map, zones manager and alerts feed already own
/// those controls; this screen links out to them rather than growing a second
/// copy. Its one action is Edit, which opens the same sheet Settings used to.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../domain/battery.dart';
import '../../domain/family.dart';
import '../../domain/geofence_alerts.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import 'child_development_screen.dart';
import 'vaccination_screen.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import 'alerts_screen.dart';
import 'family_sheets.dart';
import 'zones_screen.dart';

class ChildDetailScreen extends StatelessWidget {
  final AppController controller;
  final String childId;
  final DateTime Function()? _nowFn;
  const ChildDetailScreen({
    super.key,
    required this.controller,
    required this.childId,
    DateTime Function()? now,
  }) : _nowFn = now;

  DateTime _now() => (_nowFn ?? DateTime.now)();

  ChildProfile? _child() {
    for (final c in controller.children) {
      if (c.id == childId) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StreamBuilder<void>(
          stream: controller.changes,
          builder: (context, _) {
            final child = _child();
            // The child can be deleted from underneath us (e.g. from Settings).
            if (child == null) {
              return Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(l.t('child_gone'),
                        textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)),
                  ),
                ),
              );
            }

            final alerts = controller.alerts;
            final battery = controller.batteryFor(child.id);
            final checkIn = lastCheckIn(alerts, child.name);
            final activity = lastActivityAt(alerts, child.name);
            final visits = zoneVisitCounts(alerts, child.name);
            final mine = filterAlertsByChild(alerts, child.name);
            final now = _now();

            String ago(DateTime at) {
              final d = now.difference(at);
              return l.ago(d.isNegative ? Duration.zero : d);
            }

            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: Colors.transparent,
                  title: Text(child.name),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: l.t('set_edit_profile'),
                      onPressed: () => showEditChildSheet(context, controller, child),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                SliverList(
                  delegate: SliverChildListDelegate([
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Header(child: child, now: now),
                          const SizedBox(height: 14),

                          // ---- Status ----
                          GlassCard(
                            child: Column(
                              children: [
                                if (battery != null)
                                  _StatusRow(
                                    icon: Icons.battery_std_rounded,
                                    color: _batteryColor(battery),
                                    label: l.t('child_battery'),
                                    value: '$battery%',
                                  ),
                                if (checkIn != null) ...[
                                  if (battery != null) const _Divider(),
                                  _StatusRow(
                                    icon: Icons.how_to_reg_rounded,
                                    color: Palette.blue,
                                    label: l.t('child_last_checkin'),
                                    value: ago(checkIn),
                                  ),
                                ],
                                if (activity != null) ...[
                                  if (battery != null || checkIn != null) const _Divider(),
                                  _StatusRow(
                                    icon: Icons.history_rounded,
                                    color: Palette.violet,
                                    label: l.t('child_last_activity'),
                                    value: ago(activity),
                                  ),
                                ],
                                if (battery == null && checkIn == null && activity == null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Text(l.t('child_no_activity'),
                                        style: const TextStyle(color: Palette.textDim, fontSize: 13)),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ---- Zones (links to the manager, which owns editing) ----
                          GlassCard(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ZonesScreen(controller: controller, childId: child.id),
                            )),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text(l.t('child_zones').toUpperCase(),
                                      style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                                  const Spacer(),
                                  Text('${child.geofences.length}',
                                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontWeight: FontWeight.w700, color: Palette.violet)),
                                  const Icon(Icons.chevron_right_rounded, size: 20, color: Palette.textDim),
                                ]),
                                if (visits.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  for (final v in visits.take(3))
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3),
                                      child: Row(children: [
                                        const Icon(Icons.place_rounded, size: 15, color: Palette.good),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(v.zone, style: const TextStyle(fontSize: 14))),
                                        Text(l.t('zone_visits', {'n': v.visits}),
                                            style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                                      ]),
                                    ),
                                ] else if (child.geofences.isEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(l.t('child_no_zones'),
                                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ---- Alerts (links to the feed, which owns filtering) ----
                          GlassCard(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => AlertsScreen(controller: controller),
                            )),
                            child: Row(children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: Palette.violet.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.notifications_none_rounded, size: 20, color: Palette.violet),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(l.t('child_alerts'),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                              ),
                              Text('${mine.length}',
                                  style: const TextStyle(fontFamily: 'JetBrainsMono', fontWeight: FontWeight.w700, color: Palette.violet)),
                              const Icon(Icons.chevron_right_rounded, size: 20, color: Palette.textDim),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Color _batteryColor(int pct) => switch (batteryLevel(pct)) {
        BatteryLevel.critical => Palette.danger,
        BatteryLevel.low => Palette.amber,
        BatteryLevel.ok => Palette.textDim,
        BatteryLevel.full => Palette.good,
      };
}

class _Header extends StatelessWidget {
  final ChildProfile child;
  final DateTime now;
  const _Header({required this.child, required this.now});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Row(
      children: [
        PhotoAvatar(
          photoPath: child.photoPath,
          name: child.name,
          size: 64,
          fallbackIcon: child.gender == Gender.boy
              ? Icons.boy
              : child.gender == Gender.girl
                  ? Icons.girl
                  : Icons.child_care,
        ),
        const SizedBox(width: 16),
        // The name lives in the (pinned) app bar, so it isn't repeated here.
        Expanded(
          child: Text(
            child.hasDateOfBirth ? l.childAge(child.ageInMonths(now)) : l.t('child_no_dob'),
            style: TextStyle(
              fontSize: child.hasDateOfBirth ? 16 : 13.5,
              fontWeight: child.hasDateOfBirth ? FontWeight.w600 : FontWeight.w400,
              color: child.hasDateOfBirth ? Palette.text : Palette.textDim,
            ),
          ),
        ),
        // The age is exactly where a parent wonders what comes next, so the
        // development calendar hangs off it. Shown only with a date of birth:
        // without one the calendar has nothing to place her child on.
        if (child.hasDateOfBirth) ...[
          IconButton(
            icon: const Icon(Icons.vaccines_outlined, color: Palette.violet),
            tooltip: l.t('vac_title'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => VaccinationScreen(child: child, today: now),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.timeline_rounded, color: Palette.violet),
            tooltip: l.t('dev_title'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChildDevelopmentScreen(child: child, today: now),
            )),
          ),
        ],
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _StatusRow({required this.icon, required this.color, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13.5)),
        ]),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => const Divider(height: 14, color: Palette.border);
}
