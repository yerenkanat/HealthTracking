/// Profile page — the mother's account: avatar, name, phone, a quick summary of
/// her children + devices, and edit/settings actions. Premium light styling.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../data/photo_store.dart';
import '../../domain/appointment.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../appointments/appointments_screen.dart';
import '../settings/settings_screen.dart';
import '../theme.dart';
import '../tracking/family_sheets.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import '../widgets/photo_picker_sheet.dart';
import '../widgets/stat_tile.dart';

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
            tooltip: l.t('settings_title'),
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
                        // violetText, not violet: the lighter brand violet on its own
                        // 12% tint reads at 4.02 contrast, under the 4.5 minimum.
                        foregroundColor: Palette.violetText,
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
                  Expanded(child: StatTile(
                    icon: Icons.child_care,
                    gradient: Palette.violetPink,
                    value: '${c.children.length}',
                    label: l.t('prof_children_count'),
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: StatTile(
                    icon: Icons.watch,
                    gradient: Palette.tealBlue,
                    value: '${c.devices.length}',
                    label: l.t('prof_devices_count'),
                  )),
                ],
              ),
              const SizedBox(height: 14),
              _AppointmentsEntry(
                subtitle: _apptSubtitle(l, c),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => AppointmentsScreen(controller: c)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _apptSubtitle(L10n l, AppController c) {
    final next = c.nextAppt;
    if (next == null) return l.t('appt_none');
    final d = daysUntil(next, DateTime.now());
    final when = d == 0
        ? l.t('appt_today')
        : d == 1
            ? l.t('appt_tomorrow')
            : l.t('appt_in_days', {'n': d});
    return '${next.title} · $when';
  }
}

/// Tappable profile row that opens the reminders list, previewing the next one.
class _AppointmentsEntry extends StatelessWidget {
  final String subtitle;
  final VoidCallback onTap;
  const _AppointmentsEntry({required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return GlassCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(gradient: Palette.roseViolet, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.event_note_rounded, color: Colors.white, size: 22),
        ),
        title: Text(l.t('appt_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
        onTap: onTap,
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

