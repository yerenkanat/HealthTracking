/// A child's emergency medical-ID — a screen to read out or show in the moment,
/// and a form to fill it in.
///
/// The view leads with what a responder acts on first (allergies, conditions),
/// then blood type and medications, then the people to call — the doctor and
/// the emergency contact, each with a one-tap dial. Everything here is what the
/// parent entered; the app verifies nothing, and says so.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/child_emergency.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class ChildEmergencyScreen extends StatelessWidget {
  final String childName;
  final ChildEmergencyInfo info;
  final ValueChanged<ChildEmergencyInfo> onSave;
  const ChildEmergencyScreen({super.key, required this.childName, required this.info, required this.onSave});

  void _edit(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _EmergencyEditScreen(initial: info, onSave: onSave),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        title: Text(l.t('ei_title')),
        actions: [
          if (!info.isEmpty)
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: l.t('ei_edit'), onPressed: () => _edit(context)),
        ],
      ),
      body: info.isEmpty ? _empty(context, l) : _filled(context, l),
    );
  }

  Widget _empty(BuildContext context, dynamic l) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.medical_information_outlined, size: 44, color: Palette.textDim),
              const SizedBox(height: 14),
              Text(l.t('ei_empty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Palette.textDim, height: 1.5, fontSize: 13.5)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l.t('ei_add')),
                style: FilledButton.styleFrom(backgroundColor: Palette.violet),
              ),
            ],
          ),
        ),
      );

  Widget _filled(BuildContext context, dynamic l) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text('$childName · ${l.t('ei_subtitle')}',
              style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
          const SizedBox(height: 14),

          // What a responder needs first.
          if (info.hasCritical)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Palette.roseDeep.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Palette.roseDeep.withValues(alpha: 0.30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (info.allergies.trim().isNotEmpty) _FieldBlock(label: l.t('ei_allergies'), value: info.allergies, strong: true),
                  if (info.conditions.trim().isNotEmpty) _FieldBlock(label: l.t('ei_conditions'), value: info.conditions, strong: true),
                ],
              ),
            ),

          _Card(children: [
            if (info.bloodType.trim().isNotEmpty) _FieldBlock(label: l.t('ei_blood'), value: info.bloodType),
            if (info.medications.trim().isNotEmpty) _FieldBlock(label: l.t('ei_medications'), value: info.medications),
            if (info.notes.trim().isNotEmpty) _FieldBlock(label: l.t('ei_notes'), value: info.notes),
          ]),

          if (info.doctorName.trim().isNotEmpty || info.doctorPhone.trim().isNotEmpty)
            _ContactCard(label: l.t('ei_doctor'), name: info.doctorName, phone: info.doctorPhone, callLabel: l.t('ei_call')),
          if (info.contactName.trim().isNotEmpty || info.contactPhone.trim().isNotEmpty)
            _ContactCard(label: l.t('ei_contact'), name: info.contactName, phone: info.contactPhone, callLabel: l.t('ei_call')),

          const SizedBox(height: 8),
          Text(l.t('ei_disclaimer'), style: const TextStyle(color: Palette.textDim, fontSize: 11.5, height: 1.4)),
        ],
      );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) {
    final shown = children.where((c) => c is! SizedBox).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _FieldBlock extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  const _FieldBlock({required this.label, required this.value, this.strong = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4,
                    color: strong ? Palette.roseDeep : Palette.textDim)),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(fontSize: strong ? 15.5 : 14, fontWeight: strong ? FontWeight.w700 : FontWeight.w500, height: 1.35)),
          ],
        ),
      );
}

class _ContactCard extends StatelessWidget {
  final String label;
  final String name;
  final String phone;
  final String callLabel;
  const _ContactCard({required this.label, required this.name, required this.phone, required this.callLabel});

  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.toUpperCase(),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: Palette.textDim)),
                  const SizedBox(height: 3),
                  if (name.trim().isNotEmpty)
                    Text(name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  if (phone.trim().isNotEmpty)
                    Text(phone, style: const TextStyle(fontSize: 13, color: Palette.textDim, fontFamily: 'JetBrainsMono')),
                ],
              ),
            ),
            if (phone.trim().isNotEmpty)
              FilledButton.icon(
                onPressed: _call,
                icon: const Icon(Icons.call_rounded, size: 16),
                label: Text(callLabel),
                style: FilledButton.styleFrom(backgroundColor: Palette.teal, foregroundColor: Colors.white),
              ),
          ],
        ),
      );
}

/// The edit form.
class _EmergencyEditScreen extends StatefulWidget {
  final ChildEmergencyInfo initial;
  final ValueChanged<ChildEmergencyInfo> onSave;
  const _EmergencyEditScreen({required this.initial, required this.onSave});

  @override
  State<_EmergencyEditScreen> createState() => _EmergencyEditScreenState();
}

class _EmergencyEditScreenState extends State<_EmergencyEditScreen> {
  late final _blood = TextEditingController(text: widget.initial.bloodType);
  late final _allergies = TextEditingController(text: widget.initial.allergies);
  late final _conditions = TextEditingController(text: widget.initial.conditions);
  late final _medications = TextEditingController(text: widget.initial.medications);
  late final _doctorName = TextEditingController(text: widget.initial.doctorName);
  late final _doctorPhone = TextEditingController(text: widget.initial.doctorPhone);
  late final _contactName = TextEditingController(text: widget.initial.contactName);
  late final _contactPhone = TextEditingController(text: widget.initial.contactPhone);
  late final _notes = TextEditingController(text: widget.initial.notes);

  @override
  void dispose() {
    for (final c in [_blood, _allergies, _conditions, _medications, _doctorName, _doctorPhone, _contactName, _contactPhone, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    widget.onSave(ChildEmergencyInfo(
      bloodType: _blood.text,
      allergies: _allergies.text,
      conditions: _conditions.text,
      medications: _medications.text,
      doctorName: _doctorName.text,
      doctorPhone: _doctorPhone.text,
      contactName: _contactName.text,
      contactPhone: _contactPhone.text,
      notes: _notes.text,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        title: Text(l.t('ei_title')),
        actions: [
          TextButton(onPressed: _save, child: Text(l.t('ei_save'))),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          _field(l.t('ei_allergies'), _allergies),
          _field(l.t('ei_conditions'), _conditions),
          _field(l.t('ei_blood'), _blood),
          _field(l.t('ei_medications'), _medications),
          _field(l.t('ei_doctor'), _doctorName, hint: l.t('ei_name_hint')),
          _field(l.t('ei_doctor'), _doctorPhone, hint: l.t('ei_phone_hint'), phone: true),
          _field(l.t('ei_contact'), _contactName, hint: l.t('ei_name_hint')),
          _field(l.t('ei_contact'), _contactPhone, hint: l.t('ei_phone_hint'), phone: true),
          _field(l.t('ei_notes'), _notes, lines: 3),
          const SizedBox(height: 8),
          Text(l.t('ei_disclaimer'), style: const TextStyle(color: Palette.textDim, fontSize: 11.5, height: 1.4)),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {String? hint, bool phone = false, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: c,
          keyboardType: phone ? TextInputType.phone : (lines > 1 ? TextInputType.multiline : TextInputType.text),
          maxLines: lines,
          decoration: InputDecoration(
            labelText: hint == null ? label : '$label · $hint',
            filled: true,
            fillColor: Palette.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Palette.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Palette.border)),
          ),
        ),
      );
}
