/// MedicationsScreen — manage the supplements/medicines being tracked, and
/// check off today's doses. Adding, editing and removing all live here; the
/// women's-health card is a read-and-tick shortcut into the same data.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../domain/medication.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
import '../widgets/glass.dart';

class MedicationsScreen extends StatelessWidget {
  final AppController controller;
  final DateTime Function()? _nowFn;
  const MedicationsScreen({super.key, required this.controller, DateTime Function()? now}) : _nowFn = now;

  DateTime _now() => (_nowFn ?? DateTime.now)();

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('med_title'))),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openEditor(context),
          backgroundColor: Palette.violet,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: Text(l.t('med_add')),
        ),
        body: StreamBuilder<void>(
          stream: controller.changes,
          builder: (context, _) {
            final meds = controller.medications;
            if (meds.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.medication_outlined, size: 56, color: Palette.textDim.withValues(alpha: 0.6)),
                      const SizedBox(height: 12),
                      Text(l.t('med_empty'),
                          textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)),
                    ],
                  ),
                ),
              );
            }
            final today = _now();
            final progress = dayProgress(meds, controller.medLog, today);
            final streak = adherenceStreak(meds, controller.medLog, today);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                _TodayHeader(taken: progress.taken, planned: progress.planned, streak: streak),
                const SizedBox(height: 14),
                for (final m in meds) ...[
                  _MedRow(
                    med: m,
                    taken: dosesTaken(controller.medLog, today, m.id),
                    onTake: () => controller.takeMedicationDose(m.id, today),
                    onUndo: () => controller.undoMedicationDose(m.id, today),
                    onEdit: () => _openEditor(context, existing: m),
                    onDelete: () => _confirmDelete(context, m),
                  ),
                  const SizedBox(height: 10),
                ],
                if (adherenceRate(meds, controller.medLog, today) case final rate?) ...[
                  const SizedBox(height: 6),
                  _HistoryStrip(
                    history: adherenceHistory(meds, controller.medLog, today, days: 14),
                    rate: rate,
                  ),
                ],
                const SizedBox(height: 8),
                Text(l.t('med_disclaimer'),
                    style: const TextStyle(color: Palette.textDim, fontSize: 11.5, height: 1.4)),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Medication m) async {
    final l = L10nScope.of(context);
    final ok = await confirmDestructive(
      context,
      title: l.t('med_delete_title'),
      message: l.t('med_delete_body', {'name': m.name}),
      confirmLabel: l.t('act_remove'),
    );
    if (ok) controller.removeMedication(m.id);
  }

  Future<void> _openEditor(BuildContext context, {Medication? existing}) async {
    final result = await showModalBottomSheet<_MedDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _MedEditorSheet(initial: existing),
    );
    if (result == null) return;
    if (existing == null) {
      controller.addMedication(result.name, dose: result.dose, perDay: result.perDay);
    } else {
      controller.updateMedication(existing.id, name: result.name, dose: result.dose, perDay: result.perDay);
    }
  }
}

/// Today's dose progress + the current all-doses-taken streak.
class _TodayHeader extends StatelessWidget {
  final int taken;
  final int planned;
  final int streak;
  const _TodayHeader({required this.taken, required this.planned, required this.streak});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final done = planned > 0 && taken >= planned;
    final accent = done ? Palette.good : Palette.violet;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: accent.withValues(alpha: 0.07),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(done ? Icons.check_circle_rounded : Icons.medication_rounded, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l.t('med_today'),
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Palette.text)),
              ),
              Text('$taken/$planned',
                  style: TextStyle(fontFamily: 'JetBrainsMono', fontWeight: FontWeight.w700, color: accent, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: planned == 0 ? 0 : taken / planned,
              minHeight: 7,
              backgroundColor: Palette.glass,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          if (streak >= 2) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.local_fire_department_rounded, size: 15, color: Palette.amber),
              const SizedBox(width: 6),
              Text(l.t('med_streak', {'n': streak}),
                  style: const TextStyle(color: Palette.textDim, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ],
        ],
      ),
    );
  }
}

/// A fortnight of dose history: one bar per day, filled by how much of that
/// day's plan was taken, plus the overall rate for the week.
class _HistoryStrip extends StatelessWidget {
  final List<MedDay> history;
  final double rate;
  const _HistoryStrip({required this.history, required this.rate});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Both labels are longer in ru/kk, and with a Spacer between two
          // unbounded Texts the pair ran off a 360dp card. Flexible lets
          // whichever is longer give way instead.
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(
              child: Text(l.t('med_history').toUpperCase(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(l.t('med_adherence', {'pct': (rate * 100).round()}),
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: rate >= 0.8 ? Palette.good : Palette.amber,
                  )),
            ),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in history)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Semantics(
                        label: '${d.taken}/${d.planned}',
                        child: _DayBar(fraction: d.planned == 0 ? 0 : d.taken / d.planned),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(l.t('med_history_span', {'n': history.length}),
              style: const TextStyle(color: Palette.textDim, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final double fraction; // 0..1 of that day's plan
  const _DayBar({required this.fraction});
  @override
  Widget build(BuildContext context) {
    final full = fraction >= 1;
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: fraction <= 0 ? 0.12 : (0.2 + 0.8 * fraction),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fraction <= 0
                ? Palette.border
                : (full ? Palette.good : Palette.violet).withValues(alpha: full ? 0.85 : 0.55),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const SizedBox(width: double.infinity),
        ),
      ),
    );
  }
}

class _MedRow extends StatelessWidget {
  final Medication med;
  final int taken;
  final VoidCallback onTake;
  final VoidCallback onUndo;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _MedRow({
    required this.med,
    required this.taken,
    required this.onTake,
    required this.onUndo,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final done = taken >= med.perDay;
    final subtitle = [
      if (med.dose.isNotEmpty) med.dose,
      if (med.perDay > 1) l.t('med_per_day', {'n': med.perDay}),
    ].join(' · ');

    return GlassCard(
      onTap: onEdit,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: (done ? Palette.good : Palette.violet).withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(done ? Icons.check_rounded : Icons.medication_rounded,
                color: done ? Palette.good : Palette.violet, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(med.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                ],
              ],
            ),
          ),
          // Dose counter: undo is only offered once something's been taken.
          if (taken > 0)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded, color: Palette.textDim, size: 22),
              tooltip: l.t('med_undo'),
              onPressed: onUndo,
            ),
          Text('$taken/${med.perDay}',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: done ? Palette.good : Palette.textDim,
              )),
          IconButton(
            icon: Icon(Icons.add_circle_rounded, color: done ? Palette.border : Palette.violet, size: 26),
            tooltip: l.t('med_take'),
            onPressed: done ? null : onTake,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Palette.textDim, size: 20),
            tooltip: l.t('act_remove'),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _MedDraft {
  final String name;
  final String dose;
  final int perDay;
  const _MedDraft(this.name, this.dose, this.perDay);
}

class _MedEditorSheet extends StatefulWidget {
  final Medication? initial; // non-null → edit mode
  const _MedEditorSheet({this.initial});
  @override
  State<_MedEditorSheet> createState() => _MedEditorSheetState();
}

class _MedEditorSheetState extends State<_MedEditorSheet> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _dose = TextEditingController(text: widget.initial?.dose ?? '');
  late int _perDay = widget.initial?.perDay ?? 1;

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t(widget.initial == null ? 'med_add' : 'med_edit'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Palette.text)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: widget.initial == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l.t('med_name_label'),
              hintText: l.t('med_name_hint'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dose,
            decoration: InputDecoration(
              labelText: l.t('med_dose_label'),
              hintText: l.t('med_dose_hint'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(l.t('med_per_day_label'), style: const TextStyle(fontWeight: FontWeight.w600, color: Palette.text)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 1; i <= maxDosesPerDay; i++)
                ChoiceChip(
                  label: Text('$i'),
                  selected: _perDay == i,
                  onSelected: (_) => setState(() => _perDay = i),
                  showCheckmark: false,
                  selectedColor: Palette.violet.withValues(alpha: 0.16),
                  labelStyle: TextStyle(
                    color: _perDay == i ? Palette.violet : Palette.textDim,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: Palette.surface,
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _valid
                  ? () => Navigator.of(context).pop(_MedDraft(_name.text.trim(), _dose.text.trim(), _perDay))
                  : null,
              style: FilledButton.styleFrom(backgroundColor: Palette.violet, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(l.t('act_save'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact women's-health card: today's dose progress with one-tap ticking,
/// opening the full manager for anything more.
class MedicationCard extends StatelessWidget {
  final AppController controller;
  final DateTime today;
  final VoidCallback onOpen;
  const MedicationCard({super.key, required this.controller, required this.today, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final meds = controller.medications;
    if (meds.isEmpty) return const SizedBox.shrink();
    final p = dayProgress(meds, controller.medLog, today);
    final done = p.planned > 0 && p.taken >= p.planned;
    final accent = done ? Palette.good : Palette.violet;

    return GlassCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l.t('med_title').toUpperCase(),
                  style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              const Spacer(),
              Text('${p.taken}/${p.planned}',
                  style: TextStyle(fontFamily: 'JetBrainsMono', fontWeight: FontWeight.w700, color: accent, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          for (final m in meds.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(m.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                  Text('${dosesTaken(controller.medLog, today, m.id)}/${m.perDay}',
                      style: const TextStyle(fontFamily: 'JetBrainsMono', color: Palette.textDim, fontSize: 12.5)),
                  const SizedBox(width: 6),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: Icon(
                      dosesTaken(controller.medLog, today, m.id) >= m.perDay
                          ? Icons.check_circle_rounded
                          : Icons.add_circle_outline_rounded,
                      size: 24,
                      color: dosesTaken(controller.medLog, today, m.id) >= m.perDay ? Palette.good : Palette.violet,
                    ),
                    tooltip: l.t('med_take'),
                    onPressed: dosesTaken(controller.medLog, today, m.id) >= m.perDay
                        ? null
                        : () => controller.takeMedicationDose(m.id, today),
                  ),
                ],
              ),
            ),
          if (meds.length > 3)
            Text(l.t('med_more', {'n': meds.length - 3}),
                style: const TextStyle(color: Palette.textDim, fontSize: 12)),
        ],
      ),
    );
  }
}
