/// The soft update nudge — the gentle step between "fine" and "blocked".
///
/// WHY IT IS A STRIP AND NOT A DIALOG
///
/// The app already owns the blocking case: below the server's `minBuild` the
/// force-update screen takes over the whole app and offers no way past it. That
/// is the right shape for "this build must not run". An OPTIONAL update is a
/// different thing entirely, and a modal on launch is the wrong shape for it —
/// a mother opening the app to log a contraction is interrupted by something
/// she cannot act on right now, so she dismisses it without reading, and the
/// next time a launch-time modal appears (the one that matters) she dismisses
/// that too. So: a quiet strip at the top of the shell, in the same slot and
/// the same visual language as the offline strip, present on every tab,
/// closable, and never in the way of anything.
///
/// It is deliberately terse. `upd_body` ("This version of Ana-Bala is no longer
/// supported…") is the HARD block's copy and would be a lie here; the title and
/// the CTA are true of both, so the strip uses those and nothing else.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n_scope.dart';
import '../force_update_screen.dart' show playListingUrl;
import '../theme.dart';

class UpdateNudgeStrip extends StatelessWidget {
  /// Closes the strip. Snoozes rather than hides: see
  /// AppController.dismissUpdateNudge.
  final VoidCallback onDismiss;

  /// Opens the store listing. Defaults to the same Play listing the force-update
  /// screen opens — derived from the applicationId in build.gradle.kts, so this
  /// CTA can only ever go where a real listing is. Injectable so a test does not
  /// have to leave the process.
  final VoidCallback? onUpdate;

  const UpdateNudgeStrip({super.key, required this.onDismiss, this.onUpdate});

  static Future<void> _openStore() async {
    await launchUrl(Uri.parse(playListingUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Material(
      color: Palette.blue.withValues(alpha: 0.12),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
          child: Row(children: [
            const Icon(Icons.system_update_rounded, size: 16, color: Palette.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.t('upd_title'),
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: Palette.text),
              ),
            ),
            TextButton(
              onPressed: onUpdate ?? _openStore,
              style: TextButton.styleFrom(
                foregroundColor: Palette.blue,
                minimumSize: const Size(48, 40),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(l.t('upd_cta'),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: l.t('act_close'),
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: const Icon(Icons.close_rounded, color: Palette.textDim),
            ),
          ]),
        ),
      ),
    );
  }
}
