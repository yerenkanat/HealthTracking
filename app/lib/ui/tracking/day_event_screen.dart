/// Screen 48 — «Событие из истории дня».
///
/// «"SOS во дворе / 16:41" → карта точки → карточка «Алия нажала кнопку SOS» →
/// секция «Что было дальше» — таймлайн с временем → секция «Чем закончилось» —
/// 4 чипа выбора → «Сохранить отметку».»
///
/// The screen a mother opens the next morning. The alarm is over; what she is
/// doing here is closing it — deciding what it was, so the next one means
/// something. That is why the outcome chips are the only control on the page
/// and why there is no free-text box: at midnight nobody writes a paragraph,
/// and a field that is usually empty tells nobody anything.
library;

import 'package:flutter/material.dart';
import '../../domain/day_history.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import 'day_history_screen.dart' show RouteMapBuilder;

/// Records the parent's verdict. Returns false when it could not be saved —
/// the screen says so rather than showing a tick over a request that failed.
typedef SosOutcomeSaver = Future<bool> Function(DayEvent event, SosOutcome outcome);

class DayEventScreen extends StatefulWidget {
  final String childName;
  final DayEvent event;

  /// Everything that happened after it, for «Что было дальше».
  final List<DayEvent> laterEvents;
  final RouteMapBuilder routeMapBuilder;

  /// Omitted where nothing can record the verdict yet; the section then does
  /// not appear at all, rather than offering a button that does nothing.
  final SosOutcomeSaver? onSaveOutcome;

  /// What was already recorded, if this event has been closed before.
  final SosOutcome? initialOutcome;

  const DayEventScreen({
    super.key,
    required this.childName,
    required this.event,
    required this.routeMapBuilder,
    this.laterEvents = const [],
    this.onSaveOutcome,
    this.initialOutcome,
  });

  @override
  State<DayEventScreen> createState() => _DayEventScreenState();
}

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _DayEventScreenState extends State<DayEventScreen> {
  late SosOutcome? _picked = widget.initialOutcome;
  bool _saving = false;

  Future<void> _save() async {
    final saver = widget.onSaveOutcome;
    final choice = _picked;
    if (saver == null || choice == null || _saving) return;
    setState(() => _saving = true);
    final ok = await saver(widget.event, choice);
    if (!mounted) return;
    setState(() => _saving = false);
    final l = L10nScope.of(context);
    // The result of the request, not the fact that one was sent. A tick over a
    // failed save is how a parent believes the alarm is closed when it is not.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? l.t('sos_mark_saved') : l.t('day_failed')),
      behavior: SnackBarBehavior.floating,
    ));
    if (ok) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final e = widget.event;

    return Scaffold(
      backgroundColor: Ds.cream,
      appBar: AppBar(
        title: Text(l.t('sos_event_title', {'time': _hhmm(e.at)})),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: widget.routeMapBuilder(context, const [], [e]),
            ),
          ),
          const SizedBox(height: 16),

          // The card. Coral, because this is the one event on the timeline that
          // was an emergency, and it should not look like arriving at school.
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Ds.pastelPink,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const Icon(Icons.sos_rounded, color: Ds.coralText, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.t('sos_event_card', {'name': widget.childName}),
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: Ds.coralText,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),
          Text(l.t('sos_whats_next'),
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
          const SizedBox(height: 10),
          if (widget.laterEvents.isEmpty)
            Text(l.t('sos_no_events'),
                style: const TextStyle(
                    fontSize: 13.5, height: 1.4, color: Ds.textSecondary))
          else
            for (final x in widget.laterEvents)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(_hhmm(x.at),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Ds.textSecondary)),
                    ),
                    Expanded(
                      child: Text(
                        _laterLabel(context, x),
                        style: const TextStyle(fontSize: 14.5, color: Ds.text),
                      ),
                    ),
                  ],
                ),
              ),

          if (widget.onSaveOutcome != null) ...[
            const SizedBox(height: 24),
            Text(l.t('sos_how_ended'),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: Ds.text)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in SosOutcome.values)
                  ChoiceChip(
                    label: Text(l.t(o.l10nKey)),
                    selected: _picked == o,
                    onSelected: (_) => setState(() => _picked = o),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: DsShape.minTapTarget,
              child: FilledButton(
                // Disabled until something is chosen: saving «ничего» as an
                // outcome is worse than leaving the event open.
                onPressed: _picked == null || _saving ? null : _save,
                child: Text(l.t('sos_save_mark')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _laterLabel(BuildContext context, DayEvent x) {
    final l = L10nScope.of(context);
    return switch (x.kind) {
      DayEventKind.sos => l.t('day_sos'),
      DayEventKind.exit => x.zoneName == null
          ? l.t('day_left_unknown')
          : l.t('day_left_zone', {'zone': x.zoneName!}),
      DayEventKind.enter => x.zoneName == null
          ? l.t('day_entered_unknown')
          : l.t('day_entered_zone', {'zone': x.zoneName!}),
    };
  }
}
