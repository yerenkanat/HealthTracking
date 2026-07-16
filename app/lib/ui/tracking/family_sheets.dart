/// Bottom sheets for adding a child or a device — premium light styling.
/// Wired from the Child tab's "+" menu and Settings.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/geofence.dart';
import '../../data/photo_store.dart';
import '../../domain/country_codes.dart';
import '../../domain/family.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/photo_picker_sheet.dart';

Future<void> showEditProfileSheet(BuildContext context, AppController controller) {
  final p = controller.profile;
  final nameCtl = TextEditingController(text: p.displayName);
  final phoneCtl = TextEditingController(text: p.phoneNumber);
  final doctorCtl = TextEditingController(text: p.doctorPhone);
  var dial = p.dialCode;
  return _sheet(context, (ctx, l) {
    return StatefulBuilder(
      builder: (ctx, setState) => _SheetBody(
        title: l.t('set_edit_profile'),
        icon: Icons.person,
        fields: [
          TextField(
            controller: nameCtl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l.t('onb_name_hint')),
          ),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Palette.glass,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Palette.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: countries.firstWhere((c) => c.dial == dial, orElse: () => defaultCountry).iso + '|' + dial,
                  onChanged: (v) { if (v != null) setState(() => dial = v.split('|')[1]); },
                  items: [
                    for (final c in countries)
                      DropdownMenuItem(value: '${c.iso}|${c.dial}', child: Text('${c.flag} ${c.dial}')),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: phoneCtl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l.t('onb_phone_hint')),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: doctorCtl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: l.t('prof_doctor_hint'),
              prefixIcon: const Icon(Icons.local_hospital_outlined, size: 20),
            ),
          ),
        ],
        onSave: () {
          if (nameCtl.text.trim().isEmpty) return false;
          controller.updateProfile(controller.profile.copyWith(
            displayName: nameCtl.text.trim(),
            dialCode: dial,
            phoneNumber: phoneCtl.text.trim(),
            doctorPhone: doctorCtl.text.trim(),
          ));
          return true;
        },
      ),
    );
  });
}

Future<void> showAddChildSheet(BuildContext context, AppController controller) =>
    _childSheet(context, controller);

Future<void> showEditChildSheet(BuildContext context, AppController controller, ChildProfile child) =>
    _childSheet(context, controller, existing: child);

/// Shared add/edit child sheet: photo + name + date of birth.
Future<void> _childSheet(BuildContext context, AppController controller, {ChildProfile? existing}) {
  final isEdit = existing != null;
  final nameCtl = TextEditingController(text: existing?.name ?? '');
  DateTime? dob = existing?.dateOfBirth;
  String? photoPath = existing?.photoPath;
  Gender? gender = existing?.gender;
  final oldPhoto = existing?.photoPath;

  return _sheet(context, (ctx, l) {
    return StatefulBuilder(
      builder: (ctx, setState) => _SheetBody(
        title: l.t(isEdit ? 'act_edit' : 'tr_add_child'),
        icon: Icons.child_care,
        fields: [
          Center(
            child: _PhotoPickerAvatar(
              photoPath: photoPath,
              name: nameCtl.text,
              prefix: existing?.id ?? 'child',
              onChanged: (p) => setState(() => photoPath = p),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: nameCtl,
            autofocus: !isEdit,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l.t('onb_child_name_hint')),
            onChanged: (_) => setState(() {}), // refresh avatar initials
          ),
          const SizedBox(height: 14),
          // Gender — optional (tap again to clear).
          Text(l.t('child_gender'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final g in Gender.values)
              ChoiceChip(
                avatar: Icon(g == Gender.boy ? Icons.boy : Icons.girl,
                    size: 18, color: gender == g ? Palette.violet : Palette.textDim),
                label: Text(l.t('gender_${g.name}')),
                selected: gender == g,
                onSelected: (_) => setState(() => gender = gender == g ? null : g),
                selectedColor: Palette.violet.withValues(alpha: 0.18),
                backgroundColor: Palette.glass,
                side: const BorderSide(color: Palette.border),
                labelStyle: TextStyle(
                  color: gender == g ? Palette.text : Palette.textDim,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ]),
          const SizedBox(height: 14),
          // Date of birth — optional, but powers age-based personalization.
          _DateField(
            label: l.t('child_dob_hint'),
            helper: l.t('child_dob_help'),
            value: dob,
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: ctx,
                initialDate: dob ?? DateTime(now.year - 4, now.month, now.day),
                firstDate: DateTime(now.year - 18),
                lastDate: now,
                helpText: l.t('child_dob_hint'),
              );
              if (picked != null) setState(() => dob = picked);
            },
          ),
        ],
        onSave: () {
          final name = nameCtl.text.trim();
          if (name.isEmpty) return false;
          if (isEdit) {
            controller.updateChild(existing.copyWith(
              name: name,
              dateOfBirth: dob, clearDateOfBirth: dob == null,
              photoPath: photoPath, clearPhoto: photoPath == null,
              gender: gender, clearGender: gender == null,
            ));
          } else {
            // Default Home zone; the user can refine zones later.
            controller.addChild(ChildProfile(
              id: 'child-${DateTime.now().microsecondsSinceEpoch}',
              name: name,
              dateOfBirth: dob,
              photoPath: photoPath,
              gender: gender,
              geofences: [
                Geofence.circle('home', l.t('onb_home_label'), const Coordinates(43.238949, 76.889709), 100),
              ],
            ));
          }
          if (oldPhoto != null && oldPhoto != photoPath) {
            PhotoStore().delete(oldPhoto); // fire-and-forget cleanup
          }
          return true;
        },
      ),
    );
  });
}

/// A tappable avatar (with camera badge) that opens the photo picker and reports
/// the chosen/removed path via [onChanged] (null = removed).
class _PhotoPickerAvatar extends StatelessWidget {
  final String? photoPath;
  final String name;
  final String prefix;
  final void Function(String?) onChanged;
  const _PhotoPickerAvatar({required this.photoPath, required this.name, required this.prefix, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final r = await pickPhoto(context, prefix: prefix, canRemove: photoPath != null && photoPath!.isNotEmpty);
        if (r == null) return;
        onChanged(r.remove ? null : r.path);
      },
      child: Stack(
        children: [
          PhotoAvatar(photoPath: photoPath, name: name, size: 84, fallbackIcon: Icons.child_care),
          Positioned(
            right: 0, bottom: 0,
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: Palette.violet,
                shape: BoxShape.circle,
                border: Border.all(color: Palette.surface, width: 2.5),
              ),
              child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showAddDeviceSheet(BuildContext context, AppController controller) {
  final nameCtl = TextEditingController();
  final idCtl = TextEditingController();
  var kind = DeviceKind.band;
  final children = controller.children;
  // A tag belongs to one child; default to the currently selected child.
  String? tagChildId = controller.selectedChild?.id ?? (children.isNotEmpty ? children.first.id : null);

  return _sheet(context, (ctx, l) {
    return StatefulBuilder(
      builder: (ctx, setState) => _SheetBody(
        title: l.t('tr_add_device'),
        icon: Icons.watch,
        fields: [
          Row(children: [
            Expanded(
              child: _KindChip(
                label: l.t('dev_band'),
                selected: kind == DeviceKind.band,
                onTap: () => setState(() => kind = DeviceKind.band),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KindChip(
                label: l.t('dev_tag'),
                selected: kind == DeviceKind.tag,
                onTap: () => setState(() => kind = DeviceKind.tag),
              ),
            ),
          ]),
          // A tracker tag is linked to a specific child — let the user pick which.
          if (kind == DeviceKind.tag) ...[
            const SizedBox(height: 16),
            Text(l.t('dev_for_child'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            const SizedBox(height: 8),
            if (children.isEmpty)
              Text(l.t('dev_no_child'), style: const TextStyle(color: Palette.textDim, fontSize: 13))
            else
              Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  for (final ch in children)
                    ChoiceChip(
                      label: Text(ch.name),
                      selected: ch.id == tagChildId,
                      onSelected: (_) => setState(() => tagChildId = ch.id),
                      selectedColor: Palette.violet.withValues(alpha: 0.20),
                      backgroundColor: Palette.glass,
                      side: const BorderSide(color: Palette.border),
                      labelStyle: TextStyle(
                        color: ch.id == tagChildId ? Palette.text : Palette.textDim,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: nameCtl,
            decoration: InputDecoration(labelText: l.t('dev_name_hint')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: idCtl,
            decoration: InputDecoration(labelText: l.t('dev_id_hint')),
          ),
        ],
        onSave: () {
          final id = idCtl.text.trim();
          if (id.isEmpty) return false;
          // A tag must be linked to a child; block saving one with no child.
          if (kind == DeviceKind.tag && tagChildId == null) return false;
          controller.addDevice(PairedDevice(
            id: id,
            name: nameCtl.text.trim().isEmpty ? l.t(kind == DeviceKind.band ? 'dev_band' : 'dev_tag') : nameCtl.text.trim(),
            kind: kind,
            childId: kind == DeviceKind.tag ? tagChildId : null,
          ));
          return true;
        },
      ),
    );
  });
}

Future<void> _sheet(BuildContext context, Widget Function(BuildContext, dynamic l) body) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: body(ctx, L10nScope.of(ctx)),
    ),
  );
}

class _SheetBody extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> fields;
  final bool Function() onSave;
  const _SheetBody({required this.title, required this.icon, required this.fields, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Palette.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(gradient: Palette.violetPink, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 18),
          ...fields,
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: Palette.border),
                  foregroundColor: Palette.textDim,
                ),
                child: Text(l.t('act_cancel')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  if (onSave()) Navigator.pop(context);
                },
                child: Text(l.t('act_save')),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// A tappable, input-styled field that opens a date picker. Shows the chosen
/// date (locale-formatted) or a hint when empty, plus optional helper text.
class _DateField extends StatelessWidget {
  final String label;
  final String? helper;
  final DateTime? value;
  final VoidCallback onTap;
  const _DateField({required this.label, required this.onTap, this.helper, this.value});

  @override
  Widget build(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    final hasValue = value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.cake_outlined, size: 20),
            ),
            child: Text(
              hasValue ? ml.formatMediumDate(value!) : ml.dateHelpText,
              style: TextStyle(
                fontSize: 15.5,
                color: hasValue ? Palette.text : Palette.textDim,
              ),
            ),
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 6),
            child: Text(helper!, style: const TextStyle(color: Palette.textDim, fontSize: 12)),
          ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _KindChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Palette.violet.withValues(alpha: 0.2) : Palette.glass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Palette.violet : Palette.border),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Palette.text : Palette.textDim,
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }
}
