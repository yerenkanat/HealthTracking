/// Her antenatal plan — the state's eight-visit schedule, made legible.
///
/// The domain (antenatal_protocol.dart) is the government protocol turned into
/// an algorithm keyed to the gestational week. This screen is the face of it:
/// it leads with the one thing she needs — which visit is due now or coming up,
/// and exactly what that visit is for — then sets apart the time-sensitive
/// windows that close, and lets her open the full eight-visit plan below.
///
/// Calm content up top; the "don't miss these weeks" block is framed apart in
/// rose. The current (or next) visit is expanded by default; the rest are
/// collapsed so it never opens as a wall of tests. Every screen of it points
/// back to her own doctor — this is the standard plan, not a verdict on her care.
library;

import 'package:flutter/material.dart';

import '../../domain/antenatal_protocol.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class AntenatalPlanScreen extends StatefulWidget {
  /// Completed gestational weeks. Drives which visit leads and which windows
  /// are open.
  final int week;

  /// The estimated due date, when known — lets each visit be turned into a real
  /// appointment on the date its window opens. Null hides the booking action.
  final DateTime? dueDate;

  /// Books a protocol visit as an appointment at [at]. Wired by the caller to
  /// AppController.addAppointment, so the booking flows to the backend/DB like
  /// any other appointment. Null (with no dueDate) hides the booking action.
  final void Function(AntenatalVisit visit, DateTime at)? onBook;

  const AntenatalPlanScreen({super.key, required this.week, this.dueDate, this.onBook});

  @override
  State<AntenatalPlanScreen> createState() => _AntenatalPlanScreenState();
}

class _AntenatalPlanScreenState extends State<AntenatalPlanScreen> {
  late final Set<int> _expanded;

  @override
  void initState() {
    super.initState();
    // Open on the visit that matters now; the rest stay folded.
    final lead = currentOrNextVisit(widget.week);
    _expanded = {if (lead != null) lead.number};
  }

  /// Book [visit] as an appointment on the day its window opens, at a sensible
  /// clinic hour (10:00). Flows through the caller's onBook → addAppointment, so
  /// it reaches the backend/DB like any hand-entered appointment.
  void _book(AntenatalVisit visit) {
    final due = widget.dueDate;
    final book = widget.onBook;
    if (due == null || book == null) return;
    final l = L10nScope.of(context);
    final day = visitOpensOn(visit, due);
    book(visit, DateTime(day.year, day.month, day.day, 10, 0));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.t('an_booked'))));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final week = widget.week;
    final lead = currentOrNextVisit(week);
    final dueNow = visitAtWeek(week) != null;
    final openWindows = windowsOpenAt(week);
    final canBook = widget.dueDate != null && widget.onBook != null;

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('an_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(l.t('an_intro'),
              style: const TextStyle(color: Palette.textDim, fontSize: 13, height: 1.5)),
          const SizedBox(height: 16),

          // What now: the visit due (or next), or a gentle "you're through the
          // plan" once term has come.
          if (lead != null)
            _LeadCard(visit: lead, dueNow: dueNow, onBook: canBook ? () => _book(lead) : null)
          else
            _TermCard(),

          // The windows that close. Only shown when one is actually open — an
          // empty rose block would just be noise.
          if (openWindows.isNotEmpty) ...[
            const SizedBox(height: 16),
            _WindowsCard(windows: openWindows),
          ],

          const SizedBox(height: 22),
          _SectionLabel(l.t('an_full_plan')),
          const SizedBox(height: 4),

          // The full eight-visit plan, current one expanded.
          for (final v in antenatalVisits)
            _VisitTile(
              visit: v,
              current: v.number == lead?.number,
              expanded: _expanded.contains(v.number),
              onBook: canBook ? () => _book(v) : null,
              onToggle: () => setState(() {
                _expanded.contains(v.number)
                    ? _expanded.remove(v.number)
                    : _expanded.add(v.number);
              }),
            ),

          const SizedBox(height: 14),
          _RiskNote(),
          const SizedBox(height: 16),
          Text(l.t('an_disclaimer'),
              style: const TextStyle(color: Palette.textDim, fontSize: 12, height: 1.5)),
          const SizedBox(height: 10),
          Text(l.t('an_source'),
              style: const TextStyle(
                  color: Palette.textDim, fontSize: 11, height: 1.45, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

/// The visit that leads the screen — due now or the next one coming up. Its
/// full contents are shown, grouped by category.
class _LeadCard extends StatelessWidget {
  final AntenatalVisit visit;
  final bool dueNow;
  final VoidCallback? onBook;
  const _LeadCard({required this.visit, required this.dueNow, this.onBook});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final accent = dueNow ? Palette.violet : Palette.teal;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.14), accent.withValues(alpha: 0.04)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(dueNow ? Icons.event_available_rounded : Icons.upcoming_outlined,
                size: 18, color: accent),
            const SizedBox(width: 8),
            Text((dueNow ? l.t('an_due_now') : l.t('an_upcoming')).toUpperCase(),
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: accent)),
          ]),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(l.t('an_of_eight', {'n': visit.number}),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              Text(_weeksLabel(l, visit),
                  style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Palette.textDim)),
            ],
          ),
          const SizedBox(height: 14),
          _GroupedItems(visit: visit),
          if (onBook != null) ...[
            const SizedBox(height: 14),
            _BookButton(accent: accent, onBook: onBook!),
          ],
        ],
      ),
    );
  }
}

/// "Add to my appointments" — turns this visit into a real, dated appointment.
class _BookButton extends StatelessWidget {
  final Color accent;
  final VoidCallback onBook;
  const _BookButton({required this.accent, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onBook,
        icon: const Icon(Icons.event_available_outlined, size: 18),
        label: Text(l.t('an_book_cta')),
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

/// After the last visit's window: nothing scheduled remains.
class _TermCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Palette.surface,
        border: Border.all(color: Palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_rounded, size: 22, color: Palette.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('an_term_title'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(l.t('an_term_note'),
                    style: const TextStyle(fontSize: 13, height: 1.5, color: Palette.textDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The time-sensitive screening windows open at this week — the ones that close.
class _WindowsCard extends StatelessWidget {
  final List<AntenatalWindow> windows;
  const _WindowsCard({required this.windows});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Palette.rose.withValues(alpha: 0.08),
        border: Border.all(color: Palette.rose.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.schedule_rounded, size: 18, color: Palette.roseDeep),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l.t('an_windows_title'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: Palette.roseDeep)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(l.t('an_windows_intro'),
              style: const TextStyle(fontSize: 12, height: 1.45, color: Palette.textDim)),
          const SizedBox(height: 12),
          for (var i = 0; i < windows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _WindowRow(window: windows[i]),
          ],
        ],
      ),
    );
  }
}

class _WindowRow extends StatelessWidget {
  final AntenatalWindow window;
  const _WindowRow({required this.window});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.circle, size: 7, color: Palette.roseDeep),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Window names reuse the visit-item strings — same screening,
              // one source of truth for its wording.
              Text(l.t('an_item_${window.id}'),
                  style: const TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _Pill(
                  text: l.t('an_win_open'),
                  fg: Palette.roseDeep,
                  bg: Palette.rose.withValues(alpha: 0.16),
                ),
                Text(
                  l.t('an_win_range', {'from': window.fromWeek, 'to': window.toWeek}),
                  style: const TextStyle(
                      fontFamily: 'JetBrainsMono', fontSize: 11.5, color: Palette.textDim),
                ),
                if (window.risk)
                  Text('· ${l.t('an_risk_tag')}',
                      style: const TextStyle(
                          fontSize: 11.5, fontStyle: FontStyle.italic, color: Palette.textDim)),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

/// One visit in the full plan — a header that toggles open its grouped contents.
class _VisitTile extends StatelessWidget {
  final AntenatalVisit visit;
  final bool current;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onBook;
  const _VisitTile({
    required this.visit,
    required this.current,
    required this.expanded,
    required this.onToggle,
    this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final accent = current ? Palette.violet : Palette.textDim;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: current ? Palette.violet.withValues(alpha: 0.4) : Palette.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: current ? 0.16 : 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Text('${visit.number}',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800, color: accent)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.t('an_visit_label', {'n': visit.number}),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(_weeksLabel(l, visit),
                            style: const TextStyle(
                                fontFamily: 'JetBrainsMono',
                                fontSize: 12,
                                color: Palette.textDim)),
                      ],
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: Palette.textDim),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GroupedItems(visit: visit),
                  if (onBook != null) ...[
                    const SizedBox(height: 12),
                    _BookButton(accent: current ? Palette.violet : Palette.textDim, onBook: onBook!),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A visit's items, grouped under the protocol's own category headings.
class _GroupedItems extends StatelessWidget {
  final AntenatalVisit visit;
  const _GroupedItems({required this.visit});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final blocks = <Widget>[];
    for (final cat in AntenatalCategory.values) {
      final items = visit.items.where((it) => it.category == cat).toList();
      if (items.isEmpty) continue;
      if (blocks.isNotEmpty) blocks.add(const SizedBox(height: 12));
      blocks.add(Text(l.t('an_cat_${cat.name}').toUpperCase(),
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: _catColour(cat))));
      for (final it in items) {
        blocks.add(const SizedBox(height: 7));
        blocks.add(_ItemRow(item: it));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }
}

class _ItemRow extends StatelessWidget {
  final AntenatalItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Icon(_catIcon(item.category), size: 14, color: _catColour(item.category)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: l.t('an_item_${item.id}')),
              if (item.risk)
                TextSpan(
                  text: '  · ${l.t('an_risk_tag')}',
                  style: const TextStyle(
                      fontSize: 11.5, fontStyle: FontStyle.italic, color: Palette.textDim),
                ),
            ]),
            style: const TextStyle(fontSize: 13, height: 1.42),
          ),
        ),
      ],
    );
  }
}

class _RiskNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 15, color: Palette.textDim),
        const SizedBox(width: 8),
        Expanded(
          child: Text(l.t('an_risk_note'),
              style: const TextStyle(
                  fontSize: 12, height: 1.45, fontStyle: FontStyle.italic, color: Palette.textDim)),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Palette.textDim)),
      );
}

class _Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  const _Pill({required this.text, required this.fg, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg)),
      );
}

String _weeksLabel(dynamic l, AntenatalVisit v) => v.fromWeek == v.toWeek
    ? l.t('an_week_single', {'w': v.fromWeek})
    : l.t('an_weeks_range', {'from': v.fromWeek, 'to': v.toWeek});

IconData _catIcon(AntenatalCategory c) => switch (c) {
      AntenatalCategory.counsel => Icons.chat_bubble_outline_rounded,
      AntenatalCategory.exam => Icons.monitor_heart_outlined,
      AntenatalCategory.lab => Icons.science_outlined,
      AntenatalCategory.imaging => Icons.graphic_eq_rounded,
      AntenatalCategory.prophylaxis => Icons.medication_outlined,
    };

Color _catColour(AntenatalCategory c) => switch (c) {
      AntenatalCategory.counsel => Palette.teal,
      AntenatalCategory.exam => Palette.violet,
      AntenatalCategory.lab => Palette.roseDeep,
      AntenatalCategory.imaging => Palette.rose,
      AntenatalCategory.prophylaxis => Palette.teal,
    };
