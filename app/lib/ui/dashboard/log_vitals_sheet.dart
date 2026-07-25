/// Hand-entered vitals sheet — for users measuring with a cuff, thermometer or
/// oximeter rather than a paired band. Every field is optional; validation is
/// the pure [manual_vitals] domain, and the saved reading is triaged exactly
/// like band telemetry.
///
/// A photo shortcut sits on top: snap the device's display (or a lab slip) and
/// the server's vision model reads the numbers into the fields, which the user
/// then checks and saves through the same path. It appears only when an
/// [onScan] is supplied (i.e. the app is online with an API client).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:image_picker/image_picker.dart';
import '../../data/api_client.dart' show ExtractedReading;
import '../../domain/manual_vitals.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

/// Reads vitals off a photo. Returns what could be read (fields may be null), or
/// null on failure. Injected so the sheet stays free of the network + ApiClient.
typedef VitalsScanner = Future<ExtractedReading?> Function(List<int> bytes, String mediaType);

/// Returns the entered reading, or null if cancelled.
Future<ManualVitals?> showLogVitalsSheet(BuildContext context, {VitalsScanner? onScan}) {
  return showModalBottomSheet<ManualVitals>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _LogVitalsSheet(onScan: onScan),
  );
}

enum _ScanState { idle, busy, filled, empty, error }

class _LogVitalsSheet extends StatefulWidget {
  final VitalsScanner? onScan;
  const _LogVitalsSheet({this.onScan});
  @override
  State<_LogVitalsSheet> createState() => _LogVitalsSheetState();
}

class _LogVitalsSheetState extends State<_LogVitalsSheet> {
  final _hr = TextEditingController();
  final _spo2 = TextEditingController();
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _temp = TextEditingController();
  final _glucose = TextEditingController();

  _ScanState _scan = _ScanState.idle;
  String? _scanNote;

  @override
  void dispose() {
    for (final c in [_hr, _spo2, _sys, _dia, _temp, _glucose]) {
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
        glucose: double.tryParse(_glucose.text.trim().replaceAll(',', '.')),
      );

  Future<void> _startScan() async {
    final l = L10nScope.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 6),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded, color: Palette.violet),
            title: Text(l.t('vitals_scan_camera')),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: Palette.violet),
            title: Text(l.t('vitals_scan_gallery')),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    await _pickAndScan(source);
  }

  Future<void> _pickAndScan(ImageSource source) async {
    final scan = widget.onScan;
    if (scan == null) return;
    final XFile? file;
    try {
      // Downscale + recompress before upload: a full-res phone photo is several
      // MB, and the display digits read just as well at 1600px — smaller upload,
      // faster and cheaper extraction.
      file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 72);
    } catch (_) {
      if (mounted) setState(() => _scan = _ScanState.error); // no camera / permission denied
      return;
    }
    if (file == null || !mounted) return; // cancelled
    setState(() {
      _scan = _ScanState.busy;
      _scanNote = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final reading = await scan(bytes, _mediaTypeFor(file.name));
      if (!mounted) return;
      if (reading == null || reading.isEmpty) {
        setState(() {
          _scan = _ScanState.empty;
          _scanNote = reading?.note;
        });
        return;
      }
      _apply(reading);
      setState(() {
        _scan = _ScanState.filled;
        _scanNote = reading.note;
      });
    } catch (_) {
      if (mounted) setState(() => _scan = _ScanState.error);
    }
  }

  void _apply(ExtractedReading r) {
    void put(TextEditingController c, num? v) {
      if (v != null) c.text = '$v';
    }
    put(_sys, r.systolic);
    put(_dia, r.diastolic);
    put(_hr, r.heartRate);
    put(_spo2, r.spo2);
    put(_temp, r.temperature);
    put(_glucose, r.glucose);
  }

  static String _mediaTypeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

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
            if (widget.onScan != null) ...[
              _ScanCard(state: _scan, note: _scanNote, onTap: _scan == _ScanState.busy ? null : _startScan),
              const SizedBox(height: 14),
            ],
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
            Row(children: [
              Expanded(child: _Field(controller: _temp, label: l.t('vitals_temp'), decimal: true, onChanged: _rebuild)),
              const SizedBox(width: 10),
              Expanded(child: _Field(controller: _glucose, label: l.t('vitals_glucose'), decimal: true, onChanged: _rebuild)),
            ]),
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

/// The photo shortcut: a tappable card that reflects its own progress — idle
/// prompt, a spinner while reading, and a coloured status line afterwards.
class _ScanCard extends StatelessWidget {
  final _ScanState state;
  final String? note;
  final VoidCallback? onTap;
  const _ScanCard({required this.state, required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final busy = state == _ScanState.busy;

    (Color, String)? status() {
      switch (state) {
        case _ScanState.filled:
          return (Palette.violet, note?.isNotEmpty == true ? '${l.t('vitals_scan_filled')} · $note' : l.t('vitals_scan_filled'));
        case _ScanState.empty:
          return (Palette.textDim, l.t('vitals_scan_none'));
        case _ScanState.error:
          return (Palette.danger, l.t('vitals_scan_error'));
        case _ScanState.idle:
        case _ScanState.busy:
          return null;
      }
    }

    final s = status();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Palette.violet.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Palette.violet.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Palette.violet))
                    : const Icon(Icons.photo_camera_rounded, color: Palette.violet, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(busy ? l.t('vitals_scanning') : l.t('vitals_scan_cta'),
                        style: const TextStyle(color: Palette.text, fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(l.t('vitals_scan_hint'), style: const TextStyle(color: Palette.textDim, fontSize: 12, height: 1.25)),
                  ]),
                ),
                if (!busy) const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
              ]),
            ),
          ),
        ),
        if (s != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(state == _ScanState.filled ? Icons.check_circle_rounded : Icons.info_outline_rounded, size: 15, color: s.$1),
            const SizedBox(width: 7),
            Expanded(child: Text(s.$2, style: TextStyle(color: s.$1, fontSize: 12.5, height: 1.3))),
          ]),
        ],
      ],
    );
  }
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
