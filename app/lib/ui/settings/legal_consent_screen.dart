/// Re-consent gate — shown when the privacy policy or terms have changed since
/// the user last accepted them. Blocks the app until they accept the current
/// version, the same as first-run onboarding does, because continuing to use the
/// app under changed terms without a fresh acceptance is exactly what consent
/// versioning exists to prevent.
///
/// First-run consent is captured on the onboarding welcome step; this only fires
/// for a returning user after currentLegalVersion is bumped.
library;

import 'package:flutter/material.dart';

import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import 'legal_screen.dart';

class LegalConsentScreen extends StatelessWidget {
  /// Called when the user accepts the updated documents.
  final VoidCallback onAccept;
  const LegalConsentScreen({super.key, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Scaffold(
      backgroundColor: Palette.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Icon(Icons.gavel_rounded, size: 44, color: Palette.violet),
              const SizedBox(height: 20),
              Text(l.t('legal_update_title'),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(l.t('legal_update_body'),
                  style: const TextStyle(fontSize: 15, height: 1.5, color: Palette.textDim)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LegalScreen(doc: LegalDoc.privacy),
                    )),
                    child: Text(l.t('set_privacy')),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LegalScreen(doc: LegalDoc.terms),
                    )),
                    child: Text(l.t('set_terms')),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: onAccept,
                child: Text(l.t('legal_update_accept')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
