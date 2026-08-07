/// "This really is our watch — here is the code on the box."
///
/// The way out of a `device_not_ours` refusal. Until every box has been through
/// Приёмка, most units refused are genuine ones whose serial nobody recorded at
/// intake, so without this the registry check cannot be switched on at all: it
/// would turn away paying customers with nothing to offer them.
///
/// Every failure gets its own sentence. "It did not work" is what makes a
/// customer give up on a device she legitimately owns, and the five answers
/// need five different next steps — re-read the box, call us, or wait an hour.
library;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/device_pairing.dart';
import '../../domain/family.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../ds_widgets.dart';
import '../theme.dart';

Future<void> showClaimDeviceSheet(
  BuildContext context,
  AppController controller, {
  required DeviceKind kind,
  String? childId,
  String? name,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      // Above the keyboard: this sheet is one text field, and a field hidden
      // behind the keyboard is the whole screen not working.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ClaimDeviceSheet(
        controller: controller, kind: kind, childId: childId, name: name,
      ),
    ),
  );
}

class _ClaimDeviceSheet extends StatefulWidget {
  final AppController controller;
  final DeviceKind kind;
  final String? childId;
  final String? name;
  const _ClaimDeviceSheet({
    required this.controller, required this.kind, this.childId, this.name,
  });

  @override
  State<_ClaimDeviceSheet> createState() => _ClaimDeviceSheetState();
}

class _ClaimDeviceSheetState extends State<_ClaimDeviceSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  DeviceClaimResult? _result;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Which sentence to show. Null while nothing has been tried.
  String? _errorKey() => switch (_result) {
        DeviceClaimResult.unknownCode => 'dev_claim_unknown',
        DeviceClaimResult.alreadyClaimed => 'dev_claim_taken',
        DeviceClaimResult.blocked => 'dev_claim_blocked',
        DeviceClaimResult.tooManyAttempts => 'dev_claim_too_many',
        DeviceClaimResult.offline => 'dev_claim_offline',
        _ => null,
      };

  Future<void> _submit() async {
    setState(() { _busy = true; _result = null; });
    final r = await widget.controller.claimDevice(
      _code.text,
      kind: widget.kind,
      childId: widget.childId,
      name: widget.name,
    );
    if (!mounted) return;
    setState(() { _busy = false; _result = r; });
    if (r == DeviceClaimResult.ok) {
      Navigator.of(context).pop();
      final l = L10nScope.of(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.t('dev_claim_ok'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final errorKey = _errorKey();
    return Container(
      decoration: const BoxDecoration(
        color: Palette.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(DsShape.radiusCard)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The same grip the other sheets draw. There is no shared widget for
          // it yet; copying four lines beats inventing a different affordance
          // on the one sheet a confused customer reaches.
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(l.t('dev_claim_title'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          // Says WHERE the code is. A field labelled "code" with no idea where
          // to find one is a dead end with a text box on it.
          Text(l.t('dev_claim_body'),
              style: const TextStyle(color: Palette.textDim, fontSize: 13, height: 1.45)),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            enabled: !_busy,
            onSubmitted: (_) => _busy ? null : _submit(),
            decoration: InputDecoration(
              hintText: l.t('dev_claim_hint'),
              errorText: errorKey == null ? null : l.t(errorKey),
              // Two lines: several of these messages are a sentence, not a word.
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 18),
          DsPrimaryButton(
            label: l.t('dev_claim_action'),
            onPressed: _busy || _code.text.trim().isEmpty ? null : _submit,
          ),
        ],
      ),
    );
  }
}
