/// AppointmentsScreen — the mother's dated reminders (prenatal visits, scans,
/// lab work). Upcoming reminders sit on top (soonest first) with a countdown;
/// past ones follow, dimmed. Add via the FAB; delete asks to confirm. All list
/// logic is the verified [appointment] domain; this is presentation + a small
/// add form.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../app/app_controller.dart';
import '../../domain/appointment.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
import '../widgets/glass.dart';
import 'visit_summary.dart';

class AppointmentsScreen extends StatefulWidget {
  final AppController controller;
  final DateTime Function()? nowFn;
  const AppointmentsScreen({super.key, required this.controller, DateTime Function()? now}) : nowFn = now;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

enum _ApptTab { upcoming, past }

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  _ApptTab _tab = _ApptTab.upcoming;
  final _search = TextEditingController();

  /// Below this the list is easy to scan, and a search field is just clutter.
  static const _searchThreshold = 6;

  AppController get controller => widget.controller;
  DateTime now() => (widget.nowFn ?? DateTime.now)();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(l.t('appt_title')),
          actions: [
            IconButton(
              icon: const Icon(Icons.assignment_outlined),
              tooltip: l.t('visit_summary'),
              onPressed: () => _copyVisitSummary(context),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openAdd(context),
          backgroundColor: Palette.violet,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: Text(l.t('appt_add')),
        ),
        body: StreamBuilder<void>(
          stream: controller.changes,
          builder: (context, _) {
            final all = controller.appointments;
            if (all.isEmpty) return _EmptyState(l: l);
            // Search filters the whole set; the tabs then split what survives.
            final showSearch = all.length >= _searchThreshold;
            final split = splitAppointments(
              showSearch ? searchAppointments(all, _search.text) : all,
              now(),
            );
            // An empty selected tab falls back to the one that has items.
            if (_tab == _ApptTab.upcoming && split.upcoming.isEmpty && split.past.isNotEmpty) _tab = _ApptTab.past;
            if (_tab == _ApptTab.past && split.past.isEmpty && split.upcoming.isNotEmpty) _tab = _ApptTab.upcoming;
            final list = _tab == _ApptTab.upcoming ? split.upcoming : split.past;
            return Column(
              children: [
                if (showSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: l.t('appt_search_hint'),
                        prefixIcon: const Icon(Icons.search_rounded, color: Palette.textDim),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, color: Palette.textDim),
                                tooltip: l.t('act_clear_search'),
                                onPressed: () => setState(_search.clear),
                              ),
                        filled: true,
                        fillColor: Palette.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: _ApptTabs(
                    tab: _tab,
                    upcomingCount: split.upcoming.length,
                    pastCount: split.past.length,
                    onSelect: (t) => setState(() => _tab = t),
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Text(
                            // A fruitless search reads differently from a
                            // genuinely empty tab.
                            showSearch && _search.text.trim().isNotEmpty && split.upcoming.isEmpty && split.past.isEmpty
                                ? l.t('appt_no_match')
                                : l.t('appt_none'),
                            style: const TextStyle(color: Palette.textDim),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          children: [
                            for (final a in list)
                              _AppointmentCard(
                                appt: a,
                                now: now(),
                                past: _tab == _ApptTab.past,
                                onDelete: () => _confirmDelete(context, a),
                                onEdit: () => _openEdit(context, a),
                                onReschedule: (d) => _reschedule(a, d),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Copy a "since your last visit" digest for the appointment. Clipboard only —
  /// no native share dependency, same as the other summaries.
  Future<void> _copyVisitSummary(BuildContext context) async {
    final l = L10nScope.of(context);
    final c = controller;
    final text = buildVisitSummary(
      l,
      samples: c.samples,
      dayLogs: c.dayLogs,
      medications: c.medications,
      weights: c.weights,
      now: now(),
      name: c.displayName,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.t('visit_copied')), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Appointment a) async {
    final l = L10nScope.of(context);
    final ok = await confirmDestructive(
      context,
      title: l.t('appt_delete_title'),
      message: l.t('appt_delete_body', {'title': a.title}),
      confirmLabel: l.t('act_remove'),
    );
    if (ok) controller.removeAppointment(a.id);
  }

  Future<void> _openAdd(BuildContext context) async {
    final result = await showModalBottomSheet<_NewAppt>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddAppointmentSheet(now: now()),
    );
    if (result != null) {
      controller.addAppointment(result.title, result.at, note: result.note);
    }
  }

  void _reschedule(Appointment a, Duration by) =>
      controller.updateAppointment(a.id, a.title, a.at.add(by), note: a.note);

  Future<void> _openEdit(BuildContext context, Appointment appt) async {
    final result = await showModalBottomSheet<_NewAppt>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddAppointmentSheet(now: now(), initial: appt),
    );
    if (result != null) {
      controller.updateAppointment(appt.id, result.title, result.at, note: result.note);
    }
  }
}

/// Segmented Upcoming / Past selector with counts.
class _ApptTabs extends StatelessWidget {
  final _ApptTab tab;
  final int upcomingCount;
  final int pastCount;
  final ValueChanged<_ApptTab> onSelect;
  const _ApptTabs({required this.tab, required this.upcomingCount, required this.pastCount, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Palette.glass, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          _seg(l.t('appt_upcoming'), upcomingCount, tab == _ApptTab.upcoming, () => onSelect(_ApptTab.upcoming)),
          _seg(l.t('appt_past'), pastCount, tab == _ApptTab.past, () => onSelect(_ApptTab.past)),
        ],
      ),
    );
  }

  Widget _seg(String label, int count, bool selected, VoidCallback onTap) => Expanded(
        child: Material(
          color: selected ? Palette.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(11),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Text('$label ($count)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? Palette.violet : Palette.textDim,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  )),
            ),
          ),
        ),
      );
}

class _NewAppt {
  final String title;
  final DateTime at;
  final String note;
  const _NewAppt(this.title, this.at, this.note);
}

class _AddAppointmentSheet extends StatefulWidget {
  final DateTime now;
  final Appointment? initial; // non-null → edit mode (prefilled)
  const _AddAppointmentSheet({required this.now, this.initial});
  @override
  State<_AddAppointmentSheet> createState() => _AddAppointmentSheetState();
}

class _AddAppointmentSheetState extends State<_AddAppointmentSheet> {
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _note = TextEditingController(text: widget.initial?.note ?? '');
  late DateTime _date = widget.initial == null
      ? DateTime(widget.now.year, widget.now.month, widget.now.day)
      : DateTime(widget.initial!.at.year, widget.initial!.at.month, widget.initial!.at.day);
  late TimeOfDay _time = widget.initial == null
      ? const TimeOfDay(hour: 9, minute: 0)
      : TimeOfDay.fromDateTime(widget.initial!.at);

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime get _combined => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
  bool get _valid => _title.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ml = MaterialLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t(widget.initial == null ? 'appt_add' : 'appt_edit'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Palette.text)),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            autofocus: widget.initial == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l.t('appt_title_label'),
              hintText: l.t('appt_title_hint'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PickerTile(
                  icon: Icons.event_rounded,
                  label: ml.formatMediumDate(_date),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(widget.now.year - 1),
                      lastDate: DateTime(widget.now.year + 2),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PickerTile(
                  icon: Icons.schedule_rounded,
                  label: _time.format(context),
                  onTap: () async {
                    final picked = await showTimePicker(context: context, initialTime: _time);
                    if (picked != null) setState(() => _time = picked);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l.t('appt_note_label'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _valid ? () => Navigator.of(context).pop(_NewAppt(_title.text.trim(), _combined, _note.text.trim())) : null,
              style: FilledButton.styleFrom(backgroundColor: Palette.violet, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(l.t('act_save'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickerTile({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.glass,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Palette.border)),
          child: Row(children: [
            Icon(icon, size: 18, color: Palette.violet),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Palette.text)),
          ]),
        ),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final Appointment appt;
  final DateTime now;
  final bool past;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final ValueChanged<Duration>? onReschedule;
  const _AppointmentCard({required this.appt, required this.now, required this.onDelete, this.onEdit, this.onReschedule, this.past = false});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ml = MaterialLocalizations.of(context);
    final days = daysUntil(appt, now);
    final accent = past ? Palette.textDim : Palette.violet;
    final badge = past
        ? null
        : days == 0
            ? l.t('appt_today')
            : days == 1
                ? l.t('appt_tomorrow')
                : l.t('appt_in_days', {'n': days});

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: onEdit,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: accent.withValues(alpha: past ? 0.10 : 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.event_note_rounded, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appt.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: past ? Palette.textDim : Palette.text)),
                  const SizedBox(height: 2),
                  Text('${ml.formatMediumDate(appt.at)} · ${TimeOfDay.fromDateTime(appt.at).format(context)}',
                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                  if (appt.note.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(appt.note, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Palette.textDim, fontSize: 12.5, fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(badge, style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20, color: Palette.textDim),
              color: Palette.surfaceHi,
              tooltip: l.t('appt_actions'),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    onEdit?.call();
                  case 'day':
                    onReschedule?.call(const Duration(days: 1));
                  case 'week':
                    onReschedule?.call(const Duration(days: 7));
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (_) => [
                if (onEdit != null)
                  PopupMenuItem(value: 'edit', child: _MenuRow(icon: Icons.edit_outlined, label: l.t('appt_edit'))),
                if (onReschedule != null && !past) ...[
                  PopupMenuItem(value: 'day', child: _MenuRow(icon: Icons.today_rounded, label: l.t('appt_plus_day'))),
                  PopupMenuItem(value: 'week', child: _MenuRow(icon: Icons.date_range_rounded, label: l.t('appt_plus_week'))),
                ],
                PopupMenuItem(value: 'delete', child: _MenuRow(icon: Icons.delete_outline_rounded, label: l.t('act_remove'), danger: true)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  const _MenuRow({required this.icon, required this.label, this.danger = false});
  @override
  Widget build(BuildContext context) {
    final color = danger ? Palette.danger : Palette.text;
    return Row(children: [
      Icon(icon, size: 18, color: danger ? Palette.danger : Palette.textDim),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _EmptyState extends StatelessWidget {
  final L10n l;
  const _EmptyState({required this.l});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available_rounded, size: 56, color: Palette.textDim.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(l.t('appt_empty'),
                textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
