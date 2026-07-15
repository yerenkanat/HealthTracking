/// Bottom sheets for adding a child or a device — high-tech dark glass styling.
/// Wired from the Child tab's "+" menu.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/geofence.dart';
import '../../domain/country_codes.dart';
import '../../domain/family.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

Future<void> showEditProfileSheet(BuildContext context, AppController controller) {
  final p = controller.profile;
  final nameCtl = TextEditingController(text: p.displayName);
  final phoneCtl = TextEditingController(text: p.phoneNumber);
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
        ],
        onSave: () {
          if (nameCtl.text.trim().isEmpty) return false;
          controller.updateProfile(controller.profile.copyWith(
            displayName: nameCtl.text.trim(),
            dialCode: dial,
            phoneNumber: phoneCtl.text.trim(),
          ));
          return true;
        },
      ),
    );
  });
}

Future<void> showAddChildSheet(BuildContext context, AppController controller) {
  final nameCtl = TextEditingController();
  return _sheet(context, (ctx, l) {
    return _SheetBody(
      title: l.t('tr_add_child'),
      icon: Icons.child_care,
      fields: [
        TextField(
          controller: nameCtl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l.t('onb_child_name_hint')),
        ),
      ],
      onSave: () {
        final name = nameCtl.text.trim();
        if (name.isEmpty) return false;
        // Default Home zone; the user can refine zones later.
        controller.addChild(ChildProfile(
          id: 'child-${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          geofences: [
            Geofence.circle('home', l.t('onb_home_label'), const Coordinates(43.238949, 76.889709), 100),
          ],
        ));
        return true;
      },
    );
  });
}

Future<void> showAddDeviceSheet(BuildContext context, AppController controller) {
  final nameCtl = TextEditingController();
  final idCtl = TextEditingController();
  var kind = DeviceKind.band;
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
          controller.addDevice(PairedDevice(
            id: id,
            name: nameCtl.text.trim().isEmpty ? l.t(kind == DeviceKind.band ? 'dev_band' : 'dev_tag') : nameCtl.text.trim(),
            kind: kind,
            childId: kind == DeviceKind.tag ? controller.selectedChild?.id : null,
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
