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
