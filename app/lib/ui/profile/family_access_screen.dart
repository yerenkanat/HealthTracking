/// Screen 40 — «Семейный доступ».
///
/// «список близких с уровнем доступа → карточка приглашения со ссылкой (24 ч,
/// одноразовая) → зелёная плашка «здоровье и цикл не видит никто» →
/// «Пригласить».»
///
/// A father, a grandmother and an aunt all want to know the child got to
/// school. None of them is entitled to the mother's blood pressure, her cycle
/// or her diary — and the green banner says so.
///
/// The banner is drawn from what the SERVER says it will share, not from a
/// sentence typed here. If the server ever started sharing something of hers,
/// the banner would stop appearing rather than keep making a promise that had
/// stopped being true.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/family_access.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../widgets/confirm.dart';

/// Makes a link. Returns the token — shown once, never recoverable.
typedef InviteCreator = Future<String?> Function(AccessLevel level, String label);

class FamilyAccessScreen extends StatefulWidget {
  final Future<FamilyAccess> Function() load;
  final InviteCreator onInvite;
  final Future<bool> Function(FamilyMember) onRemove;
  final Future<bool> Function(FamilyInvite) onRevoke;

  /// Turns a raw token into the link that gets sent. Injected so the screen
  /// does not have to know the deep-link scheme.
  final String Function(String token) linkFor;

  /// Accepting a code somebody sent you. Returns the server's verdict — the
  /// refusal reason matters, because an expired link and a used one need
  /// different words.
  final Future<({bool ok, String? reason})> Function(String token)? onAccept;

  final DateTime now;

  const FamilyAccessScreen({
    super.key,
    required this.load,
    required this.onInvite,
    required this.onRemove,
    required this.onRevoke,
    required this.linkFor,
    required this.now,
    this.onAccept,
  });

  @override
  State<FamilyAccessScreen> createState() => _FamilyAccessScreenState();
}

class _FamilyAccessScreenState extends State<FamilyAccessScreen> {
  FamilyAccess? _data;
  bool _loading = true;
  bool _failed = false;

  /// The token just created, held only until she leaves the screen. The server
  /// keeps a hash and cannot give it back, so this is the one chance to copy.
  String? _freshToken;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
        _data = null;
      });
    }
  }

  Future<void> _invite() async {
    final choice = await showModalBottomSheet<({AccessLevel level, String label})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _InviteSheet(),
    );
    if (choice == null) return;
    final token = await widget.onInvite(choice.level, choice.label);
    if (!mounted) return;
    if (token == null) {
      // Said out loud. A silent failure here leaves her waiting for a link
      // that was never made.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L10nScope.of(context).t('fam_invite_failed')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _freshToken = token);
    await _reload();
  }

  Future<void> _acceptCode() async {
    final l = L10nScope.of(context);
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _AcceptDialog(),
    );
    if (code == null || code.isEmpty || !mounted) return;
    final r = await widget.onAccept!(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      // Each refusal has its own words: an expired link needs a new one, a
      // used one probably means somebody else already joined. «Не получилось»
      // for all of them helps nobody.
      content: Text(r.ok ? l.t('fam_accepted') : l.t(inviteRefusalKey(r.reason))),
      behavior: SnackBarBehavior.floating,
    ));
    if (r.ok) await _reload();
  }

  Future<void> _remove(FamilyMember m) async {
    final l = L10nScope.of(context);
    final ok = await confirmDestructive(
      context,
      title: l.t('fam_remove_confirm', {'name': m.title}),
      message: l.t('fam_remove_body'),
      confirmLabel: l.t('fam_remove'),
    );
    if (!ok || !mounted) return;
    final done = await widget.onRemove(m);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(done ? l.t('fam_removed') : l.t('fam_failed')),
      behavior: SnackBarBehavior.floating,
    ));
    if (done) await _reload();
  }

  Future<void> _revoke(FamilyInvite i) async {
    final l = L10nScope.of(context);
    final ok = await confirmDestructive(
      context,
      title: l.t('fam_revoke_confirm'),
      message: l.t('fam_revoke_body'),
      confirmLabel: l.t('fam_revoke'),
    );
    if (!ok || !mounted) return;
    final done = await widget.onRevoke(i);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(done ? l.t('fam_revoked') : l.t('fam_failed')),
      behavior: SnackBarBehavior.floating,
    ));
    if (done) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final d = _data;

    return Scaffold(
      backgroundColor: Ds.cream,
      appBar: AppBar(title: Text(l.t('fam_title'))),
      floatingActionButton: _loading || _failed
          ? null
          : FloatingActionButton.extended(
              onPressed: _invite,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(l.t('fam_invite')),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed || d == null)
            _FailureCard(onRetry: _reload)
          else ...[
            if (_freshToken != null) ...[
              _FreshLinkCard(
                link: widget.linkFor(_freshToken!),
                onDone: () => setState(() => _freshToken = null),
              ),
              const SizedBox(height: 18),
            ],

            Text(l.t('fam_who'),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
            const SizedBox(height: 10),
            if (d.members.isEmpty)
              _EmptyCard(
                title: l.t('fam_nobody'),
                body: l.t('fam_nobody_why'),
              )
            else
              for (final m in d.members)
                _MemberRow(member: m, onRemove: () => _remove(m)),

            if (d.invites.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(l.t('fam_open_invites'),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
              const SizedBox(height: 10),
              for (final i in d.invites)
                _InviteRow(
                  invite: i,
                  now: widget.now,
                  onRevoke: () => _revoke(i),
                ),
            ],

            if (d.memberships.isNotEmpty) ...[
              const SizedBox(height: 22),
              _EmptyCard(
                title: l.t('fam_i_see'),
                body: l.t('fam_i_see_body', {'n': d.memberships.length}),
              ),
            ],

            // The other side of the feature. Without it a father who was sent
            // a link has nowhere to put the code, and the whole invitation
            // path dead-ends in his hand.
            if (widget.onAccept != null) ...[
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: _acceptCode,
                icon: const Icon(Icons.link_rounded),
                label: Text(l.t('fam_have_code')),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(DsShape.minTapTarget),
                ),
              ),
            ],

            const SizedBox(height: 22),
            // Shown only while it is TRUE of the server. A promise that has
            // stopped holding must stop being made.
            if (d.sharesOnlyChildData) const _PrivacyBanner(),
          ],
        ],
      ),
    );
  }
}

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner();

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Ds.pastelMint,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_rounded, color: Ds.mintText, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('fam_privacy'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Ds.mintText)),
                const SizedBox(height: 6),
                Text(l.t('fam_privacy_body'),
                    style: const TextStyle(
                        fontSize: 13, height: 1.4, color: Ds.mintText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The link, once. It cannot be shown again.
class _FreshLinkCard extends StatelessWidget {
  final String link;
  final VoidCallback onDone;
  const _FreshLinkCard({required this.link, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Ds.pastelButter,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l.t('fam_invite_ready'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: Ds.text)),
              ),
              IconButton(
                onPressed: onDone,
                icon: const Icon(Icons.close_rounded),
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
              ),
            ],
          ),
          Text(l.t('fam_invite_once', {'n': 24}),
              style: const TextStyle(
                  fontSize: 13, height: 1.4, color: Ds.textSecondary)),
          const SizedBox(height: 12),
          SelectableText(
            link,
            style: const TextStyle(fontSize: 12.5, color: Ds.text),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: DsShape.minTapTarget,
            child: FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(l.t('fam_copied')),
                  behavior: SnackBarBehavior.floating,
                ));
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text(l.t('fam_copy')),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final FamilyMember member;
  final VoidCallback onRemove;
  const _MemberRow({required this.member, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: Ds.text)),
                const SizedBox(height: 3),
                Text(l.t(member.level.l10nKey),
                    style: const TextStyle(fontSize: 12.5, color: Ds.textSecondary)),
              ],
            ),
          ),
          TextButton(
            onPressed: onRemove,
            style: TextButton.styleFrom(foregroundColor: Ds.coralText),
            child: Text(l.t('fam_remove')),
          ),
        ],
      ),
    );
  }
}

class _InviteRow extends StatelessWidget {
  final FamilyInvite invite;
  final DateTime now;
  final VoidCallback onRevoke;
  const _InviteRow({required this.invite, required this.now, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.label.trim().isEmpty
                      ? l.t(invite.level.l10nKey)
                      : invite.label.trim(),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: Ds.text),
                ),
                const SizedBox(height: 3),
                Text(l.t('fam_expires_in', {'n': invite.hoursLeft(now)}),
                    style: const TextStyle(fontSize: 12.5, color: Ds.textSecondary)),
              ],
            ),
          ),
          TextButton(
            onPressed: onRevoke,
            style: TextButton.styleFrom(foregroundColor: Ds.coralText),
            child: Text(l.t('fam_revoke')),
          ),
        ],
      ),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet();

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  AccessLevel _level = AccessLevel.viewer;
  final _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('fam_invite'),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: Ds.text)),
          const SizedBox(height: 14),
          TextField(
            controller: _label,
            decoration: InputDecoration(labelText: l.t('fam_invite_label')),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 18),
          // Each level says what it MEANS. «Viewer / Guardian» alone asks her
          // to guess, about a decision she cannot check afterwards.
          RadioGroup<AccessLevel>(
            groupValue: _level,
            onChanged: (v) => setState(() => _level = v ?? _level),
            child: Column(
              children: [
                for (final level in AccessLevel.values)
                  RadioListTile<AccessLevel>(
                    value: level,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.t(level.l10nKey),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: Ds.text)),
                    subtitle: Text(l.t(level.descriptionKey),
                        style: const TextStyle(
                            fontSize: 12.5, color: Ds.textSecondary)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: DsShape.minTapTarget,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                  context, (level: _level, label: _label.text.trim())),
              child: Text(l.t('fam_invite')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pasting a code from an invitation.
///
/// A dialog rather than a screen: it is three seconds of work and the person
/// doing it has the code on their clipboard already.
class _AcceptDialog extends StatefulWidget {
  const _AcceptDialog();
  @override
  State<_AcceptDialog> createState() => _AcceptDialogState();
}

class _AcceptDialogState extends State<_AcceptDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AlertDialog(
      title: Text(l.t('fam_have_code')),
      content: TextField(
        controller: _code,
        autofocus: true,
        decoration: InputDecoration(labelText: l.t('fam_paste_code')),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.t('act_cancel')),
        ),
        FilledButton(
          // Disabled on an empty field: sending nothing gets a refusal that
          // says the link did not work, which is true and useless.
          onPressed: _code.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _code.text.trim()),
          child: Text(l.t('fam_accept')),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String title;
  final String body;
  const _EmptyCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w700, color: Ds.text)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.4, color: Ds.textSecondary)),
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _FailureCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('fam_failed'),
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: Text(l.t('day_retry'))),
        ],
      ),
    );
  }
}
