/// RemindersCenterScreen — the single home for every scheduled reminder: the
/// period and fertile-window nudges (cycle mode) and the daily water reminder.
/// This is the ONLY place these are toggled; other screens link here rather than
/// duplicating the controls.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../domain/reminders.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class RemindersCenterScreen extends StatelessWidget {
  final AppController controller;
  const RemindersCenterScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('rem_title'))),
        body: StreamBuilder<void>(
          stream: controller.changes,
          builder: (context, _) {
            final c = controller;
            final hasCycle = c.cycle.hasData;
            final active = activeReminderCount(
              period: c.periodReminderEnabled,
              fertile: c.fertileReminderEnabled,
              water: c.waterReminderMinutes != null,
              medication: c.medReminderMinutes != null,
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                  child: Text(l.t('rem_active', {'n': active}),
                      style: const TextStyle(color: Palette.textDim, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                GlassCard(
                  child: Column(
                    children: [
                      _ReminderTile(
                        icon: Icons.water_drop_rounded,
                        color: Palette.roseDeep,
                        title: l.t('period_reminder'),
                        subtitle: hasCycle ? l.t('period_reminder_sub') : l.t('rem_needs_cycle'),
                        value: c.periodReminderEnabled,
                        onChanged: hasCycle ? c.setPeriodReminder : null,
                      ),
                      const _ThinDivider(),
                      _ReminderTile(
                        icon: Icons.eco_rounded,
                        color: Palette.teal,
                        title: l.t('fertile_reminder'),
                        subtitle: hasCycle ? l.t('fertile_reminder_sub') : l.t('rem_needs_cycle'),
                        value: c.fertileReminderEnabled,
                        onChanged: hasCycle ? c.setFertileReminder : null,
                      ),
                      const _ThinDivider(),
                      _ReminderTile(
                        icon: Icons.local_drink_rounded,
                        color: Palette.blue,
                        title: l.t('water_reminder'),
                        subtitle: c.waterReminderMinutes == null
                            ? l.t('water_reminder_off')
                            : l.t('water_reminder_at', {'time': minutesToHhmm(c.waterReminderMinutes!)}),
                        value: c.waterReminderMinutes != null,
                        onChanged: (on) => _toggleWater(context, c, on),
                        onTapBody: c.waterReminderMinutes == null ? null : () => _pickWaterTime(context, c),
                      ),
                      const _ThinDivider(),
                      _ReminderTile(
                        icon: Icons.medication_rounded,
                        color: Palette.violet,
                        title: l.t('med_reminder'),
                        subtitle: c.medications.isEmpty
                            ? l.t('rem_needs_meds')
                            : c.medReminderMinutes == null
                                ? l.t('med_reminder_off')
                                : l.t('med_reminder_at', {'time': minutesToHhmm(c.medReminderMinutes!)}),
                        value: c.medReminderMinutes != null,
                        // Nothing to be reminded about until something's tracked.
                        onChanged: c.medications.isEmpty ? null : (on) => _toggleMed(context, c, on),
                        onTapBody: c.medReminderMinutes == null ? null : () => _pickMedTime(context, c),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(l.t('notif_safety_section').toUpperCase(),
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ),
                GlassCard(
                  child: Column(
                    children: [
                      _ReminderTile(
                        icon: Icons.swap_horiz_rounded,
                        color: Palette.good,
                        title: l.t('notif_zone'),
                        subtitle: l.t('notif_zone_sub'),
                        value: c.notificationPrefs.zoneEvents,
                        onChanged: (on) => c.setNotificationPrefs(c.notificationPrefs.copyWith(zoneEvents: on)),
                      ),
                      const _ThinDivider(),
                      _ReminderTile(
                        icon: Icons.how_to_reg_rounded,
                        color: Palette.blue,
                        title: l.t('notif_checkin'),
                        subtitle: l.t('notif_checkin_sub'),
                        value: c.notificationPrefs.checkIn,
                        onChanged: (on) => c.setNotificationPrefs(c.notificationPrefs.copyWith(checkIn: on)),
                      ),
                      const _ThinDivider(),
                      _ReminderTile(
                        icon: Icons.battery_alert_rounded,
                        color: Palette.amber,
                        title: l.t('notif_lowbattery'),
                        subtitle: l.t('notif_lowbattery_sub'),
                        value: c.notificationPrefs.lowBattery,
                        onChanged: (on) => c.setNotificationPrefs(c.notificationPrefs.copyWith(lowBattery: on)),
                      ),
                      const _ThinDivider(),
                      _ReminderTile(
                        icon: Icons.bedtime_rounded,
                        color: Palette.violet,
                        title: l.t('notif_quiet'),
                        subtitle: c.notificationPrefs.hasQuietHours
                            ? l.t('notif_quiet_at', {
                                'from': minutesToHhmm(c.notificationPrefs.quietStart!),
                                'to': minutesToHhmm(c.notificationPrefs.quietEnd!),
                              })
                            : l.t('notif_quiet_off'),
                        value: c.notificationPrefs.hasQuietHours,
                        onChanged: (on) => _toggleQuietHours(context, c, on),
                        onTapBody: c.notificationPrefs.hasQuietHours ? () => _pickQuietHours(context, c) : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(children: [
                    const Icon(Icons.sos_rounded, size: 15, color: Palette.roseDeep),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.t('notif_sos_note'),
                        style: const TextStyle(color: Palette.textDim, fontSize: 12, height: 1.4))),
                  ]),
                ),
                const SizedBox(height: 14),
                Text(l.t('rem_footer'),
                    style: const TextStyle(color: Palette.textDim, fontSize: 12, height: 1.4)),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggleWater(BuildContext context, AppController c, bool on) async {
    if (!on) {
      c.setWaterReminder(null);
      return;
    }
    final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 20, minute: 0));
    if (picked != null) c.setWaterReminder(picked.hour * 60 + picked.minute);
  }

  Future<void> _toggleMed(BuildContext context, AppController c, bool on) async {
    if (!on) {
      c.setMedReminder(null);
      return;
    }
    final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (picked != null) c.setMedReminder(picked.hour * 60 + picked.minute);
  }

  Future<void> _pickMedTime(BuildContext context, AppController c) async {
    final current = c.medReminderMinutes ?? 9 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked != null) c.setMedReminder(picked.hour * 60 + picked.minute);
  }

  Future<void> _pickWaterTime(BuildContext context, AppController c) async {
    final current = c.waterReminderMinutes ?? 20 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked != null) c.setWaterReminder(picked.hour * 60 + picked.minute);
  }

  Future<void> _toggleQuietHours(BuildContext context, AppController c, bool on) async {
    if (!on) {
      c.setNotificationPrefs(c.notificationPrefs.copyWith(clearQuietHours: true));
      return;
    }
    await _pickQuietHours(context, c);
  }

  /// Pick the quiet-hours window: start, then end. An overnight window
  /// (e.g. 22:00 → 07:00) is fine — the domain handles the wrap.
  Future<void> _pickQuietHours(BuildContext context, AppController c) async {
    final l = L10nScope.of(context);
    final p = c.notificationPrefs;
    final s0 = p.quietStart ?? 22 * 60;
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s0 ~/ 60, minute: s0 % 60),
      helpText: l.t('notif_quiet_from'),
    );
    if (start == null || !context.mounted) return;
    final e0 = p.quietEnd ?? 7 * 60;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: e0 ~/ 60, minute: e0 % 60),
      helpText: l.t('notif_quiet_to'),
    );
    if (end == null) return;
    c.setNotificationPrefs(p.copyWith(
      quietStart: start.hour * 60 + start.minute,
      quietEnd: end.hour * 60 + end.minute,
    ));
  }
}

class _ReminderTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged; // null → disabled (e.g. no cycle data)
  final VoidCallback? onTapBody; // tapping the row body (e.g. edit water time)
  const _ReminderTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.onTapBody,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return InkWell(
      onTap: onTapBody,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: disabled ? 0.06 : 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: disabled ? Palette.textDim : color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: disabled ? Palette.textDim : Palette.text)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.3)),
                ],
              ),
            ),
            Switch(value: value, activeThumbColor: color, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();
  @override
  Widget build(BuildContext context) => const Divider(height: 14, color: Palette.border);
}
