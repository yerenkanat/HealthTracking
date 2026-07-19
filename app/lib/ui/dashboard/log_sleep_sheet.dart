/// Hand-entered sleep sheet — for users without a band, or nights the band
/// missed. Times are picked rather than typed, because bedtime and wake time
/// are clock values, not numbers. Validation is the pure [manual_sleep] domain.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import '../../domain/manual_sleep.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

/// Returns the entered night, or null if cancelled.
Future<SleepEntry?> showLogSleepSheet(BuildContext context, {required DateTime now}) {
  return showModalBottomSheet<SleepEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _LogSleepSheet(now: now),
  );
}

class _LogSleepSheet extends StatefulWidget {
  final DateTime now;
  const _LogSleepSheet({required this.now});
  @override
  State<_LogSleepSheet> createState() => _LogSleepSheetState();
}

class _LogSleepSheetState extends State<_LogSleepSheet> {
  // Defaults describe an ordinary night, so most users only adjust one field.
  TimeOfDay _bed = const TimeOfDay(hour: 23, minute: 0);
  TimeOfDay _woke = const TimeOfDay(hour: 7, minute: 0);
  final _awake = TextEditingController();

  @override
  void dispose() {
    _awake.dispose();
    super.dispose();
  }

  /// Build the entry from two clock times. A night normally crosses midnight,
  /// so a wake time at or before the bedtime belongs to the following day —
  /// without this, every ordinary night would come out negative.
  SleepEntry get _entry {
    final n = widget.now;
    final bed = DateTime(n.year, n.month, n.day, _bed.hour, _bed.minute);
    var woke = DateTime(n.year, n.month, n.day, _woke.hour, _woke.minute);
    if (!woke.isAfter(bed)) woke = woke.add(const Duration(days: 1));
    return SleepEntry(bedAt: bed, wokeAt: woke, awakeMin: int.tryParse(_awake.text.trim()) ?? 0);
  }

  Future<void> _pick(bool bedtime) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: bedtime ? _bed : _woke,
    );
    if (picked == null || !mounted) return;
    setState(() => bedtime ? _bed = picked : _woke = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final entry = _entry;
    final error = validateSleepEntry(entry);
    final valid = error == null;

    String errorText() => switch (error) {
          SleepEntryError.tooLong => l.t('sleep_err_too_long'),
          SleepEntryError.awakeExceedsInBed => l.t('sleep_err_awake'),
          SleepEntryError.noSleep => l.t('sleep_err_no_sleep'),
          _ => l.t('sleep_err_empty'),
        };

    final h = entry.asleepMin ~/ 60, m = entry.asleepMin % 60;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('sleep_log_title'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Palette.text)),
            const SizedBox(height: 4),
            Text(l.t('sleep_log_sub'),
                style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.3)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _TimeField(label: l.t('sleep_bedtime'), value: _bed, onTap: () => _pick(true))),
              const SizedBox(width: 10),
              Expanded(child: _TimeField(label: l.t('sleep_woke'), value: _woke, onTap: () => _pick(false))),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _awake,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
              decoration: InputDecoration(
                labelText: l.t('sleep_awake_min'),
                helperText: l.t('sleep_awake_hint'),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            if (valid)
              Row(children: [
                const Icon(Icons.bedtime_rounded, size: 16, color: Palette.violet),
                const SizedBox(width: 8),
                Text(l.t('sleep_total', {'h': '$h', 'm': '$m'}),
                    style: const TextStyle(color: Palette.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
              ])
            else
              Row(children: [
                const Icon(Icons.error_outline_rounded, size: 16, color: Palette.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(errorText(),
                      style: const TextStyle(color: Palette.danger, fontSize: 12.5, height: 1.3)),
                ),
              ]),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: valid ? () => Navigator.of(context).pop(entry) : null,
                style: FilledButton.styleFrom(
                    backgroundColor: Palette.violet, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(l.t('act_save'),
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable clock value. Sized to the 48dp minimum so it's a comfortable
/// target, and labelled for screen readers since the value alone is ambiguous.
class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay value;
  final VoidCallback onTap;
  const _TimeField({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = value.format(context);
    return Semantics(
      button: true,
      label: '$label, $text',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          ),
          child: Text(text,
              style: const TextStyle(color: Palette.text, fontSize: 15.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
