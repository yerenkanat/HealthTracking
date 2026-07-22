/// Privacy Policy and Terms of Use.
///
/// An app that holds a woman's reproductive history and a child's name, date of
/// birth and home/school coordinates cannot ship without telling her, in plain
/// language, what it keeps and what it does with it — and a store listing will
/// not accept it without these screens either.
///
/// The copy here is an HONEST summary of what the app actually does today
/// (local-first storage, export/erase controls, the not-a-medical-device
/// boundary), carried in ru/kk/en like the rest of the app. It is marked as a
/// DRAFT pending legal/clinical review — the wording is real but not yet
/// lawyer-approved, and the banner says so rather than pretending otherwise.
library;

import 'package:flutter/material.dart';

import '../../l10n/l10n_scope.dart';
import '../theme.dart';

enum LegalDoc { privacy, terms }

class LegalScreen extends StatelessWidget {
  final LegalDoc doc;
  const LegalScreen({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final isPrivacy = doc == LegalDoc.privacy;

    final sections = isPrivacy
        ? const [
            ('legal_priv_collect_h', 'legal_priv_collect_b'),
            ('legal_priv_storage_h', 'legal_priv_storage_b'),
            ('legal_priv_cloud_h', 'legal_priv_cloud_b'),
            ('legal_priv_medical_h', 'legal_priv_medical_b'),
            ('legal_priv_controls_h', 'legal_priv_controls_b'),
            ('legal_priv_contact_h', 'legal_priv_contact_b'),
          ]
        : const [
            ('legal_terms_use_h', 'legal_terms_use_b'),
            ('legal_terms_medical_h', 'legal_terms_medical_b'),
            ('legal_terms_emergency_h', 'legal_terms_emergency_b'),
            ('legal_terms_responsib_h', 'legal_terms_responsib_b'),
            ('legal_terms_warranty_h', 'legal_terms_warranty_b'),
            ('legal_terms_law_h', 'legal_terms_law_b'),
          ];

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        title: Text(l.t(isPrivacy ? 'legal_privacy_title' : 'legal_terms_title')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _DraftBanner(text: l.t('legal_draft_note')),
          const SizedBox(height: 6),
          Text(l.t('legal_updated'),
              style: const TextStyle(color: Palette.textDim, fontSize: 12, fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
          for (final (h, b) in sections) _LegalSection(title: l.t(h), body: l.t(b)),
        ],
      ),
    );
  }
}

class _DraftBanner extends StatelessWidget {
  final String text;
  const _DraftBanner({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Palette.amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.amber.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.gavel_rounded, size: 16, color: Palette.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 12.5, height: 1.45, color: Palette.text)),
            ),
          ],
        ),
      );
}

class _LegalSection extends StatelessWidget {
  final String title;
  final String body;
  const _LegalSection({required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(body,
                style: const TextStyle(fontSize: 13.5, height: 1.5, color: Palette.textDim)),
          ],
        ),
      );
}
