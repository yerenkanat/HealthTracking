/// Help & Support — the surface a real app needs and this one was missing: a
/// short FAQ, a way to contact support, a "report a problem" path (which carries
/// a little diagnostic context in the email body), and share-the-app. All
/// offline-friendly: e-mail via the system mail app, share via the OS sheet.
///
/// No external keys. The support address is a placeholder until a real inbox
/// exists — clearly a draft, like the legal copy.
library;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n_scope.dart';
import '../theme.dart';

const _supportEmail = 'support@umay.app'; // placeholder until a real inbox exists
const _appVersion = '0.1.0';

class HelpSupportScreen extends StatelessWidget {
  /// Optional diagnostic line (locale, platform…) appended to a problem report.
  final String diagnostics;
  const HelpSupportScreen({super.key, this.diagnostics = ''});

  Future<void> _mailto(String subject, {String body = ''}) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: _encodeQuery({'subject': subject, if (body.isNotEmpty) 'body': body}),
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // Uri(queryParameters:) encodes spaces as '+', which some mail apps show
  // literally; encode manually with %20 instead.
  static String _encodeQuery(Map<String, String> params) => params.entries
      .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final faq = ['q1', 'q2', 'q3', 'q4'];

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('help_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _SectionLabel(l.t('help_faq')),
          for (final q in faq)
            _FaqTile(question: l.t('help_${q}_q'), answer: l.t('help_${q}_a')),
          const SizedBox(height: 20),
          _SectionLabel(l.t('help_contact_section')),
          _ActionRow(
            icon: Icons.mail_outline_rounded,
            title: l.t('help_contact'),
            subtitle: _supportEmail,
            onTap: () => _mailto(l.t('help_email_subject')),
          ),
          _ActionRow(
            icon: Icons.bug_report_outlined,
            title: l.t('help_report'),
            subtitle: l.t('help_report_sub'),
            onTap: () => _mailto(
              l.t('help_report_subject'),
              body: '\n\n—\n${l.t('help_report_diag')}: app $_appVersion${diagnostics.isEmpty ? '' : ', $diagnostics'}',
            ),
          ),
          _ActionRow(
            icon: Icons.ios_share_rounded,
            title: l.t('help_share'),
            subtitle: l.t('help_share_sub'),
            onTap: () => SharePlus.instance.share(ShareParams(text: l.t('help_share_text'))),
          ),
          const SizedBox(height: 20),
          // Safety reminder — support is not an emergency channel.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Palette.rose.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Palette.rose.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.emergency_outlined, size: 18, color: Palette.roseDeep),
              const SizedBox(width: 10),
              Expanded(child: Text(l.t('help_emergency_note'),
                  style: const TextStyle(fontSize: 12.5, height: 1.45, color: Palette.text))),
            ]),
          ),
          const SizedBox(height: 16),
          Center(child: Text(l.t('help_app_line', {'v': _appVersion}),
              style: const TextStyle(color: Palette.textDim, fontSize: 12))),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Palette.textDim)),
      );
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.border),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            shape: const Border(),
            title: Text(question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(answer, style: const TextStyle(fontSize: 13.5, height: 1.5, color: Palette.textDim)),
              ),
            ],
          ),
        ),
      );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionRow({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Palette.violet.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: Palette.violet),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12.5, color: Palette.textDim)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
            ]),
          ),
        ),
      );
}
