/// Settings — profile, language, children, devices, about, reset. Premium light
/// grouped-list styling. Reads/writes through the AppController.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../domain/family.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../tracking/family_sheets.dart';

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
            // ---- Profile ----
            _Section(title: l.t('set_profile'), children: [
              _Row(
                leading: Icons.person_outline,
                title: c.displayName.isEmpty ? '—' : c.displayName,
                subtitle: c.profile.hasPhone ? '${c.profile.dialCode} ${c.profile.phoneNumber}' : null,
                trailing: TextButton(
                  onPressed: () => showEditProfileSheet(context, c),
                  child: Text(l.t('act_edit')),
                ),
              ),
            ]),

            // ---- Language ----
            _Section(title: l.t('set_language'), children: [
              for (final (loc, name) in const [
                (AppLocale.ru, 'Русский'),
                (AppLocale.kk, 'Қазақша'),
                (AppLocale.en, 'English'),
              ])
                _Row(
                  leading: Icons.translate,
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
                    title: child.name,
                    subtitle: '${child.geofences.length} · ${l.t('nav_child')}',
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Palette.textDim),
                      onPressed: () => c.removeChild(child.id),
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
                          subtitle: '${l.t(d.kind == DeviceKind.band ? 'dev_band' : 'dev_tag')} · ${d.id}',
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Palette.textDim),
                            onPressed: () => c.removeDevice(d.id),
                          ),
                        ),
                    ],
            ),

            // ---- About ----
            _Section(title: l.t('set_about'), children: [
              _Row(leading: Icons.info_outline, title: 'Umay', subtitle: l.t('set_about_body')),
              _Row(leading: Icons.tag, title: l.t('set_version'), trailing: const Text('0.1.0', style: TextStyle(color: Palette.textDim))),
            ]),

            const SizedBox(height: 12),
            // ---- Reset (destructive) ----
            OutlinedButton.icon(
              onPressed: () => _confirmReset(context, c),
              icon: const Icon(Icons.restart_alt, color: Palette.danger),
              label: Text(l.t('set_reset'), style: const TextStyle(color: Palette.danger)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                side: BorderSide(color: Palette.danger.withValues(alpha: 0.4)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, AppController c) async {
    final l = L10nScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('set_reset_title')),
        content: Text(l.t('set_reset_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.t('act_cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.t('set_reset'), style: const TextStyle(color: Palette.danger)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await c.resetApp();
      if (context.mounted) Navigator.pop(context); // leave settings → onboarding shows
    }
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
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _Row({required this.leading, required this.title, this.subtitle, this.trailing, this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(leading, size: 22, color: Palette.textDim),
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
