/// Profile page — the mother's account: avatar, name, phone, a quick summary of
/// her children + devices, and edit/settings actions. Premium light styling.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../data/photo_store.dart';
import '../../l10n/l10n_scope.dart';
import '../settings/settings_screen.dart';
import '../theme.dart';
import '../tracking/family_sheets.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import '../widgets/photo_picker_sheet.dart';

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
              // Avatar (tap to add/change photo) + name + phone
              Center(
                child: Column(
                  children: [
                    _EditablePhoto(
                      photoPath: c.profile.photoPath,
                      name: c.displayName,
                      onTap: () => _editProfilePhoto(context, c),
                    ),
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

/// The mother's avatar with a small camera badge — tap to add/change the photo.
class _EditablePhoto extends StatelessWidget {
  final String? photoPath;
  final String name;
  final VoidCallback onTap;
  const _EditablePhoto({required this.photoPath, required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          PhotoAvatar(
            photoPath: photoPath,
            name: name,
            size: 96,
            shadow: [BoxShadow(color: Palette.violet.withValues(alpha: 0.3), blurRadius: 22, offset: const Offset(0, 10), spreadRadius: -6)],
          ),
          Positioned(
            right: 0, bottom: 0,
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: Palette.violet,
                shape: BoxShape.circle,
                border: Border.all(color: Palette.bg, width: 2.5),
              ),
              child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _editProfilePhoto(BuildContext context, AppController c) async {
  final r = await pickPhoto(context, prefix: 'profile', canRemove: c.profile.hasPhoto);
  if (r == null) return;
  final old = c.profile.photoPath;
  if (r.remove) {
    c.updateProfile(c.profile.copyWith(clearPhoto: true));
  } else if (r.path != null) {
    c.updateProfile(c.profile.copyWith(photoPath: r.path));
  }
  if (old != null && old != c.profile.photoPath) await PhotoStore().delete(old);
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
