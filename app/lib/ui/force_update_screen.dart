/// The force-update gate — a full-screen block shown when this build is below
/// the server's minimum (AppController.mustUpdate). It has no way back into the
/// app on purpose: a build the server has retired may be talking to an API it no
/// longer matches, or be missing a fix on the safety path, so it must not run.
///
/// The only action is "Update", which opens the store listing.
///
/// This was left unwired on the reasoning that no listing existed yet and a
/// dead link is worse than none — which had it backwards. The screen appears
/// only when the SERVER declares this build retired, and the server can only
/// say that once a newer build is published; by the time anybody sees this, the
/// listing exists. Meanwhile the reasoning shipped a full-screen block with no
/// way back into the app and no way forward either, which is the one state this
/// screen must never be in.
///
/// [onUpdate] stays injectable so a test can drive it without a plugin.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n_scope.dart';
import 'ds_widgets.dart';
import 'theme.dart';

/// The Play listing, derived from the applicationId in build.gradle.kts. Not a
/// guess: this is the canonical form, and it resolves in a browser as well as
/// in the Play app.
const playListingUrl =
    'https://play.google.com/store/apps/details?id=com.fcs.fcs_app';

class ForceUpdateScreen extends StatelessWidget {
  /// Opens the store listing. Defaults to the Play listing; a test injects its
  /// own so nothing has to leave the process.
  final VoidCallback? onUpdate;
  const ForceUpdateScreen({super.key, this.onUpdate});

  static Future<void> _openStore() async {
    // externalApplication so Play opens in the Play app rather than a webview
    // inside the build we are trying to get her off.
    await launchUrl(Uri.parse(playListingUrl),
        mode: LaunchMode.externalApplication);
  }

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
                const SizedBox(height: 28),
                // Was a violet 14px-radius button with its own padding and text
                // style — three overrides that predate the design system and
                // left the app's most blocking screen looking like a different
                // product. It is the only action here, so it is the primary
                // CTA: coral pill, ink outline, hard step.
                DsPrimaryButton(
                    label: l.t('upd_cta'), onPressed: onUpdate ?? _openStore),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
