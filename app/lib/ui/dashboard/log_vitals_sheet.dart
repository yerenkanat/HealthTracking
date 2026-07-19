/// Hand-entered vitals sheet — for users measuring with a cuff, thermometer or
/// oximeter rather than a paired band. Every field is optional; validation is
/// the pure [manual_vitals] domain, and the saved reading is triaged exactly
/// like band telemetry.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import '../../domain/manual_vitals.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

/// Returns the entered reading, or null if cancelled.
Future<ManualVitals?> showLogVitalsSheet(BuildContext context) {
  return showModalBottomSheet<ManualVitals>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _LogVitalsSheet(),
  );
}

class _LogVitalsSheet extends StatefulWidget {
  const _LogVitalsSheet();
  @override
  State<_LogVitalsSheet> createState() => _LogVitalsSheetState();
}

class _LogVitalsSheetState extends State<_LogVitalsSheet> {
  final _hr = TextEditingController();
  final _spo2 = TextEditingController();
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _temp = TextEditingController();

  @override
  void dispose() {
    for (final c in [_hr, _spo2, _sys, _dia, _temp]) {
      c.dispose();
    }
    super.dispose();
  }

  ManualVitals get _reading => ManualVitals(
        heartRate: int.tryParse(_hr.text.trim()),
        spo2: int.tryParse(_spo2.text.trim()),
        systolic: int.tryParse(_sys.text.trim()),
        diastolic: int.tryParse(_dia.text.trim()),
        temperature: double.tryParse(_temp.text.trim().replaceAll(',', '.')),
      );

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final errors = validateVitals(_reading);
    final valid = errors.isEmpty;
    // Only nag once something's been typed — a blank form isn't an error yet.
    final showError = !_reading.isEmpty && !valid;

    String errorText() {
      if (errors.contains(VitalsError.diastolicNotBelowSystolic)) return l.t('vitals_err_bp_order');
      if (errors.contains(VitalsError.bloodPressurePartial)) return l.t('vitals_err_bp_pair');
      if (errors.contains(VitalsError.outOfRange)) return l.t('vitals_err_range');
      return '';
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('vitals_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Palette.text)),
            const SizedBox(height: 4),
            Text(l.t('vitals_sub'), style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.3)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _Field(controller: _sys, label: l.t('vitals_systolic'), onChanged: _rebuild)),
              const SizedBox(width: 10),
              Expanded(child: _Field(controller: _dia, label: l.t('vitals_diastolic'), onChanged: _rebuild)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Field(controller: _hr, label: l.t('vitals_hr'), onChanged: _rebuild)),
              const SizedBox(width: 10),
              Expanded(child: _Field(controller: _spo2, label: l.t('vitals_spo2'), onChanged: _rebuild)),
            ]),
            const SizedBox(height: 12),
            _Field(controller: _temp, label: l.t('vitals_temp'), decimal: true, onChanged: _rebuild),
            if (showError) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.error_outline_rounded, size: 16, color: Palette.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(errorText(),
                      style: const TextStyle(color: Palette.danger, fontSize: 12.5, height: 1.3)),
                ),
              ]),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: valid ? () => Navigator.of(context).pop(_reading) : null,
                style: FilledButton.styleFrom(backgroundColor: Palette.violet, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(l.t('act_save'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _rebuild() => setState(() {});
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool decimal;
  final VoidCallback onChanged;
  const _Field({required this.controller, required this.label, required this.onChanged, this.decimal = false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]')),
      ],
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      onChanged: (_) => onChanged(),
    );
  }
}
