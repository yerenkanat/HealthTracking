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

import '../../domain/support_context.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';

const _appVersion = '0.1.0';

class HelpSupportScreen extends StatelessWidget {
  /// Optional diagnostic line (locale, platform…) for the message body.
  final String diagnostics;

  /// What the app can say about itself, so the operator does not have to ask.
  final SupportContext? context_;

  /// Opens WhatsApp with the composed message. Null when no number is
  /// configured — the row then says so rather than opening nothing.
  final void Function(String message)? onWrite;

  /// Self-service actions this build can actually perform. An entry with no
  /// handler is omitted: a dead one teaches her none of them work.
  final Map<SupportAction, VoidCallback> actions;

  /// Opens screen 43 — the in-app thread with the operator. Null when this
  /// build cannot reach the server, in which case the row is not drawn at all
  /// rather than opening a screen that can only fail.
  final VoidCallback? onOpenThread;

  /// How many of her tickets the desk has ANSWERED and is waiting on her.
  ///
  /// Not "unread" — nothing records what she has read, and a count that
  /// pretended to would be wrong the second time she opened the screen. This
  /// is `status = 'waiting'`, which is the server's own statement that there is
  /// an answer sitting there for her.
  final int answeredCount;

  const HelpSupportScreen({
    super.key,
    this.diagnostics = '',
    this.context_,
    this.onWrite,
    this.actions = const {},
    this.onOpenThread,
    this.answeredCount = 0,
  });



  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final faq = ['q1', 'q2', 'q3', 'q4'];

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar:
          AppBar(backgroundColor: Palette.bg, title: Text(l.t('help_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _SectionLabel(l.t('help_faq')),
          for (final q in faq)
            _FaqTile(question: l.t('help_${q}_q'), answer: l.t('help_${q}_a')),
          const SizedBox(height: 20),
          // What she can try herself, before writing to anybody. Only the
          // actions this build can actually perform — a dead row would teach
          // her that none of them work.
          if (actions.isNotEmpty) ...[
            _SectionLabel(l.t('sup_self_help')),
            for (final e in actions.entries)
              _ActionRow(
                icon: Icons.auto_fix_high_rounded,
                title: l.t(e.key.titleKey),
                subtitle: l.t(e.key.bodyKey),
                onTap: e.value,
              ),
            const SizedBox(height: 20),
          ],
          _SectionLabel(l.t('help_contact_section')),
          // ABOVE WhatsApp on purpose. This is the only channel where the
          // answer comes back into the app and where the operator can already
          // see her account, her order and her app version — and it is the only
          // one that works when she has no WhatsApp. The badge is the server
          // saying there is an answer waiting, which is the whole reason the
          // row is worth looking at.
          if (onOpenThread != null)
            _ActionRow(
              icon: Icons.forum_outlined,
              title: l.t('sup_chat_title'),
              subtitle: answeredCount > 0
                  ? l.t('sup_chat_row_waiting', {'n': '$answeredCount'})
                  : l.t('sup_chat_row_none'),
              badge: answeredCount > 0 ? '$answeredCount' : null,
              onTap: onOpenThread,
            ),
          // WhatsApp, not e-mail. This row pointed at support@umay.app — a
          // placeholder on the RETIRED brand — so every message anybody sent
          // from here went to an address nobody owns, while the shop, the
          // course and the order screen all correctly send people to WhatsApp.
          _ActionRow(
            icon: Icons.chat_bubble_outline_rounded,
            title: l.t('sup_write'),
            subtitle:
                onWrite == null ? l.t('sup_unavailable') : l.t('sup_hours'),
            onTap: onWrite == null
                ? null
                : () => onWrite!(
                      (context_ ??
                              const SupportContext(appVersion: _appVersion))
                          .message(''),
                    ),
          ),
          _ActionRow(
            icon: Icons.ios_share_rounded,
            title: l.t('help_share'),
            subtitle: l.t('help_share_sub'),
            onTap: () => SharePlus.instance
                .share(ShareParams(text: l.t('help_share_text'))),
          ),
          const SizedBox(height: 20),
          // Safety reminder — support is not an emergency channel.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Palette.rose.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
            ),
            child: Row(children: [
              const Icon(Icons.emergency_outlined,
                  size: 18, color: Palette.roseDeep),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(l.t('help_emergency_note'),
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.45, color: Palette.text))),
            ]),
          ),
          const SizedBox(height: 16),
          Center(
              child: Text(l.t('help_app_line', {'v': _appVersion}),
                  style:
                      const TextStyle(color: Palette.textDim, fontSize: 12))),
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
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: Palette.textDim)),
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
          border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            shape: const Border(),
            title: Text(question,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(answer,
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.5, color: Palette.textDim)),
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

  /// Null disables the row. Used when no support number is configured, so the
  /// contact line reads as unavailable rather than looking live and doing
  /// nothing.
  final VoidCallback? onTap;

  /// A count worth interrupting her for — an answer she has not seen. Null
  /// draws no badge at all rather than a zero.
  final String? badge;

  const _ActionRow(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.badge});
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
                  border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
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
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12.5, color: Palette.textDim)),
                  ],
                ),
              ),
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Ds.mintCta,
                    borderRadius: BorderRadius.circular(DsShape.radiusPill),
                  ),
                  // Mint, not the coral: an answer from support is good news,
                  // and red in this app means SOS.
                  child: Text(badge!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
            ]),
          ),
        ),
      );
}
