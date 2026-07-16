/// Profile page — the mother's account: avatar, name, phone, a quick summary of
/// her children + devices, and edit/settings actions. Premium light styling.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../l10n/l10n_scope.dart';
import '../settings/settings_screen.dart';
import '../theme.dart';
import '../tracking/family_sheets.dart';
import '../widgets/glass.dart';

class ProfileScreen extends StatelessWidget {
  final AppController controller;
  const ProfileScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final c = controller;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('set_profile')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Palette.textDim),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsScreen(controller: c)),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<void>(
        stream: c.changes,
        builder: (context, _) {
          final name = c.displayName.isEmpty ? '—' : c.displayName;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const SizedBox(height: 12),
              // Avatar + name + phone
              Center(
                child: Column(
                  children: [
                    _Avatar(name: c.displayName),
                    const SizedBox(height: 16),
                    Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      c.profile.hasPhone ? '${c.profile.dialCode} ${c.profile.phoneNumber}' : l.t('prof_no_phone'),
                      style: const TextStyle(color: Palette.textDim, fontSize: 14.5),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () => showEditProfileSheet(context, c),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(l.t('set_edit_profile')),
                      style: FilledButton.styleFrom(
                        backgroundColor: Palette.violet.withValues(alpha: 0.12),
                        foregroundColor: Palette.violet,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              // Summary tiles: children + devices
              Row(
                children: [
                  Expanded(child: _StatTile(
                    icon: Icons.child_care,
                    gradient: Palette.violetPink,
                    value: '${c.children.length}',
                    label: l.t('prof_children_count'),
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: _StatTile(
                    icon: Icons.watch,
                    gradient: Palette.tealBlue,
                    value: '${c.devices.length}',
                    label: l.t('prof_devices_count'),
                  )),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});
  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        gradient: Palette.violetPink,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Palette.violet.withValues(alpha: 0.3), blurRadius: 22, offset: const Offset(0, 10), spreadRadius: -6)],
      ),
      alignment: Alignment.center,
      child: initials.isEmpty
          ? const Icon(Icons.person, color: Colors.white, size: 44)
          : Text(initials,
              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700)),
    );
  }

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Gradient gradient;
  final String value;
  final String label;
  const _StatTile({required this.icon, required this.gradient, required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 14),
          Text(value, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 26, fontWeight: FontWeight.w700, height: 1)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Palette.textDim, fontSize: 13)),
        ],
      ),
    );
  }
}
