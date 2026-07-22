/// Permission priming — a plain-language "why" shown BEFORE the OS permission
/// prompt.
///
/// The OS dialog is a one-shot: deny it and the system remembers "no" for good,
/// after which the only fix is a trip to Settings that most people never make.
/// So the moment before that dialog is the most valuable UI in the app for these
/// features. This sheet explains, in the user's words, exactly why Umay needs
/// the permission and what it will and won't do with it — then hands off to the
/// real OS prompt only if she taps Continue.
///
/// It never grants anything itself; it returns whether to proceed to the OS
/// request. Keep it a thin, reusable layer so every permission gets the same
/// honest, calm treatment.
library;

import 'package:flutter/material.dart';

import '../../l10n/l10n_scope.dart';
import '../theme.dart';

/// The permissions Umay primes for. Each maps to its own icon and copy.
enum PermissionKind {
  location(Icons.location_on_outlined, 'prime_loc_title', 'prime_loc_body'),
  notifications(Icons.notifications_active_outlined, 'prime_notif_title', 'prime_notif_body');

  const PermissionKind(this.icon, this.titleKey, this.bodyKey);
  final IconData icon;
  final String titleKey;
  final String bodyKey;
}

/// Show the primer for [kind]. Resolves true if the user chose to continue to
/// the OS prompt, false if she dismissed or chose "Not now" — in which case the
/// caller must NOT fire the OS request (respecting the soft no keeps the one-shot
/// OS answer for a moment she's actually ready).
Future<bool> showPermissionPrimer(BuildContext context, PermissionKind kind) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PrimerSheet(kind: kind),
  );
  return result ?? false;
}

class _PrimerSheet extends StatelessWidget {
  final PermissionKind kind;
  const _PrimerSheet({required this.kind});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Palette.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Center(
              child: Container(
                width: 66, height: 66,
                decoration: BoxDecoration(
                  color: Palette.violet.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(kind.icon, size: 32, color: Palette.violet),
              ),
            ),
            const SizedBox(height: 18),
            Text(l.t(kind.titleKey),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(l.t(kind.bodyKey),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.5, color: Palette.textDim)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Palette.violet,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(l.t('prime_continue'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.t('prime_not_now'),
                  style: const TextStyle(color: Palette.textDim, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
