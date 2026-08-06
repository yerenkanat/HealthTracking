/// Profile page — the mother's account: avatar, name, phone, a quick summary of
/// her children + devices, and edit/settings actions. Premium light styling.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../data/photo_store.dart';
import '../../domain/appointment.dart';
import '../../domain/course_lesson.dart';
import '../../l10n/l10n.dart';
import '../content/course_route.dart';
import '../../l10n/l10n_scope.dart';
import '../appointments/appointments_screen.dart';
import '../settings/settings_screen.dart';
import '../design_system.dart';
import '../theme.dart';
import '../tracking/family_sheets.dart';
import '../widgets/avatar.dart';
import '../widgets/photo_picker_sheet.dart';
import '../ds_widgets.dart';
import '../widgets/stat_tile.dart';

class ProfileScreen extends StatelessWidget {
  final AppController controller;

  /// Open the family hub (Child tab) where children and trackers are managed.
  /// Null in tests/standalone use leaves the summary tiles as plain readouts.
  final VoidCallback? onOpenChildren;
  final VoidCallback? onOpenDevices;
  const ProfileScreen(
      {super.key,
      required this.controller,
      this.onOpenChildren,
      this.onOpenDevices});

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
                    Text(name,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      c.profile.hasPhone
                          ? '${c.profile.dialCode} ${c.profile.phoneNumber}'
                          : l.t('prof_no_phone'),
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 14.5),
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
                  Expanded(
                      child: StatTile(
                    icon: Icons.child_care,
                    color: Ds.coralCta,
                    value: '${c.children.length}',
                    label: l.t('prof_children_count'),
                    onTap: onOpenChildren,
                  )),
                  const SizedBox(width: 14),
                  Expanded(
                      child: StatTile(
                    icon: Icons.watch,
                    color: Ds.mint,
                    value: '${c.devices.length}',
                    label: l.t('prof_devices_count'),
                    onTap: onOpenDevices,
                  )),
                ],
              ),
              const SizedBox(height: 14),
              _AppointmentsEntry(
                subtitle: _apptSubtitle(l, c),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => AppointmentsScreen(controller: c)),
                ),
              ),
              const SizedBox(height: 10),
              // The Ма!Ма! course. Always visible, whether or not she owns it:
              // the locked screen is the offer, and hiding the entry point
              // entirely would mean nobody who has not bought the комплект ever
              // learns the course exists.
              _CourseEntry(
                load: c.api?.getCourse,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => CourseRoute(controller: c)),
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


/// Entry point to the Ма!Ма! course.
///
/// Shown to everyone. Somebody who has not bought the комплект sees the offer
/// behind it — hiding the row would mean she never learns the course exists,
/// which is the opposite of what a bundled upsell is for.
/// It also has to say something different to somebody who OWNS it. This row
/// read "входят в комплект" to every single person — a customer who had paid
/// 39 000 ₸ was pitched the thing she had already bought, every time she opened
/// her profile, with no sign that she was four lessons into it. The server knew
/// both facts and neither reached the screen.
class _CourseEntry extends StatefulWidget {
  final VoidCallback onTap;

  /// How to find out what she owns and how far she has got. Null in a test or
  /// a build with no API, which falls back to the offer line — the honest
  /// thing to show when we cannot check.
  final Future<CourseAccess> Function()? load;

  const _CourseEntry({required this.onTap, this.load});

  @override
  State<_CourseEntry> createState() => _CourseEntryState();
}

class _CourseEntryState extends State<_CourseEntry> {
  CourseAccess? _access;

  @override
  void initState() {
    super.initState();
    final load = widget.load;
    if (load == null) return;
    // Unawaited and unguarded: a failed request leaves the offer line, which is
    // what this row said before it could check at all. A profile screen must
    // not break because the course could not be reached.
    load().then((a) {
      if (mounted) setState(() => _access = a);
    }).catchError((_) {});
  }

  /// The one line under the title. Ordered by what it is worth saying:
  /// how far she has got beats "you own this" beats the sales pitch.
  String _subtitle(L10n l) {
    final a = _access;
    if (a == null || !a.entitled) return l.t('course_entry_sub');
    if (a.lessons.isEmpty) return l.t('course_entry_owned');
    return l.t('course_progress_of')
        .replaceFirst('{done}', '${a.completedCount}')
        .replaceFirst('{total}', '${a.lessons.length}');
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final entitled = _access?.entitled == true;
    return DsCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
              color: Ds.pastelPink,
              borderRadius: BorderRadius.circular(12)),
          child: Icon(
              entitled
                  ? Icons.play_arrow_rounded
                  : Icons.play_circle_outline_rounded,
              color: Ds.ink,
              size: 22),
        ),
        title: Text(l.t('course_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(_subtitle(l), key: const Key('course-entry-sub')),
        trailing: const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
        onTap: widget.onTap,
      ),
    );
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
    return DsCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
              color: Ds.coralCta,
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.event_note_rounded,
              color: Colors.white, size: 22),
        ),
        title: Text(l.t('appt_title'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
        trailing:
            const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
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
  const _EditablePhoto(
      {required this.photoPath, required this.name, required this.onTap});

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
            shadow: DsShape.hardShadow,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Palette.violet,
                shape: BoxShape.circle,
                border: Border.all(color: Palette.bg, width: 2.5),
              ),
              child: const Icon(Icons.photo_camera_rounded,
                  color: Colors.white, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _editProfilePhoto(BuildContext context, AppController c) async {
  final r = await pickPhoto(context,
      prefix: 'profile', canRemove: c.profile.hasPhoto);
  if (r == null) return;
  final old = c.profile.photoPath;
  if (r.remove) {
    c.updateProfile(c.profile.copyWith(clearPhoto: true));
  } else if (r.path != null) {
    c.updateProfile(c.profile.copyWith(photoPath: r.path));
  }
  if (old != null && old != c.profile.photoPath) await PhotoStore().delete(old);
}
