/// Settings — profile, language, children, devices, about, reset. Premium light
/// grouped-list styling. Reads/writes through the AppController.
library;

import 'package:flutter/material.dart';
import 'dart:io' show File;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/app_controller.dart';
import '../../ble/calibration.dart' show bpCalibrationIsStale;
import '../../domain/backup_file.dart';
import '../../domain/backup_status.dart';
import '../../domain/family.dart';
import '../../domain/reminders.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../calibration/bp_calibration_sheet.dart';
import '../design_system.dart';
import '../ds_widgets.dart';
import '../theme.dart';
import 'journey_screen.dart';
import 'help_support_screen.dart';
import 'legal_screen.dart';
import 'reminders_center_screen.dart';
import '../auth/sign_in_route.dart';
import '../tracking/child_detail_screen.dart';
import '../tracking/family_sheets.dart';
import '../widgets/avatar.dart';
import '../widgets/confirm.dart';

class SettingsScreen extends StatelessWidget {
  final AppController controller;
  const SettingsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final c = controller;

    return Scaffold(
      appBar: AppBar(title: Text(l.t('settings_title'))),
      body: StreamBuilder<void>(
        stream: c.changes,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // ---- Account (phone-OTP sign-in) ----
            _Section(title: l.t('auth_title'), children: [
              if (c.isSignedIn)
                DsRow(
                  leading: const Icon(Icons.verified_user_outlined, size: 22, color: Palette.textDim),
                  label: l.t(
                      'auth_signed_in_as', {'phone': c.authSession!.phoneE164}),
                  subtitle: l.t('auth_sign_out'),
                  labelColor: Palette.teal,
                  onTap: () async {
                    final ok = await confirmDestructive(
                      context,
                      title: l.t('auth_sign_out'),
                      message: l.t('auth_signed_in_as',
                          {'phone': c.authSession!.phoneE164}),
                      confirmLabel: l.t('auth_sign_out'),
                    );
                    if (ok) c.signOut();
                  },
                )
              else
                DsRow(
                  leading: const Icon(Icons.login_rounded, size: 22, color: Palette.textDim),
                  label: l.t('auth_sign_in_cta'),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Palette.textDim),
                  // Shared with the dashboard's setup nudge, which is where
                  // most people will now meet this — see ui/auth/sign_in_route.
                  onTap: () => openSignIn(context, c),
                ),
            ]),


            // ---- Children ----
            _Section(
              title: l.t('set_children'),
              action: _AddButton(
                  label: l.t('tr_add_child'),
                  onTap: () => showAddChildSheet(context, c)),
              children: [
                for (final child in c.children)
                  DsRow(
                    leading: PhotoAvatar(
                        photoPath: child.photoPath,
                        name: child.name,
                        size: 34,
                        fallbackIcon: child.gender == Gender.boy
                            ? Icons.boy
                            : child.gender == Gender.girl
                                ? Icons.girl
                                : Icons.child_care),
                    label: child.name,
                    subtitle: _childSubtitle(l, child),
                    // Row opens the child's overview; editing lives in there, so
                    // each destination has exactly one entry point.
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          ChildDetailScreen(controller: c, childId: child.id),
                    )),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Palette.textDim),
                      tooltip: l.t('act_remove'),
                      onPressed: () async {
                        final ok = await confirmDestructive(
                          context,
                          title: l.t('confirm_remove_child_title'),
                          message: l.t('confirm_remove_child_body',
                              {'name': child.name}),
                          confirmLabel: l.t('act_remove'),
                        );
                        if (ok) c.removeChild(child.id);
                      },
                    ),
                  ),
              ],
            ),

            // ---- Devices ----
            _Section(
              title: l.t('set_devices'),
              action: _AddButton(
                  label: l.t('tr_add_device'),
                  onTap: () => showAddDeviceSheet(context, c)),
              children: c.devices.isEmpty
                  ? [
                      DsRow(
                          leading: const Icon(Icons.watch_off_outlined, size: 22, color: Palette.textDim),
                          label: l.t('set_no_devices'))
                    ]
                  : [
                      for (final d in c.devices)
                        DsRow(
                          leading: Icon(
                              d.kind == DeviceKind.band
                                  ? Icons.watch
                                  : Icons.sensors,
                              size: 22,
                              color: Palette.textDim),
                          label: d.name,
                          subtitle: _deviceSubtitle(l, c, d),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Palette.textDim),
                            tooltip: l.t('act_remove'),
                            onPressed: () async {
                              final ok = await confirmDestructive(
                                context,
                                title: l.t('confirm_remove_device_title'),
                                message: l.t('confirm_remove_device_body',
                                    {'name': d.name}),
                                confirmLabel: l.t('act_remove'),
                              );
                              if (ok) c.removeDevice(d.id);
                            },
                          ),
                        ),
                    ],
            ),

            // ---- Notifications ----
            _Section(title: l.t('set_notifications'), children: [
              DsRow(
                leading: const Icon(Icons.notifications_active_outlined, size: 22, color: Palette.textDim),
                label: l.t('set_notifications'),
                subtitle: l.t('set_notifications_sub'),
                // The switch is its own tappable node, separate from the row's
                // title — without a label a screen reader announces "switch,
                // on" and nothing about what it controls.
                // DsToggle carries the label itself, so the wrapping Semantics
                // is gone: two nested labels announce twice.
                trailing: DsToggle(
                  value: c.notificationsEnabled,
                  onChanged: c.setNotificationsEnabled,
                  semanticLabel: l.t('set_notifications'),
                ),
                onTap: () => c.setNotificationsEnabled(!c.notificationsEnabled),
              ),
              DsRow(
                leading: const Icon(Icons.notifications_outlined, size: 22, color: Palette.textDim),
                label: l.t('rem_title'),
                subtitle: l.t('rem_active', {
                  'n': activeReminderCount(
                    period: c.periodReminderEnabled,
                    fertile: c.fertileReminderEnabled,
                    water: c.waterReminderMinutes != null,
                  )
                }),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: Palette.textDim),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RemindersCenterScreen(controller: c),
                )),
              ),
            ]),

            // ---- Blood pressure calibration (highlighted CTA) ----
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
              child: Text(l.t('set_bp_calibration').toUpperCase(),
                  style: const TextStyle(
                      color: Palette.textDim,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
            ),
            _CalibrateCta(
                status: _calStatus(l, c),
                onTap: () => showCalibrateBpSheet(context, c)),

            // ---- Data ----
            _Section(title: l.t('set_data'), children: [
              DsRow(
                leading: const Icon(Icons.insights_rounded, size: 22, color: Palette.textDim),
                label: l.t('journey_title'),
                subtitle: l.t('journey_sub'),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: Palette.textDim),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => JourneyScreen(controller: c),
                )),
              ),
              DsRow(
                leading: const Icon(Icons.download_rounded, size: 22, color: Palette.textDim),
                label: l.t('set_export'),
                subtitle: _backupSubtitle(l, c),
                trailing: shouldNudgeBackup(
                        backupFreshness(c.lastExportAt, DateTime.now()))
                    ? const Icon(Icons.error_outline_rounded,
                        color: Palette.amber)
                    : const Icon(Icons.chevron_right_rounded,
                        color: Palette.textDim),
                onTap: () => _openExport(context, c),
              ),
              DsRow(
                leading: const Icon(Icons.upload_rounded, size: 22, color: Palette.textDim),
                label: l.t('set_import'),
                subtitle: l.t('set_import_sub'),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: Palette.textDim),
                onTap: () => _openImport(context, c),
              ),
              // Erase everything. This app holds a child's name, date of birth
              // and the coordinates of their home and school, plus a woman's
              // reproductive history — there has to be a way to remove all of
              // it from the phone, before selling it or simply on request.
              // resetApp() existed for this and was wired to nothing.
              DsRow(
                leading: const Icon(Icons.delete_forever_outlined, size: 22, color: Palette.textDim),
                label: l.t('set_erase'),
                subtitle: l.t('set_erase_sub'),
                labelColor: Palette.danger,
                onTap: () => _confirmErase(context, c),
              ),
            ]),

            // ---- Language ----
            //
            // One row that says which language is on, opening a picker — not
            // three rows of radio buttons.
            //
            // It used to sit second on the screen, above her children and her
            // devices, taking a third of the first screenful to offer a choice
            // made once and never again. The things she actually manages were
            // pushed below the fold by a setting she had already set.
            _Section(title: l.t('set_language'), children: [
              DsRow(
                leading: _LangBadge(code: _langCode(c.locale), selected: true),
                label: l.t('set_language'),
                subtitle: _langName(c.locale),
                trailing: const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
                onTap: () => _pickLanguage(context, c),
              ),
            ]),

            // ---- About ----
            _Section(title: l.t('set_about'), children: [
              DsRow(
                  leading: const Icon(Icons.info_outline, size: 22, color: Palette.textDim),
                  label: 'Ana-Bala',
                  subtitle: l.t('set_about_body')),
              DsRow(
                leading: const Icon(Icons.help_outline_rounded, size: 22, color: Palette.textDim),
                label: l.t('set_help'),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: Palette.textDim),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      HelpSupportScreen(diagnostics: 'locale ${c.locale.name}'),
                )),
              ),
              DsRow(
                leading: const Icon(Icons.privacy_tip_outlined, size: 22, color: Palette.textDim),
                label: l.t('set_privacy'),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: Palette.textDim),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const LegalScreen(doc: LegalDoc.privacy),
                )),
              ),
              DsRow(
                leading: const Icon(Icons.description_outlined, size: 22, color: Palette.textDim),
                label: l.t('set_terms'),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: Palette.textDim),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const LegalScreen(doc: LegalDoc.terms),
                )),
              ),
              DsRow(
                  leading: const Icon(Icons.tag, size: 22, color: Palette.textDim),
                  label: l.t('set_version'),
                  trailing: const Text('0.1.0',
                      style: TextStyle(color: Palette.textDim))),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _openExport(BuildContext context, AppController c) async {
    final l = L10nScope.of(context);
    final json = c.exportJson();
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l.t('set_export')),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('set_export_hint'),
                  style: const TextStyle(color: Palette.textDim, fontSize: 13)),
              const SizedBox(height: 12),
              // Bounded scroll area — a Flexible in a min-height Column can fail to
              // lay out; a ConstrainedBox sized to the screen keeps the dialog from
              // overflowing on short screens while staying generous on tall ones.
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Palette.glass,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Ds.ink, width: DsShape.borderWidth)),
                  child: SingleChildScrollView(
                    child: SelectableText(json,
                        style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 11.5,
                            height: 1.35,
                            color: Palette.text)),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(l.t('act_cancel'))),
          FilledButton.icon(
            // Saves to a file and opens the system share sheet, instead of
            // putting the backup on the clipboard.
            //
            // The clipboard is a shared buffer: keyboards keep a history of it,
            // clipboard managers persist it, and it survives until something
            // else overwrites it. This particular payload is her profile and
            // phone numbers, her child's name and date of birth, the
            // coordinates of her home and her child's school, and her health
            // history. The dialog's own warning already says to keep the file
            // like a personal document and not to send it through messengers —
            // and the only button offered did the riskiest possible thing with
            // it.
            onPressed: () => _saveExport(context, dialogCtx, json),
            style: FilledButton.styleFrom(backgroundColor: Palette.violet),
            icon: const Icon(Icons.save_alt_rounded, size: 18),
            label: Text(l.t('set_export_save')),
          ),
        ],
      ),
    );
  }

  /// Write the backup to a file and hand it to the system share sheet.
  ///
  /// The file goes to the app's own directory, not to a public folder: it is
  /// readable by this app alone, and the share sheet is what grants any other
  /// app access to it — a deliberate act, once, rather than a shared buffer
  /// anything can poll.
  ///
  /// Failure is reported. A silent catch here would leave her believing a
  /// backup exists, which is worse than knowing none does.
  Future<void> _saveExport(
      BuildContext context, BuildContext dialogCtx, String json) async {
    final l = L10nScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      // Do not overwrite an earlier backup taken the same day. The second
      // export of a day replacing the first is the wrong behaviour for the only
      // copy of someone's health record.
      var seq = 0;
      var file = File('${dir.path}/${backupFileName(now)}');
      while (await file.exists()) {
        seq++;
        file = File('${dir.path}/${backupFileName(now, seq: seq)}');
      }
      await file.writeAsString(json, flush: true);

      if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: l.t('set_export_subject'),
      ));
    } catch (_) {
      if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
      messenger.showSnackBar(
        SnackBar(
            content: Text(l.t('set_export_failed')),
            behavior: SnackBarBehavior.floating),
      );
    }
  }

  /// Erase everything on this phone.
  ///
  /// The confirmation names what goes and says a backup is the only way back,
  /// because there is no undo — and the export dialog sits directly above this
  /// row, so the remedy is one tap away if she wants it first.
  Future<void> _confirmErase(BuildContext context, AppController c) async {
    final l = L10nScope.of(context);
    final ok = await confirmDestructive(
      context,
      title: l.t('set_erase_title'),
      message: l.t('set_erase_body'),
      confirmLabel: l.t('set_erase'),
    );
    if (!ok) return;
    final serverErased = await c.resetApp();
    if (!context.mounted) return;
    // Say which of the two actually happened.
    //
    // The phone is wiped either way, but "All data erased" is a claim about
    // the server too — and if the request could not be made, repeating it
    // would be the same false promise this whole change exists to remove.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(l.t(serverErased ? 'set_erased' : 'set_erased_local_only')),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: serverErased ? 4 : 8),
      ),
    );
  }

  Future<void> _openImport(BuildContext context, AppController c) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    final l = L10nScope.of(context);

    // Import REPLACES everything — profile, children, zones, cycle history —
    // so it is the most destructive action in the app, not an additive one.
    // It reached here with no confirmation at all because the guard runner
    // works from a list of known method names and nobody had added this one.
    final confirmed = await confirmDestructive(
      context,
      title: l.t('set_import_confirm_title'),
      message: l.t('set_import_confirm_body'),
      confirmLabel: l.t('set_import_confirm_cta'),
    );
    if (!confirmed || !context.mounted) return;

    final ok = c.importJson(text.trim());
    // Say when part of the file could not be read.
    //
    // The parse skips a bad entry rather than failing wholesale — right for her
    // own saved data, where the alternative is losing all of it. For a file she
    // deliberately chose to restore, reporting plain success would be a lie:
    // she would never learn that three appointments in it were unreadable and
    // are simply gone.
    final dropped = c.lastImportDropped;
    final message = !ok
        ? l.t('set_import_fail')
        : dropped == 0
            ? l.t('set_import_ok')
            : l.t('set_import_partial', {'n': dropped});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok ? null : Palette.danger,
        duration: Duration(seconds: ok && dropped == 0 ? 4 : 8),
      ),
    );
  }

  /// Export subtitle doubles as the backup-freshness line: never backed up, or
  /// how long ago, with a nudge once it goes stale.
  String _backupSubtitle(L10n l, AppController c) {
    final at = c.lastExportAt;
    if (at == null) return l.t('backup_never');
    final age = DateTime.now().difference(at);
    final ago = l.ago(age.isNegative ? Duration.zero : age);
    return backupFreshness(at, DateTime.now()) == BackupFreshness.stale
        ? l.t('backup_stale', {'ago': ago})
        : l.t('backup_last', {'ago': ago});
  }

  String _calStatus(L10n l, AppController c) {
    final cal = c.bpCalibration;
    if (cal == null) return l.t('cal_never');
    final now = DateTime.now();
    // The SAME rule the reading itself is judged by. This was a second, loose
    // `age.inDays > 8` — so the status line and the applied reading could
    // disagree about whether the calibration was still good.
    if (bpCalibrationIsStale(cal, now)) return l.t('cal_stale');
    return l.t('cal_last', {'ago': l.ago(now.difference(cal.calibratedAt))});
  }

  String _deviceSubtitle(L10n l, AppController c, PairedDevice d) {
    final kindLabel = l.t(d.kind == DeviceKind.band ? 'dev_band' : 'dev_tag');
    if (d.kind == DeviceKind.tag && d.childId != null) {
      for (final ch in c.children) {
        if (ch.id == d.childId)
          return '${l.t('dev_linked_to', {'name': ch.name})} · ${d.id}';
      }
    }
    return '$kindLabel · ${d.id}';
  }

  String _childSubtitle(L10n l, ChildProfile child) {
    final zones = l.t('child_zone_count', {'n': child.geofences.length});
    if (!child.hasDateOfBirth) return zones;
    return '${l.childAge(child.ageInMonths(DateTime.now()))} · $zones';
  }
}

/// Paste-a-backup dialog: a text field for the exported JSON, a clear warning
/// that importing REPLACES current data, and an Import button (the explicit
/// destructive confirmation). Returns the pasted text, or null on cancel. A
/// dialog (not a bottom sheet) so button/width layout stays robust.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog();
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final hasText = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(l.t('set_import')),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
                  color: Palette.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Palette.danger, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(l.t('set_import_warn'),
                        style: const TextStyle(
                            color: Palette.danger,
                            fontSize: 12.5,
                            height: 1.3))),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: TextField(
                controller: _controller,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                style:
                    const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
                decoration: InputDecoration(
                  hintText: l.t('set_import_hint'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.t('act_cancel'))),
        FilledButton(
          onPressed: hasText
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
          style: FilledButton.styleFrom(backgroundColor: Palette.danger),
          child: Text(l.t('set_import_apply')),
        ),
      ],
    );
  }
}

/// Highlighted call-to-action for weekly blood-pressure calibration — a critical
/// feature, so it gets a distinct accent card with an informative tooltip rather
/// than a plain list row.
class _CalibrateCta extends StatelessWidget {
  final String status;
  final VoidCallback onTap;
  const _CalibrateCta({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Tooltip(
      message: l.t('cal_tooltip'),
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Palette.violet.withValues(alpha: 0.10),
              border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: Ds.ink, width: DsShape.borderWidth),
                    color: Palette.violet,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.monitor_heart_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(l.t('cal_title'),
                                style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const Icon(Icons.info_outline_rounded,
                              size: 16, color: Palette.violet),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(status,
                          style: const TextStyle(
                              color: Palette.textDim, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Palette.violet),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled group of rows.
///
/// The rows are [DsRow]s rendered by [DsListCard], so this screen no longer
/// carries its own copy of "a row is an icon, a title, a subtitle and a
/// trailing control". That copy was the reason the shared primitive could not
/// express one: nothing was using it, so nobody noticed it was too small.
class _Section extends StatelessWidget {
  final String title;
  final List<DsRow> children;
  final Widget? action;
  const _Section({required this.title, required this.children, this.action});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
          child: Row(children: [
            Expanded(
              child: Text(title.toUpperCase(),
                  style: const TextStyle(
                      color: Palette.textDim,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
            ),
            // Flexible: at large accessibility text the action's label grows
            // past the row and the header overflowed by 125px. The title is
            // already Expanded, so without this the button has no give.
            if (action != null) Flexible(child: action!),
          ]),
        ),
        DsListCard(rows: children),
      ],
    );
  }
}

class _LangBadge extends StatelessWidget {
  final String code;
  final bool selected;
  const _LangBadge({required this.code, required this.selected});
  @override
  Widget build(BuildContext context) {
    final color = selected ? Palette.violet : Palette.textDim;
    return Container(
      width: 34,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(code,
          style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add, size: 18),
      // scaleDown, not ellipsis. «Добавить ребёнка» rendered as «Добавить
      // ребё…» beside its section heading on a 360dp phone — a button whose
      // verb survives and whose object does not. Shrinking keeps the whole
      // word, which is the only thing that makes it a button rather than a
      // guess.
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1),
      ),
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8)),
    );
  }
}

/// The three languages, in one place so the row and the picker cannot disagree.
///
/// Each name is written in its OWN language — a Kazakh reader looks for
/// «Қазақша», not for whatever the current interface calls Kazakh.
const _languages = <(AppLocale, String, String)>[
  (AppLocale.ru, 'Русский', 'RU'),
  (AppLocale.kk, 'Қазақша', 'KK'),
  (AppLocale.en, 'English', 'EN'),
];

String _langName(AppLocale l) =>
    _languages.firstWhere((e) => e.$1 == l, orElse: () => _languages.first).$2;
String _langCode(AppLocale l) =>
    _languages.firstWhere((e) => e.$1 == l, orElse: () => _languages.first).$3;

/// Choose the interface language.
///
/// A sheet rather than three permanent rows: it is chosen once, and the screen
/// belongs to the things she comes back to — her children, her devices, her
/// reminders.
Future<void> _pickLanguage(BuildContext context, AppController c) {
  final l = L10nScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Palette.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.t('set_language'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          for (final (loc, name, code) in _languages)
            ListTile(
              // The badge replaces the icon entirely: three identical translate
              // glyphs told the reader nothing about which language each row was.
              leading: _LangBadge(code: code, selected: c.locale == loc),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: c.locale == loc
                  ? const Icon(Icons.check_circle, color: Palette.violet)
                  : const Icon(Icons.circle_outlined, color: Palette.border),
              onTap: () {
                c.setLocale(loc);
                Navigator.of(sheetContext).pop();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
