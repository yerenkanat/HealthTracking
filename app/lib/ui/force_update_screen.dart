/// The force-update gate — a full-screen block shown when this build is below
/// the server's minimum (AppController.mustUpdate). It has no way back into the
/// app on purpose: a build the server has retired may be talking to an API it no
/// longer matches, or be missing a fix on the safety path, so it must not run.
///
/// The only action is "Update", which opens the store listing. There is no store
/// URL yet (no published listing), so [onUpdate] is optional — without it the
/// button is hidden and the message stands on its own rather than sending her to
/// a dead link.
library;

import 'package:flutter/material.dart';

import '../l10n/l10n_scope.dart';
import 'theme.dart';

class ForceUpdateScreen extends StatelessWidget {
  /// Opens the store listing. Null hides the button (no listing wired yet).
  final VoidCallback? onUpdate;
  const ForceUpdateScreen({super.key, this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Scaffold(
      backgroundColor: Palette.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Palette.violet.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.system_update_rounded, size: 44, color: Palette.violet),
                ),
                const SizedBox(height: 24),
                Text(l.t('upd_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(l.t('upd_body'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14.5, height: 1.5, color: Palette.textDim)),
                if (onUpdate != null) ...[
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onUpdate,
                      style: FilledButton.styleFrom(
                        backgroundColor: Palette.violet,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(l.t('upd_cta'),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
