/// Blood-pressure calibration sheet — the weekly manual tonometer input. The user
/// enters their cuff reading; the app pairs it with the band's latest PPG reading
/// to compute correction offsets (see AppController.calibrateBp). High-tech light.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

Future<void> showCalibrateBpSheet(BuildContext context, AppController controller) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _CalibrateBody(controller: controller),
    ),
  );
}

class _CalibrateBody extends StatefulWidget {
  final AppController controller;
  const _CalibrateBody({required this.controller});
  @override
  State<_CalibrateBody> createState() => _CalibrateBodyState();
}

class _CalibrateBodyState extends State<_CalibrateBody> {
  final _sysCtl = TextEditingController();
  final _diaCtl = TextEditingController();

  /// Set when the last attempt was refused as implausible. Cleared as soon as
  /// she edits a field, so the warning never outlives the numbers it was about.
  bool _rejected = false;

  @override
  void dispose() {
    _sysCtl.dispose();
    _diaCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ppg = widget.controller.latestBp;

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
              child: const Icon(Icons.speed_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(l.t('cal_title'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 12),
          Text(l.t('cal_intro'), style: const TextStyle(color: Palette.textDim, fontSize: 13.5, height: 1.35)),
          const SizedBox(height: 18),

          if (ppg == null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Palette.watch.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 18, color: Palette.watch),
                const SizedBox(width: 10),
                Expanded(child: Text(l.t('cal_no_band'), style: const TextStyle(fontSize: 13))),
              ]),
            )
          else ...[
            // Band reference
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: Palette.glass, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(Icons.watch, size: 18, color: Palette.textDim),
                const SizedBox(width: 10),
                Text(l.t('cal_band_reading', {'sys': ppg.systolic, 'dia': ppg.diastolic}),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: TextField(
                controller: _sysCtl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _rejected = false),
                decoration: InputDecoration(labelText: l.t('cal_cuff_sys')),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: _diaCtl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _rejected = false),
                decoration: InputDecoration(labelText: l.t('cal_cuff_dia')),
              )),
            ]),
            if (_rejected) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Palette.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline_rounded, size: 20, color: Palette.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l.t('cal_too_far'),
                        style: const TextStyle(color: Palette.danger, height: 1.35)),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _valid(ppg) ? () => _save(ppg) : null,
              child: Text(l.t('cal_title')),
            ),
          ],
        ],
      ),
    );
  }

  bool _valid(({int systolic, int diastolic}) ppg) {
    final s = int.tryParse(_sysCtl.text.trim());
    final d = int.tryParse(_diaCtl.text.trim());
    return s != null && d != null && s >= 60 && s <= 260 && d >= 30 && d < s;
  }

  void _save(({int systolic, int diastolic}) ppg) {
    final saved = widget.controller.calibrateBp(
      cuffSystolic: int.parse(_sysCtl.text.trim()),
      cuffDiastolic: int.parse(_diaCtl.text.trim()),
      ppgSystolic: ppg.systolic,
      ppgDiastolic: ppg.diastolic,
    );
    if (!saved) {
      // Nothing was stored. Say so and keep the sheet open with her numbers
      // still in it, so a mis-typed digit is one correction away — closing
      // silently would look like it worked.
      setState(() => _rejected = true);
      return;
    }
    Navigator.pop(context);
  }
}
