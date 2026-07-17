/// Settings — profile, language, children, devices, about, reset. Premium light
/// grouped-list styling. Reads/writes through the AppController.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../app/app_controller.dart';
import '../../domain/family.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../calibration/bp_calibration_sheet.dart';
import '../theme.dart';
import '../tracking/family_sheets.dart';
import '../widgets/avatar.dart';
import '../widgets/confirm.dart';

class SettingsScreen extends StatelessWidget {
  final AppController controller;
  const SettingsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final c = controller;

    return Scaffold(
      appBar: AppBar(title: Text(l.t('settings_title'))),
      body: StreamBuilder<void>(
        stream: c.changes,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // ---- Language (distinct code badge per language) ----
            _Section(title: l.t('set_language'), children: [
              for (final (loc, name, code) in const [
                (AppLocale.ru, 'Русский', 'RU'),
                (AppLocale.kk, 'Қазақша', 'KK'),
                (AppLocale.en, 'English', 'EN'),
              ])
                _Row(
                  leading: Icons.translate,
                  leadingWidget: _LangBadge(code: code, selected: c.locale == loc),
                  title: name,
                  trailing: c.locale == loc
                      ? const Icon(Icons.check_circle, color: Palette.violet)
                      : const Icon(Icons.circle_outlined, color: Palette.border),
                  onTap: () => c.setLocale(loc),
                ),
            ]),

            // ---- Children ----
            _Section(
              title: l.t('set_children'),
              action: _AddButton(label: l.t('tr_add_child'), onTap: () => showAddChildSheet(context, c)),
              children: [
                for (final child in c.children)
                  _Row(
                    leading: Icons.child_care,
                    leadingWidget: PhotoAvatar(
                      photoPath: child.photoPath, name: child.name, size: 34,
                      fallbackIcon: child.gender == Gender.boy
                          ? Icons.boy
                          : child.gender == Gender.girl
                              ? Icons.girl
                              : Icons.child_care),
                    title: child.name,
                    subtitle: _childSubtitle(l, child),
                    onTap: () => showEditChildSheet(context, c, child),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Palette.textDim),
                      tooltip: l.t('act_remove'),
                      onPressed: () async {
                        final ok = await confirmDestructive(
                          context,
                          title: l.t('confirm_remove_child_title'),
                          message: l.t('confirm_remove_child_body', {'name': child.name}),
                          confirmLabel: l.t('act_remove'),
                        );
                        if (ok) c.removeChild(child.id);
                      },
                    ),
                  ),
              ],
            ),

            // ---- Devices ----
            _Section(
              title: l.t('set_devices'),
              action: _AddButton(label: l.t('tr_add_device'), onTap: () => showAddDeviceSheet(context, c)),
              children: c.devices.isEmpty
                  ? [_Row(leading: Icons.watch_off_outlined, title: l.t('set_no_devices'))]
                  : [
                      for (final d in c.devices)
                        _Row(
                          leading: d.kind == DeviceKind.band ? Icons.watch : Icons.sensors,
                          title: d.name,
                          subtitle: _deviceSubtitle(l, c, d),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Palette.textDim),
                            tooltip: l.t('act_remove'),
                            onPressed: () async {
                              final ok = await confirmDestructive(
                                context,
                                title: l.t('confirm_remove_device_title'),
                                message: l.t('confirm_remove_device_body', {'name': d.name}),
                                confirmLabel: l.t('act_remove'),
                              );
                              if (ok) c.removeDevice(d.id);
                            },
                          ),
                        ),
                    ],
            ),

            // ---- Notifications ----
            _Section(title: l.t('set_notifications'), children: [
              _Row(
                leading: Icons.notifications_active_outlined,
                title: l.t('set_notifications'),
                subtitle: l.t('set_notifications_sub'),
                trailing: Switch(
                  value: c.notificationsEnabled,
                  activeColor: Palette.violet,
                  onChanged: c.setNotificationsEnabled,
                ),
                onTap: () => c.setNotificationsEnabled(!c.notificationsEnabled),
              ),
            ]),

            // ---- Blood pressure calibration (highlighted CTA) ----
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
              child: Text(l.t('set_bp_calibration').toUpperCase(),
                  style: const TextStyle(color: Palette.textDim, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            ),
            _CalibrateCta(status: _calStatus(l, c), onTap: () => showCalibrateBpSheet(context, c)),

            // ---- Data ----
            _Section(title: l.t('set_data'), children: [
              _Row(
                leading: Icons.download_rounded,
                title: l.t('set_export'),
                subtitle: l.t('set_export_sub'),
                trailing: const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
                onTap: () => _openExport(context, c),
              ),
            ]),

            // ---- About ----
            _Section(title: l.t('set_about'), children: [
              _Row(leading: Icons.info_outline, title: 'Umay', subtitle: l.t('set_about_body')),
              _Row(leading: Icons.tag, title: l.t('set_version'), trailing: const Text('0.1.0', style: TextStyle(color: Palette.textDim))),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _openExport(BuildContext context, AppController c) async {
    final l = L10nScope.of(context);
    final json = c.exportJson();
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l.t('set_export')),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('set_export_hint'), style: const TextStyle(color: Palette.textDim, fontSize: 13)),
              const SizedBox(height: 12),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Palette.glass, borderRadius: BorderRadius.circular(12), border: Border.all(color: Palette.border)),
                  child: SingleChildScrollView(
                    child: SelectableText(json,
                        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5, height: 1.35, color: Palette.text)),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: Text(l.t('act_cancel'))),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (!dialogCtx.mounted) return;
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.t('set_export_copied')), behavior: SnackBarBehavior.floating),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Palette.violet),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(l.t('set_export_copy')),
          ),
        ],
      ),
    );
  }

  String _calStatus(L10n l, AppController c) {
    final cal = c.bpCalibration;
    if (cal == null) return l.t('cal_never');
    final age = DateTime.now().difference(cal.calibratedAt);
    if (age.inDays > 8) return l.t('cal_stale');
    return l.t('cal_last', {'ago': l.ago(age)});
  }

  String _deviceSubtitle(L10n l, AppController c, PairedDevice d) {
    final kindLabel = l.t(d.kind == DeviceKind.band ? 'dev_band' : 'dev_tag');
    if (d.kind == DeviceKind.tag && d.childId != null) {
      for (final ch in c.children) {
        if (ch.id == d.childId) return '${l.t('dev_linked_to', {'name': ch.name})} · ${d.id}';
      }
    }
    return '$kindLabel · ${d.id}';
  }

  String _childSubtitle(L10n l, ChildProfile child) {
    final zones = '${child.geofences.length} · ${l.t('nav_child')}';
    if (!child.hasDateOfBirth) return zones;
    return '${l.childAge(child.ageInMonths(DateTime.now()))} · $zones';
  }

}

/// Highlighted call-to-action for weekly blood-pressure calibration — a critical
/// feature, so it gets a distinct accent card with an informative tooltip rather
/// than a plain list row.
class _CalibrateCta extends StatelessWidget {
  final String status;
  final VoidCallback onTap;
  const _CalibrateCta({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Tooltip(
      message: l.t('cal_tooltip'),
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Palette.violet.withValues(alpha: 0.10), Palette.pink.withValues(alpha: 0.07)],
              ),
              border: Border.all(color: Palette.violet.withValues(alpha: 0.22)),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Palette.violet, Palette.pink]),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.monitor_heart_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(l.t('cal_title'),
                                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                          ),
                          const Icon(Icons.info_outline_rounded, size: 16, color: Palette.violet),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(status, style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Palette.violet),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? action;
  const _Section({required this.title, required this.children, this.action});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
          child: Row(children: [
            Expanded(
              child: Text(title.toUpperCase(),
                  style: const TextStyle(color: Palette.textDim, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            ),
            if (action != null) action!,
          ]),
        ),
        Container(
          decoration: BoxDecoration(
            color: Palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Palette.border),
            boxShadow: Palette.cardShadow,
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Palette.border, indent: 54),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final IconData leading;
  final Widget? leadingWidget; // overrides [leading] icon when set
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _Row({required this.leading, this.leadingWidget, required this.title, this.subtitle, this.trailing, this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            leadingWidget ?? Icon(leading, size: 22, color: Palette.textDim),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// A small 2-letter language-code badge (RU / KK / EN) used in the language list
/// so each row has a distinct leading marker instead of a repeated translate icon.
class _LangBadge extends StatelessWidget {
  final String code;
  final bool selected;
  const _LangBadge({required this.code, required this.selected});
  @override
  Widget build(BuildContext context) {
    final color = selected ? Palette.violet : Palette.textDim;
    return Container(
      width: 34, height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(code,
          style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
    );
  }
}
