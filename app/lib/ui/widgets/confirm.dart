/// Confirmation dialog for destructive / irreversible actions. Use this before
/// ANY delete, remove, unpair, or reset so a single mis-tap can never silently
/// lose the user's data. Returns true only when the user explicitly confirms;
/// the confirm button is styled in the danger colour.
library;

import 'package:flutter/material.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final l = L10nScope.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.t('act_cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel,
              style: const TextStyle(color: Palette.danger, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// The same gate, without the danger colour, for a change that is significant
/// but not a deletion.
///
/// Two reasons it is not [confirmDestructive] with a different label. The
/// design doc reserves red — «Красный только SOS», ЧАСТЬ 4 rule 5 — and the
/// first caller is the door a woman uses when a pregnancy has ended, which is
/// the last place in the app to paint an alarm colour. What it keeps is the
/// part that matters: [message] must name what changes and what is kept, so
/// the confirmation is informative rather than a speed bump.
///
/// Callers should still leave an undo behind. A confirmation only proves she
/// tapped twice.
Future<bool> confirmChange(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final l = L10nScope.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.t('act_cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok ?? false;
}
