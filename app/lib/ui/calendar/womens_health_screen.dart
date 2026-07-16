/// Women's Health & Symptom Calendar (Tab 2). Three stacked zones:
///   1. a gestation header — horizontal 7-day strip + "Week 24, Day 3" progress,
///   2. an elegant month dot-matrix calendar; logged days carry a pastel dot,
///   3. a Flo-style bottom logging drawer (see [FloStyleCalendarDrawer]) that
///      slides up when a day is tapped, with big pill buttons for mood, symptoms,
///      and a fetal kick counter.
///
/// All data flows through the AppController (dayLogs, gestation, due date); this
/// screen is presentation + light month-grid math only.
library;

import 'package:flutter/material.dart' hide Flow;
import '../../app/app_controller.dart';
import '../../domain/cycle_log.dart';
import '../../domain/cycle_predictions.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'logging_drawer.dart';

class WomensHealthScreen extends StatefulWidget {
  final AppController controller;
  final DateTime Function() now;
  const WomensHealthScreen({super.key, required this.controller, DateTime Function()? now})
      : now = now ?? DateTime.now;

  @override
  State<WomensHealthScreen> createState() => _WomensHealthScreenState();
}

class _WomensHealthScreenState extends State<WomensHealthScreen> {
  late DateTime _month; // first day of the visible month
  late DateTime _today;

  @override
  void initState() {
    super.initState();
    _today = _dayOnly(widget.now());
    _month = DateTime(_today.year, _today.month, 1);
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _shiftMonth(int by) => setState(() => _month = DateTime(_month.year, _month.month + by, 1));

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final c = widget.controller;
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('cal_screen_title'))),
        body: StreamBuilder<void>(
          stream: c.changes,
          builder: (context, _) {
            final cycleMode = !c.isPregnant;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                if (cycleMode)
                  _CycleHeader(controller: c, today: _today, onSetDueDate: _pickDueDate)
                else
                  _GestationHeader(controller: c, today: _today, onSetDueDate: _pickDueDate),
                const SizedBox(height: 16),
                _MonthCalendar(
                  month: _month,
                  today: _today,
                  logs: c.dayLogs,
                  cycle: cycleMode ? c.cycle : null,
                  onPrev: () => _shiftMonth(-1),
                  onNext: () => _shiftMonth(1),
                  onTapDay: _openDay,
                ),
                if (cycleMode && c.cycle.hasData) ...[
                  const SizedBox(height: 14),
                  const _CycleLegend(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final c = widget.controller;
    final initial = c.dueDate ?? _today.add(const Duration(days: 140));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _today.subtract(const Duration(days: 300)),
      lastDate: _today.add(const Duration(days: 300)),
      helpText: L10nScope.of(context).t('cal_due_pick'),
    );
    if (picked != null) c.setDueDate(picked);
  }

  void _openDay(DateTime day) {
    final c = widget.controller;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StreamBuilder<void>(
        stream: c.changes,
        builder: (context, _) => FloStyleCalendarDrawer(
          day: day,
          log: c.logFor(day),
          pregnant: c.isPregnant,
          onToggleMood: (m) => c.toggleMoodFor(day, m),
          onToggleSymptom: (s) => c.toggleSymptomFor(day, s),
          onToggleFlow: (f) => c.toggleFlowFor(day, f),
          onKick: () => c.addKickFor(day),
          onResetKicks: () => c.resetKicksFor(day),
        ),
      ),
    );
  }
}

/// Gestation header: a "Week N, Day D" progress card + a 7-day horizontal strip
/// centred on today. When no due date is set, invites the mother to add one.
class _GestationHeader extends StatelessWidget {
  final AppController controller;
  final DateTime today;
  final VoidCallback onSetDueDate;
  const _GestationHeader({required this.controller, required this.today, required this.onSetDueDate});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final g = controller.gestation;

    if (g == null) {
      return GlassCard(
        onTap: onSetDueDate,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: const BoxDecoration(gradient: Palette.roseViolet, shape: BoxShape.circle),
              child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.t('cal_no_due_title'),
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(l.t('cal_no_due_body'),
                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.3)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Palette.textDim),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.rose.withValues(alpha: 0.14), Palette.violet.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: Palette.rose.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              MetricRing(
                fraction: g.progress,
                gradient: Palette.roseViolet,
                size: 72,
                stroke: 8,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${g.week}',
                        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 22, fontWeight: FontWeight.w700, height: 1)),
                    Text(l.t('gest_wk_short'), style: const TextStyle(color: Palette.textDim, fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('gest_week', {'w': g.week, 'd': g.dayOfWeek}),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      g.daysUntilDue >= 0
                          ? l.t('gest_days_left', {'n': g.daysUntilDue})
                          : l.t('gest_overdue'),
                      style: const TextStyle(color: Palette.textDim, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: onSetDueDate,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.edit_calendar_outlined, size: 14, color: Palette.violet),
                        const SizedBox(width: 4),
                        Text(l.t('gest_trimester', {'n': g.trimester}),
                            style: const TextStyle(color: Palette.violet, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => _confirmEndPregnancy(context),
              child: Text(l.t('cyc_end_pregnancy'),
                  style: const TextStyle(color: Palette.textDim, fontSize: 12, decoration: TextDecoration.underline)),
            ),
          ),
          const SizedBox(height: 12),
          _WeekStrip(today: today, logs: controller.dayLogs),
        ],
      ),
    );
  }

  /// Gentle, neutral confirmation before switching out of pregnancy mode.
  /// Not styled as destructive — logged data is kept, and the wording is soft.
  Future<void> _confirmEndPregnancy(BuildContext context) async {
    final l = L10nScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('cyc_end_pregnancy')),
        content: Text(l.t('cyc_end_pregnancy_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.t('act_cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.t('onb_finish'))),
        ],
      ),
    );
    if (ok == true) controller.setDueDate(null);
  }
}

/// Cycle header (non-pregnant mode): cycle day + days-to-next-period + phase,
/// with a 7-day strip. Invites the user to log a period when there's no data yet.
class _CycleHeader extends StatelessWidget {
  final AppController controller;
  final DateTime today;
  final VoidCallback onSetDueDate;
  const _CycleHeader({required this.controller, required this.today, required this.onSetDueDate});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final info = controller.cycle;

    if (!info.hasData) {
      return GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46, height: 46,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Palette.rose, Palette.roseDeep]),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.water_drop_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.t('cyc_no_data_title'),
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(l.t('cyc_no_data_body'),
                          style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _ExpectingLink(onTap: onSetDueDate),
          ],
        ),
      );
    }

    final loggedToday = controller.logFor(today).hasPeriod;
    final phaseType = cycleDayType(today, info, loggedPeriod: loggedToday);
    final until = info.daysUntilNextPeriod ?? 0;
    final subtitle = until > 0
        ? l.t('cyc_period_in', {'n': until})
        : until == 0
            ? l.t('cyc_period_today')
            : l.t('cyc_period_late', {'n': -until});

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Palette.rose.withValues(alpha: 0.14), Palette.violet.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: Palette.rose.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              MetricRing(
                fraction: (info.cycleDay ?? 1) / info.avgCycleLength,
                gradient: const LinearGradient(colors: [Palette.rose, Palette.violet]),
                size: 72, stroke: 8,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${info.cycleDay ?? 1}',
                        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 22, fontWeight: FontWeight.w700, height: 1)),
                    Text(l.t('cyc_day_short'), style: const TextStyle(color: Palette.textDim, fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subtitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    if (_phaseLabel(l, phaseType) != null)
                      _PhasePill(label: _phaseLabel(l, phaseType)!, type: phaseType),
                    const SizedBox(height: 6),
                    _ExpectingLink(onTap: onSetDueDate),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _WeekStrip(today: today, logs: controller.dayLogs),
        ],
      ),
    );
  }

  String? _phaseLabel(dynamic l, CycleDayType t) => switch (t) {
        CycleDayType.period => l.t('cyc_phase_period'),
        CycleDayType.fertile => l.t('cyc_phase_fertile'),
        CycleDayType.ovulation => l.t('cyc_phase_ovulation'),
        _ => null,
      };
}

class _PhasePill extends StatelessWidget {
  final String label;
  final CycleDayType type;
  const _PhasePill({required this.label, required this.type});
  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      CycleDayType.period => Palette.roseDeep,
      CycleDayType.ovulation => Palette.teal,
      CycleDayType.fertile => Palette.teal,
      _ => Palette.textDim,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class _ExpectingLink extends StatelessWidget {
  final VoidCallback onTap;
  const _ExpectingLink({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.pregnant_woman_rounded, size: 15, color: Palette.violet),
        const SizedBox(width: 4),
        Text(l.t('cyc_expecting'),
            style: const TextStyle(color: Palette.violet, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// 7-day horizontal strip centred on today, each day a soft chip; today is
/// highlighted, logged days carry a dot.
class _WeekStrip extends StatelessWidget {
  final DateTime today;
  final Map<String, DayLog> logs;
  const _WeekStrip({required this.today, required this.logs});

  @override
  Widget build(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    final days = [for (var i = -3; i <= 3; i++) today.add(Duration(days: i))];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final d in days)
          _DayChip(
            weekday: ml.narrowWeekdays[d.weekday % 7],
            day: d.day,
            isToday: isSameDay(d, today),
            logged: (logs[dateKey(d)]?.isNotEmpty) ?? false,
          ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  final String weekday;
  final int day;
  final bool isToday;
  final bool logged;
  const _DayChip({required this.weekday, required this.day, required this.isToday, required this.logged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(weekday, style: const TextStyle(color: Palette.textDim, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            gradient: isToday ? Palette.roseViolet : null,
            color: isToday ? null : Colors.white,
            shape: BoxShape.circle,
            border: isToday ? null : Border.all(color: Palette.border),
          ),
          alignment: Alignment.center,
          child: Text('$day',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isToday ? Colors.white : Palette.text,
              )),
        ),
        const SizedBox(height: 4),
        Container(
          width: 5, height: 5,
          decoration: BoxDecoration(
            color: logged ? Palette.rose : Colors.transparent,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

/// Elegant, low-profile month grid. Days with logged metrics show a soft pastel
/// circle; today is ringed. Tapping any day opens the logging drawer.
class _MonthCalendar extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final Map<String, DayLog> logs;
  final CycleInfo? cycle; // non-null in cycle mode → colour by cycle phase
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final void Function(DateTime day) onTapDay;
  const _MonthCalendar({
    required this.month,
    required this.today,
    required this.logs,
    required this.onPrev,
    required this.onNext,
    required this.onTapDay,
    this.cycle,
  });

  @override
  Widget build(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = first.weekday % 7; // 0 = Sunday-first column
    final cells = leadingBlanks + daysInMonth;
    final rows = (cells / 7).ceil();

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPrev,
                tooltip: ml.previousMonthTooltip,
                icon: const Icon(Icons.chevron_left, color: Palette.textDim),
              ),
              Expanded(
                child: Text(ml.formatMonthYear(month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: onNext,
                tooltip: ml.nextMonthTooltip,
                icon: const Icon(Icons.chevron_right, color: Palette.textDim),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Text(ml.narrowWeekdays[i],
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(child: _buildCell(r * 7 + col - leadingBlanks + 1, daysInMonth)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCell(int dayNum, int daysInMonth) {
    if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox(height: 40);
    final date = DateTime(month.year, month.month, dayNum);
    final log = logs[dateKey(date)];
    final logged = log?.isNotEmpty ?? false;
    final isToday = isSameDay(date, today);
    final isFuture = date.isAfter(today);

    // Colour resolution: cycle phase (cycle mode) wins, else the generic
    // "something logged" pink dot.
    Color fill = Colors.transparent;
    Color? textColor;
    Color borderColor = Palette.violet;
    if (cycle != null) {
      final type = cycleDayType(date, cycle!, loggedPeriod: log?.hasPeriod ?? false);
      final s = cycleCellStyle(type);
      fill = s.fill;
      textColor = s.text;
    } else if (logged) {
      fill = Palette.rose.withValues(alpha: 0.16);
      textColor = Palette.roseDeep;
    }

    return Semantics(
      button: !isFuture,
      child: GestureDetector(
      onTap: isFuture ? null : () => onTapDay(date),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 40,
        child: Center(
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: isToday ? Border.all(color: borderColor, width: 1.6) : null,
            ),
            alignment: Alignment.center,
            child: Text('$dayNum',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  color: textColor ?? (isFuture ? Palette.textDim.withValues(alpha: 0.5) : Palette.text),
                )),
          ),
        ),
      ),
      ),
    );
  }
}

/// Fill + text colour for each cycle day type in the month grid.
({Color fill, Color? text}) cycleCellStyle(CycleDayType type) => switch (type) {
      CycleDayType.period => (fill: Palette.roseDeep, text: Colors.white),
      CycleDayType.predictedPeriod => (fill: Palette.rose.withValues(alpha: 0.18), text: Palette.roseDeep),
      CycleDayType.ovulation => (fill: Palette.teal, text: Colors.white),
      CycleDayType.fertile => (fill: Palette.teal.withValues(alpha: 0.16), text: Palette.teal),
      CycleDayType.none => (fill: Colors.transparent, text: null),
    };

/// Legend for the cycle calendar colours.
class _CycleLegend extends StatelessWidget {
  const _CycleLegend();
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Wrap(
      spacing: 16, runSpacing: 8,
      children: [
        _LegendDot(color: Palette.roseDeep, label: l.t('cyc_period')),
        _LegendDot(color: Palette.rose.withValues(alpha: 0.5), label: l.t('cyc_predicted')),
        _LegendDot(color: Palette.teal.withValues(alpha: 0.5), label: l.t('cyc_fertile')),
        _LegendDot(color: Palette.teal, label: l.t('cyc_ovulation')),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 11, height: 11, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
    ]);
  }
}
